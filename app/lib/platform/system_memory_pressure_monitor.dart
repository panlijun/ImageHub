import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/memory_pressure.dart';
import 'windows_memory_pressure_signal.dart';

typedef MemoryPressureTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer) callback,
);

/// Receives binding notifications and polls the nonblocking Windows system
/// signal. The two-second poll is a candidate observation interval.
final class SystemMemoryPressureMonitor
    with WidgetsBindingObserver
    implements MemoryPressureMonitor {
  SystemMemoryPressureMonitor({
    WidgetsBinding? binding,
    WindowsMemoryPressureSignal? Function()? nativeSignalFactory,
    MemoryPressureTimerFactory? timerFactory,
    this.pollInterval = const Duration(seconds: 2),
  }) : assert(pollInterval > Duration.zero),
       _binding = binding ?? WidgetsBinding.instance,
       _nativeSignalFactory = nativeSignalFactory ?? _systemSignal,
       _timerFactory = timerFactory ?? Timer.periodic;

  final WidgetsBinding _binding;
  final WindowsMemoryPressureSignal? Function() _nativeSignalFactory;
  final MemoryPressureTimerFactory _timerFactory;
  final Duration pollInterval;
  final _events = StreamController<void>.broadcast(sync: true);
  bool _started = false, _closed = false;
  bool _lastNativePressure = false;
  WindowsMemoryPressureSignal? _nativeSignal;
  WindowsMemoryPressureFailure? _nativeFailure;
  Timer? _timer;
  Future<void>? _closing;

  WindowsMemoryPressureFailure? get nativeFailure => _nativeFailure;

  static WindowsMemoryPressureSignal? _systemSignal() =>
      Platform.isWindows ? Kernel32MemoryPressureSignal() : null;

  @override
  Stream<void> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_closed || _started) return;
    _started = true;
    _binding.addObserver(this);
    try {
      _nativeSignal = _nativeSignalFactory();
    } catch (error) {
      _reportFailure(
        error is WindowsMemoryPressureFailure
            ? error
            : const WindowsMemoryPressureFailure(
                WindowsMemoryPressureFailureKind.creation,
              ),
      );
      return;
    }
    if (_nativeSignal == null) return;
    if (_closed) {
      _stopNativeAfterFailure();
      return;
    }
    _readNative();
    if (_closed || _nativeFailure != null) return;
    try {
      final timer = _timerFactory(pollInterval, (_) => _readNative());
      if (_closed || _nativeFailure != null) {
        timer.cancel();
      } else {
        _timer = timer;
      }
    } catch (error) {
      _reportFailure(
        error is WindowsMemoryPressureFailure
            ? error
            : const WindowsMemoryPressureFailure(
                WindowsMemoryPressureFailureKind.observation,
              ),
      );
      _stopNativeAfterFailure();
    }
  }

  void _readNative() {
    if (_closed ||
        !_started ||
        _nativeSignal == null ||
        _nativeFailure != null) {
      return;
    }
    try {
      final pressure = _nativeSignal!.read();
      if (_closed) return;
      final previous = _lastNativePressure;
      _lastNativePressure = pressure;
      if (pressure && !previous) _events.add(null);
    } catch (_) {
      _reportFailure(
        const WindowsMemoryPressureFailure(
          WindowsMemoryPressureFailureKind.query,
        ),
      );
      _stopNativeAfterFailure();
    }
  }

  void _reportFailure(WindowsMemoryPressureFailure failure) {
    _nativeFailure = failure;
    if (!_closed) _events.addError(failure);
  }

  void _releaseNative() {
    final signal = _nativeSignal;
    if (signal == null) return;
    signal.close();
    _nativeSignal = null;
  }

  void _stopNativeAfterFailure() {
    _timer?.cancel();
    _timer = null;
    try {
      _releaseNative();
    } catch (_) {
      _reportFailure(
        const WindowsMemoryPressureFailure(
          WindowsMemoryPressureFailureKind.close,
        ),
      );
    }
  }

  @override
  void didHaveMemoryPressure() {
    if (_started && !_closed) _events.add(null);
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = _close();
  }

  Future<void> _close() async {
    WindowsMemoryPressureFailure? failure;
    try {
      if (_started) _binding.removeObserver(this);
    } catch (_) {
      failure = const WindowsMemoryPressureFailure(
        WindowsMemoryPressureFailureKind.observation,
      );
    } finally {
      _started = false;
    }
    try {
      _timer?.cancel();
    } catch (_) {
      failure = const WindowsMemoryPressureFailure(
        WindowsMemoryPressureFailureKind.observation,
      );
    } finally {
      _timer = null;
    }
    try {
      _releaseNative();
    } catch (_) {
      failure = const WindowsMemoryPressureFailure(
        WindowsMemoryPressureFailureKind.close,
      );
    }
    try {
      await _events.close();
    } finally {
      if (_nativeSignal != null) _closing = null;
    }
    if (failure != null) {
      _nativeFailure = failure;
      throw failure;
    }
  }
}
