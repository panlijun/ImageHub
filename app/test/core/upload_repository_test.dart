import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_store.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_database.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';

class QueueTestSecrets implements SecretStore {
  final values = <String, String>{};
  bool failWrites = false, failReads = false, corruptWrites = false;
  @override
  Future<void> write(String reference, String value) async {
    if (failWrites) throw const SecretStorageException();
    values[reference] = corruptWrites
        ? 'https://ibb.co/remoteID/incorrectManagementToken012345'
        : value;
  }

  @override
  Future<String?> read(String reference) async {
    if (failReads) throw const SecretStorageException();
    return values[reference];
  }

  @override
  Future<void> delete(String reference) async {
    values.remove(reference);
  }
}

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late QueueTestSecrets secrets;
  late ImageAsset asset;
  late String target;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost-upload-repository-',
    );
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final bytes = img.encodePng(img.Image(width: 8, height: 6));
    asset = (await repository.importResource(
      PlatformResource(
        displayName: '冻结输入.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    target = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '创建名称',
      anonymous: false,
      credential: 'synthetic-upload-key-A',
    );
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });
  Future<UploadBatch> enqueue(
    String intent, {
    bool forceAgain = false,
    String? targetId,
  }) => repository.enqueueUploads(
    intentId: intent,
    assetIds: [asset.id],
    targetIds: [targetId ?? target],
    allowOriginalMetadata: true,
    forceAgain: forceAgain,
  );
  Future<void> reopen() async {
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  }

  ProviderUploadSuccess catboxSuccess([String name = 'fixture.png']) =>
      ProviderUploadSuccess(
        service: ImageHostService.catbox,
        remoteId: name,
        directUrl: Uri.parse('https://files.catbox.moe/$name'),
      );
  Future<UploadExecution> begin(String itemId) async =>
      (await repository.beginUploadAttempt(itemId))!;
  Future<void> finish(
    UploadExecution execution,
    ProviderUploadResult result, {
    Duration? retryDelay,
  }) async {
    try {
      await repository.finishUploadAttempt(
        execution,
        result,
        accumulatedRunning: const Duration(seconds: 2),
        retryDelay: retryDelay,
      );
    } finally {
      await execution.release();
    }
  }

  test('UT-044 UT-051 frozen input target snapshot survives reopen and dispatch resolves current credential', () async {
    await expectLater(
      repository.enqueueUploads(
        intentId: 'not-confirmed',
        assetIds: [asset.id],
        targetIds: [target],
      ),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(await repository.listUploadBatches(), isEmpty);
    final batch = await enqueue('frozen');
    await repository.saveTarget(
      id: target,
      service: ImageHostService.catbox,
      alias: '后续名称',
      anonymous: false,
      credential: 'synthetic-upload-key-B',
    );
    await reopen();
    final restored = (await repository.listUploadBatches()).single;
    expect(restored.id, batch.id);
    expect(restored.items.single.input.version, asset.version);
    expect(restored.items.single.input.policyKey, 'original-confirmed-v1');
    expect(restored.items.single.target.alias, '创建名称');
    final execution = await begin(batch.items.single.id);
    expect(execution.target.credential, 'synthetic-upload-key-B');
    expect(execution.item.attemptCount, 1);
    expect(execution.item.currentAttemptId, execution.attemptId);
    expect(
      await repository.authorizeUploadRequest(execution.attemptId),
      isTrue,
    );
    expect(
      await repository.authorizeUploadRequest(execution.attemptId),
      isFalse,
    );
    await finish(execution, catboxSuccess());
    await repository.removeTarget(target);
    final result = (await repository.listUploadResults()).single;
    expect(result.target.alias, '创建名称');
    expect(result.target.id, target);
  });

  test('UT-048 UT-049 intent idempotence success reuse and explicit force again retain independent history', () async {
    final batch = await enqueue('once');
    expect((await enqueue('once')).id, batch.id);
    final execution = await begin(batch.items.single.id);
    await repository.authorizeUploadRequest(execution.attemptId);
    await finish(execution, catboxSuccess());
    await repository.finishUploadAttempt(
      execution,
      catboxSuccess(),
      accumulatedRunning: Duration.zero,
    );
    expect(await repository.listUploadResults(), hasLength(1));
    final reused = await enqueue('reuse');
    expect(reused.items.single.state, PublishState.succeeded);
    expect(reused.items.single.attemptCount, 0);
    expect(await repository.beginUploadAttempt(reused.items.single.id), isNull);
    final again = await enqueue('explicit-again', forceAgain: true);
    final second = await begin(again.items.single.id);
    await repository.authorizeUploadRequest(second.attemptId);
    await finish(second, catboxSuccess('second.png'));
    expect(await repository.listUploadResults(), hasLength(2));
  });

  test('UT-043 UT-057 current account generation rejects stale credential before request', () async {
    final batch = await enqueue('generation');
    final execution = await begin(batch.items.single.id);
    await repository.saveTarget(
      id: target,
      service: ImageHostService.catbox,
      alias: '更新名称',
      anonymous: false,
      credential: 'synthetic-upload-key-C',
    );
    expect(
      await repository.authorizeUploadRequest(execution.attemptId),
      isFalse,
    );
    await finish(
      execution,
      const ProviderUploadFailure(
        UploadFailureKind.targetUnavailable,
        UploadDeliveryEvidence.notSent,
      ),
    );
    final item = (await repository.listUploadBatches()).single.items.single;
    expect(item.state, PublishState.waiting);
    expect(item.waitReason, QueueWaitReason.authorization);
    expect(
      (await repository.listUploadAttempts(item.id))
          .single
          .requestMayHaveStarted,
      isFalse,
    );
    await repository.wakeUploadItem(item.id);
    final second = await begin(item.id);
    expect(second.target.credential, 'synthetic-upload-key-C');
    await finish(
      second,
      const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
    );
  });

  test('UT-044 missing frozen bytes creates input wait without a fabricated attempt', () async {
    final batch = await enqueue('missing');
    final file = await repository.originalFor(asset);
    await file.delete();
    expect(await repository.beginUploadAttempt(batch.items.single.id), isNull);
    final item = (await repository.listUploadBatches()).single.items.single;
    expect(item.state, PublishState.waiting);
    expect(item.waitReason, QueueWaitReason.inputUnavailable);
    expect(await repository.listUploadAttempts(item.id), isEmpty);
    await repository.cancelUploadItems([item.id]);
  });

  test(
    'UT-054 pause blocks only unstarted items and retains wait conditions',
    () async {
      final other = await repository.saveTarget(
        service: ImageHostService.catbox,
        alias: '匿名',
        anonymous: false,
        credential: 'SyntheticAccountFixture0123456789',
      );
      final batch = await repository.enqueueUploads(
        intentId: 'pause',
        assetIds: [asset.id],
        targetIds: [target, other],
        allowOriginalMetadata: true,
      );
      final execution = await begin(batch.items.first.id);
      await repository.setUploadWaiting(
        batch.items.last.id,
        QueueWaitReason.network,
      );
      await repository.setUploadBatchPaused(batch.id, true);
      final paused = (await repository.listUploadBatches()).single;
      expect(paused.items.first.state, PublishState.running);
      expect(paused.items.last.state, PublishState.paused);
      expect(await repository.beginUploadAttempt(paused.items.last.id), isNull);
      await finish(execution, catboxSuccess());
      await repository.setUploadBatchPaused(batch.id, false);
      final resumed = (await repository.listUploadBatches()).single.items.last;
      expect(resumed.state, PublishState.waiting);
      expect(resumed.waitReason, QueueWaitReason.network);
    },
  );

  test(
    'UT-055 success committed before cancellation remains succeeded',
    () async {
      final item = (await enqueue('success-first')).items.single;
      final execution = await begin(item.id);
      await repository.authorizeUploadRequest(execution.attemptId);
      await finish(execution, catboxSuccess());
      await repository.cancelUploadItems([item.id]);
      expect(
        (await repository.listUploadBatches()).single.items.single.state,
        PublishState.succeeded,
      );
      expect((await repository.listUploadResults()).single.late, isFalse);
    },
  );

  test('UT-056 UT-057 cancelled running input stays protected until actual IO ends and late success is independent', () async {
    final item = (await enqueue('cancel-first')).items.single;
    final execution = await begin(item.id);
    await repository.authorizeUploadRequest(execution.attemptId);
    await repository.cancelUploadItems([item.id]);
    expect(await repository.beginUploadAttempt(item.id), isNull);
    await expectLater(
      repository.purgeAssets([asset.id], confirmCopies: true),
      throwsStateError,
    );
    await repository.finishUploadAttempt(
      execution,
      catboxSuccess(),
      accumulatedRunning: const Duration(seconds: 2),
    );
    // Durable task reference may end here, but live lease still blocks purge.
    await expectLater(
      repository.purgeAssets([asset.id], confirmCopies: true),
      throwsStateError,
    );
    await execution.release();
    final batch = (await repository.listUploadBatches()).single;
    expect(batch.items.single.state, PublishState.cancelled);
    expect(batch.summary.cancelled, 1);
    expect((await repository.listUploadResults()).single.late, isTrue);
    expect(
      (await repository.purgeAssets([
        asset.id,
      ], confirmCopies: true)).copiesRemoved,
      1,
    );
  });

  test('UT-049 UT-060 unknown protects input and duplicate intents never quietly resend', () async {
    final item = (await enqueue('unknown')).items.single;
    final execution = await begin(item.id);
    await repository.authorizeUploadRequest(execution.attemptId);
    await finish(
      execution,
      const ProviderUploadUnknown(UploadFailureKind.timeout),
    );
    await repository.wakeUploadItem(item.id);
    expect(
      (await repository.listUploadBatches()).single.items.single.state,
      PublishState.unknown,
    );
    await expectLater(
      repository.purgeAssets([asset.id], confirmCopies: true),
      throwsStateError,
    );
    final duplicate = await enqueue('unknown-duplicate');
    expect(duplicate.items.single.state, PublishState.unknown);
    expect(
      await repository.beginUploadAttempt(duplicate.items.single.id),
      isNull,
    );
    expect(
      (await enqueue(
        'unknown-confirmed-again',
        forceAgain: true,
      )).items.single.state,
      PublishState.queued,
    );
  });

  for (final sent in [false, true]) {
    test(
      'UT-051 UT-062 reopen ${sent ? 'request marker becomes unknown' : 'unsent running becomes interrupted'}',
      () async {
        final item = (await enqueue('recover')).items.single;
        final execution = await begin(item.id);
        if (sent) await repository.authorizeUploadRequest(execution.attemptId);
        // Simulates an ended process worker, without claiming hardware shutdown.
        await execution.release();
        await reopen();
        final restored =
            (await repository.listUploadBatches()).single.items.single;
        expect(
          restored.state,
          sent ? PublishState.unknown : PublishState.interrupted,
        );
        expect(
          (await repository.listUploadAttempts(item.id)).single.endedAt,
          isNotNull,
        );
        await expectLater(
          repository.purgeAssets([asset.id], confirmCopies: true),
          throwsStateError,
        );
        if (sent) {
          await repository.wakeUploadItem(item.id);
          expect(await repository.beginUploadAttempt(item.id), isNull);
        } else {
          await repository.wakeUploadItem(item.id);
          final resumed = await begin(item.id);
          expect(resumed.generation, 2);
          await finish(
            resumed,
            const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
          );
        }
      },
    );
  }

  test('UT-058 UT-060 uncertain evidence cannot be converted into retry by supplied delay', () async {
    final item = (await enqueue('uncertain')).items.single;
    final execution = await begin(item.id);
    await repository.authorizeUploadRequest(execution.attemptId);
    await finish(
      execution,
      const ProviderUploadFailure(
        UploadFailureKind.network,
        UploadDeliveryEvidence.uncertain,
      ),
      retryDelay: const Duration(seconds: 2),
    );
    final restored = (await repository.listUploadBatches()).single.items.single;
    expect(restored.state, PublishState.unknown);
    expect(restored.retryDelay, isNull);
  });

  test(
    'UT-059 UT-067 retry duration persists independently from UTC and pause',
    () async {
      final item = (await enqueue('retry-duration')).items.single;
      final execution = await begin(item.id);
      await finish(
        execution,
        const ProviderUploadFailure(
          UploadFailureKind.rateLimited,
          UploadDeliveryEvidence.confirmedRejected,
        ),
        retryDelay: const Duration(seconds: 10),
      );
      await repository.setUploadBatchPaused(item.batchId, true);
      await reopen();
      final restored =
          (await repository.listUploadBatches()).single.items.single;
      expect(restored.state, PublishState.paused);
      expect(restored.retryDelay, const Duration(seconds: 10));
      expect(restored.accumulatedRunning, const Duration(seconds: 2));
      expect(restored.attemptCount, 1);
    },
  );

  test('UT-067 UT-068 monotonic checkpoints only increase current running duration and survive recovery', () async {
    final item = (await enqueue('checkpoint')).items.single;
    final execution = await begin(item.id);
    await repository.checkpointUploadAttempt(
      execution.attemptId,
      const Duration(seconds: 21),
    );
    await repository.checkpointUploadAttempt(
      execution.attemptId,
      const Duration(seconds: 2),
    );
    await execution.release();
    await reopen();
    final restored = (await repository.listUploadBatches()).single.items.single;
    expect(restored.accumulatedRunning, const Duration(seconds: 21));
    await repository.checkpointUploadAttempt(
      execution.attemptId,
      const Duration(seconds: 99),
    );
    expect(
      (await repository.listUploadBatches())
          .single
          .items
          .single
          .accumulatedRunning,
      const Duration(seconds: 21),
    );
  });

  test('UT-046 UT-066 upload task protects real processed output from expiry cleanup', () async {
    final output = await ProcessingCoordinator(repository).process(
      [asset.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        longestSide: 4,
      ),
      displayName: '独立输出.png',
      retention: OutputRetention.hour,
    );
    final batch = await repository.enqueueUploads(
      intentId: 'processed',
      outputIds: [output.id],
      targetIds: [target],
    );
    final policy = batch.items.single.input.policyKey;
    expect(policy, contains('processed-confirmed-v1:'));
    expect(policy, isNot(contains('path')));
    final afterExpiry = output.expiresAt.add(const Duration(seconds: 1));
    final protected = await withClock(
      Clock.fixed(afterExpiry),
      () => repository.cleanupOutputs(),
    );
    expect(protected.protected, 1);
    expect((await repository.getOutput(output.id)).usable, isTrue);
    await repository.cancelUploadItems([batch.items.single.id]);
    final cleaned = await withClock(
      Clock.fixed(afterExpiry),
      () => repository.cleanupOutputs(),
    );
    expect(cleaned.removed, 1);
  });

  test('UT-044 UT-046 processing policy uses canonical digest while audit summary redacts credential collisions', () async {
    final output = await ProcessingCoordinator(repository).process(
      [asset.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        longestSide: 4,
      ),
      displayName: 'fidelity-output.png',
    );
    await repository.saveTarget(
      id: target,
      service: ImageHostService.catbox,
      alias: '策略测试',
      anonymous: false,
      credential: 'fidelity',
    );
    final batch = await repository.enqueueUploads(
      intentId: 'policy-redacted',
      outputIds: [output.id],
      targetIds: [target],
    );
    final input = batch.items.single.input;
    expect(
      input.policyKey,
      matches(RegExp(r'^processed-confirmed-v1:[a-f0-9]{64}$')),
    );
    expect(input.policyKey, isNot(contains('fidelity')));
    expect(input.processingSummary, contains('[已隐藏]'));
    expect(input.processingSummary, isNot(contains('fidelity')));
    final execution = await begin(batch.items.single.id);
    expect(execution.item.input.version, output.version);
    await finish(
      execution,
      const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
    );
    await reopen();
    expect(
      (await repository.listUploadBatches())
          .single
          .items
          .single
          .input
          .processingSummary,
      input.processingSummary,
    );
  });

  for (final totalBudget in [false, true]) {
    test(
      'UT-059 UT-068 durable ${totalBudget ? 'thirty minute running budget' : 'four attempt limit'} blocks another execution',
      () async {
        final item = (await enqueue('dispatch-limit')).items.single;
        for (var index = 0; index < (totalBudget ? 1 : 4); index++) {
          final execution = await begin(item.id);
          if (totalBudget) {
            await repository.checkpointUploadAttempt(
              execution.attemptId,
              const Duration(minutes: 30),
            );
          }
          await finish(
            execution,
            const ProviderUploadFailure(
              UploadFailureKind.authorization,
              UploadDeliveryEvidence.notSent,
            ),
          );
          await repository.wakeUploadItem(item.id);
        }
        expect(await repository.beginUploadAttempt(item.id), isNull);
        final restored =
            (await repository.listUploadBatches()).single.items.single;
        expect(restored.state, PublishState.failed);
        expect(restored.attemptCount, totalBudget ? 1 : 4);
        expect(
          (await repository.listUploadAttempts(item.id)).length,
          totalBudget ? 1 : 4,
        );
      },
    );
  }

  for (final readFault in [false, true]) {
    test(
      'UT-048 protected management ${readFault ? 'readback fault recovers secure reference' : 'write fault preserves ordinary success without plaintext'}',
      () async {
        final imgbb = await repository.saveTarget(
          service: ImageHostService.imgbb,
          alias: 'ImgBB',
          anonymous: false,
          credential: 'synthetic-imgbb-key',
        );
        final item = (await enqueue(
          'management',
          targetId: imgbb,
        )).items.single;
        final execution = await begin(item.id);
        await repository.authorizeUploadRequest(execution.attemptId);
        final management =
            'https://ibb.co/remoteID/syntheticManagementToken012345';
        secrets.failWrites = !readFault;
        secrets.failReads = readFault;
        await finish(
          execution,
          ProviderUploadSuccess(
            service: ImageHostService.imgbb,
            remoteId: 'remoteID',
            directUrl: Uri.parse('https://i.ibb.co/imageID/fixture.png'),
            viewerUrl: Uri.parse('https://ibb.co/remoteID'),
            managementSecret: SensitiveManagementSecret(management),
          ),
        );
        expect(
          (await repository.listUploadBatches()).single.items.single.state,
          PublishState.succeeded,
        );
        expect(
          (await repository.listUploadResults()).single.managementAvailable,
          isFalse,
        );
        secrets.failWrites = false;
        secrets.failReads = false;
        await reopen();
        expect(
          (await repository.listUploadResults()).single.managementAvailable,
          readFault,
        );
        await repository.close();
        final db = sqlite3.open('${root.path}/library.sqlite');
        try {
          final ordinary =
              db
                  .select(
                    "SELECT input_json,target_json,remote_id,direct_url,viewer_url FROM remote_upload_results",
                  )
                  .toString() +
              db
                  .select('SELECT proposal_json FROM upload_result_operations')
                  .toString() +
              db
                  .select(
                    'SELECT input_json,target_json,policy_key,message FROM upload_publications',
                  )
                  .toString();
          for (final secret in [
            management,
            'syntheticManagementToken012345',
            'synthetic-imgbb-key',
            'synthetic-upload-key-A',
          ]) {
            expect(ordinary, isNot(contains(secret)));
          }
        } finally {
          db.close();
        }
      },
    );
  }

  test(
    'UT-048 unsafe provider success never creates ordinary history',
    () async {
      final item = (await enqueue('unsafe')).items.single;
      final execution = await begin(item.id);
      await repository.authorizeUploadRequest(execution.attemptId);
      await finish(
        execution,
        ProviderUploadSuccess(
          service: ImageHostService.catbox,
          remoteId: 'fixture.png',
          directUrl: Uri.parse('https://evil.example/fixture.png'),
        ),
      );
      expect(await repository.listUploadResults(), isEmpty);
      expect(
        (await repository.listUploadBatches()).single.items.single.state,
        PublishState.unknown,
      );
    },
  );

  test('UT-048 mismatched management readback preserves ordinary result and never marks corrupt secret available', () async {
    final imgbb = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: 'ImgBB',
      anonymous: false,
      credential: 'synthetic-imgbb-key',
    );
    final item = (await enqueue(
      'corrupt-management',
      targetId: imgbb,
    )).items.single;
    final execution = await begin(item.id);
    await repository.authorizeUploadRequest(execution.attemptId);
    final beforeReferences = secrets.values.keys.toSet();
    secrets.corruptWrites = true;
    await finish(
      execution,
      ProviderUploadSuccess(
        service: ImageHostService.imgbb,
        remoteId: 'remoteID',
        directUrl: Uri.parse('https://i.ibb.co/imageID/fixture.png'),
        managementSecret: SensitiveManagementSecret(
          'https://ibb.co/remoteID/syntheticManagementToken012345',
        ),
      ),
    );
    expect(
      (await repository.listUploadResults()).single.managementAvailable,
      isFalse,
    );
    expect(
      (await repository.listUploadBatches()).single.items.single.state,
      PublishState.succeeded,
    );
    expect(secrets.values.keys.toSet(), beforeReferences);
  });

  test('UT-048 newly known management token masks all existing task and result snapshots durably on reopen', () async {
    const token = 'futureManagementToken012345';
    final namedAsset = (await repository.importResource(
      PlatformResource(
        displayName: '$token.png',
        openRead: () =>
            Stream.value(img.encodePng(img.Image(width: 7, height: 5))),
      ),
    )).asset!;
    await repository.saveTarget(
      id: target,
      service: ImageHostService.catbox,
      alias: token,
      anonymous: false,
    );
    final imgbb = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: token,
      anonymous: false,
      credential: 'synthetic-imgbb-key',
    );
    final prior = await repository.enqueueUploads(
      intentId: 'before-token-known',
      assetIds: [namedAsset.id],
      targetIds: [target],
      allowOriginalMetadata: true,
    );
    final current = await repository.enqueueUploads(
      intentId: 'token-confirmation',
      assetIds: [namedAsset.id],
      targetIds: [imgbb],
      allowOriginalMetadata: true,
    );
    expect(prior.items.single.input.displayName, contains(token));
    final execution = await begin(current.items.single.id);
    await repository.authorizeUploadRequest(execution.attemptId);
    await finish(
      execution,
      ProviderUploadSuccess(
        service: ImageHostService.imgbb,
        remoteId: 'remoteID',
        directUrl: Uri.parse('https://i.ibb.co/imageID/fixture.png'),
        managementSecret: SensitiveManagementSecret(
          'https://ibb.co/remoteID/$token',
        ),
      ),
    );
    secrets.failReads = true;
    await reopen();
    for (final batch in await repository.listUploadBatches()) {
      expect(batch.items.single.input.displayName, isNot(contains(token)));
      expect(batch.items.single.target.alias, isNot(contains(token)));
    }
    final result = (await repository.listUploadResults()).single;
    expect(result.input.displayName, isNot(contains(token)));
    expect(result.target.alias, isNot(contains(token)));
    secrets.failReads = false;
    await reopen();
    // Re-registering the confirmed result's UUID reference also protects a
    // fresh task created after reopening, while source names remain intact.
    final fresh = await repository.enqueueUploads(
      intentId: 'after-token-known',
      assetIds: [namedAsset.id],
      targetIds: [target],
      allowOriginalMetadata: true,
    );
    expect(fresh.items.single.input.displayName, isNot(contains(token)));
    expect(fresh.items.single.target.alias, isNot(contains(token)));
    await repository.close();
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      final ordinary =
          db
              .select('SELECT input_json,target_json FROM upload_publications')
              .toString() +
          db
              .select(
                'SELECT input_json,target_json FROM remote_upload_results',
              )
              .toString();
      expect(ordinary, isNot(contains(token)));
      expect(db.select('SELECT id FROM upload_publications'), hasLength(3));
    } finally {
      db.close();
    }
  });

  test('UT-093 own schema4 upgrades to current schema preserving stable library and account IDs; future refuses without rewrite', () async {
    await repository.close();
    var db = sqlite3.open('${root.path}/library.sqlite');
    for (final table in [
      'diagnostic_records',
      'restored_output_origins',
      'imported_upload_histories',
      'restore_operations',
      'upload_events',
      'upload_result_operations',
      'remote_upload_results',
      'upload_attempts',
      'upload_publications',
      'upload_processing_jobs',
      'upload_batches',
    ]) {
      db.execute('DROP TABLE $table');
    }
    db.execute('PRAGMA user_version=4');
    db.close();
    await reopen();
    expect((await repository.getAsset(asset.id))!.version, asset.version);
    expect((await repository.listTargets()).single.id, target);
    expect(await repository.listUploadBatches(), isEmpty);
    await enqueue('upgraded');
    await repository.close();
    db = sqlite3.open('${root.path}/library.sqlite');
    expect(
      db.select('PRAGMA user_version').single.values.single,
      librarySchemaVersion,
    );
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    db.execute('PRAGMA user_version=${librarySchemaVersion + 1}');
    db.close();
    await expectLater(
      LibraryRepository.open(root, secretStore: secrets),
      throwsA(isA<LibraryOpenException>()),
    );
    db = sqlite3.open('${root.path}/library.sqlite');
    expect(
      db.select('PRAGMA user_version').single.values.single,
      librarySchemaVersion + 1,
    );
    expect(db.select('SELECT id FROM upload_batches'), hasLength(1));
    db.close();
  });
}
