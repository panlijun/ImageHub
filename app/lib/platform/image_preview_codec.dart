import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/platform_resource.dart';
import '../core/png_orientation.dart';

/// SDK decoding keeps animation frames sequential; no application frame cache.
/// These limits are candidate guards, rather than measured device guarantees.
Future<ui.Codec> decodeOriginalPreview(
  Uint8List bytes, {
  required int memoryBudgetBytes,
}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    if (memoryBudgetBytes <= 0 || bytes.length * 2 > memoryBudgetBytes) {
      throw const ResourceFailure(FailureKind.resourceBudget);
    }
    // The SDK handles JPEG/WebP orientation. PNG eXIf needs an explicit
    // transform, with CRC/TIFF parsing kept off the UI thread.
    final orientation = _isPng(bytes)
        ? await Isolate.run(() => readPngOrientation(bytes))
        : 1;
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width < 1 || descriptor.height < 1) {
      throw const ResourceFailure(FailureKind.invalidImage);
    }
    final scale = math.min(
      1.0,
      2048 / math.max(descriptor.width, descriptor.height),
    );
    final width = math.max(1, (descriptor.width * scale).round());
    final height = math.max(1, (descriptor.height * scale).round());
    // Encoded buffers, native canvas and current/next/display frame handles.
    final estimate =
        bytes.length * 2 +
        descriptor.width * descriptor.height * 4 * 2 +
        width * height * 4 * (orientation == 1 ? 3 : 5);
    if (estimate > memoryBudgetBytes) {
      throw const ResourceFailure(FailureKind.resourceBudget);
    }
    final codec = await descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: height,
    );
    // Keep native descriptor/buffer ownership until frame IO and codec disposal
    // have ended. Creating the codec alone does not decode its first frame.
    final owned = _OwnedPreviewCodec(codec, descriptor, buffer, orientation);
    descriptor = null;
    buffer = null;
    return owned;
  } on ResourceFailure {
    rethrow;
  } catch (_) {
    throw const ResourceFailure(FailureKind.invalidImage);
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

final class _OwnedPreviewCodec implements ui.Codec {
  _OwnedPreviewCodec(
    this._codec,
    this._descriptor,
    this._buffer,
    this._orientation,
  );
  final ui.Codec _codec;
  final ui.ImageDescriptor _descriptor;
  final ui.ImmutableBuffer _buffer;
  final int _orientation;
  bool _disposed = false;
  bool _nativeReleased = false;
  int _activeFrames = 0;
  @override
  int get frameCount => _codec.frameCount;
  @override
  int get repetitionCount => _codec.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() async {
    if (_disposed) throw const ResourceFailure(FailureKind.invalidImage);
    _activeFrames++;
    try {
      final source = await _codec.getNextFrame();
      final result = _orientation == 1
          ? source
          : await _orientFrame(source, _orientation);
      if (_disposed) {
        result.image.dispose();
        throw const ResourceFailure(FailureKind.invalidImage);
      }
      return result;
    } on ResourceFailure {
      rethrow;
    } catch (_) {
      throw const ResourceFailure(FailureKind.invalidImage);
    } finally {
      _activeFrames--;
      if (_disposed && _activeFrames == 0) _releaseNative();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Codec/descriptor/buffer must outlive any already accepted SDK decode or
    // Picture.toImage, even if a caller requests disposal while it is pending.
    if (_activeFrames == 0) _releaseNative();
  }

  void _releaseNative() {
    if (_nativeReleased) return;
    _nativeReleased = true;
    var failed = false;
    for (final release in [
      _codec.dispose,
      _descriptor.dispose,
      _buffer.dispose,
    ]) {
      try {
        release();
      } catch (_) {
        failed = true;
      }
    }
    if (failed) throw const ResourceFailure(FailureKind.invalidImage);
  }
}

bool _isPng(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

Future<ui.FrameInfo> _orientFrame(ui.FrameInfo source, int orientation) async {
  final image = source.image;
  final w = image.width.toDouble();
  final h = image.height.toDouble();
  // x' = a*x+c*y+tx, y' = b*x+d*y+ty. All coordinates are exact integers;
  // no resampling or trigonometric quarter-turn approximation is needed.
  final (a, b, c, d, tx, ty) = switch (orientation) {
    2 => (-1.0, 0.0, 0.0, 1.0, w, 0.0),
    3 => (-1.0, 0.0, 0.0, -1.0, w, h),
    4 => (1.0, 0.0, 0.0, -1.0, 0.0, h),
    5 => (0.0, 1.0, 1.0, 0.0, 0.0, 0.0),
    6 => (0.0, 1.0, -1.0, 0.0, h, 0.0),
    7 => (0.0, -1.0, -1.0, 0.0, h, w),
    8 => (0.0, -1.0, 1.0, 0.0, 0.0, w),
    _ => throw const ResourceFailure(FailureKind.invalidImage),
  };
  final recorder = ui.PictureRecorder();
  ui.Picture? picture;
  try {
    final canvas = ui.Canvas(recorder);
    canvas.transform(
      Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]),
    );
    canvas.drawImage(
      image,
      ui.Offset.zero,
      ui.Paint()
        ..filterQuality = ui.FilterQuality.none
        ..isAntiAlias = false
        ..blendMode = ui.BlendMode.src,
    );
    picture = recorder.endRecording();
    final transformed = await picture.toImage(
      orientation >= 5 ? image.height : image.width,
      orientation >= 5 ? image.width : image.height,
    );
    return _OrientedFrameInfo(transformed, source.duration);
  } finally {
    // A cancellation/dispose request is not proof that rasterization finished.
    // These resources stay owned until the actual toImage future has returned.
    try {
      if (recorder.isRecording) recorder.endRecording().dispose();
    } finally {
      try {
        picture?.dispose();
      } finally {
        image.dispose();
      }
    }
  }
}

final class _OrientedFrameInfo implements ui.FrameInfo {
  const _OrientedFrameInfo(this.image, this.duration);
  @override
  final ui.Image image;
  @override
  final Duration duration;
}
