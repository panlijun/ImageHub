import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/time_source.dart';
import '../../../core/network_state.dart';
import '../../accounts/domain/account_models.dart';
import '../data/provider_adapters.dart';
import '../domain/provider_models.dart';
import '../domain/queue_policy.dart';
import '../domain/upload_queue_models.dart';
import 'upload_queue_store.dart';
import 'upload_retry_policy.dart';
import 'upload_processing_coordinator.dart';

final class UploadLiveProgress {
  const UploadLiveProgress(this.attemptId, this.activity);
  final String attemptId;
  final UploadActivity activity;
}

/// A dispatch barrier, acquired only after real attempt IO has settled.
/// Releasing it does not unpause persisted batches or restore network consent.
final class UploadRestoreHold {
  UploadRestoreHold._(this._release);
  final void Function() _release;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// Application-scoped; constructing or attaching this service never uploads.
/// A user explicitly grants this session permission. Network observation and
/// persisted transport policy separately gate future dispatch.
final class UploadCoordinator {
  UploadCoordinator(
    this.store, {
    required Iterable<ProviderAdapter> adapters,
    TimeSource? time,
    int concurrency = 3,
    NetworkSnapshot initialNetwork = const NetworkSnapshot.unknown(),
    NetworkUploadPolicy? networkPolicy,
    this.watchdogInterval = const Duration(seconds: 1),
    this.processing,
  }) : time = time ?? SystemTimeSource(),
       _adapters = {for (final adapter in adapters) adapter.service: adapter},
       _concurrency = _checkedConcurrency(concurrency),
       _networkSnapshot = initialNetwork,
       _networkPolicy = networkPolicy ?? NetworkUploadPolicy.wifiAndEthernet {
    _changes = store.changes.listen((_) => _schedule());
    _accounts = store.accountChanges.listen((id) {
      unawaited(_accountChanged(id));
    });
    _processingChanges = processing?.changes.listen((_) => _notify());
  }
  final UploadQueueStore store;
  final TimeSource time;
  final Duration watchdogInterval;
  final UploadProcessingCoordinator? processing;
  StreamSubscription<void>? _processingChanges;
  final Map<ImageHostService, ProviderAdapter> _adapters;
  final Map<String, _RunningUpload> _running = {};
  final Map<String, Duration> _retryDeadlines = {};
  final Map<String, UploadLiveProgress> _progress = {};
  final StreamController<void> _updates = StreamController.broadcast();
  late final StreamSubscription<void> _changes;
  late final StreamSubscription<String> _accounts;
  Future<void>? _pumping;
  Future<void>? _closing;
  Future<UploadRestoreHold>? _restoreDraining;
  Timer? _retryTimer;
  int _concurrency;
  NetworkSnapshot _networkSnapshot;
  NetworkUploadPolicy _networkPolicy;
  bool _networkAllowed = false, _pending = false, _closed = false;
  bool _restoreBlocked = false, _restoreReady = false;
  String? _failure;
  Stream<void> get changes => _updates.stream;
  Map<String, UploadLiveProgress> get progress => Map.unmodifiable(_progress);
  String? get failure => _failure ?? processing?.failure;
  bool get networkAllowed => _networkAllowed;
  NetworkSnapshot get networkSnapshot => _networkSnapshot;
  NetworkUploadPolicy get networkPolicy => _networkPolicy;
  bool get networkEligible => _networkPolicy.allows(_networkSnapshot);
  bool get dispatchAllowed => _networkAllowed && networkEligible;
  int get activeCount => _running.length;
  int get concurrency => _concurrency;
  bool get closing => _closing != null;
  bool get restoreBlocked => _restoreBlocked;
  bool get hasUnsettledIO =>
      _running.values.any((job) => job.cleanupFailed) ||
      (processing?.hasUnsettledIO ?? false);

  static int _checkedConcurrency(int value) {
    if (value < 1 || value > 8) throw ArgumentError('上传并发必须是 1–8。');
    return value;
  }

  void _notify() {
    if (!_updates.isClosed) _updates.add(null);
  }

  void setConcurrency(int value) {
    _concurrency = _checkedConcurrency(value);
    _schedule();
  }

  void setNetworkSnapshot(NetworkSnapshot snapshot) {
    if (closing || _closed || snapshot == _networkSnapshot) return;
    _networkSnapshot = snapshot;
    _networkChanged();
  }

  void setNetworkPolicy(NetworkUploadPolicy policy) {
    if (closing || _closed || policy == _networkPolicy) return;
    _networkPolicy = policy;
    _networkChanged();
  }

  void _networkChanged() {
    // Observation never grants or revokes user consent, nor cancels an actual
    // request. Its outcome remains independently confirmed or unknown.
    _notify();
    if (dispatchAllowed) unawaited(_resumeAfterNetworkChange());
    _schedule();
  }

  Future<void> _resumeAfterNetworkChange() async {
    try {
      await resumeWaiting();
    } catch (_) {
      _failure = '网络变化后的任务检查未完成，已有意图保留；请重试。';
      _notify();
    }
  }

  Future<void> setNetworkAllowed(bool allowed) async {
    if (closing || _closed || _restoreBlocked) return;
    _networkAllowed = allowed;
    if (!allowed) {
      // Withdrawing permission stops actual attempts. It is not cancellation
      // of user intent and cannot establish absence of a remote side effect.
      for (final running in _running.values) {
        running.interrupted = true;
        running.cancel.cancel();
      }
    } else {
      await resumeWaiting();
    }
    _notify();
    _schedule();
    await _pumping;
  }

  Future<void> resumeWaiting() async {
    if (closing || _closed || _restoreBlocked || !dispatchAllowed) return;
    for (final batch in await store.listBatches()) {
      if (closing || _closed || _restoreBlocked || !dispatchAllowed) return;
      if (batch.paused) continue;
      for (final item in batch.items) {
        if (closing || _closed || _restoreBlocked || !dispatchAllowed) return;
        if (item.userPaused) continue;
        if (item.state == PublishState.interrupted ||
            (item.state == PublishState.waiting &&
                item.waitReason != QueueWaitReason.retry)) {
          // Unknown never reaches here. Wake does not create a new attempt;
          // the durable dispatch gate rechecks every input and current target.
          await store.wake(item.id);
        }
      }
    }
    _schedule();
  }

  Future<void> pauseBatch(String id, bool paused) async {
    _checkPauseAllowed(paused);
    await store.pauseBatch(id, paused);
    if (!paused) await resumeWaiting();
    _schedule();
  }

  Future<void> pauseItem(String id, bool paused) async {
    _checkPauseAllowed(paused);
    // This only changes future dispatch. An active attempt is rejected by the
    // durable state gate and never receives a cancellation signal here.
    await store.pauseItem(id, paused);
    if (!paused) await resumeWaiting();
    _schedule();
  }

  void _checkPauseAllowed(bool paused) {
    if (closing || _closed) {
      throw const UploadQueueFailure('上传协调器正在关闭或已关闭，不能修改暂停状态。');
    }
    if (_restoreBlocked && !paused) {
      throw const UploadQueueFailure('恢复维护期间不能恢复派发，请等待维护结束。');
    }
  }

  Future<void> cancelItems(Iterable<String> ids) async {
    final selected = ids.toSet();
    // Persist cancellation first so a racing complete response is late
    // evidence, never a replacement of the user's already recorded terminal.
    await store.cancel(selected);
    for (final id in selected) {
      _running[id]?.cancel.cancel();
    }
    _schedule();
  }

  Future<void> _accountChanged(String id) async {
    try {
      // All changes revoke in-flight authorization, including replacement of
      // a credential under the same stable UUID. The old request is stopped
      // best-effort; its valid late confirmation still belongs to its attempt.
      for (final running in _running.values) {
        if (running.execution.item.target.id == id) {
          running.interrupted = true;
          running.cancel.cancel();
        }
      }
      if (_restoreBlocked) return;
      for (final batch in await store.listBatches()) {
        if (batch.paused) continue;
        for (final item in batch.items) {
          if (!item.userPaused &&
              item.target.id == id &&
              item.state == PublishState.waiting &&
              item.waitReason == QueueWaitReason.authorization) {
            await store.wake(item.id);
          }
        }
      }
      _schedule();
    } catch (_) {
      _failure = '账号变化后的任务检查未完成，请重试。';
      _notify();
    }
  }

  void _schedule() {
    if (_closed || closing || _restoreBlocked) return;
    _pending = true;
    _pumping ??= _pump().whenComplete(() {
      _pumping = null;
      if (_pending && !closing && !_closed && !_restoreBlocked) _schedule();
    });
  }

  Future<void> refresh() async {
    _failure = null;
    await processing?.refresh();
    _schedule();
    await _pumping;
  }

  Future<void> _pump() async {
    try {
      while (_pending && !closing && !_closed && !_restoreBlocked) {
        _pending = false;
        _retryTimer?.cancel();
        Duration? earliest;
        final batches = await store.listBatches();
        if (_restoreBlocked) return;
        final surviving = <String>{};
        for (final batch in batches) {
          for (final item in batch.items) {
            if (_restoreBlocked) return;
            if ((item.state == PublishState.waiting ||
                    item.state == PublishState.paused) &&
                item.waitReason == QueueWaitReason.retry) {
              surviving.add(item.id);
              final deadline = _retryDeadlines.putIfAbsent(
                item.id,
                () => time.monotonic + (item.retryDelay ?? Duration.zero),
              );
              if (!batch.paused && !item.userPaused && dispatchAllowed) {
                final remaining = deadline - time.monotonic;
                if (remaining <= Duration.zero) {
                  await store.wake(item.id);
                } else if (earliest == null || remaining < earliest) {
                  earliest = remaining;
                }
              }
            }
            if (batch.paused ||
                item.userPaused ||
                item.state != PublishState.queued ||
                _running.containsKey(item.id)) {
              continue;
            }
            if (!dispatchAllowed) {
              await store.setWaiting(item.id, QueueWaitReason.network);
              continue;
            }
            final adapter = _adapters[item.target.service];
            if (adapter == null || !adapter.limits.verified) {
              await store.setWaiting(
                item.id,
                QueueWaitReason.capabilityUnknown,
              );
              continue;
            }
            if (_running.length >= _concurrency) continue;
            final execution = await store.begin(
              item.id,
              mayDispatch: () =>
                  dispatchAllowed && !closing && !_restoreBlocked,
            );
            if (execution == null) continue;
            // Closing/permission may have changed while file verification was
            // in flight. Do not start a request simply because a lease exists.
            final running = _RunningUpload(execution);
            _running[item.id] = running;
            running.done = _execute(running, adapter);
            unawaited(running.done);
            _notify();
          }
        }
        _retryDeadlines.removeWhere((id, _) => !surviving.contains(id));
        if (earliest != null && !closing && !_restoreBlocked) {
          _retryTimer = Timer(earliest, _schedule);
        }
      }
    } catch (_) {
      _pending = false;
      _failure = '上传队列读取或派发未确认，请重试。已有数据仍保留。';
      _notify();
    }
  }

  Future<void> _execute(_RunningUpload running, ProviderAdapter adapter) async {
    final execution = running.execution;
    final budget = ExecutionBudget(
      time,
      accumulatedRunning: execution.item.accumulatedRunning,
    );
    Timer? watchdog;
    var result = const ProviderUploadCancelled(
      UploadDeliveryEvidence.notSent,
    ) as ProviderUploadResult;
    var settled = true;
    try {
      if (!dispatchAllowed || closing || _restoreBlocked) {
        running.interrupted = true;
      }
      if (running.interrupted || running.cancel.isCancelled) {
        running.cancel.cancel();
      } else if (execution.item.accumulatedRunning >=
          ExecutionBudget.totalLimit) {
        result = const ProviderUploadFailure(
          UploadFailureKind.timeout,
          UploadDeliveryEvidence.notSent,
        );
      } else if (await store.authorize(execution.attemptId)) {
        // Recheck runtime authorization after the durable gate returned: a
        // revocation between the await and request construction cancels before
        // the adapter reads or sends any byte.
        if (!dispatchAllowed ||
            closing ||
            _restoreBlocked ||
            running.interrupted ||
            running.cancel.isCancelled) {
          running.interrupted = true;
          running.cancel.cancel();
        }
        if (!running.cancel.isCancelled) {
          budget.beginAttempt();
          watchdog = Timer.periodic(watchdogInterval, (_) {
            running.checkpoint ??= _checkpoint(running, budget).whenComplete(
              () {
                running.checkpoint = null;
              },
            );
            if (budget.reached != null) {
              running.interrupted = true;
              running.cancel.cancel();
            }
          });
          result = await adapter.upload(
            file: execution.file,
            actualFormat: execution.item.input.version.format,
            expectedBytes: execution.item.input.version.byteCount,
            target: execution.target,
            cancelToken: running.cancel,
            onActivity: (activity) {
              final previous = _progress[execution.item.id]?.activity;
              // Repeated unchanged byte callbacks are not transmission activity.
              if (activity.bytes > 0 &&
                  (previous == null ||
                      previous.direction != activity.direction ||
                      activity.bytes > previous.bytes)) {
                budget.activity();
              }
              _progress[execution.item.id] = UploadLiveProgress(
                execution.attemptId,
                activity,
              );
              _notify();
            },
          );
        }
      } else {
        result = const ProviderUploadFailure(
          UploadFailureKind.targetUnavailable,
          UploadDeliveryEvidence.notSent,
        );
      }
    } on ProviderCleanupException {
      // The adapter explicitly could not confirm actual IO cleanup. Keep both
      // durable protection and the real lease; exit must report this blockage.
      settled = false;
      running.cleanupFailed = true;
      result = const ProviderUploadUnknown(UploadFailureKind.unknown);
      _failure = '网络文件使用尚未确认结束，已保留保护；请检查系统后重试退出。';
    } catch (_) {
      result = const ProviderUploadUnknown(UploadFailureKind.unknown);
      _failure = '本次上传未确认，请核查远端结果。';
    } finally {
      watchdog?.cancel();
      budget.stopAttempt();
      await running.checkpoint;
      try {
        final delay = automaticUploadRetryDelay(
          result,
          completedAttempts: execution.item.attemptCount,
          time: time,
        );
        await store.finish(
          execution,
          result,
          accumulatedRunning: budget.accumulatedRunning,
          retryDelay: delay,
          interrupted: running.interrupted,
        );
        // A gate may change between durable begin/authorize and the adapter.
        // Only explicit not-sent evidence permits automatic continued intent;
        // never wake an unknown request or replace a terminal confirmation.
        if (running.interrupted &&
            result is ProviderUploadCancelled &&
            result.evidence == UploadDeliveryEvidence.notSent &&
            !closing &&
            !_restoreBlocked) {
          if (dispatchAllowed) {
            await store.wake(execution.item.id);
          } else {
            await store.setWaiting(execution.item.id, QueueWaitReason.network);
          }
        }
      } catch (_) {
        _failure = '上传结果提交未确认，已保留恢复记录；请重开后核查。';
      } finally {
        if (settled) {
          try {
            await execution.release();
          } catch (_) {
            _failure = '已结束文件使用，但保护记录清理失败；请重开后检查。';
          }
          _running.remove(execution.item.id);
          _progress.remove(execution.item.id);
        }
        _notify();
        _schedule();
      }
    }
  }

  Future<void> _checkpoint(
    _RunningUpload running,
    ExecutionBudget budget,
  ) async {
    try {
      await store.checkpoint(
        running.execution.attemptId,
        budget.accumulatedRunning,
      );
    } catch (_) {
      running.interrupted = true;
      running.cancel.cancel();
      _failure = '运行时间保护记录保存失败，已停止后续请求；请重开后核查。';
      _notify();
    }
  }

  /// Stop new dispatch immediately, persist pause, then drain real IO outside
  /// the repository write gate. A failed drain leaves dispatch blocked and can
  /// be retried; it never returns a usable hold on uncertain cleanup.
  Future<UploadRestoreHold> holdForRestore() {
    if (_closed || closing || _restoreDraining != null || _restoreReady) {
      return Future.error(const UploadQueueFailure('上传协调器关闭或已有恢复维护，不能取得恢复保护。'));
    }
    _restoreBlocked = true;
    processing?.blockForRestore();
    _networkAllowed = false;
    _pending = false;
    _retryTimer?.cancel();
    for (final running in _running.values) {
      running.interrupted = true;
      running.cancel.cancel();
    }
    _notify();
    return _restoreDraining = _drainForRestore().whenComplete(() {
      _restoreDraining = null;
    });
  }

  Future<UploadRestoreHold> _drainForRestore() async {
    try {
      // Includes any begin() already waiting for file verification. Its
      // execution observes the barrier before contacting the adapter.
      await _pumping;
      if (_closed || closing) {
        throw const UploadQueueFailure('上传协调器正在关闭，不能提交恢复。');
      }
      for (final batch in await store.listBatches()) {
        if (batch.items.any((item) => !item.state.terminal)) {
          await store.pauseBatch(batch.id, true);
        }
      }
      // Persist the pause before waiting for a possibly long pixel worker.
      // A process interruption during this drain must not resume its batches.
      await processing?.holdForRestore();
      await Future.wait(_running.values.map((job) => job.done).toList());
      if (hasUnsettledIO || _running.isNotEmpty || _closed || closing) {
        throw const UploadQueueFailure('上传实际文件使用未确认结束，已阻止恢复提交。');
      }
      _restoreReady = true;
      return UploadRestoreHold._(() {
        _restoreReady = false;
        _restoreBlocked = false;
        processing?.resumeAfterRestore();
        _notify();
        _schedule();
      });
    } catch (_) {
      _failure = '恢复前暂停或实际 IO 收尾未确认，已阻止恢复提交；请重试。';
      _notify();
      throw const UploadQueueFailure('恢复前暂停或实际 IO 收尾未确认，已阻止恢复提交；请重试。');
    }
  }

  /// Graceful shutdown preserves pending intent. Interrupted requests may be
  /// unknown; it does not pretend they were cancelled or remotely rolled back.
  Future<void> close() => _closing ??= _close().catchError((Object error) {
    _closing = null;
    throw error;
  });
  Future<void> _close() async {
    _networkAllowed = false;
    _retryTimer?.cancel();
    processing?.blockForRestore();
    await _pumping;
    for (final running in _running.values) {
      running.interrupted = true;
      running.cancel.cancel();
    }
    await processing?.close();
    await Future.wait(_running.values.map((job) => job.done).toList());
    if (hasUnsettledIO) {
      throw const UploadQueueFailure('网络文件使用收尾未确认，暂不能安全关闭资料库。');
    }
    _closed = true;
    await _changes.cancel();
    await _accounts.cancel();
    await _processingChanges?.cancel();
    await _updates.close();
  }
}

final class _RunningUpload {
  _RunningUpload(this.execution);
  final UploadExecution execution;
  final CancelToken cancel = CancelToken();
  late Future<void> done;
  Future<void>? checkpoint;
  bool interrupted = false, cleanupFailed = false;
}
