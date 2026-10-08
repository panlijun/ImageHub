import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/managed_file_store.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory sandbox;
  late Directory root;
  LibraryRepository? repository;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost_source_cancel_');
    root = Directory(p.join(sandbox.path, 'library'));
  });
  tearDown(() async {
    await repository?.close();
    repository = null;
    await sandbox.delete(recursive: true);
  });

  Future<File> picture(String name, {int red = 80}) async {
    final image = img.Image(width: 3, height: 2, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(red, 30, 160, 255));
    return File(p.join(sandbox.path, name))
        .writeAsBytes(img.encodePng(image), flush: true);
  }

  for (final afterChunk in [false, true]) {
    test('UT-003 / UT-010 / UT-011 / UT-091 cancel stalled source '
        '${afterChunk ? 'after first chunk' : 'before first chunk'} waits for '
        'actual cleanup and retains root lock and stage', () async {
      repository = await LibraryRepository.open(root);
      final source = _BlockedSource();
      final token = CancellationToken();
      final firstWrite = Completer<void>();
      final copied = <int>[];
      var importCompleted = false;
      var closeCompleted = false;
      final importing = repository!.importResource(
        source.resource,
        cancellation: token,
        onProgress: (progress) {
          copied.add(progress.bytesCopied);
          if (progress.bytesCopied > 0 && !firstWrite.isCompleted) {
            firstWrite.complete();
          }
        },
      );
      _observeCompletion(importing, () => importCompleted = true);
      Future<void>? closing;
      try {
        await _wait(source.listened.future);
        if (afterChunk) {
          source.controller.add([137, 80, 78, 71]);
          await _wait(firstWrite.future);
        }
        token.cancel();
        await _wait(source.cancelEntered.future);
        closing = repository!.close();
        _observeCompletion(closing, () => closeCompleted = true);
        await _microtasks();
        expect(source.cancelCalls, 1);
        expect(source.actualIoEnded, false);
        expect(importCompleted, false);
        expect(closeCompleted, false);
        final journal = _journal(root);
        expect(journal, hasLength(1));
        expect(journal.single['phase'], 'writing');
        expect(_assetCount(root), 0);
        final stage = File(
          p.join(root.path, journal.single['stage_path'] as String),
        );
        expect(await stage.exists(), true);
        expect(await stage.length(), afterChunk ? 4 : 0);
        await expectLater(
          LibraryRepository.open(root),
          throwsA(isA<LibraryOpenException>()),
        );
        expect(importCompleted, false);
        expect(closeCompleted, false);
        expect(await stage.exists(), true);

        source.finishActualIo();
        final result = await _wait(importing);
        expect(source.actualIoEnded, true);
        expect(result.status, ImportStatus.cancelled);
        expect(result.failure!.kind, FailureKind.cancelled);
        expect(result.asset, isNull);
        await _wait(closing);
        repository = null;
        expect(_journal(root), isEmpty);
        expect(await _stageFiles(root), isEmpty);
        expect(
          await Directory(p.join(root.path, 'originals')).list().toList(),
          isEmpty,
        );
        expect(copied, afterChunk ? [0, 4] : [0]);

        repository = await LibraryRepository.open(root);
        expect((await repository!.listAssets()).total, 0);
        expect(repository!.recoveredImportCount, 0);
        final retry = await picture('retry.png');
        final saved = await repository!.importResource(
          PlatformResource.file(retry),
        );
        expect(saved.status, ImportStatus.saved);
        expect(
          await repository!.verifyCopy(saved.asset!),
          CopyAvailability.available,
        );
        expect(await retry.exists(), true);
      } finally {
        // Never leave our own simulated IO gate blocking repository teardown,
        // including when an assertion fails before the gate is released.
        token.cancel();
        source.finishActualIo();
        await importing;
        await closing;
        source.dispose();
      }
    });
  }

  test('UT-003 / UT-011 / UT-091 source cleanup error after actual IO ends is '
      'storage failure with retained journal, recovered without committing', () async {
    repository = await LibraryRepository.open(root);
    final original = await picture('saved.png');
    final committed = await repository!.importResource(
      PlatformResource.file(original),
    );
    expect(committed.status, ImportStatus.saved);
    final originalBytes = await original.readAsBytes();
    final source = _BlockedSource(failCleanup: true);
    final token = CancellationToken();
    final firstWrite = Completer<void>();
    final importing = repository!.importResource(
      source.resource,
      cancellation: token,
      onProgress: (progress) {
        if (progress.bytesCopied > 0 && !firstWrite.isCompleted) {
          firstWrite.complete();
        }
      },
    );
    try {
      await _wait(source.listened.future);
      source.controller.add([137, 80, 78, 71]);
      await _wait(firstWrite.future);
      token.cancel();
      await _wait(source.cancelEntered.future);
      expect(source.actualIoEnded, false);
      source.finishActualIo();
      final result = await _wait(importing);
      // The fixture first drains its actual IO, then fails cleanup. This does
      // not claim a never-ending source can be safely released after an error.
      expect(source.actualIoEnded, true);
      expect(source.cancelCalls, 1);
      expect(result.status, ImportStatus.failed);
      expect(result.failure!.kind, FailureKind.storage);
      expect(result.asset, isNull);
      final journal = _journal(root);
      expect(journal, hasLength(1));
      expect(journal.single['phase'], 'writing');
      final stage = File(
        p.join(root.path, journal.single['stage_path'] as String),
      );
      expect(await stage.readAsBytes(), [137, 80, 78, 71]);
      expect(
        (await repository!.listAssets()).items.single.id,
        committed.asset!.id,
      );
      expect(
        await repository!.verifyCopy(committed.asset!),
        CopyAvailability.available,
      );

      await repository!.close();
      repository = null;
      expect(await stage.exists(), true);
      expect(_journal(root), hasLength(1));
      repository = await LibraryRepository.open(root);
      expect(repository!.recoveryIssues, isEmpty);
      expect(repository!.recoveredImportCount, 0);
      expect(_journal(root), isEmpty);
      expect(await _stageFiles(root), isEmpty);
      expect(
        (await repository!.listAssets()).items.single.id,
        committed.asset!.id,
      );
      expect(
        await (await repository!.originalFor(committed.asset!)).readAsBytes(),
        originalBytes,
      );
      await repository!.recover();
      expect(_journal(root), isEmpty);
      expect(await _stageFiles(root), isEmpty);
      expect((await repository!.listAssets()).total, 1);
      await repository!.close();
      repository = await LibraryRepository.open(root);
      expect(
        (await repository!.listAssets()).items.single.id,
        committed.asset!.id,
      );
    } finally {
      token.cancel();
      source.finishActualIo();
      await importing;
      source.dispose();
    }
  });

  test(
    'UT-003 / UT-011 cancellation during beforeWrite does not write the '
    'delivered chunk and waits for both write gate and source cleanup',
    () async {
      final store = await ManagedFileStore.open(root);
      final source = _BlockedSource();
      final token = CancellationToken();
      final writeEntered = Completer<void>();
      final releaseWrite = Completer<void>();
      const stagePath = 'staging/00000000-0000-4000-8000-000000000001.part';
      final progress = <int>[];
      var completed = false;
      final copying = store.copySource(
        source.resource,
        stagePath,
        token,
        1024,
        progress.add,
        beforeWrite: (bytes) async {
          expect(bytes, 4);
          writeEntered.complete();
          await releaseWrite.future;
        },
      );
      final checked = expectLater(copying, _fails(FailureKind.cancelled));
      _observeCompletion(copying, () => completed = true);
      try {
        await _wait(source.listened.future);
        source.controller.add([137, 80, 78, 71]);
        await _wait(writeEntered.future);
        token.cancel();
        await _microtasks();
        expect(completed, false);
        expect(source.cancelCalls, 0);
        final stage = await store.file(stagePath);
        expect(await stage.length(), 0);
        releaseWrite.complete();
        await _wait(source.cancelEntered.future);
        expect(completed, false);
        expect(await stage.length(), 0);
        expect(progress, isEmpty);
        source.finishActualIo();
        await _wait(checked);
        expect(source.actualIoEnded, true);
        expect(await stage.readAsBytes(), isEmpty);
        await store.deleteStage(stagePath);
      } finally {
        token.cancel();
        if (!releaseWrite.isCompleted) releaseWrite.complete();
        source.finishActualIo();
        try {
          await checked;
        } finally {
          source.dispose();
          await store.close();
        }
      }
    },
  );

  final sourceErrors = <(Object, FailureKind)>[
    (const ResourceFailure(FailureKind.cloudPending), FailureKind.cloudPending),
    (
      const ResourceFailure(FailureKind.permissionDenied),
      FailureKind.permissionDenied,
    ),
    (
      const FileSystemException('missing', '', OSError('', 2)),
      FailureKind.sourceMissing,
    ),
    (
      const FileSystemException('permission', '', OSError('', 13)),
      FailureKind.permissionDenied,
    ),
    (StateError('source unavailable'), FailureKind.unavailable),
  ];
  for (final synchronous in [true, false]) {
    for (final (error, expected) in sourceErrors) {
      test(
        'UT-003 / UT-010 ${synchronous ? 'opening' : 'stream'} source error '
        '${expected.name} keeps classification and prior committed image',
        () async {
          repository = await LibraryRepository.open(root);
          final original = await picture('prior.png');
          final saved = await repository!.importResource(
            PlatformResource.file(original),
          );
          final result = await repository!.importResource(
            PlatformResource(
              displayName: 'unavailable.png',
              openRead: () {
                if (synchronous) throw error;
                return Stream<List<int>>.error(error);
              },
            ),
          );
          expect(result.status, ImportStatus.failed);
          expect(result.failure!.kind, expected);
          expect(
            (await repository!.listAssets()).items.single.id,
            saved.asset!.id,
          );
          expect(
            await repository!.verifyCopy(saved.asset!),
            CopyAvailability.available,
          );
          expect(_journal(root), isEmpty);
          expect(await _stageFiles(root), isEmpty);
        },
      );
    }
  }
}

Matcher _fails(FailureKind kind) => throwsA(
  isA<ResourceFailure>().having((failure) => failure.kind, 'kind', kind),
);

// Watchdog only for test orchestration; no production IO cleanup is timed out.
Future<T> _wait<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 10));

void _observeCompletion<T>(Future<T> future, void Function() completed) {
  unawaited(
    future.then<void>(
      (_) => completed(),
      onError: (Object _, StackTrace _) => completed(),
    ),
  );
}

Future<void> _microtasks() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.value();
  }
}

Future<List<FileSystemEntity>> _stageFiles(Directory root) =>
    Directory(p.join(root.path, 'staging')).list().toList();

List<Map<String, Object?>> _journal(Directory root) {
  final database = sqlite3.open(
    p.join(root.path, 'library.sqlite'),
    mode: OpenMode.readOnly,
  );
  try {
    return database
        .select('SELECT id, phase, stage_path FROM import_operations')
        .map((row) => Map<String, Object?>.from(row))
        .toList();
  } finally {
    database.close();
  }
}

int _assetCount(Directory root) {
  final database = sqlite3.open(
    p.join(root.path, 'library.sqlite'),
    mode: OpenMode.readOnly,
  );
  try {
    return database
            .select('SELECT COUNT(*) AS count FROM assets')
            .single['count']
        as int;
  } finally {
    database.close();
  }
}

class _BlockedSource {
  _BlockedSource({this.failCleanup = false}) {
    controller = StreamController<List<int>>(
      onListen: listened.complete,
      onCancel: () async {
        cancelCalls++;
        cancelEntered.complete();
        await _actualIoGate.future;
        actualIoEnded = true;
        if (failCleanup) {
          throw StateError('cleanup failed after actual IO drained');
        }
      },
    );
  }
  final bool failCleanup;
  final listened = Completer<void>();
  final cancelEntered = Completer<void>();
  final _actualIoGate = Completer<void>();
  late final StreamController<List<int>> controller;
  var cancelCalls = 0;
  var actualIoEnded = false;

  PlatformResource get resource => PlatformResource(
    displayName: 'stalled.png',
    openRead: () => controller.stream,
  );

  void finishActualIo() {
    if (!_actualIoGate.isCompleted) _actualIoGate.complete();
  }

  void dispose() {
    unawaited(controller.close());
  }
}
