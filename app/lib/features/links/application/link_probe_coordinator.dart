import 'dart:async';

import 'package:dio/dio.dart';

import '../../gallery/data/library_repository.dart';
import '../../upload/domain/upload_queue_models.dart';
import '../data/link_probe_gateway.dart';
import '../domain/link_availability.dart';

/// No timers, resume behavior or requests are created by construction.
final class LinkProbeCoordinator {
  LinkProbeCoordinator(this.repository, this.gateway);
  final LibraryRepository repository;
  final LinkProbeGateway gateway;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  Future<LinkProbeBatchReport>? _running;
  CancelToken? _cancelToken;
  bool _closed = false, _cleanupFailed = false;
  int completed = 0, total = 0;
  bool get busy => _running != null;

  Future<LinkProbeBatchReport> run(
    LinkProbePlan plan, {
    required bool confirmNetwork,
  }) {
    if (!confirmNetwork || _closed || busy || _cleanupFailed) {
      return Future.value(
        LinkProbeBatchReport(
          status: LinkProbeBatchStatus.rejected,
          updated: 0,
          skipped: plan.results.length,
          total: plan.results.length,
        ),
      );
    }
    final token = CancelToken();
    _cancelToken = token;
    completed = 0;
    total = plan.results.length;
    final operation = _run(plan, token);
    _running = operation;
    _changes.add(null);
    return operation.whenComplete(() {
      _running = null;
      _cancelToken = null;
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  Future<LinkProbeBatchReport> _run(
    LinkProbePlan plan,
    CancelToken token,
  ) async {
    var updated = 0, skipped = 0, failed = false;
    for (final result in plan.results) {
      if (token.isCancelled) break;
      LinkProbeExecution? execution;
      var settled = true;
      var outcome = LinkProbeOutcome.unconfirmed;
      try {
        execution = await repository.beginLinkProbe(
          plan,
          result.id,
          confirmNetwork: true,
        );
        if (token.isCancelled) {
          outcome = LinkProbeOutcome.cancelled;
        } else {
          outcome = await gateway.check(
            url: execution.result.directUrl,
            service: execution.result.target.service,
            cancelToken: token,
          );
        }
      } on LinkProbeCleanupFailure {
        settled = false;
        _cleanupFailed = true;
        failed = true;
        if (execution != null) repository.retainUnsettledLinkProbe(execution);
      } catch (_) {
        // A failed boundary has no trusted response or printable exception.
        failed = true;
      }
      if (execution != null && settled) {
        try {
          if (await repository.finishLinkProbe(
            execution,
            token.isCancelled ? LinkProbeOutcome.cancelled : outcome,
          )) {
            updated++;
          } else {
            skipped++;
          }
        } catch (_) {
          failed = true;
        }
      } else {
        skipped++;
      }
      completed++;
      if (!_changes.isClosed) _changes.add(null);
      if (failed) break;
    }
    return LinkProbeBatchReport(
      status: failed
          ? LinkProbeBatchStatus.failed
          : token.isCancelled
          ? LinkProbeBatchStatus.cancelled
          : LinkProbeBatchStatus.completed,
      updated: updated,
      skipped: skipped + (total - completed),
      total: total,
    );
  }

  void cancel() {
    _cancelToken?.cancel();
  }

  Future<void> close() async {
    _closed = true;
    cancel();
    await _running;
    if (_cleanupFailed) {
      throw const UploadQueueFailure('链接检测收尾未确认，保护仍保留；尚未安全退出。');
    }
    if (!_changes.isClosed) await _changes.close();
  }
}
