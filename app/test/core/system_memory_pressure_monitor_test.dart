import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/platform/system_memory_pressure_monitor.dart';
import 'package:imagehost/platform/windows_memory_pressure_signal.dart';

final class _Signal implements WindowsMemoryPressureSignal {
  bool pressure = false;
  int reads = 0, closes = 0;
  bool failRead = false, failClose = false;
  @override
  bool read() {
    reads++;
    if (failRead) throw StateError('secret-native-query');
    return pressure;
  }

  @override
  void close() {
    closes++;
    if (failClose) throw StateError('secret-native-close');
  }
}

final class _Timer implements Timer {
  _Timer(this.callback);
  final void Function(Timer) callback;
  bool cancelled = false;
  int _tick = 0;
  // Deliberately permit a queued callback even after cancel to check isolation.
  void fire() {
    _tick++;
    callback(this);
  }

  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => _tick;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('NFR-003 UT-101 Windows immediate read, native edges and repeated states preserve binding events', () async {
    final signal = _Signal();
    late _Timer timer;
    var events = 0, factories = 0;
    final monitor = SystemMemoryPressureMonitor(
      binding: binding,
      nativeSignalFactory: () {
        factories++;
        return signal;
      },
      pollInterval: const Duration(milliseconds: 37),
      timerFactory: (interval, callback) {
        expect(interval, const Duration(milliseconds: 37));
        return timer = _Timer(callback);
      },
    );
    monitor.events.listen((_) => events++);
    await monitor.start();
    await monitor.start();
    expect(signal.reads, 1);
    expect(factories, 1);
    expect(events, 0);
    signal.pressure = true;
    timer.fire();
    timer.fire();
    expect(events, 1);
    signal.pressure = false;
    timer.fire();
    signal.pressure = true;
    timer.fire();
    expect(events, 2);
    binding.handleMemoryPressure();
    expect(events, 3);
    await monitor.close();
    expect(timer.cancelled, true);
    expect(signal.closes, 1);
  });

  test('NFR-003 UT-101 initial true emits once after subscription; close isolates late timer and binding callbacks', () async {
    final signal = _Signal()..pressure = true;
    late _Timer timer;
    var events = 0, done = false;
    final monitor = SystemMemoryPressureMonitor(
      binding: binding,
      nativeSignalFactory: () => signal,
      timerFactory: (_, callback) => timer = _Timer(callback),
    );
    monitor.events.listen((_) => events++, onDone: () => done = true);
    await monitor.start();
    expect(events, 1);
    timer.fire();
    expect(events, 1);
    final reads = signal.reads;
    await monitor.close();
    await monitor.close();
    await monitor.start();
    timer.fire();
    binding.handleMemoryPressure();
    monitor.didHaveMemoryPressure();
    expect(signal.reads, reads);
    expect(signal.closes, 1);
    expect(events, 1);
    expect(done, true);
  });

  test('NFR-003 UT-101 factory failure has fixed feedback and cannot invent native pressure', () async {
    final errors = <Object>[];
    var events = 0, timers = 0;
    final monitor = SystemMemoryPressureMonitor(
      binding: binding,
      nativeSignalFactory: () => throw StateError('secret-native-create'),
      timerFactory: (_, callback) {
        timers++;
        return _Timer(callback);
      },
    );
    monitor.events.listen((_) => events++, onError: errors.add);
    await monitor.start();
    expect(events, 0);
    expect(timers, 0);
    expect(errors, hasLength(1));
    expect(
      monitor.nativeFailure?.kind,
      WindowsMemoryPressureFailureKind.creation,
    );
    expect(errors.single.toString(), '系统内存压力观察创建失败。');
    binding.handleMemoryPressure();
    expect(events, 1);
    await monitor.close();
  });

  test('NFR-003 UT-101 failed immediate query closes its handle and reports no pressure', () async {
    final signal = _Signal()..failRead = true;
    final errors = <Object>[];
    var events = 0;
    final monitor = SystemMemoryPressureMonitor(
      binding: binding,
      nativeSignalFactory: () => signal,
      timerFactory: (_, _) => throw StateError('must not create timer'),
    );
    monitor.events.listen((_) => events++, onError: errors.add);
    await monitor.start();
    expect(signal.reads, 1);
    expect(signal.closes, 1);
    expect(events, 0);
    expect(monitor.nativeFailure?.kind, WindowsMemoryPressureFailureKind.query);
    expect(errors.single.toString(), '系统内存压力状态读取失败。');
    await monitor.close();
    expect(signal.closes, 1);
  });

  test('NFR-003 UT-101 timer creation failure releases an already-created native handle', () async {
    final signal = _Signal();
    final errors = <Object>[];
    final monitor = SystemMemoryPressureMonitor(
      binding: binding,
      nativeSignalFactory: () => signal,
      timerFactory: (_, _) => throw StateError('secret-timer'),
    );
    monitor.events.listen((_) => fail('no pressure'), onError: errors.add);
    await monitor.start();
    expect(signal.reads, 1);
    expect(signal.closes, 1);
    expect(errors.single.toString(), '系统内存压力定时观察失败。');
    await monitor.close();
  });

  test('NFR-003 UT-101 close failure still completes stream and detaches timer/binding; explicit retry retains handle', () async {
    final signal = _Signal()..failClose = true;
    late _Timer timer;
    var done = false, events = 0;
    final monitor = SystemMemoryPressureMonitor(
      binding: binding,
      nativeSignalFactory: () => signal,
      timerFactory: (_, callback) => timer = _Timer(callback),
    );
    monitor.events.listen((_) => events++, onDone: () => done = true);
    await monitor.start();
    await expectLater(
      monitor.close(),
      throwsA(
        isA<WindowsMemoryPressureFailure>().having(
          (error) => error.kind,
          'kind',
          WindowsMemoryPressureFailureKind.close,
        ),
      ),
    );
    expect(done, true);
    expect(timer.cancelled, true);
    expect(signal.closes, 1);
    timer.fire();
    binding.handleMemoryPressure();
    expect(events, 0);
    expect(signal.reads, 1);
    expect(monitor.nativeFailure?.toString(), '系统内存压力观察句柄关闭未确认。');
    signal.failClose = false;
    await monitor.close();
    await monitor.close();
    expect(signal.closes, 2);
  });

  test('NFR-003 UT-101 timer factory callback failure cancels returned timer and retains failed close for retry', () async {
    final signal = _Signal()..failClose = true;
    late _Timer timer;
    final errors = <Object>[];
    final monitor = SystemMemoryPressureMonitor(
      binding: binding,
      nativeSignalFactory: () => signal,
      timerFactory: (_, callback) {
        timer = _Timer(callback);
        signal.failRead = true;
        timer.fire();
        return timer;
      },
    );
    monitor.events.listen((_) => fail('no pressure'), onError: errors.add);
    await monitor.start();
    expect(timer.cancelled, true);
    expect(signal.closes, 1);
    expect(errors, hasLength(2));
    expect(
      (errors[0] as WindowsMemoryPressureFailure).kind,
      WindowsMemoryPressureFailureKind.query,
    );
    expect(
      (errors[1] as WindowsMemoryPressureFailure).kind,
      WindowsMemoryPressureFailureKind.close,
    );
    timer.fire();
    expect(signal.reads, 2);
    signal.failClose = false;
    await monitor.close();
    expect(signal.closes, 2);
  });

  test('NFR-003 UT-101 periodic query failure stops late polling and closes native handle', () async {
    final signal = _Signal();
    late _Timer timer;
    final errors = <Object>[];
    var events = 0;
    final monitor = SystemMemoryPressureMonitor(
      binding: binding,
      nativeSignalFactory: () => signal,
      timerFactory: (_, callback) => timer = _Timer(callback),
    );
    monitor.events.listen((_) => events++, onError: errors.add);
    await monitor.start();
    signal.failRead = true;
    timer.fire();
    timer.fire();
    expect(events, 0);
    expect(errors, hasLength(1));
    expect(timer.cancelled, true);
    expect(signal.reads, 2);
    expect(signal.closes, 1);
    await monitor.close();
  });
}
