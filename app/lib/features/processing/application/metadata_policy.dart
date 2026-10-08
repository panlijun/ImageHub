import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../../../core/platform_resource.dart';
import '../../../core/png_orientation.dart';
import '../domain/processing_models.dart';

class ColorMetadata {
  ColorMetadata({
    this.icc,
    Map<String, Uint8List>? pngColor,
    this.orientation = 1,
  }) : pngColor = Map.unmodifiable(pngColor ?? {});
  final Uint8List? icc;
  final Map<String, Uint8List> pngColor;
  final int orientation;
  String get identity => sha256.convert([
    ...?icc,
    for (final key in pngColor.keys.toList()..sort()) ...[
      ...key.codeUnits,
      ...pngColor[key]!,
    ],
  ]).toString();
}

/// Explicit allow-list, independent of encoder defaults. ICC support is limited
/// to validated RGB/XYZ matrix + TRC input/display profiles (ICC.1 §§7–10):
/// https://www.color.org/specification/ICC.1-2022-05.pdf
/// Unsupported colour transforms fail visibly instead of dropping their tags.
class MetadataPolicy {
  static const maxIccBytes = 1024 * 1024;
  static void clearPrivateMetadata(img.Image image) {
    for (final frame in image.frames) {
      frame.exif = img.ExifData();
      frame.textData = null;
      frame.iccProfile = null;
    }
  }

  static ColorMetadata inspect(Uint8List bytes, String format) {
    Uint8List? profile;
    final color = <String, Uint8List>{};
    var orientation = 1;
    if (format == 'PNG') {
      try {
        orientation = readPngOrientation(bytes);
      } on ResourceFailure {
        throw const ProcessingFailure(
          ProcessingFailureKind.invalidImage,
          'PNG 图片方向元数据或内容结构无效。',
        );
      }
      for (final chunk in _pngChunks(bytes)) {
        if (chunk.name == 'iCCP') {
          if (profile != null) _unsupportedColor();
          final separator = chunk.data.indexOf(0);
          if (separator < 1 ||
              separator > 79 ||
              separator + 2 > chunk.data.length ||
              chunk.data[separator + 1] != 0) {
            _unsupportedColor();
          }
          profile = sanitizeIcc(
            _inflateBounded(Uint8List.sublistView(chunk.data, separator + 2)),
          );
        } else if ({'sRGB', 'gAMA', 'cHRM', 'cICP'}.contains(chunk.name)) {
          if (color.containsKey(chunk.name)) _unsupportedColor();
          _validatePngColor(chunk.name, chunk.data);
          color[chunk.name] = chunk.data;
        }
      }
      // ICC/sRGB/cICP precedence is complex; reject contradictory declarations.
      if (profile != null &&
          (color.containsKey('sRGB') || color.containsKey('cICP'))) {
        _unsupportedColor();
      }
    } else if (format == 'JPEG') {
      final fragments = <int, Uint8List>{};
      int? count;
      for (final segment in _jpegSegments(bytes)) {
        if (segment.marker == 0xe1 &&
            _starts(segment.data, 'Exif\u0000\u0000')) {
          final exif = img.ExifData.fromInputBuffer(
            img.InputBuffer(Uint8List.sublistView(segment.data, 6)),
          );
          orientation = exif.imageIfd.orientation ?? 1;
        }
        if (segment.marker == 0xe2) {
          if (!_starts(segment.data, 'ICC_PROFILE\u0000') ||
              segment.data.length < 14) {
            _unsupportedColor();
          }
          final sequence = segment.data[12];
          final total = segment.data[13];
          if (total < 1 ||
              sequence < 1 ||
              sequence > total ||
              (count != null && count != total) ||
              fragments.containsKey(sequence)) {
            _unsupportedColor();
          }
          count = total;
          fragments[sequence] = Uint8List.sublistView(segment.data, 14);
        }
        // RGB and grayscale JPEG only; CMYK/YCCK need a tested colour transform.
        if ({0xc0, 0xc1, 0xc2}.contains(segment.marker)) {
          if (segment.data.length < 6 || !{1, 3}.contains(segment.data[5])) {
            _unsupportedColor();
          }
        }
      }
      if (count != null) {
        if (fragments.length != count) _unsupportedColor();
        final builder = BytesBuilder(copy: false);
        for (var i = 1; i <= count; i++) {
          if (builder.length + fragments[i]!.length > maxIccBytes) {
            _unsupportedColor();
          }
          builder.add(fragments[i]!);
        }
        profile = sanitizeIcc(builder.takeBytes());
      }
    } else if (format == 'WebP') {
      for (final chunk in _webpChunks(bytes)) {
        if (chunk.name == 'EXIF') {
          final data = _starts(chunk.data, 'Exif\u0000\u0000')
              ? Uint8List.sublistView(chunk.data, 6)
              : chunk.data;
          orientation =
              img.ExifData.fromInputBuffer(img.InputBuffer(data))
                  .imageIfd
                  .orientation ??
              1;
        }
        if (chunk.name == 'ICCP') {
          if (profile != null) _unsupportedColor();
          profile = sanitizeIcc(chunk.data);
        }
      }
    } else if (format == 'BMP' && bytes.length >= 18) {
      final dibSize = ByteData.sublistView(bytes).getUint32(14, Endian.little);
      if (dibSize >= 108) {
        // V4 calibrated RGB/V5 linked or embedded profiles are not silently lost.
        if (bytes.length < 122 ||
            ByteData.sublistView(bytes).getUint32(70, Endian.little) !=
                0x73524742) {
          _unsupportedColor();
        }
      }
    }
    if (orientation < 1 || orientation > 8) _unsupportedColor();
    return ColorMetadata(
      icc: profile,
      pngColor: color,
      orientation: orientation,
    );
  }

  static ColorMetadata combine(
    List<ColorMetadata> inputs,
    ProcessingFormat target,
  ) {
    if (inputs.any((input) => input.identity != inputs.first.identity)) {
      throw const ProcessingFailure(
        ProcessingFailureKind.colorMetadataUnsupported,
        '拼接图片的颜色空间不同，当前引擎不能安全统一颜色，请先转换为同一颜色空间。',
      );
    }
    final result = inputs.first;
    if (target != ProcessingFormat.png && result.pngColor.isNotEmpty) {
      // These precise declarations are equivalent to the standard sRGB default.
      final c = result.pngColor;
      final srgbChromaticities = [
        31270,
        32900,
        64000,
        33000,
        30000,
        60000,
        15000,
        6000,
      ];
      if ((c['gAMA'] != null && _u32(c['gAMA']!, 0) != 45455) ||
          (c['cICP'] != null &&
              !_equal(c['cICP']!, Uint8List.fromList([1, 13, 0, 1]))) ||
          (c['cHRM'] != null &&
              List.generate(
                8,
                (i) => _u32(c['cHRM']!, i * 4),
              ).asMap().entries.any(
                (entry) => entry.value != srgbChromaticities[entry.key],
              ))) {
        _unsupportedColor();
      }
      return ColorMetadata(icc: result.icc);
    }
    return result;
  }

  static Uint8List applyAndVerify(
    Uint8List bytes,
    ProcessingFormat format,
    ColorMetadata color,
  ) {
    final builder = BytesBuilder(copy: false);
    switch (format) {
      case ProcessingFormat.png:
        builder.add(bytes.sublist(0, 8));
        for (final chunk in _pngChunks(bytes)) {
          if (!{'IHDR', 'IDAT', 'IEND'}.contains(chunk.name)) _privateOutput();
          builder.add(chunk.raw);
          if (chunk.name == 'IHDR') {
            if (color.icc != null) {
              final compressed = ZLibCodec().encode(color.icc!);
              builder.add(
                _pngChunk(
                  'iCCP',
                  Uint8List.fromList([
                    ...'Color'.codeUnits,
                    0,
                    0,
                    ...compressed,
                  ]),
                ),
              );
            }
            for (final entry in color.pngColor.entries) {
              builder.add(_pngChunk(entry.key, entry.value));
            }
          }
        }
      case ProcessingFormat.jpeg:
        builder.add(bytes.sublist(0, 2));
        if (color.icc != null) {
          const fragmentBytes = 65519;
          final count =
              (color.icc!.length + fragmentBytes - 1) ~/ fragmentBytes;
          for (var i = 0; i < count; i++) {
            final end = (i + 1) * fragmentBytes < color.icc!.length
                ? (i + 1) * fragmentBytes
                : color.icc!.length;
            final data = [
              ...'ICC_PROFILE\u0000'.codeUnits,
              i + 1,
              count,
              ...color.icc!.sublist(i * fragmentBytes, end),
            ];
            final length = data.length + 2;
            builder.add([255, 0xe2, length >> 8, length & 255, ...data]);
          }
        }
        for (final segment in _jpegSegments(bytes)) {
          if (segment.marker == 0xe1 ||
              segment.marker == 0xfe ||
              (segment.marker >= 0xe2 && segment.marker <= 0xef)) {
            _privateOutput();
          }
        }
        builder.add(bytes.sublist(2));
      case ProcessingFormat.webp:
        final chunks = _webpChunks(bytes);
        final payload = BytesBuilder(copy: false)..add('WEBP'.codeUnits);
        var sawExtended = false;
        for (final chunk in chunks) {
          if (!{'VP8X', 'VP8 ', 'VP8L', 'ALPH'}.contains(chunk.name)) {
            _privateOutput();
          }
          if (chunk.name == 'VP8X') {
            sawExtended = true;
            final data = Uint8List.fromList(chunk.data);
            if (color.icc != null) data[0] |= 0x20;
            payload.add(_webpChunk('VP8X', data));
            if (color.icc != null) payload.add(_webpChunk('ICCP', color.icc!));
          } else {
            if (!sawExtended && color.icc != null) {
              final decoder = img.WebPDecoder();
              final info = decoder.startDecode(bytes)!;
              final data = Uint8List(10)..[0] = 0x20;
              _put24(data, 4, info.width - 1);
              _put24(data, 7, info.height - 1);
              payload.add(_webpChunk('VP8X', data));
              payload.add(_webpChunk('ICCP', color.icc!));
              sawExtended = true;
            }
            payload.add(chunk.raw);
          }
        }
        final contents = payload.takeBytes();
        final header = Uint8List(8)..setRange(0, 4, 'RIFF'.codeUnits);
        ByteData.sublistView(header)
            .setUint32(4, contents.length, Endian.little);
        builder
          ..add(header)
          ..add(contents);
    }
    final result = builder.takeBytes();
    final actual = inspect(result, switch (format) {
      ProcessingFormat.png => 'PNG',
      ProcessingFormat.jpeg => 'JPEG',
      ProcessingFormat.webp => 'WebP',
    });
    if (actual.identity != color.identity || actual.orientation != 1) {
      _privateOutput();
    }
    // Check containers explicitly; decoding alone does not establish privacy.
    if (format == ProcessingFormat.png &&
        _pngChunks(result).any(
          (chunk) => !{
            'IHDR',
            'IDAT',
            'IEND',
            'iCCP',
            'sRGB',
            'gAMA',
            'cHRM',
            'cICP',
          }.contains(chunk.name),
        )) {
      _privateOutput();
    }
    if (format == ProcessingFormat.webp &&
        _webpChunks(result).any(
          (chunk) =>
              !{'VP8X', 'VP8 ', 'VP8L', 'ALPH', 'ICCP'}.contains(chunk.name),
        )) {
      _privateOutput();
    }
    return result;
  }

  static Uint8List sanitizeIcc(Uint8List profile) {
    if (profile.length < 132 ||
        profile.length > maxIccBytes ||
        _u32(profile, 0) != profile.length ||
        _text(profile, 36, 4) != 'acsp' ||
        !{2, 4}.contains(profile[8]) ||
        profile[9] > 0x40 ||
        profile[10] != 0 ||
        profile[11] != 0 ||
        !{'scnr', 'mntr'}.contains(_text(profile, 12, 4)) ||
        _text(profile, 16, 4) != 'RGB ' ||
        _text(profile, 20, 4) != 'XYZ ' ||
        _u32(profile, 64) > 3) {
      _unsupportedColor();
    }
    // ICC PCS illuminant is D50; do not carry arbitrary header payloads.
    const d50 = [0x0000f6d6, 0x00010000, 0x0000d32d];
    for (var i = 0; i < 3; i++) {
      if ((_u32(profile, 68 + i * 4) - d50[i]).abs() > 2) _unsupportedColor();
    }
    final count = _u32(profile, 128);
    if (count < 7 || count > 128 || 132 + count * 12 > profile.length) {
      _unsupportedColor();
    }
    const xyzTags = {'wtpt', 'bkpt', 'rXYZ', 'gXYZ', 'bXYZ', 'lumi'};
    const curveTags = {'rTRC', 'gTRC', 'bTRC'};
    const removable = {
      'desc',
      'cprt',
      'dmnd',
      'dmdd',
      'meta',
      'pseq',
      'psid',
      'targ',
      'tech',
    };
    final retained = <String, Uint8List>{};
    final seen = <String>{};
    final ranges = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      final record = 132 + i * 12;
      final tag = _text(profile, record, 4);
      final offset = _u32(profile, record + 4);
      final length = _u32(profile, record + 8);
      if (!seen.add(tag) ||
          offset % 4 != 0 ||
          offset < 132 + count * 12 ||
          length < 8 ||
          offset > profile.length - length) {
        _unsupportedColor();
      }
      for (final range in ranges) {
        if (offset < range.$2 &&
            offset + length > range.$1 &&
            !(offset == range.$1 && offset + length == range.$2)) {
          _unsupportedColor();
        }
      }
      ranges.add((offset, offset + length));
      final data = Uint8List.fromList(profile.sublist(offset, offset + length));
      if (removable.contains(tag)) continue;
      if (data.sublist(4, 8).any((value) => value != 0)) _unsupportedColor();
      final type = _text(data, 0, 4);
      if (xyzTags.contains(tag)) {
        if (type != 'XYZ ' || length != 20) _unsupportedColor();
      } else if (tag == 'chad') {
        if (type != 'sf32' || length != 44) _unsupportedColor();
      } else if (curveTags.contains(tag)) {
        if (type == 'curv') {
          if (length < 12) _unsupportedColor();
          final entries = _u32(data, 8);
          if (entries > 65536 || length != 12 + entries * 2) {
            _unsupportedColor();
          }
          var previous = -1;
          for (var k = 0; k < entries; k++) {
            final value = ByteData.sublistView(data).getUint16(12 + k * 2);
            if (value < previous || (entries == 1 && value == 0)) {
              _unsupportedColor();
            }
            previous = value;
          }
        } else if (type == 'para') {
          if (length < 16) _unsupportedColor();
          final function = ByteData.sublistView(data).getUint16(8);
          const parameters = [1, 3, 4, 5, 7];
          if (function > 4 ||
              data[10] != 0 ||
              data[11] != 0 ||
              length != 12 + parameters[function] * 4 ||
              ByteData.sublistView(data).getInt32(12) <= 0) {
            _unsupportedColor();
          }
        } else {
          _unsupportedColor();
        }
      } else {
        // Includes LUT transforms, named colours and viewing-condition models.
        _unsupportedColor();
      }
      retained[tag] = data;
    }
    if (!{
      'wtpt',
      'rXYZ',
      'gXYZ',
      'bXYZ',
      'rTRC',
      'gTRC',
      'bTRC',
    }.every(retained.containsKey)) {
      _unsupportedColor();
    }
    // Replace required human description/copyright tags with fixed non-identifiers.
    retained['desc'] = profile[8] == 4
        ? _mluc('RGB colour')
        : _description('RGB colour');
    retained['cprt'] = profile[8] == 4
        ? _mluc('')
        : Uint8List.fromList([...'text'.codeUnits, 0, 0, 0, 0, 0]);
    final keys = retained.keys.toList()..sort();
    var total = 132 + keys.length * 12;
    for (final key in keys) {
      total += (retained[key]!.length + 3) & ~3;
    }
    final result = Uint8List(total);
    final header = ByteData.sublistView(result);
    header.setUint32(0, total);
    result[8] = profile[8];
    result[9] = profile[9];
    result.setRange(12, 24, profile.sublist(12, 24));
    header
      ..setUint16(24, 2000)
      ..setUint16(26, 1)
      ..setUint16(28, 1);
    result.setRange(36, 40, 'acsp'.codeUnits);
    result.setRange(64, 80, profile.sublist(64, 80));
    // Flags, manufacturer/model, device attributes, CMM, platform, creator,
    // profile ID, unused bytes and original timestamp remain canonical zero.
    header.setUint32(128, keys.length);
    var offset = 132 + keys.length * 12;
    for (var i = 0; i < keys.length; i++) {
      final record = 132 + i * 12;
      final value = retained[keys[i]]!;
      result.setRange(record, record + 4, keys[i].codeUnits);
      header
        ..setUint32(record + 4, offset)
        ..setUint32(record + 8, value.length);
      result.setRange(offset, offset + value.length, value);
      offset += (value.length + 3) & ~3;
    }
    return result;
  }
}

class _Chunk {
  const _Chunk(this.name, this.data, this.raw);
  final String name;
  final Uint8List data;
  final Uint8List raw;
}

List<_Chunk> _pngChunks(Uint8List bytes) {
  final chunks = <_Chunk>[];
  var offset = 8;
  while (offset < bytes.length) {
    if (offset > bytes.length - 12) _unsupportedColor();
    final length = _u32(bytes, offset);
    if (length > bytes.length - offset - 12) _unsupportedColor();
    final name = _text(bytes, offset + 4, 4);
    final end = offset + length + 12;
    if (_crc32(Uint8List.sublistView(bytes, offset + 4, end - 4)) !=
        _u32(bytes, end - 4)) {
      _unsupportedColor();
    }
    chunks.add(
      _Chunk(
        name,
        Uint8List.sublistView(bytes, offset + 8, end - 4),
        Uint8List.sublistView(bytes, offset, end),
      ),
    );
    offset = end;
    if (name == 'IEND') {
      if (offset != bytes.length) _unsupportedColor();
      break;
    }
  }
  if (chunks.isEmpty ||
      chunks.first.name != 'IHDR' ||
      chunks.last.name != 'IEND') {
    _unsupportedColor();
  }
  return chunks;
}

class _JpegSegment {
  const _JpegSegment(this.marker, this.data);
  final int marker;
  final Uint8List data;
}

List<_JpegSegment> _jpegSegments(Uint8List bytes) {
  final segments = <_JpegSegment>[];
  var offset = 2;
  while (offset < bytes.length) {
    if (bytes[offset++] != 255) _unsupportedColor();
    while (offset < bytes.length && bytes[offset] == 255) {
      offset++;
    }
    if (offset >= bytes.length) _unsupportedColor();
    final marker = bytes[offset++];
    if (marker == 0xda || marker == 0xd9) break;
    if (marker == 0 ||
        marker == 0xd8 ||
        marker == 0x01 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
      _unsupportedColor();
    }
    if (offset > bytes.length - 2) _unsupportedColor();
    final length = ByteData.sublistView(bytes).getUint16(offset);
    if (length < 2 || length > bytes.length - offset) _unsupportedColor();
    segments.add(
      _JpegSegment(
        marker,
        Uint8List.sublistView(bytes, offset + 2, offset + length),
      ),
    );
    offset += length;
  }
  return segments;
}

List<_Chunk> _webpChunks(Uint8List bytes) {
  if (bytes.length < 12 ||
      !_starts(bytes, 'RIFF') ||
      _text(bytes, 8, 4) != 'WEBP' ||
      ByteData.sublistView(bytes).getUint32(4, Endian.little) !=
          bytes.length - 8) {
    _unsupportedColor();
  }
  final chunks = <_Chunk>[];
  var offset = 12;
  while (offset < bytes.length) {
    if (offset > bytes.length - 8) _unsupportedColor();
    final length = ByteData.sublistView(bytes)
        .getUint32(offset + 4, Endian.little);
    if (length > bytes.length - offset - 8) _unsupportedColor();
    final end = offset + 8 + length + (length & 1);
    if (end > bytes.length) _unsupportedColor();
    chunks.add(
      _Chunk(
        _text(bytes, offset, 4),
        Uint8List.sublistView(bytes, offset + 8, offset + 8 + length),
        Uint8List.sublistView(bytes, offset, end),
      ),
    );
    offset = end;
  }
  return chunks;
}

Uint8List _pngChunk(String name, Uint8List data) {
  final result = Uint8List(data.length + 12);
  ByteData.sublistView(result).setUint32(0, data.length);
  result.setRange(4, 8, name.codeUnits);
  result.setRange(8, 8 + data.length, data);
  ByteData.sublistView(result).setUint32(
    result.length - 4,
    _crc32(Uint8List.sublistView(result, 4, result.length - 4)),
  );
  return result;
}

Uint8List _webpChunk(String name, Uint8List data) {
  final result = Uint8List(8 + data.length + (data.length & 1));
  result.setRange(0, 4, name.codeUnits);
  ByteData.sublistView(result).setUint32(4, data.length, Endian.little);
  result.setRange(8, 8 + data.length, data);
  return result;
}

void _validatePngColor(String name, Uint8List data) {
  if (name == 'sRGB' && (data.length != 1 || data[0] > 3)) _unsupportedColor();
  if (name == 'gAMA' && (data.length != 4 || _u32(data, 0) == 0)) {
    _unsupportedColor();
  }
  if (name == 'cHRM' &&
      (data.length != 32 ||
          List.generate(
            8,
            (i) => _u32(data, i * 4),
          ).any((value) => value > 100000))) {
    _unsupportedColor();
  }
  if (name == 'cICP' &&
      (data.length != 4 ||
          !{1, 9, 12}.contains(data[0]) ||
          !{1, 13}.contains(data[1]) ||
          data[2] != 0 ||
          data[3] != 1)) {
    _unsupportedColor();
  }
}

Uint8List _inflateBounded(Uint8List bytes) {
  final sink = _BoundedSink();
  final decoder = ZLibDecoder().startChunkedConversion(sink);
  decoder
    ..add(bytes)
    ..close();
  return sink.builder.takeBytes();
}

class _BoundedSink implements Sink<List<int>> {
  final builder = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (builder.length + data.length > MetadataPolicy.maxIccBytes) {
      _unsupportedColor();
    }
    builder.add(data);
  }

  @override
  void close() {}
}

Uint8List _mluc(String text) {
  final data = Uint8List(28 + text.length * 2);
  data.setRange(0, 4, 'mluc'.codeUnits);
  final view = ByteData.sublistView(data)
    ..setUint32(8, 1)
    ..setUint32(12, 12)
    ..setUint16(16, 0x656e)
    ..setUint16(18, 0x5553)
    ..setUint32(20, text.length * 2)
    ..setUint32(24, 28);
  for (var i = 0; i < text.length; i++) {
    view.setUint16(28 + i * 2, text.codeUnitAt(i));
  }
  return data;
}

Uint8List _description(String text) {
  final ascii = [...text.codeUnits, 0];
  final data = Uint8List(12 + ascii.length + 78);
  data.setRange(0, 4, 'desc'.codeUnits);
  ByteData.sublistView(data).setUint32(8, ascii.length);
  data.setRange(12, 12 + ascii.length, ascii);
  return data;
}

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset);
String _text(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(Uint8List.sublistView(bytes, offset, offset + length));
bool _starts(Uint8List bytes, String value) =>
    bytes.length >= value.length && _text(bytes, 0, value.length) == value;
bool _equal(Uint8List a, Uint8List b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => i).every((i) => a[i] == b[i]);
void _put24(Uint8List data, int offset, int value) {
  data[offset] = value & 255;
  data[offset + 1] = (value >> 8) & 255;
  data[offset + 2] = (value >> 16) & 255;
}

int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return crc ^ 0xffffffff;
}

Never _unsupportedColor() => throw const ProcessingFailure(
  ProcessingFailureKind.colorMetadataUnsupported,
  '颜色元数据无效或超出已验证的 RGB 颜色允许清单，请使用受支持的颜色空间副本。',
);
Never _privateOutput() => throw const ProcessingFailure(
  ProcessingFailureKind.colorMetadataUnsupported,
  '输出元数据校验未通过，未生成可用结果。',
);
