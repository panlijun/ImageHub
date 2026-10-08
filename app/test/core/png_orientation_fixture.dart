import 'dart:typed_data';

import 'package:image/image.dart' as img;

const orientedPixelIndices = <int, List<int>>{
  1: [0, 1, 2, 3, 4, 5],
  2: [1, 0, 3, 2, 5, 4],
  3: [5, 4, 3, 2, 1, 0],
  4: [4, 5, 2, 3, 0, 1],
  5: [0, 2, 4, 1, 3, 5],
  6: [4, 2, 0, 5, 3, 1],
  7: [5, 3, 1, 4, 2, 0],
  8: [1, 3, 5, 0, 2, 4],
};

List<int> matrixPixel(int index) => [
  20 + index * 30,
  35 + index * 20,
  240 - index * 20,
  255,
];

img.Image orientationMatrix({int scale = 1, bool reverse = false}) {
  final image = img.Image(width: 2 * scale, height: 3 * scale, numChannels: 4);
  for (final pixel in image) {
    final index = (pixel.y ~/ scale) * 2 + pixel.x ~/ scale;
    final value = matrixPixel(reverse ? 5 - index : index);
    pixel.setRgba(value[0], value[1], value[2], value[3]);
  }
  return image;
}

Uint8List orientationTiff(
  int orientation, {
  Endian endian = Endian.little,
  int type = 3,
  int count = 1,
  bool duplicate = false,
}) {
  final bytes = Uint8List(duplicate ? 38 : 26);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 2, endian == Endian.little ? [0x49, 0x49] : [0x4d, 0x4d]);
  data
    ..setUint16(2, 42, endian)
    ..setUint32(4, 8, endian)
    ..setUint16(8, duplicate ? 2 : 1, endian);
  for (var index = 0; index < (duplicate ? 2 : 1); index++) {
    final offset = 10 + index * 12;
    data
      ..setUint16(offset, 0x0112, endian)
      ..setUint16(offset + 2, type, endian)
      ..setUint32(offset + 4, count, endian)
      ..setUint16(offset + 8, orientation, endian);
  }
  return bytes;
}

Uint8List addPngExif(Uint8List png, Uint8List exif, {bool duplicate = false}) {
  final chunk = pngChunk('eXIf', exif);
  return Uint8List.fromList([
    ...png.sublist(0, 33),
    ...chunk,
    if (duplicate) ...chunk,
    ...png.sublist(33),
  ]);
}

Uint8List pngChunk(String type, Uint8List data) {
  final bytes = Uint8List(data.length + 12);
  final view = ByteData.sublistView(bytes)..setUint32(0, data.length);
  bytes.setRange(4, 8, type.codeUnits);
  bytes.setRange(8, 8 + data.length, data);
  var crc = 0xffffffff;
  for (final byte in bytes.sublist(4, bytes.length - 4)) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  view.setUint32(bytes.length - 4, crc ^ 0xffffffff);
  return bytes;
}
