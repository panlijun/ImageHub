import 'dart:async';

import '../../../core/platform_resource.dart';
import '../../gallery/data/library_repository.dart';
import '../../gallery/domain/library_models.dart';
import '../../processing/application/image_processor.dart';
import '../../processing/application/processing_coordinator.dart';
import '../../processing/domain/output_models.dart';
import '../../processing/domain/processing_models.dart';
import '../domain/upload_processing_models.dart';
import '../domain/upload_queue_models.dart';

/// Executes only previously confirmed local plans. It owns no network consent.
final class UploadProcessingCoordinator {
  UploadProcessingCoordinator(
    this.repository, {
    ImageProcessor processor = const ImageProcessor(),
    ProcessingCoordinator? processing,
    bool scanOnCreate = true,
  }) : executionEpoch = repository.executionEpoch,
       _processing =
           processing ??
           ProcessingCoordinator(repository, processor: processor) {
    _changes = repository.uploadChanges.listen((_) => _schedule());
    _settings = repository.settingsChanges.listen((_) => _schedule());
    if (scanOnCreate) _schedule();
  }

  final LibraryRepository repository;
  final String executionEpoch;
  final ProcessingCoordinator _processing;
  final Map<String, _RunningProcessing> _running = {};
  final StreamController<void> _updates = StreamController.broadcast();
  late final StreamSubscription<void> _changes, _settings;
  Future<void>? _pumping, _closing, _restoreDraining;
  bool _pending = false, _blocked = false, _closed = false;
  bool _settlementFailed = false;
  String? _failure;

  Stream<void> get changes => _updates.stream;
  String? get failure => _failure;
  int get activeCount => _running.length;
  bool get closing => _closing != null;
  bool get restoreBlocked => _blocked;
  bool get hasUnsettledIO => _settlementFailed;

  Future<T> _inEpoch<T>(Future<T> Function() action) =>
      repository.runInExecutionEpoch(executionEpoch, action);

  void _notify() {
    if (!_updates.isClosed) _updates.add(null);
  }

  void _schedule() {
    if (_closed || closing || _blocked || _settlementFailed) return;
    _pending = true;
    _pumping ??= _pump().whenComplete(() {
      _pumping = null;
      if (_pending && !_closed && !closing && !_blocked) _schedule();
    });
  }

  Future<void> refresh() async {
    if (!_settlementFailed) _failure = null;
    _schedule();
    await _pumping;
  }

  Future<void> _pump() async {
    try {
      while (_pending && !_closed && !closing && !_blocked) {
        _pending = false;
        // Pausing one dependent must not cancel another target's shared work.
        for (final running in _running.values.toList()) {
          if (!await _inEpoch(
            () =>
                repository.uploadProcessingHasActiveDependents(running.job.id),
          )) {
            running.cancel.cancel();
          }
        }
        final jobs = await _inEpoch(repository.listUploadProcessingJobs);
        for (final candidate in jobs) {
          if (_closed || closing || _blocked || _settlementFailed) return;
          if (_running.length >=
              repository.currentDeviceSettings.processingConcurrency) {
            break;
          }
          if (candidate.state != UploadProcessingState.queued ||
              _running.containsKey(candidate.id)) {
            continue;
          }
          final job = await _inEpoch(
            () => repository.beginUploadProcessingJob(candidate.id),
          );
          if (job == null) continue;
          final running = _RunningProcessing(job);
          _running[job.id] = running;
          if (_closed || closing || _blocked) {
            running.interrupted = true;
            running.cancel.cancel();
          }
          running.done = _execute(running);
          unawaited(running.done);
          _notify();
        }
      }
    } catch (_) {
      _pending = false;
      _failure = '上传前本地处理读取或启动未确认，已有任务保留；请刷新重试。';
      _notify();
    }
  }

  Future<void> _execute(_RunningProcessing running) async {
    ProcessedOutput? output;
    var sourceChanged = false;
    var inputUnavailable = false;
    var cancelled = false;
    try {
      output = await _inEpoch(
        () => _processing.process(
          running.job.plan.assetIds,
          (inputs) {
            try {
              return running.job.plan.bind(inputs);
            } on UploadQueueFailure {
              sourceChanged = true;
              rethrow;
            }
          },
          displayName: '上传处理结果',
          retention: running.job.retention,
          cancellation: running.cancel,
          typedSourceFailures: true,
          onOutputIntent: (intent) => repository.recordUploadProcessingOutput(
            running.job.id,
            intent.id,
          ),
        ),
      );
      cancelled = output?.state == OutputState.cancelled;
    } catch (error) {
      cancelled =
          running.cancel.isCancelled ||
          (error is ResourceFailure && error.kind == FailureKind.cancelled) ||
          (error is ProcessingFailure &&
              error.kind == ProcessingFailureKind.cancelled);
      inputUnavailable =
          sourceChanged ||
          (error is ResourceFailure &&
              const {
                FailureKind.unavailable,
                FailureKind.sourceMissing,
                FailureKind.invalidImage,
                FailureKind.permissionDenied,
              }.contains(error.kind)) ||
          (error is ProcessingFailure &&
              error.kind == ProcessingFailureKind.inputChanged);
    } finally {
      // process() returns only after the real pixel worker, output writer,
      // original lease and shared memory permit have all completed finalizers.
      try {
        // A confirmed output remains valid when cancellation arrives during
        // finalizers. The repository preserves cancelled dependent terminals
        // independently and must not dispatch them from this late evidence.
        final usable =
            output != null &&
            output.usable &&
            output.availability == CopyAvailability.available;
        await _inEpoch(
          () => repository.finishUploadProcessingJob(
            running.job.id,
            outputId: usable ? output!.id : null,
            cancelled: cancelled || running.cancel.isCancelled,
            interrupted: running.interrupted,
            inputUnavailable: inputUnavailable,
            failureMessage: '上传前本地处理未完成，原图未上传；请检查来源与处理参数。',
          ),
        );
      } catch (_) {
        _settlementFailed = true;
        _failure = '本地处理已结束，但任务收尾未确认，保护记录已保留；请重开后核查。';
      } finally {
        _running.remove(running.job.id);
        _notify();
        _schedule();
      }
    }
  }

  void _stopClaims() {
    _blocked = true;
    _pending = false;
    for (final running in _running.values) {
      running.interrupted = true;
      running.cancel.cancel();
    }
    _notify();
  }

  Future<void> holdForRestore() {
    _stopClaims();
    return _restoreDraining ??= _drain().whenComplete(() {
      _restoreDraining = null;
    });
  }

  /// Synchronous barrier used before session shutdown starts other awaits.
  void blockForRestore() => _stopClaims();

  Future<void> _drain() async {
    await _pumping;
    await Future.wait(_running.values.map((job) => job.done).toList());
    if (_settlementFailed || _running.isNotEmpty) {
      throw const UploadQueueFailure('上传前本地处理收尾未确认，暂不能安全关闭或恢复资料库。');
    }
  }

  void resumeAfterRestore() {
    if (_closed || closing || repository.executionEpoch != executionEpoch) {
      return;
    }
    _blocked = false;
    _schedule();
  }

  Future<void> close() {
    if (_closed) return Future.value();
    _stopClaims();
    return _closing ??= _close().catchError((Object error) {
      _closing = null;
      throw error;
    });
  }

  Future<void> _close() async {
    await _restoreDraining;
    await _drain();
    _closed = true;
    await _changes.cancel();
    await _settings.cancel();
    await _updates.close();
  }
}

final class _RunningProcessing {
  _RunningProcessing(this.job);
  final UploadProcessingJob job;
  final CancellationToken cancel = CancellationToken();
  late final Future<void> done;
  bool interrupted = false;
}
