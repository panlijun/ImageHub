import 'dart:async';

import 'package:dio/dio.dart';

import '../../gallery/data/library_repository.dart';
import '../../upload/domain/upload_queue_models.dart';
import '../data/remote_deletion_gateway.dart';
import '../domain/remote_deletion.dart';

/// Created lazily; no requests, retry timers or restart dispatch.
final class RemoteDeletionCoordinator {
  RemoteDeletionCoordinator(this.repository, this.gateway)
    : _epoch = repository.executionEpoch;
  final LibraryRepository repository;
  final RemoteDeletionGateway gateway;
  final String _epoch;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  Future<RemoteDeletionRecord>? _running;
  CancelToken? _token;
  bool _closed = false, _cleanupFailed = false;
  bool get busy => _running != null;

  Future<RemoteDeletionRecord> run(
    RemoteDeletionPlan plan, {
    required bool confirmNetwork,
    required bool confirmRemoteDeletion,
  }) {
    if (_closed ||
        busy ||
        _cleanupFailed ||
        !confirmNetwork ||
        !confirmRemoteDeletion) {
      return Future.error(const UploadQueueFailure('远端删除未独立确认，或前一请求尚未安全结束。'));
    }
    final token = CancelToken();
    _token = token;
    final operation = repository.runInExecutionEpoch(
      _epoch,
      () => _run(plan, token),
    );
    _running = operation;
    _changes.add(null);
    return operation.whenComplete(() {
      _running = null;
      _token = null;
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  Future<RemoteDeletionRecord> _run(
    RemoteDeletionPlan plan,
    CancelToken token,
  ) async {
    final subscription = repository.accountChanges.listen((id) {
      if (id == plan.result.target.id) token.cancel();
    });
    RemoteDeletionExecution? execution;
    var authorized = false;
    var outcome = RemoteDeletionOutcome.cancelled;
    try {
      execution = await repository.beginRemoteDeletion(
        plan,
        confirmNetwork: true,
        confirmRemoteDeletion: true,
      );
      if (!token.isCancelled) {
        try {
          await repository.authorizeRemoteDeletion(execution);
          authorized = true;
        } catch (_) {
          outcome = const RemoteDeletionOutcome(
            RemoteDeletionState.notSent,
            RemoteDeletionReason.authorizationChanged,
          );
        }
        if (authorized) {
          // Gateway cancellation before its actual fetch remains notSent.
          try {
            outcome = await gateway.delete(
              request: execution.request,
              cancelToken: token,
            );
          } on RemoteDeletionCleanupFailure {
            _cleanupFailed = true;
            repository.retainUnsettledRemoteDeletion(execution);
            throw const UploadQueueFailure('删除网络真实收尾未确认，保护已保留；尚未安全退出。');
          } catch (_) {
            // A generic error cannot prove that a side effect was not sent.
            outcome = RemoteDeletionOutcome.unknown;
          }
        }
      }
      return await repository.finishRemoteDeletion(execution, outcome);
    } finally {
      await subscription.cancel();
    }
  }

  void cancel() => _token?.cancel();
  void blockNewRequests() {
    _closed = true;
    cancel();
  }

  Future<void> close() async {
    blockNewRequests();
    try {
      await _running;
    } catch (_) {
      // Settled failures preserve SQL evidence. Unsettled failures below block.
    }
    if (_cleanupFailed) {
      throw const UploadQueueFailure('删除网络真实收尾未确认，保护仍保留；尚未安全退出。');
    }
    if (!_changes.isClosed) await _changes.close();
  }
}
