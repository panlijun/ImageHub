import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:imagehost/core/managed_file_store.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';

List<int> fixture() {
  final image = img.Image(width: 48, height: 32);
  img.fill(image, color: img.ColorRgb8(30, 100, 210));
  return img.encodePng(image);
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    final mode = args[0];
    final root = Directory(args[1]);
    if (mode == 'lock') {
      try {
        final store = await ManagedFileStore.open(root);
        stdout.writeln('LOCKED');
        await stdin
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first;
        await store.close();
      } on LibraryOpenException {
        stdout.writeln('BLOCKED');
        exitCode = 3;
      }
      return;
    }
    final repository = await LibraryRepository.open(
      root,
      faultHook: mode == 'interrupt'
          ? (boundary) async {
              if (boundary.name == args[2]) exit(73);
            }
          : null,
    );
    if (mode == 'interrupt' || mode == 'import') {
      final result = await repository.importResource(
        PlatformResource(
          displayName: 'new-image.png',
          openRead: () => Stream.value(fixture()),
        ),
      );
      if (result.status != ImportStatus.saved) {
        throw StateError('Import failed');
      }
    }
    final page = await repository.listAssets();
    for (final asset in page.items) {
      if (await repository.verifyCopy(asset) != CopyAvailability.available) {
        throw StateError('Copy unavailable');
      }
      if (asset.version.sha256 != sha256.convert(fixture()).toString()) {
        throw StateError('Bytes mismatch');
      }
    }
    stdout.writeln(
      jsonEncode({
        'count': page.total,
        'ids': page.items.map((e) => e.id).toList(),
        'recovered': repository.recoveredImportCount,
        'issues': repository.recoveryIssues.length,
      }),
    );
    await repository.close();
    return;
  }
  final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
  final sandbox = await Directory(temporaryRoot)
      .createTemp('imagehost_process_');
  final sandboxPath = await sandbox.resolveSymbolicLinks();
  final script = Platform.script.toFilePath();
  final lockProcesses = <Process>[];
  Future<ProcessResult> child(List<String> arguments) => Process.run(
    Platform.resolvedExecutable,
    ['run', script, ...arguments],
    workingDirectory: Directory.current.path,
  );
  void require(bool value, String message) {
    if (!value) throw StateError(message);
  }

  try {
    for (final boundary in ImportBoundary.values) {
      final root = '${sandbox.path}/${boundary.name}';
      final interrupted = await child(['interrupt', root, boundary.name]);
      require(
        interrupted.exitCode == 73,
        'No abrupt exit at ${boundary.name}: ${interrupted.stderr}',
      );
      final first = await child(['verify', root]);
      require(first.exitCode == 0, 'Recovery failed: ${first.stderr}');
      final result = jsonDecode(first.stdout.toString().trim()) as Map;
      final expected =
          [ImportBoundary.copy, ImportBoundary.verified].contains(boundary)
          ? 0
          : 1;
      require(
        result['count'] == expected && result['issues'] == 0,
        'Invalid state: $result',
      );
      final second = await child(['verify', root]);
      require(
        second.exitCode == 0,
        'Repeated recovery failed: ${second.stderr}',
      );
      final repeated = jsonDecode(second.stdout.toString().trim()) as Map;
      require(
        jsonEncode(result['ids']) == jsonEncode(repeated['ids']),
        'Identity changed on recovery',
      );
      stdout.writeln(
        'PASS abrupt process exit ${boundary.name}: $expected assets, stable IDs, verified bytes',
      );
    }
    final normalRoot = '${sandbox.path}/normal';
    final imported = await child(['import', normalRoot]);
    final reopened = await child(['verify', normalRoot]);
    require(
      imported.exitCode == 0 && reopened.exitCode == 0,
      'Normal restart failed',
    );
    require(
      jsonEncode((jsonDecode(imported.stdout.toString()) as Map)['ids']) ==
          jsonEncode((jsonDecode(reopened.stdout.toString()) as Map)['ids']),
      'Normal restart identity changed',
    );
    stdout.writeln(
      'PASS separate-process normal close/reopen: independent bytes and stable identity',
    );
    final lockRoot = '${sandbox.path}/lock';
    final holder = await Process.start(Platform.resolvedExecutable, [
      'run',
      script,
      'lock',
      lockRoot,
    ]);
    lockProcesses.add(holder);
    unawaited(holder.stderr.drain<void>().catchError((Object _) {}));
    final holderLine = await holder.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 30));
    require(holderLine == 'LOCKED', 'First process did not lock');
    final blocked = await child(['lock', lockRoot]);
    require(
      blocked.exitCode == 3 && blocked.stdout.toString().trim() == 'BLOCKED',
      'Second process was not blocked',
    );
    holder.stdin.writeln('close');
    await holder.stdin.flush();
    require(
      await holder.exitCode.timeout(const Duration(seconds: 30)) == 0,
      'Lock holder did not exit',
    );
    final reopenedLock = await Process.start(Platform.resolvedExecutable, [
      'run',
      script,
      'lock',
      lockRoot,
    ]);
    lockProcesses.add(reopenedLock);
    unawaited(reopenedLock.stderr.drain<void>().catchError((Object _) {}));
    require(
      await reopenedLock.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 30)) ==
          'LOCKED',
      'Lock not released',
    );
    reopenedLock.stdin.writeln('close');
    await reopenedLock.stdin.flush();
    require(await reopenedLock.exitCode == 0, 'Reopened lock did not close');
    stdout.writeln(
      'PASS ${Platform.operatingSystem} cross-process exclusive library lock and release',
    );
  } finally {
    var allLockProcessesStopped = true;
    for (final process in lockProcesses) {
      try {
        process.stdin.writeln('close');
        await process.stdin.flush().timeout(const Duration(seconds: 10));
        await process.stdin.close().timeout(const Duration(seconds: 10));
      } catch (_) {
        // A process that already exited can have a closed input pipe. Its
        // actual exit still must be confirmed before deleting the test files.
      }
      try {
        await process.exitCode.timeout(const Duration(seconds: 10));
      } catch (_) {
        allLockProcessesStopped = false;
      }
    }
    if (!allLockProcessesStopped) {
      throw StateError(
        'Lock process shutdown is uncertain; verification files are preserved',
      );
    }
    final target = await sandbox.resolveSymbolicLinks();
    if (target != sandboxPath ||
        p.dirname(target) != temporaryRoot ||
        !p.basename(target).startsWith('imagehost_process_')) {
      throw StateError('Process verification cleanup ownership is uncertain');
    }
    await Directory(target).delete(recursive: true);
  }
}
