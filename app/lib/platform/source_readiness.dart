import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

enum SourceReadiness { ready, cloudPending, unknown }

/// Metadata-only source check. It never reads image bytes or requests download.
/// Android/iOS/macOS currently remain unknown pending platform acquisition APIs.
class SourceReadinessProbe {
  const SourceReadinessProbe();

  Future<SourceReadiness> check(String path) async {
    if (!Platform.isWindows || !_validWindowsPath(path)) {
      return SourceReadiness.unknown;
    }
    try {
      return await Isolate.run(() => _windowsReadiness(path));
    } catch (_) {
      return SourceReadiness.unknown;
    }
  }

  /// GetFileAttributesW reports a symbolic link's attributes, not its target.
  /// Reparse points without explicit recall/offline evidence cannot prove ready.
  static SourceReadiness classifyWindowsAttributes(int? attributes) {
    if (attributes == null ||
        attributes < 0 ||
        attributes >= 0xffffffff ||
        (attributes & 0x10) != 0) {
      return SourceReadiness.unknown;
    }
    if ((attributes & (0x1000 | 0x400000)) != 0) {
      return SourceReadiness.cloudPending;
    }
    // 0x40000 means EA for GetFileAttributesW. RECALL_ON_OPEN uses the same
    // value only in directory enumeration, so it is not recall proof here.
    // https://learn.microsoft.com/en-us/windows/win32/fileio/file-attribute-constants
    if ((attributes & (0x400 | 0x40000)) != 0) return SourceReadiness.unknown;
    return SourceReadiness.ready;
  }

  /// Bounded metadata walk for ordinary local drive paths. The injectable
  /// native-value functions also let tests prove an unsafe ancestor stops all
  /// subsequent queries, without accessing a real remote or reparse target.
  static SourceReadiness inspectWindowsPath(
    String path, {
    required int Function(String root) driveType,
    required int? Function(String path) attributes,
  }) {
    final ancestors = _windowsPathPrefixes(path);
    if (ancestors == null) return SourceReadiness.unknown;
    if (!const {2, 3, 5, 6}.contains(driveType(ancestors.first))) {
      return SourceReadiness.unknown;
    }
    for (final ancestor in ancestors.take(ancestors.length - 1)) {
      final flags = attributes(ancestor);
      if (flags == null ||
          flags < 0 ||
          flags >= 0xffffffff ||
          (flags & 0x10) == 0 ||
          (flags & 0x400) != 0) {
        return SourceReadiness.unknown;
      }
    }
    return classifyWindowsAttributes(attributes(ancestors.last));
  }
}

bool _validWindowsPath(String path) => _windowsPathPrefixes(path) != null;

List<String>? _windowsPathPrefixes(String path) {
  if (path.length < 3 ||
      path.length >= 32767 ||
      path.contains('\u0000') ||
      !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path)) {
    return null;
  }
  final normalized = path.replaceAll('/', '\\');
  final root = normalized.substring(0, 3);
  if (normalized.length == 3) return [root];
  final segments = normalized.substring(3).split('\\');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    return null;
  }
  final prefixes = <String>[root];
  var current = root;
  for (final segment in segments) {
    current = current.endsWith('\\')
        ? '$current$segment'
        : '$current\\$segment';
    prefixes.add(current);
  }
  return prefixes;
}

typedef _GetAttributesNative = Uint32 Function(Pointer<Utf16> path);
typedef _GetAttributes = int Function(Pointer<Utf16> path);

SourceReadiness _windowsReadiness(String path) {
  try {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final getAttributes = kernel
        .lookupFunction<_GetAttributesNative, _GetAttributes>(
          'GetFileAttributesW',
        );
    final getDriveType = kernel
        .lookupFunction<_GetAttributesNative, _GetAttributes>('GetDriveTypeW');
    return SourceReadinessProbe.inspectWindowsPath(
      path,
      driveType: (root) => _readWindowsValue(getDriveType, root),
      attributes: (candidate) => _readWindowsValue(getAttributes, candidate),
    );
  } catch (_) {
    return SourceReadiness.unknown;
  }
}

int _readWindowsValue(_GetAttributes function, String path) {
  final nativePath = path.toNativeUtf16(allocator: calloc);
  try {
    return function(nativePath);
  } finally {
    calloc.free(nativePath);
  }
}
