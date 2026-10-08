import '../../accounts/domain/account_models.dart';
import '../domain/provider_models.dart';
import '../domain/upload_queue_models.dart';

/// Scheduler boundary. Storage commits state, snapshots and protection;
/// scheduling alone owns concurrency, transport cancellation and retry clocks.
abstract interface class UploadQueueStore {
  Stream<void> get changes;
  Stream<String> get accountChanges;
  Future<List<UploadBatch>> listBatches();
  Future<void> setWaiting(String itemId, QueueWaitReason reason);
  Future<void> wake(String itemId);
  Future<UploadExecution?> begin(
    String itemId, {
    required bool Function() mayDispatch,
  });
  Future<bool> authorize(String attemptId);
  Future<void> checkpoint(String attemptId, Duration accumulatedRunning);
  Future<void> finish(
    UploadExecution execution,
    ProviderUploadResult result, {
    required Duration accumulatedRunning,
    Duration? retryDelay,
    bool interrupted = false,
  });
  Future<void> cancel(Iterable<String> itemIds);
  Future<void> pauseBatch(String batchId, bool paused);
  Future<void> pauseItem(String itemId, bool paused);
  Future<ResolvedTarget> resolveTarget(String id);
}
