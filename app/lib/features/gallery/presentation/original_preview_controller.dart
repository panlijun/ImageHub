import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../core/platform_resource.dart';
import '../../../platform/image_preview_codec.dart';
import '../application/original_preview_reader.dart';

typedef OriginalPreviewLoader = Future<OriginalPreviewInput> Function(
  CancellationToken cancellation,
);
typedef OriginalPreviewCodecFactory = Future<ui.Codec> Function(
  OriginalPreviewInput input,
);

/// Owns one displayed frame and at most one pending frame. Pausing preserves
/// the displayed frame even if a native getNextFrame call is already running.
class OriginalPreviewController extends ChangeNotifier {
  OriginalPreviewController({
    required this.loader,
    OriginalPreviewCodecFactory? codecFactory,
  }) : _codecFactory = codecFactory ?? _decode;

  static Future<ui.Codec> _decode(OriginalPreviewInput input) =>
      decodeOriginalPreview(
        input.bytes,
        memoryBudgetBytes: input.memoryBudgetBytes,
      );

  final OriginalPreviewLoader loader;
  final OriginalPreviewCodecFactory _codecFactory;
  final CancellationToken _cancellation = CancellationToken();
  OriginalPreviewInput? _input;
  ui.Codec? _codec;
  ui.Image? _image;
  ui.FrameInfo? _pendingFrame;
  Duration _duration = const Duration(milliseconds: 100);
  Timer? _timer;
  Future<void>? _work, _closing;
  bool _started = false, _closed = false, _foreground = true;
  bool _requestedPlaying = false, _busy = false, _finished = false;
  bool _restarting = false;
  int _frameIndex = 0, _repeatsUsed = 0;
  String? _error;

  ui.Image? get image => _image;
  int get frameIndex => _frameIndex;
  int get frameCount => _codec?.frameCount ?? 0;
  bool get loading => !_closed && _image == null && _error == null;
  bool get playing => !_closed && _requestedPlaying && _foreground;
  bool get animated => frameCount > 1;
  String? get error => _error;
  bool get closed => _closed;

  Future<void> start() {
    if (_started || _closed) return _work ?? Future.value();
    _started = true;
    return _work = _open();
  }

  Future<void> _open() async {
    _busy = true;
    try {
      _input = await loader(_cancellation);
      if (_closed) return;
      _codec = await _codecFactory(_input!);
      if (_closed) return;
      if (_codec!.frameCount < 1) {
        throw const ResourceFailure(FailureKind.invalidImage);
      }
      final first = await _codec!.getNextFrame();
      if (_closed) {
        first.image.dispose();
        return;
      }
      _show(first);
      _requestedPlaying = animated;
      notifyListeners();
    } catch (failure) {
      _fail(failure);
    } finally {
      _busy = false;
      _schedule();
    }
  }

  void _show(ui.FrameInfo frame) {
    final previous = _image;
    _image = frame.image;
    // A zero duration cannot create an unbounded immediate decode loop.
    _duration = frame.duration < const Duration(milliseconds: 10)
        ? const Duration(milliseconds: 10)
        : frame.duration;
    previous?.dispose();
  }

  void pause() {
    if (_closed) return;
    _requestedPlaying = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void play() {
    if (_closed || !animated || _error != null) return;
    if (_finished) {
      _restarting = true;
      _finished = false;
      _repeatsUsed = 0;
    }
    _requestedPlaying = true;
    _schedule();
    notifyListeners();
  }

  void setForeground(bool foreground) {
    if (_closed || foreground == _foreground) return;
    _foreground = foreground;
    _timer?.cancel();
    _timer = null;
    _schedule();
    notifyListeners();
  }

  void _schedule() {
    if (!playing || !animated || _busy || _timer != null || _error != null) {
      return;
    }
    _timer = Timer(_duration, () {
      _timer = null;
      _work = _advance();
    });
  }

  Future<void> _advance() async {
    if (!playing || _busy || _codec == null) return;
    if (_frameIndex == frameCount - 1 &&
        !_restarting &&
        _codec!.repetitionCount >= 0 &&
        _repeatsUsed >= _codec!.repetitionCount) {
      _requestedPlaying = false;
      _finished = true;
      notifyListeners();
      return;
    }
    _busy = true;
    try {
      final next = _pendingFrame ?? await _codec!.getNextFrame();
      _pendingFrame = null;
      if (_closed) {
        next.image.dispose();
      } else if (!playing) {
        _pendingFrame = next;
      } else {
        final index = (_frameIndex + 1) % frameCount;
        if (index == 0) {
          if (!_restarting) _repeatsUsed++;
          _restarting = false;
        }
        _frameIndex = index;
        _show(next);
        notifyListeners();
      }
    } catch (failure) {
      _fail(failure);
    } finally {
      _busy = false;
      _schedule();
    }
  }

  void _fail(Object failure) {
    if (_closed) return;
    _timer?.cancel();
    _timer = null;
    _requestedPlaying = false;
    _error =
        failure is ResourceFailure && failure.kind == FailureKind.resourceBudget
        ? '图片超出当前预览内存预算；永久副本保持不变。'
        : '无法安全读取或解码本机副本，请检查副本后重试。';
    notifyListeners();
  }

  /// A cancelled request or popped route is not proof that native IO has ended.
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _requestedPlaying = false;
    _cancellation.cancel();
    _timer?.cancel();
    _timer = null;
    return _closing = _drain();
  }

  Future<void> _drain() async {
    try {
      await _work;
    } finally {
      try {
        _pendingFrame?.image.dispose();
        _pendingFrame = null;
        _image?.dispose();
        _image = null;
        _codec?.dispose();
        _codec = null;
      } finally {
        _input?.release();
        _input = null;
      }
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
