import '../../accounts/domain/account_models.dart';
import '../../gallery/data/library_repository.dart';
import '../application/upload_queue_store.dart';
import '../domain/provider_models.dart';
import '../domain/upload_queue_models.dart';

final class LibraryUploadQueueStore implements UploadQueueStore {
  LibraryUploadQueueStore(this.repository) : _epoch = repository.executionEpoch;
  final LibraryRepository repository;
  final String _epoch;
  Future<T> _current<T>(Future<T> Function() action) =>
      repository.runInExecutionEpoch(_epoch, action);
  @override
  Stream<void> get changes => repository.uploadChanges;
  @override
  Stream<String> get accountChanges => repository.accountChanges;
  @override
  Future<List<UploadBatch>> listBatches() =>
      _current(repository.listUploadBatches);
  @override
  Future<void> setWaiting(String id, QueueWaitReason reason) =>
      _current(() => repository.setUploadWaiting(id, reason));
  @override
  Future<void> wake(String id) => _current(() => repository.wakeUploadItem(id));
  @override
  Future<UploadExecution?> begin(
    String id, {
    required bool Function() mayDispatch,
  }) => _current(
    () => repository.beginUploadAttempt(id, mayDispatch: mayDispatch),
  );
  @override
  Future<bool> authorize(String id) =>
      _current(() => repository.authorizeUploadRequest(id));
  @override
  Future<void> checkpoint(String id, Duration accumulatedRunning) => _current(
    () => repository.checkpointUploadAttempt(id, accumulatedRunning),
  );
  @override
  Future<void> finish(
    UploadExecution execution,
    ProviderUploadResult result, {
    required Duration accumulatedRunning,
    Duration? retryDelay,
    bool interrupted = false,
  }) => _current(
    () => repository.finishUploadAttempt(
      execution,
      result,
      accumulatedRunning: accumulatedRunning,
      retryDelay: retryDelay,
      interrupted: interrupted,
    ),
  );
  @override
  Future<void> cancel(Iterable<String> ids) =>
      _current(() => repository.cancelUploadItems(ids));
  @override
  Future<void> pauseBatch(String id, bool paused) =>
      _current(() => repository.setUploadBatchPaused(id, paused));
  @override
  Future<void> pauseItem(String id, bool paused) =>
      _current(() => repository.setUploadItemPaused(id, paused));
  @override
  Future<ResolvedTarget> resolveTarget(String id) =>
      _current(() => repository.resolveTarget(id));
}
