import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../integration_test/support/backup_interop_harness.dart';

typedef _FreeNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef _FreeDart = int Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef _MoveNative = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _MoveDart = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _ErrorNative = Uint32 Function();
typedef _ErrorDart = int Function();
typedef _VolumeNative = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _VolumeDart = int Function(Pointer<Utf16>, Pointer<Utf16>, int);

/// Test host only; identical Win32 publication flags to the production runner.
final class WindowsStorageCapacity {
  WindowsStorageCapacity() {
    interopRequire(Platform.isWindows, 'windows-host-required');
    final library = DynamicLibrary.open('kernel32.dll');
    _free = library.lookupFunction<_FreeNative, _FreeDart>(
      'GetDiskFreeSpaceExW',
    );
    _move = library.lookupFunction<_MoveNative, _MoveDart>('MoveFileExW');
    _error = library.lookupFunction<_ErrorNative, _ErrorDart>('GetLastError');
    _volumePath = library.lookupFunction<_VolumeNative, _VolumeDart>(
      'GetVolumePathNameW',
    );
    _volumeName = library.lookupFunction<_VolumeNative, _VolumeDart>(
      'GetVolumeNameForVolumeMountPointW',
    );
  }
  late final _FreeDart _free;
  late final _MoveDart _move;
  late final _ErrorDart _error;
  late final _VolumeDart _volumePath;
  late final _VolumeDart _volumeName;
  String _volume(String path) {
    final input = path.toNativeUtf16();
    final mount = calloc<Uint16>(32768).cast<Utf16>();
    final name = calloc<Uint16>(128).cast<Utf16>();
    try {
      if (_volumePath(input, mount, 32768) == 0 ||
          _volumeName(mount, name, 128) == 0) {
        throw StateError('Win32 volume verification failed: ${_error()}');
      }
      return name.toDartString().toLowerCase();
    } finally {
      calloc.free(input);
      calloc.free(mount);
      calloc.free(name);
    }
  }

  Future<int> availableBytes(Directory directory) async {
    final path = directory.absolute.path.toNativeUtf16();
    final available = calloc<Uint64>();
    final total = calloc<Uint64>();
    final free = calloc<Uint64>();
    try {
      if (_free(path, available, total, free) == 0) {
        throw StateError('Win32 capacity failed: ${_error()}');
      }
      return available.value;
    } finally {
      calloc.free(path);
      calloc.free(available);
      calloc.free(total);
      calloc.free(free);
    }
  }

  Future<bool> publishExclusive(File source, File destination) async {
    await requireNoLinks(source.path, file: true);
    await requireNoLinks(p.dirname(destination.path));
    interopRequire(
      _volume(source.absolute.path) ==
          _volume(destination.parent.absolute.path),
      'same-volume-required',
    );
    final from = source.absolute.path.toNativeUtf16();
    final to = destination.absolute.path.toNativeUtf16();
    try {
      if (_move(from, to, 0) != 0) return true;
      final error = _error();
      if (error == 80 || error == 183) return false;
      throw StateError('Win32 exclusive publication failed: $error');
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
  }
}

Future<void> requireNoLinks(String path, {bool file = false}) async {
  var current = p.normalize(p.absolute(path));
  var expected = file
      ? FileSystemEntityType.file
      : FileSystemEntityType.directory;
  while (true) {
    interopRequire(
      await FileSystemEntity.type(current, followLinks: false) == expected,
      'ordinary-path-required',
    );
    if (expected == FileSystemEntityType.directory) {
      interopRequire(
        p.equals(await Directory(current).resolveSymbolicLinks(), current),
        'canonical-path-required',
      );
    }
    final parent = p.dirname(current);
    if (parent == current) break;
    current = parent;
    expected = FileSystemEntityType.directory;
  }
}

final class OwnedBackupWorkspace {
  OwnedBackupWorkspace._(this.directory, this.token);
  final Directory directory;
  final String token;
  static Future<OwnedBackupWorkspace> create(String target) async {
    final workspace = p.normalize(
      p.absolute(p.join(Directory.current.path, '..')),
    );
    interopRequire(
      await File(p.join(workspace, 'AGENTS.md')).exists() &&
          await File(p.join(workspace, 'app', 'pubspec.yaml')).exists(),
      'run-from-app-required',
    );
    final selected = p.normalize(p.absolute(target));
    interopRequire(
      p.isWithin(workspace, selected) &&
          await FileSystemEntity.type(selected, followLinks: false) ==
              FileSystemEntityType.notFound,
      'new-workspace-child-required',
    );
    await requireNoLinks(p.dirname(selected));
    final directory = await Directory(selected).create();
    final token = const Uuid().v4();
    final marker = File(p.join(directory.path, '.backup-verification-owner'));
    await marker.create(exclusive: true);
    await marker.writeAsString(token, flush: true);
    await requireNoLinks(directory.path);
    return OwnedBackupWorkspace._(directory, token);
  }

  /// Call only after every library, snapshot and IO future has really ended.
  Future<void> removeAfterSuccess() async {
    await requireNoLinks(directory.path);
    final marker = File(p.join(directory.path, '.backup-verification-owner'));
    await requireNoLinks(marker.path, file: true);
    interopRequire(await marker.readAsString() == token, 'workspace-owner');
    await for (final item in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      interopRequire(p.isWithin(directory.path, item.path), 'cleanup-boundary');
      final type = await FileSystemEntity.type(item.path, followLinks: false);
      interopRequire(
        type == FileSystemEntityType.file ||
            type == FileSystemEntityType.directory,
        'cleanup-ordinary-item',
      );
      await requireNoLinks(item.path, file: type == FileSystemEntityType.file);
    }
    await directory.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _readExpectation(String path) async {
  final file = File(path);
  await requireNoLinks(file.path, file: true);
  interopRequire(await file.length() <= 128 * 1024, 'bounded-expectation-json');
  final expected = Map<String, Object?>.from(
    jsonDecode(await file.readAsString()) as Map,
  );
  validateInteropExpectation(expected);
  return expected;
}

Future<void> _writeEmbeddedTest(
  String targetPath,
  List<String> payloads, {
  required bool matrix,
}) async {
  validateInteropMatrix(payloads);
  final target = File(p.absolute(targetPath));
  final appRoot = p.normalize(Directory.current.absolute.path);
  interopRequire(
    (p.isWithin(p.join(appRoot, 'integration_test'), target.path) ||
            p.isWithin(p.join(appRoot, 'build'), target.path)) &&
        p.extension(target.path) == '.dart',
    'test-only-embedding',
  );
  interopRequire(
    await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.notFound,
    'new-test-file-required',
  );
  await requireNoLinks(target.parent.path);
  final test = p.absolute('integration_test/backup_interop_test.dart');
  final import = p
      .relative(test, from: target.parent.path)
      .split(p.separator)
      .join('/');
  final invocation = matrix
      ? 'interop.runBackupInteropMatrix(${jsonEncode(payloads)}, exportCurrent: true)'
      : 'interop.runEmbeddedBackupInterop(${jsonEncode(payloads.single)})';
  await target.create(exclusive: true);
  await target.writeAsString(
    'import ${jsonEncode(import)} as interop;\nvoid main() => $invocation;\n',
    flush: true,
  );
  stdout.writeln(
    jsonEncode({
      'fixtureVersion': 1,
      'origins': payloads
          .map((p) => BackupInteropPayload.decode(p).originPlatform)
          .toList(),
      'embedded': true,
    }),
  );
}

Future<void> main(List<String> args) async {
  try {
    await _runFixture(args);
  } catch (_) {
    stderr.writeln(
      'Backup fixture command rejected; no verification success recorded.',
    );
    exitCode = 1;
  }
}

Future<void> _runFixture(List<String> args) async {
  if (args.length < 2) {
    stdout.writeln(
      'Usage (from app): export NEW_WORKSPACE_ROOT\n'
      '  verify NEW_WORKSPACE_ROOT EXPECTATION_JSON EXPORT_DIRECTORY\n'
      '  capture NEW_WORKSPACE_ROOT RAW_LOG_FILE\n'
      '  embed EXPECTATION_JSON EXPORT_DIRECTORY NEW_TEST_DART\n'
      '  embed-matrix NEW_TEST_DART EXPECTATION EXPORT_DIRECTORY [EXPECTATION EXPORT_DIRECTORY...]',
    );
    return;
  }
  if (args.first == 'embed') {
    interopRequire(args.length == 4, 'embed-arguments');
    final expected = await _readExpectation(args[1]);
    await requireNoLinks(p.absolute(args[2]));
    final payload = await encodeInteropPayload(expected, Directory(args[2]));
    await _writeEmbeddedTest(args[3], [payload], matrix: false);
    return;
  }
  if (args.first == 'embed-matrix') {
    interopRequire(
      args.length >= 6 && args.length <= 10 && (args.length - 2).isEven,
      'matrix-arguments',
    );
    final payloads = <String>[];
    for (var index = 2; index < args.length; index += 2) {
      final expected = await _readExpectation(args[index]);
      await requireNoLinks(p.absolute(args[index + 1]));
      payloads.add(
        await encodeInteropPayload(expected, Directory(args[index + 1])),
      );
    }
    await _writeEmbeddedTest(args[1], payloads, matrix: true);
    return;
  }
  interopRequire(
    {'capture', 'export', 'verify'}.contains(args.first),
    'command',
  );
  interopRequire(
    (args.first == 'export' && args.length == 2) ||
        (args.first == 'capture' && args.length == 3) ||
        (args.first == 'verify' && args.length == 4),
    'command-arguments',
  );
  final owned = await OwnedBackupWorkspace.create(args[1]);
  try {
    if (args.first == 'capture') {
      final log = File(args[2]);
      await requireNoLinks(log.path, file: true);
      final lines = await log
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.contains(interopExportPrefix))
          .take(2)
          .toList();
      final payload = captureInteropPayload(lines);
      final exports = await Directory(p.join(owned.directory.path, 'exports'))
          .create();
      final expected = Map<String, Object?>.from(
        jsonDecode(jsonEncode(payload.expectation)) as Map,
      );
      final packages = expected['packages'] as Map;
      for (final mode in ['full', 'metadata']) {
        final file = File(p.join(exports.path, '$mode.zip'));
        await file.create(exclusive: true);
        await file.writeAsBytes(payload.bytes[mode]!, flush: true);
        (packages[mode] as Map)['fileName'] = '$mode.zip';
      }
      // Re-read the actual closed saved bytes before publishing the expectation.
      final confirmed = await encodeInteropPayload(expected, exports);
      interopRequire(
        BackupInteropPayload.decode(confirmed).originPlatform ==
            payload.originPlatform,
        'captured-origin',
      );
      await File(p.join(owned.directory.path, 'expectation.json'))
          .writeAsString(jsonEncode(expected), flush: true);
      stdout.writeln(
        jsonEncode({
          'fixtureVersion': 1,
          'originPlatform': payload.originPlatform,
          'captured': true,
          'packages': {
            for (final mode in ['full', 'metadata'])
              mode: {
                'byteCount': (packages[mode] as Map)['byteCount'],
                'sha256': (packages[mode] as Map)['sha256'],
              },
          },
        }),
      );
      return;
    }
    final capacity = WindowsStorageCapacity();
    final harness = BackupInteropHarness(
      availableBytes: capacity.availableBytes,
      publishExclusive: capacity.publishExclusive,
    );
    if (args.first == 'export') {
      final expected = await harness.exportFixtures(owned.directory);
      validateInteropExpectation(expected);
      await File(p.join(owned.directory.path, 'expectation.json'))
          .writeAsString(jsonEncode(expected), flush: true);
      stdout.writeln(jsonEncode(expected));
    } else {
      final expected = await _readExpectation(args[2]);
      await requireNoLinks(p.absolute(args[3]));
      final packages = expected['packages'] as Map;
      final results = <Object?>[];
      for (final mode in ['full', 'metadata']) {
        final row = Map<String, Object?>.from(packages[mode] as Map);
        final root = await Directory(p.join(owned.directory.path, mode))
            .create();
        results.add(
          await harness.verifyPackage(
            File(p.join(args[3], row['fileName'] as String)),
            row,
            root,
            originPlatform: expected['originPlatform'] as String,
          ),
        );
      }
      stdout.writeln(jsonEncode({'results': results}));
    }
  } catch (_) {
    stderr.writeln('Backup verification failed; owned workspace retained.');
    exitCode = 1;
  }
}
