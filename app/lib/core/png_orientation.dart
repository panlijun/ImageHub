import 'dart:typed_data';

import 'platform_resource.dart';

/// Reads the PNG eXIf IFD0 orientation without relying on codec EXIF support.
/// Original bytes stay untouched. Malformed chunks or ambiguous EXIF fail with
/// a fixed safe classification before decoded pixels can become usable.
int readPngOrientation(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 8 ||
      List.generate(8, (i) => i).any((i) => bytes[i] != signature[i])) {
    _invalid();
  }
  final view = ByteData.sublistView(bytes);
  var offset = 8;
  var first = true;
  var ended = false;
  var seenExif = false;
  var orientation = 1;
  while (offset < bytes.length) {
    if (bytes.length - offset < 12) _invalid();
    final length = view.getUint32(offset);
    if (length > bytes.length - offset - 12) _invalid();
    final end = offset + length + 12;
    final name = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (first ? name != 'IHDR' || length != 13 : name == 'IHDR') {
      _invalid();
    }
    if (_crc32(Uint8List.sublistView(bytes, offset + 4, end - 4)) !=
        view.getUint32(end - 4)) {
      _invalid();
    }
    if (name == 'eXIf') {
      if (seenExif) _invalid();
      seenExif = true;
      orientation = _tiffOrientation(
        Uint8List.sublistView(bytes, offset + 8, end - 4),
      );
    }
    offset = end;
    first = false;
    if (name == 'IEND') {
      if (length != 0 || offset != bytes.length) _invalid();
      ended = true;
      break;
    }
  }
  if (first || !ended) _invalid();
  return orientation;
}

int _tiffOrientation(Uint8List bytes) {
  if (bytes.length < 8) _invalid();
  final endian = bytes[0] == 0x49 && bytes[1] == 0x49
      ? Endian.little
      : bytes[0] == 0x4d && bytes[1] == 0x4d
      ? Endian.big
      : null;
  if (endian == null) _invalid();
  final view = ByteData.sublistView(bytes);
  if (view.getUint16(2, endian) != 42) _invalid();
  final offset = view.getUint32(4, endian);
  if (offset < 8 || offset > bytes.length - 6) _invalid();
  final count = view.getUint16(offset, endian);
  if (count > (bytes.length - offset - 6) ~/ 12) _invalid();
  final end = offset + 2 + count * 12;
  final next = view.getUint32(end, endian);
  if (next != 0 &&
      (next < 8 ||
          next > bytes.length - 6 ||
          (next >= offset && next < end + 4))) {
    _invalid();
  }
  var seen = false;
  var orientation = 1;
  for (var index = 0; index < count; index++) {
    final entry = offset + 2 + index * 12;
    if (view.getUint16(entry, endian) != 0x0112) continue;
    if (seen ||
        view.getUint16(entry + 2, endian) != 3 ||
        view.getUint32(entry + 4, endian) != 1) {
      _invalid();
    }
    seen = true;
    orientation = view.getUint16(entry + 8, endian);
    if (orientation < 1 || orientation > 8) _invalid();
  }
  return orientation;
}

int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return crc ^ 0xffffffff;
}

Never _invalid() => throw const ResourceFailure(FailureKind.invalidImage);
