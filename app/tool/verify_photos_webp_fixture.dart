import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

void main() {
  final source = img.Image(width: 1, height: 1, numChannels: 3)
    ..setPixelRgb(0, 0, 37, 83, 149);
  final bytes = img.encodeWebP(source);
  final decoded = img.decodeWebP(bytes);
  if (decoded == null || decoded.width != 1 || decoded.height != 1) {
    throw StateError('The synthetic WebP fixture did not decode.');
  }
  final pixel = decoded.getPixel(0, 0);
  if (pixel.r != 37 || pixel.g != 83 || pixel.b != 149) {
    throw StateError('The synthetic lossless WebP pixel changed.');
  }
  stdout.writeln(
    jsonEncode({
      'format': 'WebP',
      'byteCount': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'base64': base64Encode(bytes),
      'decodedWidth': decoded.width,
      'decodedHeight': decoded.height,
      'pixel': [pixel.r, pixel.g, pixel.b],
    }),
  );
}
