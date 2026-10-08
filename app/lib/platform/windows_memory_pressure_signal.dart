import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

abstract interface class WindowsMemoryPressureSignal {
  bool read();
  void close();
}

enum WindowsMemoryPressureFailureKind {
  unavailable,
  creation,
  query,
  close,
  closed,
  observation,
}

/// Fixed classifications only; no native error text or external information.
final class WindowsMemoryPressureFailure implements Exception {
  const WindowsMemoryPressureFailure(this.kind);
  final WindowsMemoryPressureFailureKind kind;

  @override
  String toString() => switch (kind) {
    WindowsMemoryPressureFailureKind.unavailable => '系统内存压力接口不可用。',
    WindowsMemoryPressureFailureKind.creation => '系统内存压力观察创建失败。',
    WindowsMemoryPressureFailureKind.query => '系统内存压力状态读取失败。',
    WindowsMemoryPressureFailureKind.close => '系统内存压力观察句柄关闭未确认。',
    WindowsMemoryPressureFailureKind.closed => '系统内存压力观察已关闭。',
    WindowsMemoryPressureFailureKind.observation => '系统内存压力定时观察失败。',
  };
}

/// Injectable Win32 calls; Query uses the API's BOOL output separately from its
/// BOOL return value. A failed query never becomes a low-memory observation.
abstract interface class WindowsMemoryPressureApi {
  Pointer<Void> createNotification(int notificationType);
  bool queryNotification(Pointer<Void> handle, Pointer<Int32> lowMemory);
  bool closeHandle(Pointer<Void> handle);
}

final class Kernel32MemoryPressureSignal
    implements WindowsMemoryPressureSignal {
  Kernel32MemoryPressureSignal({WindowsMemoryPressureApi? api}) {
    try {
      if (api == null && !Platform.isWindows) {
        throw const WindowsMemoryPressureFailure(
          WindowsMemoryPressureFailureKind.unavailable,
        );
      }
      _api = api ?? _Kernel32MemoryPressureApi();
    } catch (_) {
      throw const WindowsMemoryPressureFailure(
        WindowsMemoryPressureFailureKind.unavailable,
      );
    }
    try {
      final handle = _api.createNotification(
        0,
      ); // LowMemoryResourceNotification
      if (handle == nullptr) {
        throw const WindowsMemoryPressureFailure(
          WindowsMemoryPressureFailureKind.creation,
        );
      }
      // No fallible work occurs between receiving and retaining this handle.
      _handle = handle;
    } catch (_) {
      throw const WindowsMemoryPressureFailure(
        WindowsMemoryPressureFailureKind.creation,
      );
    }
  }

  late final WindowsMemoryPressureApi _api;
  Pointer<Void>? _handle;

  @override
  bool read() {
    final handle = _handle;
    if (handle == null) {
      throw const WindowsMemoryPressureFailure(
        WindowsMemoryPressureFailureKind.closed,
      );
    }
    Pointer<Int32>? output;
    try {
      output = calloc<Int32>();
      if (!_api.queryNotification(handle, output)) {
        throw const WindowsMemoryPressureFailure(
          WindowsMemoryPressureFailureKind.query,
        );
      }
      return output.value != 0;
    } catch (_) {
      throw const WindowsMemoryPressureFailure(
        WindowsMemoryPressureFailureKind.query,
      );
    } finally {
      if (output != null) calloc.free(output);
    }
  }

  @override
  void close() {
    final handle = _handle;
    if (handle == null) return;
    try {
      if (!_api.closeHandle(handle)) {
        throw const WindowsMemoryPressureFailure(
          WindowsMemoryPressureFailureKind.close,
        );
      }
      _handle = null;
    } catch (_) {
      // Keep ownership on failure so the caller can retry. Timer cancellation
      // is not evidence that CloseHandle succeeded.
      throw const WindowsMemoryPressureFailure(
        WindowsMemoryPressureFailureKind.close,
      );
    }
  }
}

typedef _CreateNative = Pointer<Void> Function(Int32);
typedef _Create = Pointer<Void> Function(int);
typedef _QueryNative = Int32 Function(Pointer<Void>, Pointer<Int32>);
typedef _Query = int Function(Pointer<Void>, Pointer<Int32>);
typedef _CloseNative = Int32 Function(Pointer<Void>);
typedef _Close = int Function(Pointer<Void>);

final class _Kernel32MemoryPressureApi implements WindowsMemoryPressureApi {
  _Kernel32MemoryPressureApi() {
    final kernel = DynamicLibrary.open('kernel32.dll');
    // Resolve everything before allocating any native notification handle.
    _create = kernel.lookupFunction<_CreateNative, _Create>(
      'CreateMemoryResourceNotification',
    );
    _query = kernel.lookupFunction<_QueryNative, _Query>(
      'QueryMemoryResourceNotification',
    );
    _close = kernel.lookupFunction<_CloseNative, _Close>('CloseHandle');
  }

  late final _Create _create;
  late final _Query _query;
  late final _Close _close;

  @override
  Pointer<Void> createNotification(int notificationType) =>
      _create(notificationType);
  @override
  bool queryNotification(Pointer<Void> handle, Pointer<Int32> lowMemory) =>
      _query(handle, lowMemory) != 0;
  @override
  bool closeHandle(Pointer<Void> handle) => _close(handle) != 0;
}
