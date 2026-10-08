import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_history.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

final class _Secrets extends QueueTestSecrets {
  final deleted = <String>[];
  @override
  Future<void> delete(String reference) async {
    deleted.add(reference);
    await super.delete(reference);
  }
}

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late _Secrets secrets;
  late ImageAsset asset;
  late String cat, imgbb;
  final extras = <LibraryRepository>[];
  var ordinal = 0;
  var failHook = false;
  const managementToken = 'SyntheticHistoryManagementToken0123456789';
  const failure = ProviderUploadFailure(
    UploadFailureKind.quota,
    UploadDeliveryEvidence.confirmedRejected,
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-history-clear-');
    root = Directory('${sandbox.path}/library');
    secrets = _Secrets();
    failHook = false;
    repository = await LibraryRepository.open(
      root,
      secretStore: secrets,
      historyClearFaultHook: (boundary) async {
        expect(boundary, UploadHistoryClearBoundary.recordsDeleted);
        if (failHook) throw StateError('synthetic transaction failure');
      },
    );
    asset = (await repository.importResource(
      PlatformResource(
        displayName: '真实历史输入.png',
        openRead: () =>
            Stream.value(img.encodePng(img.Image(width: 8, height: 6))),
      ),
    )).asset!;
    cat = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '冻结目标',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    imgbb = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '管理目标',
      anonymous: false,
      credential: 'SyntheticHistoryApiCredential0123456789',
    );
    extras.clear();
  });
  tearDown(() async {
    for (final extra in extras) {
      await extra.close();
    }
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  List<Map<String, Object?>> rows(String table, {Directory? at}) {
    final db = sqlite3.open(
      '${(at ?? root).path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return db
          .select('SELECT * FROM "$table" ORDER BY 1')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
    } finally {
      db.close();
    }
  }

  void mutate(void Function(Database) action, {Directory? at}) {
    final db = sqlite3.open('${(at ?? root).path}/library.sqlite');
    try {
      db.execute('PRAGMA foreign_keys=ON');
      action(db);
    } finally {
      db.close();
    }
  }

  Future<UploadBatch> enqueue({
    String? intent,
    String? target,
    String? output,
    bool forceAgain = true,
    LibraryRepository? owner,
  }) => (owner ?? repository).enqueueUploads(
    intentId: intent ?? const Uuid().v4(),
    assetIds: output == null ? [asset.id] : [],
    outputIds: output == null ? [] : [output],
    targetIds: [target ?? cat],
    allowOriginalMetadata: true,
    forceAgain: forceAgain,
  );
  Future<UploadExecution> begin(UploadBatch batch) async =>
      (await repository.beginUploadAttempt(batch.items.single.id))!;
  ProviderUploadSuccess success(
    UploadExecution execution, {
    bool management = false,
  }) {
    final name = 'history${++ordinal}', service = execution.item.target.service;
    return ProviderUploadSuccess(
      service: service,
      remoteId: service == ImageHostService.catbox ? '$name.png' : name,
      directUrl: Uri.parse(
        service == ImageHostService.catbox
            ? 'https://files.catbox.moe/$name.png'
            : 'https://i.ibb.co/$name/image.png',
      ),
      viewerUrl: service == ImageHostService.imgbb
          ? Uri.parse('https://ibb.co/$name')
          : null,
      managementSecret: management
          ? SensitiveManagementSecret('https://ibb.co/$name/$managementToken')
          : null,
    );
  }

  Future<void> finish(
    UploadExecution execution,
    ProviderUploadResult outcome, {
    bool release = true,
    bool interrupted = false,
  }) async {
    try {
      await repository.finishUploadAttempt(
        execution,
        outcome,
        accumulatedRunning: Duration.zero,
        interrupted: interrupted,
      );
    } finally {
      if (release) await execution.release();
    }
  }

  Future<UploadBatch> failed({String? output}) async {
    final batch = await enqueue(output: output);
    await finish(await begin(batch), failure);
    return batch;
  }

  Future<UploadHistoryClearPlan> plan(
    Iterable<String> publications, {
    Iterable<String> imported = const [],
    LibraryRepository? owner,
  }) => (owner ?? repository).prepareUploadHistoryClear(
    publicationIds: publications,
    importedHistoryIds: imported,
  );
  Future<UploadHistoryClearResult> clear(
    UploadHistoryClearPlan plan, {
    LibraryRepository? owner,
  }) => (owner ?? repository).clearUploadHistory(
    plan,
    confirmHistoryRemoval: true,
  );
  String id(UploadBatch batch) => batch.items.single.id;
  Future<(LibraryRepository, Directory)> restore(BackupMode mode) async {
    final snapshot = await repository.captureBackupSnapshot(mode: mode);
    final zip = File('${sandbox.path}/backup-${++ordinal}.zip');
    try {
      await BackupZipWriter().write(snapshot, zip);
    } finally {
      await snapshot.release();
    }
    final backup = await const BackupZipReader().preflight(
      zip,
      await Directory('${sandbox.path}/preflight-$ordinal').create(),
      availableBytes: (_) async => 1 << 40,
    );
    final destinationRoot = Directory('${sandbox.path}/restored-$ordinal');
    final destination = await LibraryRepository.open(
      destinationRoot,
      secretStore: _Secrets(),
    );
    extras.add(destination);
    final hold = await destination.acquireRestoreHold();
    try {
      final preparation = await destination.prepareMergeRestore(
        hold: hold,
        backup: backup,
      );
      expect(preparation.plan.canCommit, true);
      await destination.commitMergeRestore(
        preparation: preparation,
        availableBytes: (_) async => 1 << 40,
        publishExclusive: (source, target) async {
          if (await FileSystemEntity.type(target.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            return false;
          }
          await source.rename(target.path);
          return true;
        },
      );
    } finally {
      await hold.release();
      await backup.dispose();
    }
    return (destination, destinationRoot);
  }

  test('UT-066 strict UUID selection deduplicates in explicit order and missing records stay preserved', () async {
    final a = await failed(), b = await failed(), missing = const Uuid().v4();
    final selected = [id(b), id(a), id(b), missing];
    final prepared = await plan(selected);
    selected.add(const Uuid().v4());
    expect(prepared.eligible.map((e) => e.reference.id), [id(b), id(a)]);
    expect(prepared.eligibleCount, 2);
    expect(prepared.preservedCount, 1);
    expect(prepared.preserved.single.reason, UploadHistoryProtection.missing);
    expect(() => prepared.eligible.clear(), throwsUnsupportedError);
    expect(() => prepared.preserved.clear(), throwsUnsupportedError);
    await expectLater(plan([' ${id(a)}']), throwsA(isA<UploadQueueFailure>()));
    await expectLater(
      plan([], imported: ['../history']),
      throwsA(isA<UploadQueueFailure>()),
    );
    await expectLater(
      repository.clearUploadHistory(prepared, confirmHistoryRemoval: false),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(rows('upload_publications'), hasLength(2));
    final result = await clear(prepared);
    expect(result.publicationRemoved, 2);
    expect(result.importedRemoved, 0);
    expect(result.preservedCount, 1);
  });

  test('UT-038/066 all six real active states and their processed-input dependencies survive selected history clearing', () async {
    final output = await ProcessingCoordinator(repository).process(
      [asset.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        longestSide: 4,
      ),
      displayName: '受保护输出.png',
    );
    final queued = await enqueue(output: output.id);
    final waiting = await enqueue(output: output.id);
    await repository.setUploadWaiting(
      id(waiting),
      QueueWaitReason.capabilityUnknown,
    );
    final paused = await enqueue(output: output.id);
    await repository.setUploadBatchPaused(paused.id, true);
    final interrupted = await enqueue(output: output.id);
    await finish(
      await begin(interrupted),
      const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
      interrupted: true,
    );
    final unknown = await enqueue(output: output.id);
    await finish(
      await begin(unknown),
      const ProviderUploadUnknown(UploadFailureKind.protocol),
    );
    final running = await enqueue(output: output.id),
        execution = await begin(running);
    try {
      final before = rows('output_references'),
          beforeLeases = rows('output_leases');
      final prepared = await plan(
        [queued, waiting, paused, interrupted, unknown, running].map(id),
      );
      expect(prepared.eligible, isEmpty);
      expect(prepared.preserved, hasLength(6));
      expect(
        prepared.preserved.every(
          (e) => e.reason == UploadHistoryProtection.active,
        ),
        true,
      );
      expect(
        (await repository.listUploadBatches())
            .map((b) => b.items.single.state)
            .toSet(),
        {
          PublishState.queued,
          PublishState.waiting,
          PublishState.paused,
          PublishState.interrupted,
          PublishState.unknown,
          PublishState.running,
        },
      );
      expect((await clear(prepared)).removedCount, 0);
      expect(rows('output_references'), before);
      expect(rows('output_leases'), beforeLeases);
      expect((await repository.getOutput(output.id)).usable, true);
    } finally {
      await finish(
        execution,
        const ProviderUploadUnknown(UploadFailureKind.protocol),
      );
    }
  });

  test('UT-038/066 cancelled intent and late confirmation remain protected until actual execution release', () async {
    final batch = await enqueue(target: imgbb), execution = await begin(batch);
    try {
      expect(
        await repository.authorizeUploadRequest(execution.attemptId),
        true,
      );
      await repository.cancelUploadItems([id(batch)]);
      final cancelled = await plan([id(batch)]);
      expect(
        cancelled.preserved.single.reason,
        UploadHistoryProtection.inputInUse,
      );
      await repository.finishUploadAttempt(
        execution,
        success(execution, management: true),
        accumulatedRunning: Duration.zero,
      );
      expect((await repository.listUploadResults()).single.late, true);
      expect(rows('version_references'), isEmpty);
      expect(rows('upload_attempts').single['ended_utc'], isNotNull);
      final afterFinish = await plan([id(batch)]);
      expect(
        afterFinish.preserved.single.reason,
        UploadHistoryProtection.inputInUse,
      );
      expect((await clear(afterFinish)).removedCount, 0);
    } finally {
      await execution.release();
    }
    final beforeResults = rows('remote_upload_results'),
        beforeSecrets = Map.of(secrets.values);
    final result = await clear(await plan([id(batch)]));
    expect(result.removedCount, 1);
    expect(rows('remote_upload_results'), beforeResults);
    expect(secrets.values, beforeSecrets);
    expect(secrets.deleted, isEmpty);
  });

  test('UT-038/066 real SQL lease-release failure keeps terminal history protected until cleanup can finish', () async {
    final batch = await enqueue(), execution = await begin(batch);
    await finish(execution, failure, release: false);
    mutate(
      (db) => db.execute(
        "CREATE TRIGGER fail_lease_release BEFORE DELETE ON file_leases BEGIN SELECT RAISE(ABORT,'synthetic lease failure'); END",
      ),
    );
    try {
      await expectLater(execution.release(), throwsA(isA<Exception>()));
      expect(rows('file_leases'), hasLength(1));
      expect(
        (await plan([id(batch)])).preserved.single.reason,
        UploadHistoryProtection.inputInUse,
      );
      expect(rows('upload_publications'), hasLength(1));
    } finally {
      mutate((db) => db.execute('DROP TRIGGER fail_lease_release'));
      await execution.release();
    }
    expect((await clear(await plan([id(batch)]))).removedCount, 1);
  });

  test('UT-038/066 retained task references block their own terminal history without removing unrelated dependencies', () async {
    final batch = await failed(),
        owner = const Uuid().v4(),
        own = const Uuid().v4();
    mutate((db) {
      db.execute(
        'INSERT INTO version_references(id,version_id,owner_type,owner_id) VALUES(?,?,?,?)',
        [own, asset.version.id, 'task', id(batch)],
      );
      db.execute(
        'INSERT INTO version_references(id,version_id,owner_type,owner_id) VALUES(?,?,?,?)',
        [const Uuid().v4(), asset.version.id, 'task', owner],
      );
    });
    final prepared = await plan([id(batch)]);
    expect(
      prepared.preserved.single.reason,
      UploadHistoryProtection.retainedDependency,
    );
    expect((await clear(prepared)).removedCount, 0);
    mutate(
      (db) => db.execute('DELETE FROM version_references WHERE id=?', [own]),
    );
    expect((await clear(await plan([id(batch)]))).removedCount, 1);
    expect(rows('version_references').single['owner_id'], owner);
  });

  test('UT-066 pending management journal protects owning attempt and reused-success publication without its own attempt', () async {
    final batch = await enqueue(target: imgbb), execution = await begin(batch);
    expect(await repository.authorizeUploadRequest(execution.attemptId), true);
    secrets.failReads = true;
    await finish(execution, success(execution, management: true));
    expect(rows('upload_result_operations'), hasLength(1));
    expect(rows('file_leases'), isEmpty);
    final reused = await enqueue(target: imgbb, forceAgain: false);
    expect(reused.items.single.state, PublishState.succeeded);
    expect(reused.items.single.currentAttemptId, null);
    final ordinary = rows('remote_upload_results'),
        journal = rows('upload_result_operations'),
        protected = Map.of(secrets.values);
    final prepared = await plan([id(batch), id(reused)]);
    expect(prepared.eligible, isEmpty);
    expect(prepared.preserved.map((e) => e.reason), [
      UploadHistoryProtection.pendingResult,
      UploadHistoryProtection.pendingResult,
    ]);
    expect((await clear(prepared)).removedCount, 0);
    expect(rows('remote_upload_results'), ordinary);
    expect(rows('upload_result_operations'), journal);
    expect(secrets.values, protected);
    expect(secrets.deleted, isEmpty);
    secrets.failReads = false;
  });

  test('UT-066 selected clearing preserves every asset byte organization result secret other history and policy snapshot', () async {
    final category = await repository.createCategory('整理分类');
    await repository.updateOrganization(
      [asset.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['保留标签'],
      favorite: true,
    );
    final selected = await enqueue(target: imgbb),
        execution = await begin(selected);
    await finish(execution, success(execution, management: true));
    final other = await failed();
    final before = {
      for (final table in [
        'assets',
        'versions',
        'device_copies',
        'categories',
        'tags',
        'asset_tags',
        'remote_upload_results',
        'provider_targets',
      ])
        table: rows(table),
    };
    final otherRow = rows('upload_publications')
        .singleWhere((r) => r['id'] == id(other));
    final bytes = await File(
      '${root.path}/${rows('device_copies').single['relative_path']}',
    ).readAsBytes();
    final protected = Map.of(secrets.values);
    var changes = 0;
    final subscription = repository.uploadChanges.listen((_) => changes++);
    final result = await clear(await plan([id(selected)]));
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    expect(result.publicationRemoved, 1);
    expect(changes, 1);
    for (final entry in before.entries) {
      expect(rows(entry.key), entry.value, reason: entry.key);
    }
    expect(rows('upload_publications').single, otherRow);
    expect(rows('upload_attempts').single['item_id'], id(other));
    expect(rows('upload_events').every((r) => r['item_id'] == id(other)), true);
    expect(
      await File(
        '${root.path}/${rows('device_copies').single['relative_path']}',
      ).readAsBytes(),
      bytes,
    );
    expect(secrets.values, protected);
    expect(secrets.deleted, isEmpty);
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(
      (await repository.listUploadBatches())
          .singleWhere((b) => b.id == other.id)
          .items
          .single
          .input
          .policyKey,
      other.items.single.input.policyKey,
    );
    expect(rows('remote_upload_results'), before['remote_upload_results']);
    expect(secrets.values, protected);
  });

  test('UT-066 empty batch retains intent receipt across close and same-intent retry never creates another publication', () async {
    const intent = 'confirmed-history-intent';
    final batch = await enqueue(intent: intent);
    await finish(await begin(batch), failure);
    await clear(await plan([id(batch)]));
    expect((await repository.listUploadBatches()).single.items, isEmpty);
    expect(rows('upload_batches').single['intent_id'], intent);
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final retry = await enqueue(intent: intent);
    expect(retry.id, batch.id);
    expect(retry.items, isEmpty);
    expect(rows('upload_publications'), isEmpty);
    expect(rows('upload_attempts'), isEmpty);
    expect(rows('upload_batches'), hasLength(1));
  });

  for (final table in [
    'upload_publications',
    'upload_attempts',
    'upload_events',
    'remote_upload_results',
  ]) {
    test(
      'UT-066 full confirmation fingerprint rejects changed $table and rolls back the entire selected set',
      () async {
        final a = await enqueue(), execution = await begin(a);
        await finish(execution, success(execution));
        final b = await failed(), prepared = await plan([id(a), id(b)]);
        mutate((db) {
          switch (table) {
            case 'upload_publications':
              db.execute(
                'UPDATE upload_publications SET message=? WHERE id=?',
                ['changed', id(a)],
              );
            case 'upload_attempts':
              db.execute('UPDATE upload_attempts SET outcome=? WHERE id=?', [
                'changed',
                execution.attemptId,
              ]);
            case 'upload_events':
              db.execute('UPDATE upload_events SET reason=? WHERE item_id=?', [
                'changed',
                id(a),
              ]);
            case 'remote_upload_results':
              db.execute(
                'UPDATE remote_upload_results SET confirmed_utc=confirmed_utc+1 WHERE attempt_id=?',
                [execution.attemptId],
              );
          }
        });
        final before = rows('upload_publications'),
            attempts = rows('upload_attempts'),
            events = rows('upload_events');
        await expectLater(clear(prepared), throwsA(isA<UploadQueueFailure>()));
        expect(rows('upload_publications'), before);
        expect(rows('upload_attempts'), attempts);
        expect(rows('upload_events'), events);
      },
    );
  }

  test('UT-066 tampered resultId or result snapshot refuses clearing while ordinary confirmations remain intact', () async {
    final selected = await enqueue(), execution = await begin(selected);
    await finish(execution, success(execution));
    final other = await enqueue(target: imgbb),
        otherExecution = await begin(other);
    await finish(otherExecution, success(otherExecution, management: true));
    final ordinary = rows('remote_upload_results');
    final originalResult = ordinary.singleWhere(
      (r) => r['attempt_id'] == execution.attemptId,
    );
    final unrelatedResult = ordinary.singleWhere(
      (r) => r['attempt_id'] == otherExecution.attemptId,
    );
    mutate(
      (db) => db.execute(
        'UPDATE upload_publications SET result_id=? WHERE id=?',
        [unrelatedResult['id'], id(selected)],
      ),
    );
    await expectLater(plan([id(selected)]), throwsA(isA<UploadQueueFailure>()));
    expect(rows('remote_upload_results'), ordinary);
    mutate((db) {
      db.execute('UPDATE upload_publications SET result_id=? WHERE id=?', [
        originalResult['id'],
        id(selected),
      ]);
      final snapshot = jsonDecode(
        originalResult['input_json'] as String,
      ) as Map<String, dynamic>;
      (snapshot['version'] as Map<String, dynamic>)['byteCount'] =
          asset.version.byteCount + 1;
      db.execute('UPDATE remote_upload_results SET input_json=? WHERE id=?', [
        jsonEncode(snapshot),
        originalResult['id'],
      ]);
    });
    await expectLater(plan([id(selected)]), throwsA(isA<UploadQueueFailure>()));
    expect(rows('upload_publications'), hasLength(2));
    expect(rows('remote_upload_results'), hasLength(2));
    expect(secrets.deleted, isEmpty);
  });

  test('UT-066 protected entries becoming terminal invalidate the old plan and never add implicit deletion', () async {
    final terminal = await failed(), queued = await enqueue();
    final prepared = await plan([id(terminal), id(queued)]);
    expect(prepared.eligibleCount, 1);
    await repository.cancelUploadItems([id(queued)]);
    await expectLater(clear(prepared), throwsA(isA<UploadQueueFailure>()));
    expect(rows('upload_publications'), hasLength(2));
    expect((await clear(await plan([id(terminal)]))).removedCount, 1);
    expect(rows('upload_publications').single['id'], id(queued));
  });

  test(
    'UT-066 plans bind owner and execution epoch across close and reopen',
    () async {
      final batch = await failed(), prepared = await plan([id(batch)]);
      final other = await LibraryRepository.open(
        Directory('${sandbox.path}/other'),
        secretStore: _Secrets(),
      );
      extras.add(other);
      await expectLater(
        clear(prepared, owner: other),
        throwsA(isA<UploadQueueFailure>()),
      );
      await repository.close();
      repository = await LibraryRepository.open(root, secretStore: secrets);
      await expectLater(clear(prepared), throwsA(isA<UploadQueueFailure>()));
      expect(rows('upload_publications').single['id'], id(batch));
    },
  );

  test('UT-066 same-owner actual replacement rotates epoch and rejects even an unchanged empty confirmation', () async {
    await failed();
    final prepared = await plan([]), beforeEpoch = repository.executionEpoch;
    final snapshot = await repository.captureBackupSnapshot(
      mode: BackupMode.full,
    );
    final zip = File('${sandbox.path}/epoch-replacement.zip');
    try {
      await BackupZipWriter().write(snapshot, zip);
    } finally {
      await snapshot.release();
    }
    final backup = await const BackupZipReader().preflight(
      zip,
      await Directory('${sandbox.path}/epoch-preflight').create(),
      availableBytes: (_) async => 1 << 40,
    );
    final hold = await repository.acquireRestoreHold();
    try {
      final replacement = await repository.prepareReplacementRestore(
        hold: hold,
        backup: backup,
        availableBytes: (_) async => 1 << 40,
      );
      final report = await repository.commitReplacementRestore(
        preparation: replacement,
        availableBytes: (_) async => 1 << 40,
        publishExclusive: (source, target) async {
          if (await FileSystemEntity.type(target.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            return false;
          }
          await source.rename(target.path);
          return true;
        },
      );
      expect(report.cleanupPending, false);
    } finally {
      await hold.release();
      await backup.dispose();
    }
    expect(repository.executionEpoch, isNot(beforeEpoch));
    await expectLater(clear(prepared), throwsA(isA<UploadQueueFailure>()));
    expect((await clear(await plan([]))).removedCount, 0);
    expect(await repository.listImportedUploadHistories(), hasLength(1));
  });

  test('UT-066 close immediately rejects a new prepare while waiting for a real input lease', () async {
    final batch = await enqueue(), execution = await begin(batch);
    final closing = repository.close();
    try {
      await expectLater(plan([id(batch)]), throwsA(isA<UploadQueueFailure>()));
    } finally {
      await finish(
        execution,
        const ProviderUploadUnknown(UploadFailureKind.protocol),
      );
      await closing;
    }
  });

  test('UT-066 SEC new credential masks old confirmation labels and invalidates the earlier plan', () async {
    const future = 'FutureHistoryCredential0123456789';
    await repository.saveTarget(
      id: cat,
      service: ImageHostService.catbox,
      alias: '目标$future',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    final batch = await failed(), prepared = await plan([id(batch)]);
    expect(prepared.eligible.single.target.alias, contains(future));
    await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '新凭据',
      anonymous: false,
      credential: future,
    );
    await expectLater(clear(prepared), throwsA(isA<UploadQueueFailure>()));
    final masked = await plan([id(batch)]);
    expect(masked.eligible.single.target.alias, isNot(contains(future)));
    expect(masked.eligible.single.target.alias, contains('[已隐藏]'));
    expect(rows('upload_publications'), hasLength(1));
  });

  test('UT-066 deletion hook failure before commit rolls back events attempts and publications together', () async {
    final a = await failed(),
        b = await failed(),
        prepared = await plan([id(b), id(a)]);
    final before = {
      for (final table in [
        'upload_events',
        'upload_attempts',
        'upload_publications',
        'upload_batches',
      ])
        table: rows(table),
    };
    failHook = true;
    await expectLater(clear(prepared), throwsA(isA<UploadQueueFailure>()));
    for (final entry in before.entries) {
      expect(rows(entry.key), entry.value);
    }
    failHook = false;
    expect((await clear(prepared)).removedCount, 2);
    expect(rows('upload_batches'), before['upload_batches']);
  });

  for (final corruption in ['future-state', 'input-json', 'digest-mismatch']) {
    test(
      'UT-066 malformed $corruption refuses a plan without deleting a valid selected neighbor',
      () async {
        final a = await failed(), b = await failed();
        mutate((db) {
          switch (corruption) {
            case 'future-state':
              db.execute('UPDATE upload_publications SET state=? WHERE id=?', [
                'future-state',
                id(a),
              ]);
            case 'input-json':
              db.execute(
                'UPDATE upload_publications SET input_json=? WHERE id=?',
                ['{broken', id(a)],
              );
            case 'digest-mismatch':
              db.execute(
                'UPDATE upload_publications SET byte_count=byte_count+1 WHERE id=?',
                [id(a)],
              );
          }
        });
        final before = rows('upload_publications');
        await expectLater(
          plan([id(b), id(a)]),
          throwsA(isA<UploadQueueFailure>()),
        );
        expect(rows('upload_publications'), before);
      },
    );
  }

  for (final mode in BackupMode.values) {
    test(
      'UT-066 ${mode.name} actual backup restore clears only imported namespace and preserves ordinary confirmation and source native identity',
      () async {
        final source = await enqueue(), execution = await begin(source);
        await finish(execution, success(execution));
        final failedSource = await failed();
        final (destination, destinationRoot) = await restore(mode);
        final ordinary = rows('remote_upload_results', at: destinationRoot),
            originals = rows('assets', at: destinationRoot),
            protected = Map.of(secrets.values);
        final imported = await destination.listImportedUploadHistories();
        expect(imported, hasLength(2));
        expect(rows('upload_publications', at: destinationRoot), isEmpty);
        final prepared = await plan(
          [id(source)],
          imported: [id(source)],
          owner: destination,
        );
        expect(
          prepared.eligible.single.reference.kind,
          UploadHistoryKind.imported,
        );
        expect(
          prepared.preserved.single.reason,
          UploadHistoryProtection.missing,
        );
        final result = await clear(prepared, owner: destination);
        expect(result.importedRemoved, 1);
        expect(result.publicationRemoved, 0);
        expect(
          (await destination.listImportedUploadHistories()).single.id,
          id(failedSource),
        );
        expect(rows('remote_upload_results', at: destinationRoot), ordinary);
        expect(rows('assets', at: destinationRoot), originals);
        expect(rows('upload_publications'), hasLength(2));
        expect(rows('upload_attempts'), hasLength(2));
        expect(secrets.values, protected);
        expect(
          mode == BackupMode.metadata
              ? rows(
                  'device_copies',
                  at: destinationRoot,
                ).every((r) => r['availability'] == 'missing')
              : rows(
                  'device_copies',
                  at: destinationRoot,
                ).every((r) => r['availability'] == 'available'),
          true,
        );
      },
    );
  }

  test('UT-066 imported IDs matching a native publication stay independent and imported embedded attempts never delete native attempts', () async {
    final source = await failed();
    final (destination, destinationRoot) = await restore(BackupMode.full);
    final restoredAsset = (await destination.listAssets()).items.single;
    final nativeTarget = await destination.saveTarget(
      service: ImageHostService.catbox,
      alias: '本机目标',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    final native = await destination.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [restoredAsset.id],
      targetIds: [nativeTarget],
      allowOriginalMetadata: true,
    );
    final execution = (await destination.beginUploadAttempt(id(native)))!;
    try {
      await destination.finishUploadAttempt(
        execution,
        failure,
        accumulatedRunning: Duration.zero,
      );
    } finally {
      await execution.release();
    }
    // Controlled namespace-collision fault: both histories still originate in
    // actual enqueue / backup restore, with valid SQL and manifest evidence.
    mutate((db) {
      db.execute('BEGIN');
      db.execute('PRAGMA defer_foreign_keys=ON');
      db.execute('UPDATE upload_publications SET id=? WHERE id=?', [
        id(source),
        id(native),
      ]);
      db.execute('UPDATE upload_events SET item_id=? WHERE item_id=?', [
        id(source),
        id(native),
      ]);
      db.execute('UPDATE upload_attempts SET item_id=? WHERE item_id=?', [
        id(source),
        id(native),
      ]);
      final row = db
          .select('SELECT snapshot_json FROM imported_upload_histories')
          .single;
      final fragment =
          jsonDecode(row['snapshot_json'] as String) as Map<String, dynamic>;
      final history =
          (fragment['history'] as List).single as Map<String, dynamic>;
      ((history['attempts'] as List).single as Map<String, dynamic>)['id'] =
          execution.attemptId;
      db.execute('UPDATE imported_upload_histories SET snapshot_json=?', [
        jsonEncode(fragment),
      ]);
      db.execute('COMMIT');
    }, at: destinationRoot);
    final beforeNative = rows('upload_publications', at: destinationRoot),
        beforeAttempts = rows('upload_attempts', at: destinationRoot),
        beforeEvents = rows('upload_events', at: destinationRoot);
    final prepared = await plan([], imported: [id(source)], owner: destination);
    expect((await clear(prepared, owner: destination)).importedRemoved, 1);
    expect(rows('upload_publications', at: destinationRoot), beforeNative);
    expect(rows('upload_attempts', at: destinationRoot), beforeAttempts);
    expect(rows('upload_events', at: destinationRoot), beforeEvents);
  });

  test('UT-066 damaged imported confirmation refuses the entire mixed clear without empty-history overwrite', () async {
    final source = await failed();
    final (destination, destinationRoot) = await restore(BackupMode.full);
    final prepared = await plan([], imported: [id(source)], owner: destination);
    final original = rows('imported_upload_histories', at: destinationRoot);
    mutate(
      (db) => db.execute(
        'UPDATE imported_upload_histories SET snapshot_json=?',
        ['{broken'],
      ),
      at: destinationRoot,
    );
    await expectLater(
      clear(prepared, owner: destination),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(
      rows(
        'imported_upload_histories',
        at: destinationRoot,
      ).single['snapshot_json'],
      '{broken',
    );
    expect(rows('assets', at: destinationRoot), hasLength(1));
    mutate(
      (db) => db.execute(
        'UPDATE imported_upload_histories SET snapshot_json=?',
        [original.single['snapshot_json']],
      ),
      at: destinationRoot,
    );
    expect((await clear(prepared, owner: destination)).importedRemoved, 1);
  });
}
