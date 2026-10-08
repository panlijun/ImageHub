import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_database.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late QueueTestSecrets secrets;
  late ImageAsset asset;
  late String target;
  late List<int> sourceBytes;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-item-pause-');
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    sourceBytes = img.encodePng(img.Image(width: 8, height: 6));
    asset = (await repository.importResource(
      PlatformResource(
        displayName: '暂停保留.png',
        openRead: () => Stream.value(sourceBytes),
      ),
    )).asset!;
    target = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '冻结目标',
      anonymous: false,
      credential: 'synthetic-item-pause-key-123456789',
    );
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  File getDatabaseFile() => File('${root.path}/library.sqlite');
  void mutate(void Function(Database) action) {
    final db = sqlite3.open(getDatabaseFile().path);
    try {
      action(db);
    } finally {
      db.close();
    }
  }

  List<Map<String, Object?>> rows(String table) {
    final db = sqlite3.open(getDatabaseFile().path, mode: OpenMode.readOnly);
    try {
      return db
          .select('SELECT * FROM "$table" ORDER BY rowid')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } finally {
      db.close();
    }
  }

  Map<String, Object?> snapshot() {
    final db = sqlite3.open(getDatabaseFile().path, mode: OpenMode.readOnly);
    try {
      return {
        'version': db.select('PRAGMA user_version').single.values.single,
        'schema': db
            .select(
              "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
            )
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
        for (final table in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        ))
          table['name'] as String: db
              .select('SELECT * FROM "${table['name']}" ORDER BY rowid')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
      };
    } finally {
      db.close();
    }
  }

  Future<UploadBatch> enqueue(String intent, {List<String>? targets}) =>
      repository.enqueueUploads(
        intentId: intent,
        assetIds: [asset.id],
        targetIds: targets ?? [target],
        allowOriginalMetadata: true,
        forceAgain: true,
      );
  Future<UploadPublication> item(String id) async =>
      (await repository.listUploadBatches())
          .expand((b) => b.items)
          .firstWhere((i) => i.id == id);
  Future<void> reopen() async {
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  }

  Future<void> finish(
    UploadExecution execution,
    ProviderUploadResult result, {
    Duration? retryDelay,
  }) async {
    try {
      await repository.finishUploadAttempt(
        execution,
        result,
        accumulatedRunning: const Duration(seconds: 1),
        retryDelay: retryDelay,
      );
    } finally {
      await execution.release();
    }
  }

  test('UT-054 QUE-003 item pause persists real SQLite and files, isolates peers and batches, repeated intent has no new event attempt or lease', () async {
    final peerTarget = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '另一个目标',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    final batch = await enqueue('first', targets: [target, peerTarget]);
    final other = await enqueue('other');
    final id = batch.items.first.id;
    final references = rows('version_references');
    await repository.setUploadItemPaused(id, true);
    final paused = await item(id);
    expect(paused.userPaused, true);
    expect(paused.state, PublishState.paused);
    final before = snapshot();
    await repository.setUploadItemPaused(id, true);
    await repository.wakeUploadItem(id);
    await repository.setUploadWaiting(id, QueueWaitReason.network);
    expect(await repository.beginUploadAttempt(id), isNull);
    expect(snapshot(), before);
    expect((await item(batch.items.last.id)).state, PublishState.queued);
    expect((await item(other.items.single.id)).state, PublishState.queued);
    expect(rows('version_references'), references);
    expect(rows('upload_attempts'), isEmpty);
    expect(rows('file_leases'), isEmpty);
    expect(rows('output_leases'), isEmpty);
    await reopen();
    final restored = await item(id);
    expect(restored.id, paused.id);
    expect(restored.input.version, paused.input.version);
    expect(restored.target.id, paused.target.id);
    expect(restored.userPaused, true);
    expect(restored.state, PublishState.paused);
    expect(
      await (await repository.originalFor(asset)).readAsBytes(),
      sourceBytes,
    );
    await repository.setUploadItemPaused(id, false);
    expect((await item(id)).userPaused, false);
    expect((await item(id)).state, PublishState.queued);
    final resumed = snapshot();
    await repository.setUploadItemPaused(id, false);
    expect(snapshot(), resumed);
  });

  for (final itemFirst in [true, false]) {
    test(
      'UT-054 QUE-003 ${itemFirst ? 'item then batch' : 'batch then item'} pause preserves independent intent through both resume orders',
      () async {
        final batch = await enqueue('both-$itemFirst');
        final id = batch.items.single.id;
        if (itemFirst) {
          await repository.setUploadItemPaused(id, true);
          await repository.setUploadBatchPaused(batch.id, true);
        } else {
          await repository.setUploadBatchPaused(batch.id, true);
          await repository.setUploadItemPaused(id, true);
        }
        await repository.setUploadBatchPaused(batch.id, false);
        expect((await item(id)).userPaused, true);
        expect((await item(id)).state, PublishState.paused);
        expect(await repository.beginUploadAttempt(id), isNull);
        await repository.setUploadBatchPaused(batch.id, true);
        await repository.setUploadItemPaused(id, false);
        expect((await item(id)).userPaused, false);
        expect((await item(id)).state, PublishState.paused);
        await repository.wakeUploadItem(id);
        await repository.setUploadWaiting(id, QueueWaitReason.network);
        expect((await item(id)).state, PublishState.paused);
        expect(await repository.beginUploadAttempt(id), isNull);
        await repository.setUploadBatchPaused(batch.id, false);
        expect((await item(id)).state, PublishState.queued);
      },
    );
  }

  test('UT-054 UT-061 QUE-003 real retry waiting reason and delay survive item pause reopen and batch resume', () async {
    final batch = await enqueue('retry');
    final id = batch.items.single.id;
    final execution = (await repository.beginUploadAttempt(id))!;
    await finish(
      execution,
      const ProviderUploadFailure(
        UploadFailureKind.network,
        UploadDeliveryEvidence.notSent,
      ),
      retryDelay: const Duration(seconds: 8),
    );
    final waiting = await item(id);
    expect(waiting.state, PublishState.waiting);
    expect(waiting.waitReason, QueueWaitReason.retry);
    expect(waiting.retryDelay, const Duration(seconds: 8));
    await repository.setUploadItemPaused(id, true);
    await repository.setUploadBatchPaused(batch.id, true);
    await reopen();
    await repository.setUploadItemPaused(id, false);
    final paused = await item(id);
    expect(paused.state, PublishState.paused);
    expect(paused.waitReason, waiting.waitReason);
    expect(paused.retryDelay, waiting.retryDelay);
    expect(paused.attemptCount, 1);
    await repository.setUploadBatchPaused(batch.id, false);
    final restored = await item(id);
    expect(restored.state, PublishState.waiting);
    expect(restored.waitReason, waiting.waitReason);
    expect(restored.retryDelay, waiting.retryDelay);
    expect(rows('upload_attempts'), hasLength(1));
    expect(rows('file_leases'), isEmpty);
  });

  for (final batchPause in [false, true]) {
    test(
      'UT-054 UT-062 QUE-003 interrupted item uses legal atomic transitions for batchPause=$batchPause without allocating a new attempt',
      () async {
        final batch = await enqueue('interrupted');
        final id = batch.items.single.id;
        final execution = (await repository.beginUploadAttempt(id))!;
        await execution.release();
        await reopen();
        expect((await item(id)).state, PublishState.interrupted);
        if (batchPause) {
          await repository.setUploadBatchPaused(batch.id, true);
        } else {
          await repository.setUploadItemPaused(id, true);
        }
        expect((await item(id)).state, PublishState.paused);
        if (batchPause) {
          await repository.setUploadBatchPaused(batch.id, false);
        } else {
          await repository.setUploadItemPaused(id, false);
        }
        expect((await item(id)).state, PublishState.queued);
        expect((await item(id)).attemptCount, 1);
        expect(rows('upload_attempts'), hasLength(1));
        expect(rows('file_leases'), isEmpty);
        final states = rows('upload_events')
            .map((row) => PublishState.values.byName(row['state'] as String))
            .toList();
        expect(states, [
          PublishState.queued,
          PublishState.running,
          PublishState.interrupted,
          PublishState.queued,
          PublishState.paused,
          PublishState.queued,
        ]);
        for (var index = 1; index < states.length; index++) {
          expect(
            PublishTransitions.permits(states[index - 1], states[index]),
            true,
          );
        }
      },
    );
  }

  for (final state in [
    PublishState.running,
    PublishState.unknown,
    PublishState.succeeded,
    PublishState.failed,
    PublishState.cancelled,
  ]) {
    test(
      'UT-054 QUE-003 $state rejects pause and resume without data or evidence changes',
      () async {
        final id = (await enqueue('reject-${state.name}')).items.single.id;
        final execution = (await repository.beginUploadAttempt(id))!;
        if (state == PublishState.cancelled) {
          await repository.cancelUploadItems([id]);
        }
        if (state != PublishState.running) {
          await finish(execution, switch (state) {
            PublishState.unknown => const ProviderUploadUnknown(
              UploadFailureKind.timeout,
            ),
            PublishState.succeeded => ProviderUploadSuccess(
              service: ImageHostService.catbox,
              remoteId: 'paused-fixture.png',
              directUrl: Uri.parse(
                'https://files.catbox.moe/paused-fixture.png',
              ),
            ),
            PublishState.failed => const ProviderUploadFailure(
              UploadFailureKind.formatUnsupported,
              UploadDeliveryEvidence.notSent,
            ),
            _ => const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
          });
        }
        expect((await item(id)).state, state);
        final before = snapshot();
        for (final paused in [true, false]) {
          await expectLater(
            repository.setUploadItemPaused(id, paused),
            throwsA(isA<UploadQueueFailure>()),
          );
          expect(snapshot(), before);
        }
        if (state == PublishState.running) {
          expect(rows('file_leases'), hasLength(1));
          await finish(
            execution,
            const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
          );
        }
      },
    );
  }

  test('UT-093 IT-006 QUE-003 own schema8 migrates to current with stable identities protection secrets and original bytes', () async {
    final batch = await enqueue('migration-eight');
    await repository.setUploadBatchPaused(batch.id, true);
    await repository.close();
    final savedSecrets = Map.of(secrets.values);
    mutate((db) {
      db.execute(
        'ALTER TABLE upload_publications DROP COLUMN processing_job_id',
      );
      db.execute('DROP TABLE upload_processing_jobs');
      db.execute('ALTER TABLE upload_publications DROP COLUMN user_paused');
      db.execute('PRAGMA user_version=8');
    });
    final before = snapshot();
    final db = LibraryDatabase(getDatabaseFile());
    try {
      await db.customSelect('SELECT * FROM library_metadata').get();
    } finally {
      await db.close();
    }
    final after = snapshot();
    expect(after['version'], librarySchemaVersion);
    for (final key in before.keys.where(
      (k) => k != 'schema' && k != 'version',
    )) {
      expect(
        after[key],
        key == 'upload_publications'
            ? [
                for (final row in before[key] as List<Map<String, Object?>>)
                  {...row, 'user_paused': 0, 'processing_job_id': null},
              ]
            : before[key],
        reason: '$key stable evidence',
      );
    }
    expect((after['upload_publications'] as List).single['user_paused'], 0);
    expect((after['version_references'] as List), hasLength(1));
    mutate((db) {
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(
        db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        ),
        hasLength(28),
      );
    });
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect((await item(batch.items.single.id)).userPaused, false);
    expect((await item(batch.items.single.id)).state, PublishState.paused);
    expect(secrets.values, savedSecrets);
    expect((await repository.listTargets()).single.id, target);
    expect(
      await (await repository.originalFor(asset)).readAsBytes(),
      sourceBytes,
    );
    await repository.setUploadItemPaused(batch.items.single.id, true);
    await reopen();
    expect((await item(batch.items.single.id)).userPaused, true);
  });

  test('UT-093 QUE-003 schema8 pending restore refuses before any structure data or file mutation', () async {
    await enqueue('pending-restore');
    await repository.close();
    mutate((db) {
      db.execute(
        'ALTER TABLE upload_publications DROP COLUMN processing_job_id',
      );
      db.execute('DROP TABLE upload_processing_jobs');
      db.execute('ALTER TABLE upload_publications DROP COLUMN user_paused');
      db.execute('PRAGMA user_version=8');
      db.execute('INSERT INTO restore_operations VALUES (?, ?, ?, ?)', [
        '00000000-0000-4000-8000-000000000001',
        'replace-rollback',
        '{"retainedEvidence":true}',
        1,
      ]);
    });
    final before = snapshot();
    final bytes = await getDatabaseFile().readAsBytes();
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        LibraryRepository.open(root, secretStore: secrets),
        throwsA(isA<LibraryOpenException>()),
      );
      expect(snapshot(), before);
      expect(await getDatabaseFile().readAsBytes(), bytes);
    }
  });
}
