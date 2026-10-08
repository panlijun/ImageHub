import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_history.dart';
import 'package:imagehost/features/upload/domain/upload_processing_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

// IT-004 partial: real temporary SQLite, managed PNGs and the shared isolate
// engine. Controlled provider result structures below verify local receipt
// persistence only; no HTTP request, real provider confirmation, device crash
// or platform acceptance is asserted by these repository tests.
void main() {
  const prefix = 'imagehost-upload-processing-repository-';
  late Directory sandbox, root;
  late LibraryRepository repository;
  late QueueTestSecrets secrets;
  late ImageAsset asset;
  late List<String> targets;
  final activeJobs = <String>{};

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(prefix);
    root = Directory(p.join(sandbox.path, 'library'));
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final image = img.Image(width: 12, height: 8);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x * 17, y * 23, (x + y) * 9);
      }
    }
    final bytes = img.encodePng(image);
    asset = (await repository.importResource(
      PlatformResource(
        displayName: '真实冻结来源.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    // Source, version and target identities come from real committed imports
    // and account writes; tests retain those UUIDs through every reopen.
    targets = [
      for (var i = 0; i < 2; i++)
        await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '冻结目标 $i',
          anonymous: false,
          credential: 'synthetic-processing-key-$i',
        ),
    ];
    activeJobs.clear();
  });

  tearDown(() async {
    // Test workers are joined in each test's finally before guards are drained.
    for (final id in activeJobs.toList()) {
      try {
        await repository.finishUploadProcessingJob(
          id,
          failureMessage: '测试已结束，实际处理已退出。',
          interrupted: true,
        );
      } finally {
        activeJobs.remove(id);
      }
    }
    await repository.close();
    final temp = p.normalize(await Directory.systemTemp.resolveSymbolicLinks());
    final owned = p.normalize(await sandbox.resolveSymbolicLinks());
    if (!p.isAbsolute(owned) ||
        !p.isWithin(temp, owned) ||
        !p.basename(owned).startsWith(prefix)) {
      throw StateError('拒绝删除未确认归属的测试目录。');
    }
    await Directory(owned).delete(recursive: true);
  });

  ProcessingRecipe recipe({int longestSide = 6}) => ProcessingRecipe(
    operation: ProcessingOperation.compress,
    mode: ProcessingMode.sizeFirst,
    longestSide: longestSide,
  );

  UploadProcessingSelection selection(ProcessingRecipe value) =>
      UploadProcessingSelection(assetIds: [asset.id], recipe: value);

  Future<UploadBatch> enqueue(
    String intent,
    Iterable<UploadProcessingSelection> selections,
  ) => repository.enqueueUploads(
    intentId: intent,
    processing: selections,
    targetIds: targets,
  );

  Future<UploadBatch> batch(String id) async =>
      (await repository.listUploadBatches()).singleWhere((b) => b.id == id);

  Future<UploadProcessingJob> claim(String id) async {
    final job = await repository.beginUploadProcessingJob(id);
    expect(job, isNotNull);
    activeJobs.add(id);
    return job!;
  }

  Future<void> finishJob(
    String id, {
    String? outputId,
    String? failureMessage,
    bool inputUnavailable = false,
    bool interrupted = false,
  }) async {
    try {
      await repository.finishUploadProcessingJob(
        id,
        outputId: outputId,
        failureMessage: failureMessage,
        inputUnavailable: inputUnavailable,
        interrupted: interrupted,
      );
    } finally {
      activeJobs.remove(id);
    }
  }

  Future<ProcessedOutput> process(UploadProcessingJob job) =>
      ProcessingCoordinator(repository).process(
        job.plan.assetIds,
        job.plan.bind,
        displayName: '共享处理结果.png',
        retention: job.retention,
        typedSourceFailures: true,
        onOutputIntent: (intent) =>
            repository.recordUploadProcessingOutput(job.id, intent.id),
      );

  Future<void> reopen() async {
    expect(activeJobs, isEmpty);
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  }

  int count(String table, {String? where, List<Object?> values = const []}) {
    final db = sqlite3.open(
      p.join(root.path, 'library.sqlite'),
      mode: OpenMode.readOnly,
    );
    try {
      return db
              .select(
                'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}',
                values,
              )
              .single['n']
          as int;
    } finally {
      db.close();
    }
  }

  Future<void> settleUnsent(UploadExecution execution) async {
    try {
      // The repository's notSent outcome is exercised without calling an
      // adapter or manufacturing a remote success receipt.
      await repository.finishUploadAttempt(
        execution,
        const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
        accumulatedRunning: Duration.zero,
      );
    } finally {
      await execution.release();
    }
  }

  test('UT-046 UT-062 UT-066 IT-004 partial ready pixel output remains durably protected before job confirmation and transfers protection to publications', () async {
    final queued = await enqueue('ready-output-protection-transfer', [
      selection(recipe()),
    ]);
    final job = await claim(
      (await repository.listUploadProcessingJobs()).single.id,
    );
    final output = await process(job);
    expect(output.usable, isTrue);
    final bytes = await output.file!.readAsBytes();
    final afterExpiry = output.expiresAt.add(const Duration(seconds: 1));
    // The worker, output writer and actual input lease have all settled. Only
    // the durable job reference now protects the still-unassociated output.
    expect(count('file_leases'), 0);
    expect(count('output_leases'), 0);
    expect(
      count(
        'output_references',
        where: 'owner_type=? AND owner_id=? AND output_id=?',
        values: ['task', job.id, output.id],
      ),
      1,
    );
    final pending = (await repository.listUploadProcessingJobs()).single;
    expect(pending.state, UploadProcessingState.running);
    expect(pending.outputId, output.id);
    final protectedBeforeCommit = await withClock(
      Clock.fixed(afterExpiry),
      repository.cleanupOutputs,
    );
    expect(protectedBeforeCommit.removed, 0);
    expect(protectedBeforeCommit.protected, 1);
    expect(protectedBeforeCommit.failedIds, isEmpty);
    expect(await output.file!.readAsBytes(), bytes);
    expect((await repository.getOutput(output.id)).usable, isTrue);
    expect(count('processed_outputs'), 1);
    await finishJob(job.id, outputId: output.id);
    expect(
      count('output_references', where: 'owner_id=?', values: [job.id]),
      0,
    );
    for (final item in (await batch(queued.id)).items) {
      expect(item.input.referenceId, output.id);
      expect(item.input.kind, UploadInputKind.processed);
      expect(
        count(
          'output_references',
          where: 'owner_type=? AND owner_id=? AND output_id=?',
          values: ['task', item.id, output.id],
        ),
        1,
      );
    }
    expect(
      count('output_references', where: 'output_id=?', values: [output.id]),
      2,
    );
    final protectedAfterCommit = await withClock(
      Clock.fixed(afterExpiry),
      repository.cleanupOutputs,
    );
    expect(protectedAfterCommit.removed, 0);
    expect(protectedAfterCommit.protected, 1);
    await repository.cancelUploadItems(queued.items.map((i) => i.id));
    expect(
      count('output_references', where: 'output_id=?', values: [output.id]),
      0,
    );
    final cleaned = await withClock(
      Clock.fixed(afterExpiry),
      repository.cleanupOutputs,
    );
    expect(cleaned.removed, 1);
    expect(cleaned.protected, 0);
    expect(cleaned.failedIds, isEmpty);
    expect(await output.file!.exists(), isFalse);
    expect(count('processed_outputs'), 0);
    expect(await repository.verifyCopy(asset), CopyAvailability.available);
    expect(count('upload_attempts'), 0);
  });

  Future<(UploadBatch, UploadProcessingJob, ProcessedOutput)> confirmedPixels(
    String intent,
  ) async {
    final queued = await enqueue(intent, [selection(recipe())]);
    final job = await claim(
      (await repository.listUploadProcessingJobs())
          .singleWhere((candidate) => candidate.batchId == queued.id)
          .id,
    );
    final output = await process(job);
    expect(output.usable, isTrue);
    await finishJob(job.id, outputId: output.id);
    return (await batch(queued.id), job, output);
  }

  Future<void> persistControlledReceipts(UploadBatch processed) async {
    for (var index = 0; index < processed.items.length; index++) {
      final execution = await repository.beginUploadAttempt(
        processed.items[index].id,
      );
      expect(execution, isNotNull);
      try {
        expect(execution!.item.input.kind, UploadInputKind.processed);
        expect(
          await repository.authorizeUploadRequest(execution.attemptId),
          isTrue,
        );
        final name = 'controlled-processing-receipt-$index.png';
        // Exact ordinary fixture accepted by the same repository boundary used
        // after an adapter has settled. This is not a network/service test.
        await repository.finishUploadAttempt(
          execution,
          ProviderUploadSuccess(
            service: ImageHostService.catbox,
            remoteId: name,
            directUrl: Uri.parse('https://files.catbox.moe/$name'),
          ),
          accumulatedRunning: Duration.zero,
        );
      } finally {
        await execution?.release();
      }
    }
  }

  Future<void> persistControlledUnknowns(UploadBatch processed) async {
    for (final item in processed.items) {
      final execution = await repository.beginUploadAttempt(item.id);
      expect(execution, isNotNull);
      try {
        expect(
          await repository.authorizeUploadRequest(execution!.attemptId),
          isTrue,
        );
        await repository.finishUploadAttempt(
          execution,
          const ProviderUploadUnknown(UploadFailureKind.network),
          accumulatedRunning: Duration.zero,
        );
      } finally {
        await execution?.release();
      }
    }
  }

  for (final failure in [false, true]) {
    test(
      'UT-046 UT-062 IT-004 partial shared ${failure ? 'failure' : 'ready output'} preserves mixed target unknown frozen evidence and its output protection',
      () async {
        final confirmed = await confirmedPixels('mixed-unknown-source');
        await persistControlledUnknowns(confirmed.$1);
        final originalUnknowns = (await batch(confirmed.$1.id)).items;
        expect(
          originalUnknowns.map((i) => i.state),
          everyElement(PublishState.unknown),
        );
        if (failure) {
          // A real engine budget rejection keeps the exact valid PNG/source and
          // old output intact; no failed pixels or provider result are fabricated.
          await repository.close();
          repository = await LibraryRepository.open(
            root,
            secretStore: secrets,
            memoryBudgetBytes: 1,
          );
        }
        final freshTarget = await repository.saveTarget(
          service: ImageHostService.catbox,
          alias: '混合批次新匿名目标',
          anonymous: false,
          credential: 'SyntheticAccountFixture0123456789',
        );
        final mixed = await repository.enqueueUploads(
          intentId: 'mixed-unknown-next',
          processing: [selection(recipe())],
          targetIds: [targets.first, freshTarget],
        );
        expect(mixed.items, hasLength(2));
        final before = mixed.items.singleWhere(
          (i) => i.target.id == targets.first,
        );
        final fresh = mixed.items.singleWhere(
          (i) => i.target.id == freshTarget,
        );
        expect(before.state, PublishState.unknown);
        expect(before.input.kind, UploadInputKind.processed);
        expect(before.input.referenceId, confirmed.$3.id);
        expect(before.input.version, confirmed.$3.version);
        expect(before.attemptCount, 0);
        expect(fresh.state, PublishState.waiting);
        expect(fresh.processingPending, isTrue);
        expect(before.processingJobId, fresh.processingJobId);
        final running = await claim(fresh.processingJobId!);
        String? newOutputId;
        if (failure) {
          await expectLater(
            process(running),
            throwsA(
              isA<ProcessingFailure>().having(
                (error) => error.kind,
                'real shared engine budget rejection',
                ProcessingFailureKind.resourceBudget,
              ),
            ),
          );
          await finishJob(running.id, failureMessage: '真实处理预算拒绝，原图未上传。');
        } else {
          final output = await process(running);
          expect(output.usable, isTrue);
          newOutputId = output.id;
          expect(newOutputId, isNot(confirmed.$3.id));
          await finishJob(running.id, outputId: newOutputId);
        }
        final after = await batch(mixed.id);
        final untouched = after.items.singleWhere((i) => i.id == before.id);
        final resolved = after.items.singleWhere((i) => i.id == fresh.id);
        expect(untouched.state, PublishState.unknown);
        expect(untouched.input.kind, before.input.kind);
        expect(untouched.input.referenceId, before.input.referenceId);
        expect(untouched.input.version, before.input.version);
        expect(untouched.input.policyKey, before.input.policyKey);
        expect(
          untouched.input.processingSummary,
          before.input.processingSummary,
        );
        expect(untouched.input.displayName, before.input.displayName);
        expect(untouched.attemptCount, before.attemptCount);
        expect(untouched.generation, before.generation);
        expect(untouched.currentAttemptId, before.currentAttemptId);
        expect(untouched.waitReason, before.waitReason);
        expect(untouched.updatedAt, before.updatedAt);
        expect(await repository.beginUploadAttempt(untouched.id), isNull);
        await repository.wakeUploadItem(untouched.id);
        expect(
          (await batch(mixed.id)).items
              .singleWhere((i) => i.id == before.id)
              .state,
          PublishState.unknown,
        );
        expect(
          resolved.state,
          failure ? PublishState.failed : PublishState.queued,
        );
        expect(
          resolved.input.kind,
          failure ? UploadInputKind.original : UploadInputKind.processed,
        );
        expect(resolved.input.referenceId, failure ? asset.id : newOutputId);
        expect(resolved.attemptCount, 0);
        expect(
          count(
            'output_references',
            where: 'owner_id=? AND output_id=?',
            values: [untouched.id, confirmed.$3.id],
          ),
          1,
        );
        expect(
          count(
            'version_references',
            where: 'owner_id=?',
            values: [running.id],
          ),
          0,
        );
        expect(count('upload_attempts'), 2);
        expect(count('processed_outputs'), failure ? 1 : 2);
        expect((await repository.getOutput(confirmed.$3.id)).usable, isTrue);
        for (final original in (await batch(confirmed.$1.id)).items) {
          expect(original.state, PublishState.unknown);
          expect(original.input.referenceId, confirmed.$3.id);
          expect(original.attemptCount, 1);
        }
      },
    );
  }

  test('UT-046 UT-062 IT-004 partial exact frozen plan and target reuse persisted processed receipt without another pixel job or attempt', () async {
    final confirmed = await confirmedPixels('receipt-source');
    await persistControlledReceipts(confirmed.$1);
    final results = await repository.listUploadResults();
    expect(results, hasLength(2));
    final byTarget = {for (final result in results) result.target.id: result};
    expect(count('upload_attempts'), 2);
    expect(count('processed_outputs'), 1);
    await reopen();
    final reused = await enqueue('receipt-reused', [selection(recipe())]);
    final reusedJob = (await repository.listUploadProcessingJobs()).singleWhere(
      (job) => job.batchId == reused.id,
    );
    expect(reusedJob.plan.canonical, confirmed.$2.plan.canonical);
    expect(reusedJob.state, UploadProcessingState.cancelled);
    expect(await repository.beginUploadProcessingJob(reusedJob.id), isNull);
    expect(reused.items, hasLength(2));
    for (final item in reused.items) {
      expect(item.state, PublishState.succeeded);
      expect(item.input.kind, UploadInputKind.processed);
      expect(item.input.referenceId, confirmed.$3.id);
      expect(item.input.version, confirmed.$3.version);
      expect(item.input.policyKey, confirmed.$2.plan.policyKey);
      expect(item.resultId, byTarget[item.target.id]!.id);
      expect(item.attemptCount, 0);
      expect(item.currentAttemptId, isNull);
      expect(item.waitReason, isNull);
      expect(await repository.beginUploadAttempt(item.id), isNull);
      expect(await repository.listUploadAttempts(item.id), isEmpty);
    }
    expect(
      count('version_references', where: 'owner_type=?', values: ['task']),
      0,
    );
    expect(
      count('output_references', where: 'owner_type=?', values: ['task']),
      0,
    );
    expect(count('processed_outputs'), 1);
    expect(count('upload_attempts'), 2);
    expect(
      (await repository.listUploadResults()).map((r) => r.id).toSet(),
      results.map((r) => r.id).toSet(),
    );
    final repeated = await enqueue('receipt-reused', [selection(recipe())]);
    expect(repeated.id, reused.id);
    expect(
      repeated.items.map((i) => i.id).toList(),
      reused.items.map((i) => i.id).toList(),
    );
  });

  for (final deleted in [true, false]) {
    test(
      'UT-046 UT-062 IT-004 partial ${deleted ? 'deleted receipt' : 'explicit forceAgain'} creates a new frozen pending processing dependency',
      () async {
        final confirmed = await confirmedPixels('receipt-exclusion-source');
        await persistControlledReceipts(confirmed.$1);
        final receipts = await repository.listUploadResults();
        final first = receipts.singleWhere((r) => r.target.id == targets.first);
        if (deleted) {
          // Seed only the existing local observation after clean close. No HEAD
          // request or deletion is made and no remote status is asserted here.
          await repository.close();
          final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
          try {
            db.execute(
              'UPDATE remote_upload_results SET link_state=?,link_reason=?,link_checked_utc=?,probe_http_status=?,probe_generation=1 WHERE id=?',
              [
                'deleted',
                'gone',
                DateTime.now().toUtc().millisecondsSinceEpoch,
                410,
                first.id,
              ],
            );
          } finally {
            db.close();
          }
          repository = await LibraryRepository.open(root, secretStore: secrets);
        }
        final next = await repository.enqueueUploads(
          intentId: 'receipt-exclusion-next',
          processing: [selection(recipe())],
          targetIds: targets,
          forceAgain: !deleted,
        );
        final job = (await repository.listUploadProcessingJobs()).singleWhere(
          (j) => j.batchId == next.id,
        );
        expect(job.id, isNot(confirmed.$2.id));
        expect(job.state, UploadProcessingState.queued);
        expect(job.plan.canonical, confirmed.$2.plan.canonical);
        expect(job.outputId, isNull);
        for (final item in next.items) {
          final excluded = !deleted || item.target.id == targets.first;
          expect(
            item.state,
            excluded ? PublishState.waiting : PublishState.succeeded,
          );
          expect(
            item.input.kind,
            excluded ? UploadInputKind.original : UploadInputKind.processed,
          );
          expect(item.resultId, excluded ? isNull : isNotNull);
          expect(item.processingPending, excluded);
          expect(item.attemptCount, 0);
          expect(await repository.beginUploadAttempt(item.id), isNull);
        }
        expect(
          count('version_references', where: 'owner_id=?', values: [job.id]),
          1,
        );
        expect(count('upload_attempts'), 2);
        expect(count('processed_outputs'), 1);
        expect((await repository.listUploadResults()), hasLength(2));
      },
    );
  }

  test('UT-046 UT-062 IT-004 partial unknown matching frozen plan blocks new processing and upload while forceAgain freezes a fresh intent', () async {
    final confirmed = await confirmedPixels('unknown-policy-source');
    for (final item in confirmed.$1.items) {
      final execution = await repository.beginUploadAttempt(item.id);
      expect(execution, isNotNull);
      try {
        expect(
          await repository.authorizeUploadRequest(execution!.attemptId),
          isTrue,
        );
        await repository.finishUploadAttempt(
          execution,
          const ProviderUploadUnknown(UploadFailureKind.network),
          accumulatedRunning: Duration.zero,
        );
      } finally {
        await execution?.release();
      }
    }
    await reopen();
    final blocked = await enqueue('unknown-policy-blocked', [
      selection(recipe()),
    ]);
    final blockedJob = (await repository.listUploadProcessingJobs())
        .singleWhere((job) => job.batchId == blocked.id);
    expect(await repository.beginUploadProcessingJob(blockedJob.id), isNull);
    expect(blockedJob.state, UploadProcessingState.cancelled);
    expect(
      count('version_references', where: 'owner_id=?', values: [blockedJob.id]),
      0,
    );
    for (final item in blocked.items) {
      expect(item.state, PublishState.unknown);
      expect(item.input.kind, UploadInputKind.processed);
      expect(item.input.referenceId, confirmed.$3.id);
      expect(item.input.version, confirmed.$3.version);
      expect(item.input.policyKey, confirmed.$2.plan.policyKey);
      expect(item.attemptCount, 0);
      expect(await repository.beginUploadAttempt(item.id), isNull);
    }
    expect(count('upload_attempts'), 2);
    expect(count('processed_outputs'), 1);
    expect(await repository.listUploadResults(), isEmpty);
    for (final item in blocked.items) {
      expect(
        count(
          'output_references',
          where: 'owner_id=? AND output_id=?',
          values: [item.id, confirmed.$3.id],
        ),
        1,
      );
    }
    final deliberate = await repository.enqueueUploads(
      intentId: 'unknown-policy-explicit-again',
      processing: [selection(recipe())],
      targetIds: targets,
      forceAgain: true,
    );
    final deliberateJob = (await repository.listUploadProcessingJobs())
        .singleWhere((job) => job.batchId == deliberate.id);
    expect(deliberateJob.state, UploadProcessingState.queued);
    expect(
      deliberate.items.map((i) => i.state),
      everyElement(PublishState.waiting),
    );
    expect(deliberate.items.every((i) => i.processingPending), isTrue);
    expect(deliberateJob.plan.canonical, confirmed.$2.plan.canonical);
    expect(count('upload_attempts'), 2);
    expect(count('processed_outputs'), 1);
  });

  test('UT-046 UT-062 IT-004 partial exact policy rejects changed recipe and same alias new target UUID receipts', () async {
    final confirmed = await confirmedPixels('exact-receipt-identity-source');
    await persistControlledReceipts(confirmed.$1);
    final changed = await enqueue('exact-recipe-changed', [
      selection(recipe(longestSide: 4)),
    ]);
    expect(
      changed.items.map((i) => i.state),
      everyElement(PublishState.waiting),
    );
    expect(
      changed.items.every((i) => i.processingPending && i.resultId == null),
      isTrue,
    );
    final replacementTarget = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '冻结目标 0',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    final another = await repository.enqueueUploads(
      intentId: 'exact-target-identity-changed',
      processing: [selection(recipe())],
      targetIds: [replacementTarget],
    );
    expect(another.items.single.state, PublishState.waiting);
    expect(another.items.single.resultId, isNull);
    expect(another.items.single.target.id, replacementTarget);
    expect(another.items.single.processingPending, isTrue);
    expect(count('upload_attempts'), 2);
    expect(count('processed_outputs'), 1);
  });

  test('UT-046 UT-062 IT-004 partial reopening unfinished running job with cancelled dependents retires source protection without pixels', () async {
    final queued = await enqueue('cancelled-running-recovery', [
      selection(recipe()),
    ]);
    final job = await claim(
      (await repository.listUploadProcessingJobs()).single.id,
    );
    // Normal guard finalization precedes the durable stop-boundary fixture;
    // this does not leave actual IO alive or claim a hardware crash test.
    await finishJob(job.id, interrupted: true);
    await repository.cancelUploadItems(queued.items.map((i) => i.id));
    await repository.close();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      db.execute(
        'UPDATE upload_processing_jobs SET state=?,output_id=NULL WHERE id=?',
        ['running', job.id],
      );
      db.execute(
        'INSERT INTO version_references(id,version_id,owner_type,owner_id) VALUES(?,?,?,?)',
        [
          '00000000-0000-4000-8000-000000000901',
          asset.version.id,
          'task',
          job.id,
        ],
      );
      expect(db.select('SELECT id FROM processed_outputs'), isEmpty);
    } finally {
      db.close();
    }
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final restored = (await repository.listUploadProcessingJobs()).single;
    expect(restored.id, job.id);
    expect(restored.state, UploadProcessingState.cancelled);
    expect(restored.outputId, isNull);
    expect(await repository.beginUploadProcessingJob(job.id), isNull);
    expect(
      count('version_references', where: 'owner_type=?', values: ['task']),
      0,
    );
    expect(count('processed_outputs'), 0);
    expect(count('upload_attempts'), 0);
    final restoredBatch = await batch(queued.id);
    expect(
      restoredBatch.items.map((i) => i.id).toList(),
      queued.items.map((i) => i.id).toList(),
    );
    expect(
      restoredBatch.items.map((i) => i.state),
      everyElement(PublishState.cancelled),
    );
    expect(await repository.verifyCopy(asset), CopyAvailability.available);
  });

  test('UT-046 UT-062 IT-004 partial duplicate selections and targets share one real output without original fallback', () async {
    final chosen = selection(recipe());
    final queued = await enqueue('shared-duplicates', [chosen, chosen]);
    final jobs = await repository.listUploadProcessingJobs();
    expect(jobs, hasLength(1));
    expect(queued.items, hasLength(2));
    final repeated = await enqueue('shared-duplicates', [chosen, chosen]);
    expect(repeated.id, queued.id);
    expect(
      repeated.items.map((i) => i.id).toList(),
      queued.items.map((i) => i.id).toList(),
    );
    expect((await repository.listUploadProcessingJobs()), hasLength(1));
    expect(queued.items.map((i) => i.processingJobId).toSet(), {
      jobs.single.id,
    });
    for (final item in queued.items) {
      expect(item.state, PublishState.waiting);
      expect(item.waitReason, QueueWaitReason.processing);
      expect(item.attemptCount, 0);
      expect(await repository.beginUploadAttempt(item.id), isNull);
      await repository.wakeUploadItem(item.id);
      expect(await repository.beginUploadAttempt(item.id), isNull);
      expect(await repository.listUploadAttempts(item.id), isEmpty);
    }
    expect(count('file_leases'), 0);
    expect(count('output_leases'), 0);
    final job = await claim(jobs.single.id);
    final output = await process(job);
    expect(output.usable, isTrue);
    expect(output.version!.width, 6);
    expect(output.version!.height, 4);
    await repository.cancelUploadItems([queued.items.first.id]);
    await repository.setUploadItemPaused(queued.items[1].id, true);
    await finishJob(job.id, outputId: output.id);
    final ready = await batch(queued.id);
    expect(ready.items, hasLength(2));
    expect(ready.items.first.state, PublishState.cancelled);
    expect(ready.items.first.processingPending, isTrue);
    expect(ready.items[1].state, PublishState.paused);
    for (final item in ready.items.skip(1)) {
      expect(item.input.kind, UploadInputKind.processed);
      expect(item.input.referenceId, output.id);
      expect(item.input.version, output.version);
      expect(item.input.policyKey, job.plan.policyKey);
      expect(item.attemptCount, 0);
    }
    await repository.setUploadItemPaused(ready.items.last.id, false);
    expect((await batch(queued.id)).items.last.state, PublishState.queued);
    expect(count('processed_outputs'), 1);
    expect(count('upload_attempts'), 0);
    final execution = await repository.beginUploadAttempt(ready.items.last.id);
    expect(execution, isNotNull);
    try {
      expect(execution!.item.input.kind, UploadInputKind.processed);
      expect(execution.file.path, output.file!.path);
      expect(count('file_leases'), 0);
      expect(count('output_leases'), 1);
    } finally {
      if (execution != null) await settleUnsent(execution);
    }
  });

  test('UT-046 UT-062 IT-004 partial ready B dispatches independently while A waits or fails and paused A resumes legally', () async {
    final queued = await enqueue('independent-jobs', [
      selection(recipe(longestSide: 0)),
      selection(recipe(longestSide: 4)),
    ]);
    final jobs = await repository.listUploadProcessingJobs();
    expect(jobs, hasLength(2));
    final a = jobs.singleWhere((j) => j.plan.recipe.longestSide == 0);
    final b = jobs.singleWhere((j) => j.plan.recipe.longestSide == 4);
    final aItems = queued.items
        .where((i) => i.processingJobId == a.id)
        .toList();
    final bItems = queued.items
        .where((i) => i.processingJobId == b.id)
        .toList();
    final bRunning = await claim(b.id);
    final output = await process(bRunning);
    await finishJob(b.id, outputId: output.id);
    expect(
      (await repository.listUploadProcessingJobs())
          .singleWhere((j) => j.id == a.id)
          .state,
      UploadProcessingState.queued,
    );
    final execution = await repository.beginUploadAttempt(bItems.first.id);
    expect(execution, isNotNull);
    if (execution != null) await settleUnsent(execution);
    await repository.wakeUploadItem(bItems.first.id);
    await repository.setUploadItemPaused(aItems.last.id, true);
    final aRunning = await claim(a.id);
    await expectLater(process(aRunning), throwsA(isA<ProcessingFailure>()));
    await finishJob(a.id, failureMessage: '共享引擎拒绝无效最长边；原图未上传。');
    var current = await batch(queued.id);
    expect(
      current.items.singleWhere((i) => i.id == aItems.first.id).state,
      PublishState.failed,
    );
    expect(
      current.items.singleWhere((i) => i.id == aItems.last.id).state,
      PublishState.paused,
    );
    await repository.setUploadItemPaused(aItems.last.id, false);
    current = await batch(queued.id);
    expect(
      current.items.singleWhere((i) => i.id == aItems.last.id).state,
      PublishState.failed,
    );
    expect(await repository.beginUploadAttempt(aItems.last.id), isNull);
    for (final item in current.items.where((i) => i.processingJobId == b.id)) {
      expect(item.state, PublishState.queued);
      expect(item.input.referenceId, output.id);
    }
    final db = sqlite3.open(
      p.join(root.path, 'library.sqlite'),
      mode: OpenMode.readOnly,
    );
    try {
      final events = db.select(
        'SELECT state FROM upload_events WHERE item_id=? ORDER BY rowid',
        [aItems.last.id],
      );
      expect(
        events.map((r) => r['state']).toList(),
        containsAllInOrder(['paused', 'waiting', 'failed']),
      );
    } finally {
      db.close();
    }
    final original = await repository.originalFor(asset);
    final originalBytes = await original.readAsBytes();
    final outputBytes = await output.file!.readAsBytes();
    final clear = await repository.prepareUploadHistoryClear(
      publicationIds: aItems.map((i) => i.id),
      importedHistoryIds: const [],
    );
    expect(clear.eligibleCount, 2);
    await repository.clearUploadHistory(clear, confirmHistoryRemoval: true);
    expect(await original.readAsBytes(), originalBytes);
    expect(await output.file!.readAsBytes(), outputBytes);
    expect((await repository.getOutput(output.id)).usable, isTrue);
  });

  test('UT-046 UT-062 IT-004 partial queued reopen retains source UUID version parameters retention and frozen targets', () async {
    final initial = await repository.loadSettings();
    await repository.saveSettings(
      initial,
      DeviceSettings(defaultOutputRetention: OutputRetention.week),
      defaultTargetIds: targets,
    );
    final chosen = selection(
      ProcessingRecipe(
        operation: ProcessingOperation.compress,
        mode: ProcessingMode.sizeFirst,
        outputFormat: ProcessingFormat.jpeg,
        longestSide: 5,
        quality: 73,
        backgroundConfirmed: true,
      ),
    );
    final queued = await enqueue('frozen-plan', [chosen]);
    final originalJob = (await repository.listUploadProcessingJobs()).single;
    await repository.saveTarget(
      id: targets.first,
      service: ImageHostService.catbox,
      alias: '稍后改名',
      anonymous: false,
      credential: 'synthetic-replaced-key',
    );
    final newer = await repository.loadSettings();
    await repository.saveSettings(
      newer,
      DeviceSettings(
        quality: 12,
        longestSide: 900,
        processingMode: ProcessingMode.fidelity,
        defaultOutputRetention: OutputRetention.hour,
      ),
      defaultTargetIds: [targets.last],
    );
    await reopen();
    final restored = (await repository.listUploadProcessingJobs()).single;
    expect(restored.id, originalJob.id);
    expect(restored.plan.canonical, originalJob.plan.canonical);
    expect(restored.plan.assetIds, [asset.id]);
    expect(restored.plan.versions, [asset.version]);
    expect(restored.retention, OutputRetention.week);
    expect(restored.state, UploadProcessingState.queued);
    expect(restored.plan.toJson().toString(), isNot(contains(root.path)));
    final current = await batch(queued.id);
    expect(current.items.map((i) => i.target.id).toList(), targets);
    expect(current.items.first.target.alias, '冻结目标 0');
    expect(current.items.every((i) => i.processingPending), isTrue);
    final running = await claim(restored.id);
    final output = await process(running);
    await finishJob(running.id, outputId: output.id);
    expect(output.request.quality, 73);
    expect(output.request.longestSide, 5);
    expect(output.request.outputFormat, ProcessingFormat.jpeg);
    expect(
      output.expiresAt.difference(output.createdAt),
      OutputRetention.week.duration,
    );
  });

  test('UT-046 UT-062 IT-004 partial ready output with unfinished running log recovers same UUID without pixel rerun', () async {
    final queued = await enqueue('ready-before-job-confirmation', [
      selection(recipe()),
    ]);
    final job = await claim(
      (await repository.listUploadProcessingJobs()).single.id,
    );
    final output = await process(job);
    final bytes = await output.file!.readAsBytes();
    // Drain the real finished worker normally, leaving the publications bound
    // to their original source. Only then inject the persisted stop boundary.
    await finishJob(job.id, interrupted: true);
    await repository.close();
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      db.execute(
        'UPDATE upload_processing_jobs SET state=?,output_id=? WHERE id=?',
        ['running', output.id, job.id],
      );
      expect(db.select('SELECT id FROM processed_outputs'), hasLength(1));
    } finally {
      db.close();
    }
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final recovered = (await repository.listUploadProcessingJobs()).single;
    expect(recovered.id, job.id);
    expect(recovered.state, UploadProcessingState.ready);
    expect(recovered.outputId, output.id);
    expect(count('processed_outputs'), 1);
    expect(await output.file!.readAsBytes(), bytes);
    for (final item in (await batch(queued.id)).items) {
      expect(item.input.referenceId, output.id);
      expect(item.input.version, output.version);
      expect(item.state, PublishState.queued);
      expect(item.attemptCount, 0);
    }
    expect(
      count('version_references', where: 'owner_id=?', values: [job.id]),
      0,
    );
    expect(
      count('output_references', where: 'output_id=?', values: [output.id]),
      2,
    );
  });

  test('UT-046 UT-062 IT-004 partial missing frozen bytes wait explicitly and require exact repair plus processing retry', () async {
    final queued = await enqueue('missing-source', [selection(recipe())]);
    final original = await repository.originalFor(asset);
    final bytes = await original.readAsBytes();
    final job = (await repository.listUploadProcessingJobs()).single;
    await original.delete();
    final running = await claim(job.id);
    await expectLater(process(running), throwsA(isA<ResourceFailure>()));
    await finishJob(
      job.id,
      inputUnavailable: true,
      failureMessage: '冻结来源缺失，未退回原图。',
    );
    for (final item in (await batch(queued.id)).items) {
      expect(item.state, PublishState.waiting);
      expect(item.waitReason, QueueWaitReason.inputUnavailable);
      expect(item.input.version, asset.version);
      expect(item.attemptCount, 0);
      expect(await repository.beginUploadAttempt(item.id), isNull);
    }
    await expectLater(
      repository.retryUploadProcessingJob(job.id),
      throwsA(isA<StateError>()),
    );
    await original.writeAsBytes(bytes, flush: true);
    expect(
      (await repository.listUploadProcessingJobs()).single.state,
      UploadProcessingState.waiting,
    );
    expect(await repository.beginUploadProcessingJob(job.id), isNull);
    await repository.retryUploadProcessingJob(job.id);
    final repaired = (await repository.listUploadProcessingJobs()).single;
    expect(repaired.state, UploadProcessingState.queued);
    expect(repaired.plan.canonical, job.plan.canonical);
    final output = await process(await claim(job.id));
    await finishJob(job.id, outputId: output.id);
    expect(
      (await batch(queued.id)).items.map((i) => i.state),
      everyElement(PublishState.queued),
    );
    expect(count('upload_attempts'), 0);
  });

  test('UT-046 UT-062 IT-004 partial cancelling every queued dependent releases durable job references and history clear keeps original bytes', () async {
    final queued = await enqueue('cancel-queued-job', [selection(recipe())]);
    final job = (await repository.listUploadProcessingJobs()).single;
    final original = await repository.originalFor(asset);
    final bytes = await original.readAsBytes();
    expect(
      count('version_references', where: 'owner_id=?', values: [job.id]),
      1,
    );
    await repository.cancelUploadItems(queued.items.map((i) => i.id));
    expect(
      (await repository.listUploadProcessingJobs()).single.state,
      UploadProcessingState.cancelled,
    );
    expect(
      count('version_references', where: 'owner_type=?', values: ['task']),
      0,
    );
    expect(await repository.beginUploadProcessingJob(job.id), isNull);
    final clear = await repository.prepareUploadHistoryClear(
      publicationIds: queued.items.map((i) => i.id),
      importedHistoryIds: const [],
    );
    expect(clear.eligibleCount, 2);
    expect(
      (await repository.clearUploadHistory(
        clear,
        confirmHistoryRemoval: true,
      )).removedCount,
      2,
    );
    expect(await original.readAsBytes(), bytes);
    expect((await repository.getAsset(asset.id))!.version, asset.version);
    await reopen();
    expect(
      count('version_references', where: 'owner_type=?', values: ['task']),
      0,
    );
    expect(
      await enqueue('cancel-queued-job', [selection(recipe())]),
      isA<UploadBatch>()
          .having((b) => b.id, 'stable intent ledger', queued.id)
          .having((b) => b.items, 'cleared publications', isEmpty),
    );
  });

  test('UT-046 UT-062 IT-004 partial cancelled intent cannot clear or export completed history while real processing leases remain', () async {
    final queued = await enqueue('active-cancelled-job', [selection(recipe())]);
    final job = await claim(
      (await repository.listUploadProcessingJobs()).single.id,
    );
    final entered = Completer<void>(), release = Completer<void>();
    final worker = ProcessingCoordinator(repository).process(
      job.plan.assetIds,
      job.plan.bind,
      displayName: '实际受保护处理.png',
      retention: job.retention,
      onOutputIntent: (intent) async {
        await repository.recordUploadProcessingOutput(job.id, intent.id);
        entered.complete();
        await release.future;
      },
    );
    unawaited(
      worker.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!entered.isCompleted) entered.completeError(error, stack);
        },
      ),
    );
    late final ProcessedOutput output;
    try {
      await entered.future;
      expect(count('file_leases'), 1);
      await repository.cancelUploadItems(queued.items.map((i) => i.id));
      final clear = await repository.prepareUploadHistoryClear(
        publicationIds: queued.items.map((i) => i.id),
        importedHistoryIds: const [],
      );
      expect(clear.eligibleCount, 0);
      expect(clear.preservedCount, 2);
      expect(
        clear.preserved.map((i) => i.reason),
        everyElement(UploadHistoryProtection.inputInUse),
      );
      final snapshot = await repository.captureBackupSnapshot(
        mode: BackupMode.metadata,
      );
      try {
        expect(snapshot.manifest.history, isEmpty);
      } finally {
        await snapshot.release();
      }
    } finally {
      if (!release.isCompleted) release.complete();
      output = await worker;
      await finishJob(job.id, outputId: output.id);
    }
    expect(output.usable, isTrue);
    expect(
      (await batch(queued.id)).items.map((i) => i.state),
      everyElement(PublishState.cancelled),
    );
    expect(count('file_leases'), 0);
    final snapshot = await repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    try {
      expect(
        snapshot.manifest.history.map((h) => h.id).toSet(),
        queued.items.map((i) => i.id).toSet(),
      );
    } finally {
      await snapshot.release();
    }
    final clear = await repository.prepareUploadHistoryClear(
      publicationIds: queued.items.map((i) => i.id),
      importedHistoryIds: const [],
    );
    expect(clear.eligibleCount, 2);
    final bytes = await output.file!.readAsBytes();
    await repository.clearUploadHistory(clear, confirmHistoryRemoval: true);
    expect(await output.file!.readAsBytes(), bytes);
    expect((await repository.getOutput(output.id)).usable, isTrue);
    expect(await repository.verifyCopy(asset), CopyAvailability.available);
  });
}
