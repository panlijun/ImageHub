import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/image_processor.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/application/upload_processing_coordinator.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_processing_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

/// A real image engine with a controllable entrance. Cancellation requests do
/// not settle this future: opening the gate performs actual pixels/isolate IO
/// through super.process, and ProcessingCoordinator then handles cancellation.
/// This reproduces a worker that cannot finish immediately on a cancel signal.
class _GatedRealProcessor extends ImageProcessor {
  final _entered = <int, Completer<void>>{};
  final _gates = <int, Completer<void>>{};
  final calls = <int>[];
  final tokens = <int, CancellationToken?>{};
  final exited = <int>{};

  Future<void> entered(int side) =>
      (_entered[side] ??= Completer<void>()).future;

  void release(int side) {
    final gate = _gates[side] ??= Completer<void>();
    if (!gate.isCompleted) gate.complete();
  }

  void releaseAll() {
    for (final side in {..._gates.keys, ..._entered.keys}) {
      release(side);
    }
  }

  @override
  Future<ProcessingResult> process(
    ProcessingRequest request, {
    int memoryBudgetBytes = 512 * 1024 * 1024,
    CancellationToken? cancellation,
    File? destination,
  }) async {
    final side = request.longestSide;
    calls.add(side);
    tokens[side] = cancellation;
    final entered = _entered[side] ??= Completer<void>();
    if (!entered.isCompleted) entered.complete();
    final gate = _gates[side] ??= Completer<void>();
    await gate.future;
    try {
      return await super.process(
        request,
        memoryBudgetBytes: memoryBudgetBytes,
        destination: destination,
      );
    } finally {
      exited.add(side);
    }
  }
}

// IT-004 partial: actual local actors, database and pixel workers, without a
// provider request, remote result fixture, hardware interruption or PT claim.
void main() {
  const prefix = 'imagehost-upload-processing-coordinator-';
  late Directory sandbox, root;
  late LibraryRepository repository;
  late QueueTestSecrets secrets;
  late ImageAsset asset;
  late String target;
  late _GatedRealProcessor processor;
  final actors = <UploadProcessingCoordinator>[];

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(prefix);
    root = Directory(p.join(sandbox.path, 'library'));
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final pixels = img.Image(width: 16, height: 10);
    for (var y = 0; y < pixels.height; y++) {
      for (var x = 0; x < pixels.width; x++) {
        pixels.setPixelRgb(x, y, x * 11, y * 19, (x + y) * 8);
      }
    }
    final bytes = img.encodePng(pixels);
    asset = (await repository.importResource(
      PlatformResource(
        displayName: 'actor真实来源.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    target = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: 'actor目标',
      anonymous: false,
      credential: 'synthetic-actor-key',
    );
    processor = _GatedRealProcessor();
    actors.clear();
  });

  tearDown(() async {
    processor.releaseAll();
    for (final actor in actors) {
      await actor.close();
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

  UploadProcessingCoordinator actor() {
    final value = UploadProcessingCoordinator(
      repository,
      processor: processor,
      scanOnCreate: false,
    );
    actors.add(value);
    return value;
  }

  Future<UploadBatch> enqueue(String intent, List<int> sides) =>
      repository.enqueueUploads(
        intentId: intent,
        targetIds: [target],
        processing: [
          for (final side in sides)
            UploadProcessingSelection(
              assetIds: [asset.id],
              recipe: ProcessingRecipe(
                operation: ProcessingOperation.compress,
                mode: ProcessingMode.sizeFirst,
                longestSide: side,
              ),
            ),
        ],
      );

  Future<void> waitUntil(Future<bool> Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('真实处理 actor 未达到预期状态。');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<UploadPublication> publication(String id) async =>
      (await repository.listUploadBatches())
          .expand((b) => b.items)
          .singleWhere((item) => item.id == id);

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

  test('UT-046 UT-062 IT-004 partial real actor starts two jobs and ready B can dispatch while A retains actual input IO', () async {
    final settings = await repository.loadSettings();
    await repository.saveSettings(
      settings,
      DeviceSettings(processingConcurrency: 2),
      defaultTargetIds: [target],
    );
    final queued = await enqueue('actor-independent', [8, 4]);
    final jobs = await repository.listUploadProcessingJobs();
    final a = jobs.singleWhere((j) => j.plan.recipe.longestSide == 8);
    final b = jobs.singleWhere((j) => j.plan.recipe.longestSide == 4);
    final value = actor();
    await value.refresh();
    await Future.wait([processor.entered(8), processor.entered(4)])
        .timeout(const Duration(seconds: 15));
    expect(value.activeCount, 2);
    expect(count('file_leases'), 2);
    expect(count('upload_attempts'), 0);
    processor.release(4);
    await waitUntil(
      () async =>
          (await repository.listUploadProcessingJobs())
              .singleWhere((j) => j.id == b.id)
              .state ==
          UploadProcessingState.ready,
    );
    await waitUntil(() async => value.activeCount == 1);
    expect(value.activeCount, 1);
    expect(processor.exited, contains(4));
    expect(processor.exited, isNot(contains(8)));
    expect(
      (await repository.listUploadProcessingJobs())
          .singleWhere((j) => j.id == a.id)
          .state,
      UploadProcessingState.running,
    );
    final bItem = queued.items.singleWhere((i) => i.processingJobId == b.id);
    final execution = await repository.beginUploadAttempt(bItem.id);
    expect(execution, isNotNull);
    try {
      expect(execution!.item.input.kind, UploadInputKind.processed);
      expect(execution.item.input.version.width, 4);
      expect(count('file_leases'), 1);
      expect(count('output_leases'), 1);
      expect(
        await repository.beginUploadAttempt(
          queued.items.singleWhere((i) => i.processingJobId == a.id).id,
        ),
        isNull,
      );
    } finally {
      if (execution != null) {
        try {
          await repository.finishUploadAttempt(
            execution,
            const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
            accumulatedRunning: Duration.zero,
          );
        } finally {
          await execution.release();
        }
      }
    }
    processor.release(8);
    await waitUntil(() async => value.activeCount == 0);
    expect(value.failure, isNull);
    expect(
      (await repository.listUploadProcessingJobs()).map((j) => j.state),
      everyElement(UploadProcessingState.ready),
    );
    expect(count('processed_outputs', where: 'state=?', values: ['ready']), 2);
    expect(count('file_leases'), 0);
  });

  test('UT-046 UT-062 IT-004 partial actor and library close wait after cancellation until actual pixel process and finalizers exit', () async {
    await enqueue('actor-close-drain', [8]);
    final value = actor();
    await value.refresh();
    await processor.entered(8).timeout(const Duration(seconds: 15));
    final epoch = repository.executionEpoch;
    var actorClosed = false, libraryClosed = false;
    final closingActor = value.close().then((_) {
      actorClosed = true;
    });
    final closingLibrary = repository.close().then((_) {
      libraryClosed = true;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(processor.tokens[8]!.isCancelled, isTrue);
      expect(actorClosed, isFalse);
      expect(libraryClosed, isFalse);
      expect(processor.exited, isEmpty);
      expect(count('file_leases'), 1);
      expect(
        count('upload_processing_jobs', where: 'state=?', values: ['running']),
        1,
      );
    } finally {
      processor.release(8);
      await closingActor;
      await closingLibrary;
    }
    expect(processor.exited, contains(8));
    expect(value.activeCount, 0);
    expect(value.hasUnsettledIO, isFalse);
    expect(repository.executionEpoch, isNot(epoch));
    expect(count('file_leases'), 0);
    expect(count('output_leases'), 0);
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(
      (await repository.listUploadProcessingJobs()).single.state,
      UploadProcessingState.queued,
    );
    expect(count('upload_attempts'), 0);
  });

  test('UT-046 UT-062 IT-004 partial restore hold waits for actual process keeps leases and requires explicit batch continuation', () async {
    final queued = await enqueue('actor-restore-drain', [8]);
    final value = actor();
    await value.refresh();
    await processor.entered(8).timeout(const Duration(seconds: 15));
    var actorDrained = false, libraryHeld = false;
    final actorHold = value.holdForRestore().then((_) {
      actorDrained = true;
    });
    final libraryHold = repository.acquireRestoreHold().then((hold) {
      libraryHeld = true;
      return hold;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(value.restoreBlocked, isTrue);
      expect(processor.tokens[8]!.isCancelled, isTrue);
      expect(actorDrained, isFalse);
      expect(libraryHeld, isFalse);
      expect(processor.exited, isEmpty);
      expect(count('file_leases'), 1);
      expect(
        count('upload_processing_jobs', where: 'state=?', values: ['running']),
        1,
      );
    } finally {
      processor.release(8);
      await actorHold;
      final held = await libraryHold;
      await held.release();
    }
    expect(processor.exited, contains(8));
    expect(count('file_leases'), 0);
    expect(value.activeCount, 0);
    expect((await repository.listUploadBatches()).single.paused, isTrue);
    expect(
      (await publication(queued.items.single.id)).state,
      PublishState.paused,
    );
    value.resumeAfterRestore();
    await value.refresh();
    expect(processor.calls, [8]);
    expect(
      (await repository.listUploadProcessingJobs()).single.state,
      UploadProcessingState.queued,
    );
    await repository.setUploadBatchPaused(queued.id, false);
    await value.refresh();
    await waitUntil(
      () async =>
          (await repository.listUploadProcessingJobs()).single.state ==
          UploadProcessingState.ready,
    );
    await waitUntil(() async => value.activeCount == 0);
    expect(processor.calls, [8, 8]);
    expect(
      (await publication(queued.items.single.id)).input.kind,
      UploadInputKind.processed,
    );
    expect(count('upload_attempts'), 0);
  });

  test('UT-046 UT-062 IT-004 partial old execution epoch actor cannot write to reopened library or claim its later intent', () async {
    final queued = await enqueue('actor-old-epoch', [8]);
    final oldActor = actor();
    await oldActor.refresh();
    await processor.entered(8).timeout(const Duration(seconds: 15));
    processor.release(8);
    await waitUntil(() async => oldActor.activeCount == 0);
    final oldEpoch = oldActor.executionEpoch;
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(repository.executionEpoch, isNot(oldEpoch));
    final later = await enqueue('actor-later-epoch', [4]);
    final attemptsBefore = count('upload_attempts');
    final outputsBefore = count('processed_outputs');
    oldActor.resumeAfterRestore();
    await oldActor.refresh();
    expect(oldActor.activeCount, 0);
    expect(processor.calls, [8]);
    expect(count('upload_attempts'), attemptsBefore);
    expect(count('processed_outputs'), outputsBefore);
    expect(
      (await publication(later.items.single.id)).processingPending,
      isTrue,
    );
    expect(
      (await repository.listUploadProcessingJobs())
          .singleWhere((j) => j.batchId == later.id)
          .state,
      UploadProcessingState.queued,
    );
    expect(
      (await repository.listUploadProcessingJobs())
          .singleWhere((j) => j.batchId == queued.id)
          .state,
      UploadProcessingState.ready,
    );
  });

  test('UT-046 UT-062 IT-004 partial worker source mutation waits without upload and explicit retry uses repaired frozen bytes', () async {
    final source = File(p.join(root.path, asset.deviceCopy.relativePath));
    final originalBytes = await source.readAsBytes();
    final queued = await enqueue('actor-worker-source-changed', [8]);
    final job = (await repository.listUploadProcessingJobs()).single;
    final value = actor();
    await value.refresh();
    await processor.entered(8).timeout(const Duration(seconds: 15));
    expect(value.activeCount, 1);
    expect(repository.processingScheduler.activeCount, 1);
    expect(count('file_leases'), 1);
    expect(
      count('processed_outputs', where: 'state=?', values: ['writing']),
      1,
    );
    expect(count('upload_attempts'), 0);

    // Fault injection after lease/intent creation but before the real engine
    // checks the frozen version. This changes actual managed source bytes.
    await source.writeAsBytes([...originalBytes, 0], flush: true);
    processor.release(8);
    await waitUntil(
      () async =>
          (await repository.listUploadProcessingJobs()).single.state ==
          UploadProcessingState.waiting,
    );
    await waitUntil(() async => value.activeCount == 0);
    expect(processor.exited, contains(8));
    expect(repository.processingScheduler.activeCount, 0);
    expect(count('file_leases'), 0);
    expect(count('output_leases'), 0);
    expect(count('processed_outputs', where: 'state=?', values: ['failed']), 1);
    expect(value.failure, isNull);
    final waiting = await publication(queued.items.single.id);
    expect(waiting.state, PublishState.waiting);
    expect(waiting.waitReason, QueueWaitReason.inputUnavailable);
    expect(waiting.processingPending, isTrue);
    expect(waiting.attemptCount, 0);
    expect(await repository.beginUploadAttempt(waiting.id), isNull);
    expect(count('upload_attempts'), 0);

    // Repair alone grants no retry or original-upload permission.
    await source.writeAsBytes(originalBytes, flush: true);
    await value.refresh();
    expect(processor.calls, [8]);
    expect(
      (await repository.listUploadProcessingJobs()).single.state,
      UploadProcessingState.waiting,
    );
    await repository.retryUploadProcessingJob(job.id);
    await value.refresh();
    await waitUntil(
      () async =>
          (await repository.listUploadProcessingJobs()).single.state ==
          UploadProcessingState.ready,
    );
    await waitUntil(() async => value.activeCount == 0);
    final ready = await publication(waiting.id);
    expect(processor.calls, [8, 8]);
    expect(ready.input.kind, UploadInputKind.processed);
    expect(ready.processingPending, isFalse);
    expect(ready.attemptCount, 0);
    expect(count('upload_attempts'), 0);
    expect(count('file_leases'), 0);
    expect(count('output_leases'), 0);
    expect(repository.processingScheduler.activeCount, 0);
    expect(count('processed_outputs', where: 'state=?', values: ['ready']), 1);
    expect(value.failure, isNull);
  });
}
