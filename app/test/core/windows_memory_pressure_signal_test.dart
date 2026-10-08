import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/platform/windows_memory_pressure_signal.dart';

final class _Api implements WindowsMemoryPressureApi {
  Pointer<Void> handle = Pointer<Void>.fromAddress(73);
  final createdTypes = <int>[];
  final queried = <Pointer<Void>>[];
  final closed = <Pointer<Void>>[];
  bool querySuccess = true, closeSuccess = true;
  int state = 0;
  Object? queryError;

  @override
  Pointer<Void> createNotification(int type) {
    createdTypes.add(type);
    return handle;
  }

  @override
  bool queryNotification(Pointer<Void> handle, Pointer<Int32> lowMemory) {
    queried.add(handle);
    if (queryError != null) throw queryError!;
    lowMemory.value = state;
    return querySuccess;
  }

  @override
  bool closeHandle(Pointer<Void> handle) {
    closed.add(handle);
    return closeSuccess;
  }
}

Matcher _failure(WindowsMemoryPressureFailureKind kind) =>
    isA<WindowsMemoryPressureFailure>().having(
      (error) => error.kind,
      'kind',
      kind,
    );

void main() {
  test('NFR-003 UT-101 Windows create zero never adopts or closes an absent handle', () {
    final api = _Api()..handle = nullptr;
    expect(
      () => Kernel32MemoryPressureSignal(api: api),
      throwsA(_failure(WindowsMemoryPressureFailureKind.creation)),
    );
    expect(api.createdTypes, [0]);
    expect(api.queried, isEmpty);
    expect(api.closed, isEmpty);
  });

  test('NFR-003 UT-101 Win32 query BOOL result and output BOOL have independent meaning', () {
    final api = _Api();
    final signal = Kernel32MemoryPressureSignal(api: api);
    expect(signal.read(), false);
    api.state = -1;
    expect(signal.read(), true);
    api.querySuccess = false;
    expect(
      signal.read,
      throwsA(_failure(WindowsMemoryPressureFailureKind.query)),
    );
    api.querySuccess = true;
    api.queryError = StateError('native-secret-and-path');
    try {
      signal.read();
      fail('query error must reject the observation');
    } on WindowsMemoryPressureFailure catch (error) {
      expect(error.kind, WindowsMemoryPressureFailureKind.query);
      expect(error.toString(), '系统内存压力状态读取失败。');
      expect(error.toString(), isNot(contains('native-secret')));
    }
    signal.close();
    expect(api.closed, [api.handle]);
  });

  test('NFR-003 UT-101 CloseHandle zero retains ownership for explicit retry and success is idempotent', () {
    final api = _Api()..closeSuccess = false;
    final signal = Kernel32MemoryPressureSignal(api: api);
    expect(
      signal.close,
      throwsA(_failure(WindowsMemoryPressureFailureKind.close)),
    );
    api.closeSuccess = true;
    signal.close();
    signal.close();
    expect(api.closed, [api.handle, api.handle]);
    expect(
      signal.read,
      throwsA(_failure(WindowsMemoryPressureFailureKind.closed)),
    );
  });

  test('NFR-003 Windows host kernel32 nonblocking read and CloseHandle sub-contract without inducing pressure', () {
    final signal = Kernel32MemoryPressureSignal();
    try {
      expect(signal.read(), isA<bool>());
      expect(signal.read(), isA<bool>());
    } finally {
      signal.close();
    }
    signal.close();
    expect(
      signal.read,
      throwsA(_failure(WindowsMemoryPressureFailureKind.closed)),
    );
  }, skip: !Platform.isWindows);
}
