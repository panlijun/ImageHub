part of 'library_repository.dart';

final class LinkProbePlan {
  LinkProbePlan._(
    this._owner,
    this._epoch,
    Iterable<RemoteUploadResult> results,
    Map<String, String> fingerprints,
  ) : results = List.unmodifiable(results),
      _fingerprints = Map.unmodifiable(fingerprints);
  final LibraryRepository _owner;
  final String _epoch;
  final List<RemoteUploadResult> results;
  final Map<String, String> _fingerprints;
}

/// The coordinator owns this guard until actual transport IO has ended.
final class LinkProbeExecution {
  LinkProbeExecution._(
    this._owner,
    this._epoch,
    this._id,
    this.result,
    this._generation,
    this._fingerprint,
  );
  final LibraryRepository _owner;
  final String _epoch, _id, _fingerprint;
  final int _generation;
  final RemoteUploadResult result;
  bool _ended = false;
}

extension LibraryLinkProbes on LibraryRepository {
  String _probeFingerprint(RemoteUploadResult result) => hashing.sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'copy': _linkFingerprint(result),
            'attempt': result.attemptId,
            'service': result.target.service.name,
            'anonymous': result.target.anonymous,
            'reference': result.input.referenceId,
            'policy': result.input.policyKey,
            'confirmed': result.confirmedAt.millisecondsSinceEpoch,
            'late': result.late,
            'viewer': result.viewerUrl?.toString(),
          }),
        ),
      )
      .toString();
  LinkAvailabilityRecord _linkAvailability(RemoteUploadResultRow row) {
    try {
      final state = LinkAvailability.values.byName(row.linkState);
      final reason = row.linkReason == null
          ? null
          : LinkProbeReason.values.byName(row.linkReason!);
      if (row.probeGeneration < 0 ||
          row.probeHttpStatus != null &&
              (row.probeHttpStatus! < 100 || row.probeHttpStatus! > 599) ||
          state == LinkAvailability.recorded &&
              (reason != null ||
                  row.linkCheckedUtc != null ||
                  row.probeHttpStatus != null ||
                  row.lastAccessibleUtc != null ||
                  row.probeGeneration != 0) ||
          state != LinkAvailability.recorded &&
              (reason == null ||
                  row.linkCheckedUtc == null ||
                  row.probeGeneration == 0) ||
          state == LinkAvailability.accessible &&
              (reason != LinkProbeReason.reachable ||
                  row.probeHttpStatus != 200 ||
                  row.lastAccessibleUtc == null) ||
          state == LinkAvailability.deleted &&
              (reason != LinkProbeReason.gone || row.probeHttpStatus != 410) ||
          state == LinkAvailability.unknown &&
              (reason == LinkProbeReason.reachable ||
                  reason == LinkProbeReason.gone)) {
        throw const UploadQueueFailure('链接检测证据无法安全读取，历史已保留。');
      }
      DateTime? date(int? utc) => utc == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(utc, isUtc: true);
      return LinkAvailabilityRecord(
        state: state,
        reason: reason,
        checkedAt: date(row.linkCheckedUtc),
        lastAccessibleAt: date(row.lastAccessibleUtc),
        httpStatus: row.probeHttpStatus,
      );
    } catch (_) {
      throw const UploadQueueFailure('链接检测证据无法安全读取，历史已保留。');
    }
  }

  Future<LinkProbePlan> prepareLinkProbe(Iterable<String> resultIds) =>
      _serial(() async {
        if (_closing != null || _unsettledLinkProbeIds.isNotEmpty) {
          throw const UploadQueueFailure('资料库尚未安全结束操作，不能开始检测。');
        }
        await _syncOrdinaryLinkMasks();
        final ids = _linkIds(resultIds);
        if (ids.isEmpty) throw const UploadQueueFailure('请先选择明确的链接范围。');
        final results = await _linksInOrder(ids);
        if (results.any((result) => result == null)) {
          throw const UploadQueueFailure('已选链接已变化，请重新选择。');
        }
        final present = results.cast<RemoteUploadResult>();
        return LinkProbePlan._(this, _executionEpoch, present, {
          for (final result in present) result.id: _probeFingerprint(result),
        });
      });

  Future<LinkProbeExecution> beginLinkProbe(
    LinkProbePlan plan,
    String resultId, {
    required bool confirmNetwork,
  }) => _serial(() async {
    if (!confirmNetwork ||
        !identical(plan._owner, this) ||
        plan._epoch != _executionEpoch ||
        _closing != null ||
        _unsettledLinkProbeIds.isNotEmpty ||
        _activeRemoteDeletionIds.isNotEmpty ||
        !plan._fingerprints.containsKey(resultId)) {
      throw const UploadQueueFailure('链接检测范围尚未确认或已失效，请重新确认。');
    }
    await _syncOrdinaryLinkMasks();
    final row = await (_db.select(
      _db.remoteUploadResults,
    )..where((t) => t.id.equals(resultId))).getSingleOrNull();
    if (row == null ||
        _probeFingerprint(_linkResult(row)) != plan._fingerprints[resultId]) {
      throw const UploadQueueFailure('已选链接已变化，未继续发送检测请求。');
    }
    final generation = row.probeGeneration + 1;
    await (_db.update(
      _db.remoteUploadResults,
    )..where((t) => t.id.equals(resultId))).write(
      RemoteUploadResultsCompanion(
        linkState: const Value('unknown'),
        linkReason: const Value('interrupted'),
        linkCheckedUtc: Value(clock.now().toUtc().millisecondsSinceEpoch),
        probeGeneration: Value(generation),
        probeHttpStatus: const Value(null),
      ),
    );
    final execution = LinkProbeExecution._(
      this,
      _executionEpoch,
      const Uuid().v4(),
      _linkResult(row),
      generation,
      plan._fingerprints[resultId]!,
    );
    _activeLinkProbeIds.add(execution._id);
    _uploadChanges.add(null);
    return execution;
  });

  /// Only call after the gateway has confirmed real fetch/source settlement.
  Future<bool> finishLinkProbe(
    LinkProbeExecution execution,
    LinkProbeOutcome outcome,
  ) async {
    if (!identical(execution._owner, this) || execution._ended) {
      throw const UploadQueueFailure('链接检测执行身份已失效。');
    }
    try {
      return await _serial(() async {
        if (execution._epoch != _executionEpoch) {
          throw const UploadQueueFailure('链接检测属于旧会话，未更新当前资料库。');
        }
        final status = outcome.httpStatus;
        if (outcome.state == LinkAvailability.recorded ||
            status != null && (status < 100 || status > 599) ||
            outcome.state == LinkAvailability.accessible &&
                (outcome.reason != LinkProbeReason.reachable ||
                    status != 200) ||
            outcome.state == LinkAvailability.deleted &&
                (outcome.reason != LinkProbeReason.gone || status != 410) ||
            outcome.state == LinkAvailability.unknown &&
                (outcome.reason == LinkProbeReason.reachable ||
                    outcome.reason == LinkProbeReason.gone)) {
          throw const UploadQueueFailure('链接检测结果无法安全确认，历史保留。');
        }
        final row = await (_db.select(
          _db.remoteUploadResults,
        )..where((t) => t.id.equals(execution.result.id))).getSingleOrNull();
        if (row == null ||
            row.probeGeneration != execution._generation ||
            _probeFingerprint(_linkResult(row)) != execution._fingerprint) {
          return false;
        }
        final now = clock.now().toUtc().millisecondsSinceEpoch;
        await (_db.update(
          _db.remoteUploadResults,
        )..where((t) => t.id.equals(row.id))).write(
          RemoteUploadResultsCompanion(
            linkState: Value(outcome.state.name),
            linkReason: Value(outcome.reason.name),
            linkCheckedUtc: Value(now),
            probeHttpStatus: Value(status),
            lastAccessibleUtc: Value(
              outcome.state == LinkAvailability.accessible
                  ? now
                  : row.lastAccessibleUtc,
            ),
          ),
        );
        _uploadChanges.add(null);
        return true;
      }, settling: true);
    } catch (_) {
      throw const UploadQueueFailure('链接检测状态保存未确认，已有历史保留；请刷新核对。');
    } finally {
      execution._ended = true;
      _activeLinkProbeIds.remove(execution._id);
      _unsettledLinkProbeIds.remove(execution._id);
      if (_activeLinkProbeIds.isEmpty && _linkProbeDrain != null) {
        _linkProbeDrain!.complete();
        _linkProbeDrain = null;
      }
    }
  }

  void retainUnsettledLinkProbe(LinkProbeExecution execution) {
    if (!identical(execution._owner, this) || execution._ended) return;
    _unsettledLinkProbeIds.add(execution._id);
    // Wake a waiting close/restore to report failure; retain the actual guard.
    _linkProbeDrain?.complete();
    _linkProbeDrain = null;
  }

  Future<void> _waitLinkProbeDrain() async {
    if (_unsettledLinkProbeIds.isEmpty && _activeLinkProbeIds.isNotEmpty) {
      await (_linkProbeDrain ??= Completer<void>()).future;
    }
    if (_activeLinkProbeIds.isNotEmpty || _unsettledLinkProbeIds.isNotEmpty) {
      throw const UploadQueueFailure('链接检测网络收尾尚未确认，未安全关闭或恢复资料库。');
    }
  }
}
