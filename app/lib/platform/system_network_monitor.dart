import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/network_state.dart';

/// Observes local system routes only. It never probes an external host.
final class SystemNetworkMonitor
    with WidgetsBindingObserver
    implements NetworkMonitor {
  SystemNetworkMonitor({
    Duration readTimeout = const Duration(seconds: 3),
    BinaryMessenger? binaryMessenger,
    WidgetsBinding? binding,
    TargetPlatform? platform,
  }) : _timeout = readTimeout,
       _messenger = binaryMessenger,
       _binding = binding ?? WidgetsBinding.instance,
       _platform = platform ?? defaultTargetPlatform {
    if (readTimeout <= Duration.zero) {
      throw ArgumentError('网络观察等待时间必须为正数。');
    }
  }

  final Duration _timeout;
  final BinaryMessenger? _messenger;
  final WidgetsBinding _binding;
  final TargetPlatform _platform;
  final _changes = StreamController<NetworkSnapshot>.broadcast();
  NetworkSnapshot _current = const NetworkSnapshot.unknown();
  StreamSubscription<Object?>? _subscription;
  _NetworkEvents? _events;
  Future<void>? _start;
  Future<void>? _close;
  int _revision = 0;
  int _generation = 0;
  bool _closed = false;
  bool _foreground = true;

  @override
  NetworkSnapshot get current => _current;

  @override
  Stream<NetworkSnapshot> get changes => _changes.stream;

  @override
  Future<void> start() {
    if (_closed) return Future<void>.value();
    return _start ??= _startObservation();
  }

  Future<void> _startObservation() async {
    _binding.addObserver(this);
    _foreground = _isForeground(_binding.lifecycleState);
    await _refresh();
  }

  @override
  Future<void> refresh() {
    if (_closed) return Future<void>.value();
    if (_start == null) return start();
    return _refresh();
  }

  Future<bool> _ensureSubscription() async {
    if (_closed) return false;
    if (_subscription != null) return _events!.ready;
    final previous = _events;
    if (previous != null) await previous.close();
    if (_closed) return false;
    if (_subscription != null) return _events!.ready;
    final generation = ++_generation;
    late final _NetworkEvents events;
    events = _NetworkEvents(
      _messenger ?? ServicesBinding.instance.defaultBinaryMessenger,
      _timeout,
      () => identical(_events, events),
    );
    _events = events;
    _subscription = events.stream.listen(
      (value) {
        if (_closed || generation != _generation) return;
        ++_revision;
        _publish(_foreground ? _parse(value) : const NetworkSnapshot.unknown());
      },
      onError: (Object _, StackTrace _) {
        if (_closed || generation != _generation) return;
        ++_revision;
        _publish(const NetworkSnapshot.unknown());
      },
      onDone: () {
        if (_closed || generation != _generation) return;
        _subscription = null;
        ++_revision;
        _publish(const NetworkSnapshot.unknown());
      },
    );
    return events.ready;
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    if (!_foreground) {
      _publish(const NetworkSnapshot.unknown());
      return;
    }
    if (!await _ensureSubscription()) return;
    if (_closed || !_foreground || revision != _revision) return;
    NetworkSnapshot snapshot;
    try {
      final result = await MethodChannel(
        'io.imagehost/network',
        const StandardMethodCodec(),
        _messenger,
      ).invokeMethod<Object?>('read').timeout(_timeout);
      snapshot = _parse(result);
    } catch (_) {
      // No raw platform exception or object is displayed or logged.
      snapshot = const NetworkSnapshot.unknown();
    }
    if (!_closed && _foreground && revision == _revision) _publish(snapshot);
  }

  NetworkSnapshot _parse(Object? value) {
    try {
      return NetworkSnapshot.fromPlatform(value);
    } catch (_) {
      return const NetworkSnapshot.unknown();
    }
  }

  void _publish(NetworkSnapshot snapshot) {
    if (_closed || snapshot == _current) return;
    _current = snapshot;
    _changes.add(snapshot);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed) return;
    _foreground = _isForeground(state);
    if (_foreground) {
      unawaited(refresh());
    } else {
      ++_revision;
      _publish(const NetworkSnapshot.unknown());
    }
  }

  bool _isForeground(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      (state == AppLifecycleState.inactive &&
          (_platform == TargetPlatform.windows ||
              _platform == TargetPlatform.macOS));

  @override
  Future<void> close() => _close ??= _closeObservation();

  Future<void> _closeObservation() async {
    _closed = true;
    ++_revision;
    ++_generation;
    _binding.removeObserver(this);
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    // A bounded native cancel is awaited; a missing/hung backend cannot block
    // library shutdown. Local handlers are already detached before this wait.
    await _events?.close();
    await _changes.close();
  }
}

/// Flutter's EventChannel reports listen/cancel failures through FlutterError,
/// including raw platform exception text. This local implementation preserves
/// its StandardMethodCodec protocol, but fails closed without that error sink.
final class _NetworkEvents {
  _NetworkEvents(this._messenger, this._timeout, this._ownsChannel) {
    _controller = StreamController<Object?>.broadcast(
      onListen: _listen,
      onCancel: () => unawaited(close()),
    );
  }

  static const _name = 'io.imagehost/network_changes';
  static const _codec = StandardMethodCodec();
  final BinaryMessenger _messenger;
  final Duration _timeout;
  final bool Function() _ownsChannel;
  late final StreamController<Object?> _controller;
  final _ready = Completer<bool>();
  Future<void>? _close;
  bool _ended = false;
  bool _active = false;
  Object? _pending;
  bool _hasPending = false;

  Stream<Object?> get stream => _controller.stream;
  Future<bool> get ready async => await _ready.future && !_ended;

  void _listen() {
    _messenger.setMessageHandler(_name, _onMessage);
    unawaited(_activate());
  }

  Future<void> _activate() async {
    try {
      final request = MethodChannel(
        _name,
        _codec,
        _messenger,
      ).invokeMethod<void>('listen');
      // A backend reply arriving after timeout/close cannot revive listening.
      unawaited(
        request.then<void>((_) {
          if (_ended && _ownsChannel()) unawaited(_cancelNative());
        }, onError: (Object _, StackTrace _) {}),
      );
      await request.timeout(_timeout);
      if (_ended) return;
      _active = true;
      if (_hasPending) {
        _controller.add(_pending);
        _pending = null;
        _hasPending = false;
      }
      _ready.complete(true);
    } catch (_) {
      if (!_ended) {
        if (!_ready.isCompleted) _ready.complete(false);
        _controller.addError(const _NetworkObservationUnavailable());
        unawaited(close());
      }
    }
  }

  Future<ByteData?> _onMessage(ByteData? message) async {
    if (_ended) return null;
    if (message == null) {
      unawaited(close());
      return null;
    }
    try {
      final value = _codec.decodeEnvelope(message);
      if (_active) {
        _controller.add(value);
      } else {
        // Only the latest initial observation matters. Nothing is eligible
        // until the native listen handshake has completed successfully.
        _pending = value;
        _hasPending = true;
      }
    } catch (_) {
      _controller.addError(const _NetworkObservationUnavailable());
      unawaited(close());
    }
    return null;
  }

  Future<void> _cancelNative() async {
    try {
      await MethodChannel(
        _name,
        _codec,
        _messenger,
      ).invokeMethod<void>('cancel').timeout(_timeout);
    } catch (_) {
      // System observation has no data/file IO; keep local listening detached.
    }
  }

  Future<void> close() => _close ??= _finish();

  Future<void> _finish() async {
    _ended = true;
    if (!_ready.isCompleted) _ready.complete(false);
    _pending = null;
    _hasPending = false;
    _messenger.setMessageHandler(_name, null);
    // Publish termination promptly, even if native cancel has not replied.
    unawaited(_controller.close());
    await _cancelNative();
  }
}

final class _NetworkObservationUnavailable implements Exception {
  const _NetworkObservationUnavailable();
}
