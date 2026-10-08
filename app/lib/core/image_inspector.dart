import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart' as hashing;

import 'bake_image_orientation.dart';
import 'platform_resource.dart';
import 'png_orientation.dart';

class ImageMetadata {
  const ImageMetadata({
    required this.format,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.orientation,
  });
  final String format;
  final int width;
  final int height;
  final int frameCount;
  final int orientation;
}

/// Candidate budgets from TS 6.4, pending four-device memory calibration.
class ImageInspector {
  const ImageInspector(this.memoryBudgetBytes);
  final int memoryBudgetBytes;
  Future<ImageMetadata> inspect(File file) =>
      Isolate.run(() => inspectImage(file.path, memoryBudgetBytes));
  Future<void> thumbnail(File input, File output, {int frame = 0}) =>
      Isolate.run(() async {
        final bytes = await _thumbnailBytes(
          input.path,
          memoryBudgetBytes,
          frame,
        );
        await output.writeAsBytes(bytes, flush: true);
      });

  /// No output file or background FileImage read survives this Future.
  Future<Uint8List> thumbnailBytes(
    File input, {
    required String expectedSha256,
    required int expectedByteCount,
    int frame = 0,
  }) => Isolate.run(
    () => _thumbnailBytes(
      input.path,
      memoryBudgetBytes,
      frame,
      expectedSha256: expectedSha256,
      expectedByteCount: expectedByteCount,
    ),
  );
}

Future<Uint8List> _thumbnailBytes(
  String path,
  int budget,
  int frame, {
  String? expectedSha256,
  int? expectedByteCount,
}) async {
  final file = File(path);
  if (await file.length() > budget ~/ 4) {
    throw const ResourceFailure(FailureKind.resourceBudget);
  }
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (buffer.length + chunk.length > budget ~/ 4) {
      throw const ResourceFailure(FailureKind.resourceBudget);
    }
    buffer.add(chunk);
  }
  final bytes = buffer.takeBytes();
  if ((expectedByteCount != null && bytes.length != expectedByteCount) ||
      (expectedSha256 != null &&
          hashing.sha256.convert(bytes).toString() != expectedSha256)) {
    throw const ResourceFailure(FailureKind.invalidImage);
  }
  final decoded = _decode(bytes, budget);
  if (frame < 0 || frame >= decoded.numFrames) {
    throw const ResourceFailure(FailureKind.invalidImage);
  }
  // Frame zero is also the animation container in image. Detach exactly the
  // requested frame before orientation/resize so a preview cannot become APNG.
  var image = bakeImageOrientation(decoded.getFrame(frame));
  if (image.hasPalette) image = image.convert(numChannels: 4);
  if (image.width > 480 || image.height > 480) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 480 : null,
      height: image.height > image.width ? 480 : null,
      interpolation: img.Interpolation.average,
    );
  }
  final result = img.encodePng(image, singleFrame: true);
  if (result.length > 2 * 1024 * 1024) {
    throw const ResourceFailure(FailureKind.resourceBudget);
  }
  return result;
}

String _format(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71) {
    return 'PNG';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'JPEG';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'WebP';
  }
  if (bytes.length >= 6 &&
      [
        'GIF87a',
        'GIF89a',
      ].contains(String.fromCharCodes(bytes.sublist(0, 6)))) {
    return 'GIF';
  }
  if (bytes.length >= 2 && bytes[0] == 66 && bytes[1] == 77) return 'BMP';
  // Explicit known alternatives are unsupported; arbitrary bytes are invalid.
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
    throw const ResourceFailure(FailureKind.unsupported);
  }
  if (img.findDecoderForData(bytes) != null) {
    throw const ResourceFailure(FailureKind.unsupported);
  }
  throw const ResourceFailure(FailureKind.invalidImage);
}

img.Image _decode(Uint8List bytes, int budget) {
  final format = _format(bytes);
  final pngOrientation = format == 'PNG' ? readPngOrientation(bytes) : null;
  try {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    // image 4.10.1 counts WebP animation records: a valid static WebP has
    // no animation table (numFrames == 0) but decodes as one image.
    final frameCount = info is img.WebPInfo && !info.hasAnimation
        ? 1
        : info?.numFrames ?? 0;
    if (info == null || info.width < 1 || info.height < 1 || frameCount < 1) {
      throw const ResourceFailure(FailureKind.invalidImage);
    }
    // Input + decode + validation intermediate allocation; reject before pixels.
    final estimate =
        bytes.length * 2 + info.width * info.height * 4 * frameCount * 3;
    if (estimate > budget) {
      throw const ResourceFailure(FailureKind.resourceBudget);
    }
    final result = decoder!.decode(bytes);
    if (result == null) throw const ResourceFailure(FailureKind.invalidImage);
    if (pngOrientation != null) {
      // image's PNG codec currently omits eXIf. Preserve the confirmed marker
      // on every exact frame so metadata and detached thumbnails agree.
      for (final frame in result.frames) {
        frame.exif.imageIfd.orientation = pngOrientation;
      }
    }
    return result;
  } on ResourceFailure {
    rethrow;
  } catch (_) {
    throw const ResourceFailure(FailureKind.invalidImage);
  }
}

Future<ImageMetadata> inspectImage(String path, int budget) async {
  final file = File(path);
  if (await file.length() > budget ~/ 4) {
    throw const ResourceFailure(FailureKind.resourceBudget);
  }
  final bytes = await file.readAsBytes();
  final format = _format(bytes);
  final decoded = _decode(bytes, budget);
  final orientation = decoded.exif.imageIfd.orientation ?? 1;
  return ImageMetadata(
    format: format,
    width: orientation >= 5 && orientation <= 8
        ? decoded.height
        : decoded.width,
    height: orientation >= 5 && orientation <= 8
        ? decoded.width
        : decoded.height,
    frameCount: decoded.numFrames,
    orientation: orientation,
  );
}
