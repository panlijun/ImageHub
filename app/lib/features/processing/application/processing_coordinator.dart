import 'dart:io';

import '../../../core/platform_resource.dart';
import '../../gallery/data/library_repository.dart';
import '../domain/output_models.dart';
import '../domain/processing_models.dart';
import 'image_processor.dart';
import 'processing_scheduler.dart';

/// Shared by every platform; native resource selection is outside this class.
class ProcessingCoordinator {
  const ProcessingCoordinator(
    this.repository, {
    this.processor = const ImageProcessor(),
  });
  final LibraryRepository repository;
  final ImageProcessor processor;

  Future<ProcessedOutput> process(
    Iterable<String> assetIds,
    ProcessingRequest Function(List<ProcessingInput>) createRequest, {
    required String displayName,
    OutputRetention? retention,
    CancellationToken? cancellation,
    Future<void> Function(OutputWriteIntent intent)? onOutputIntent,
    bool typedSourceFailures = false,
  }) async {
    final ids = List<String>.unmodifiable(assetIds);
    cancellation?.throwIfCancelled();
    final lease = await repository.acquireAssetLease(
      ids,
      purpose: '本地图片处理',
      typedSourceFailures: typedSourceFailures,
    );
    ProcessingPermit? permit;
    OutputWriteIntent? intent;
    ProcessingFailure? failure;
    Object? sourceFailure;
    try {
      permit = await repository.processingScheduler.acquire(
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      final inputs = List<ProcessingInput>.unmodifiable(
        lease.assets.map(
          (asset) => ProcessingInput(
            file: File(lease.pathsByVersion[asset.version.id]!),
            assetId: asset.id,
            version: asset.version,
          ),
        ),
      );
      final request = createRequest(inputs);
      final plan = processor.plan(
        request,
        memoryBudgetBytes: permit.memoryBudgetBytes,
      );
      intent = await repository.beginOutput(
        request,
        displayName: displayName,
        retention:
            retention ??
            repository.currentDeviceSettings.defaultOutputRetention,
        requiredStorageBytes:
            plan.outputSize.width * plan.outputSize.height * 8 + 1024 * 1024,
      );
      // Associate durable dependent work before any worker writes output bytes.
      await onOutputIntent?.call(intent);
      await repository.outputIntentBoundary();
      final result = await processor.process(
        request,
        memoryBudgetBytes: permit.memoryBudgetBytes,
        cancellation: cancellation,
        destination: intent.destination,
      );
      cancellation?.throwIfCancelled();
      return await repository.confirmOutput(intent.id, result);
    } catch (error) {
      if (typedSourceFailures &&
          ((error is ProcessingFailure &&
                  error.kind == ProcessingFailureKind.inputChanged) ||
              (error is ResourceFailure &&
                  const {
                    FailureKind.unavailable,
                    FailureKind.sourceMissing,
                    FailureKind.invalidImage,
                    FailureKind.permissionDenied,
                  }.contains(error.kind)))) {
        sourceFailure = error;
      }
      failure = error is ProcessingFailure
          ? error
          : ProcessingFailure(
              error is ResourceFailure && error.kind == FailureKind.cancelled
                  ? ProcessingFailureKind.cancelled
                  : ProcessingFailureKind.storage,
              error is ResourceFailure ? error.message : '处理未确认，请检查结果记录。',
            );
      if (intent == null) rethrow;
    } finally {
      try {
        if (intent != null) {
          await repository.finishOutputWrite(intent.id, failure: failure);
        }
      } finally {
        try {
          await lease.release();
        } finally {
          permit?.release();
        }
      }
    }
    if (sourceFailure != null) throw sourceFailure;
    return repository.getOutput(intent.id);
  }
}
