part of 'library_repository.dart';

final class RemoteDeletionPlan {
  RemoteDeletionPlan._(
    this._owner,
    this._epoch,
    this.result,
    this._fingerprint,
    this.targetGeneration,
  );
  final LibraryRepository _owner;
  final String _epoch, _fingerprint;
  final RemoteUploadResult result;
  final int targetGeneration;
}

/// Runtime authorization never enters a plan, audit, portable backup or UI.
final class RemoteDeletionExecution {
  RemoteDeletionExecution._(
    this._owner,
    this._epoch,
    this.record,
    this.request,
  );
  final LibraryRepository _owner;
  final String _epoch;
  final RemoteDeletionRecord record;
  final CatboxDeletionRequest request;
  bool _ended = false, _authorized = false;
  @override
  String toString() => 'RemoteDeletionExecution([受保护执行])';
}

extension LibraryRemoteDeletions on LibraryRepository {
  static const _remoteDeletionPrefix = 'remote_delete_v1/';
  String _deletionFingerprint(RemoteUploadResult result) => hashing.sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'probe': _probeFingerprint(result),
            'remoteId': result.remoteId,
            'input': _inputSnapshot(result.input),
          }),
        ),
      )
      .toString();

  void _checkDeletionResult(RemoteUploadResult result) {
    final url = result.directUrl;
    if (result.target.service != ImageHostService.catbox ||
        result.target.anonymous ||
        !CatboxDeletionRequest.validFilename(result.remoteId) ||
        url.toString() != 'https://files.catbox.moe/${result.remoteId}') {
      throw const UploadQueueFailure('该结果没有已接入的单文件账号删除能力，只能移除本地结果。');
    }
  }

  Future<ResolvedTarget> _deletionTarget(String id, {int? generation}) async {
    final ResolvedTarget target;
    try {
      target = await _resolveTarget(id);
    } on AccountFailure catch (error) {
      throw UploadQueueFailure(error.message);
    } catch (_) {
      throw const UploadQueueFailure('当前受保护授权无法读取，未发送删除请求。');
    }
    if (target.target.service != ImageHostService.catbox ||
        target.target.anonymous ||
        target.credential == null ||
        generation != null && target.target.generation != generation) {
      throw const UploadQueueFailure('原目标或当前删除授权已变化，未发送远端删除请求。');
    }
    return target;
  }

  Future<RemoteUploadResult> _deletionResult(String id) async {
    await _syncOrdinaryLinkMasks();
    final row = await (_db.select(
      _db.remoteUploadResults,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) throw const UploadQueueFailure('普通链接结果已变化，请重新选择。');
    final result = _linkResult(row);
    _checkDeletionResult(result);
    return result;
  }

  Future<RemoteDeletionPlan> prepareRemoteDeletion(String resultId) =>
      _serial(() async {
        if (_closing != null || _unsettledRemoteDeletionIds.isNotEmpty) {
          throw const UploadQueueFailure('删除网络尚未安全收尾，不能准备新请求。');
        }
        _linkIds([resultId]);
        var result = await _deletionResult(resultId);
        final target = await _deletionTarget(result.target.id);
        // Resolving credentials can register a newly protected value.
        result = await _deletionResult(resultId);
        return RemoteDeletionPlan._(
          this,
          _executionEpoch,
          result,
          _deletionFingerprint(result),
          target.target.generation,
        );
      });

  Future<RemoteDeletionExecution> beginRemoteDeletion(
    RemoteDeletionPlan plan, {
    required bool confirmNetwork,
    required bool confirmRemoteDeletion,
  }) => _serial(() async {
    if (!confirmNetwork ||
        !confirmRemoteDeletion ||
        !identical(plan._owner, this) ||
        plan._epoch != _executionEpoch ||
        _closing != null ||
        _activeRemoteDeletionIds.isNotEmpty ||
        _activeLinkProbeIds.isNotEmpty) {
      throw const UploadQueueFailure('独立网络删除确认已失效，或已有请求尚未收尾。');
    }
    final target = await _deletionTarget(
      plan.result.target.id,
      generation: plan.targetGeneration,
    );
    final result = await _deletionResult(plan.result.id);
    if (_deletionFingerprint(result) != plan._fingerprint) {
      throw const UploadQueueFailure('链接或目标已变化，请重新确认远端删除范围。');
    }
    final request = CatboxDeletionRequest(
      filename: result.remoteId,
      userhash: target.credential!,
    );
    final record = RemoteDeletionRecord(
      id: const Uuid().v4(),
      resultId: result.id,
      attemptId: result.attemptId,
      targetId: result.target.id,
      fingerprint: plan._fingerprint,
      targetGeneration: plan.targetGeneration,
      state: RemoteDeletionState.prepared,
      createdUtc: clock.now().toUtc().millisecondsSinceEpoch,
    );
    await _writeRemoteDeletion(record);
    final execution = RemoteDeletionExecution._(
      this,
      _executionEpoch,
      record,
      request,
    );
    _activeRemoteDeletionIds.add(record.id);
    _uploadChanges.add(null);
    return execution;
  });

  Future<void> authorizeRemoteDeletion(RemoteDeletionExecution execution) =>
      _serial(() async {
        _checkRemoteExecution(execution);
        if (_closing != null || execution._authorized) {
          throw const UploadQueueFailure('删除请求授权已失效，未再次发送。');
        }
        final target = await _deletionTarget(
          execution.record.targetId,
          generation: execution.record.targetGeneration,
        );
        final result = await _deletionResult(execution.record.resultId);
        if (target.credential != execution.request.userhash ||
            _deletionFingerprint(result) != execution.record.fingerprint) {
          throw const UploadQueueFailure('链接或授权已变化，未发送删除请求。');
        }
        await _db.transaction(() async {
          await _writeRemoteDeletion(
            _deletionRecord(execution.record, RemoteDeletionState.sending),
          );
          final row = await (_db.select(
            _db.remoteUploadResults,
          )..where((t) => t.id.equals(result.id))).getSingle();
          await (_db.update(
            _db.remoteUploadResults,
          )..where((t) => t.id.equals(result.id))).write(
            RemoteUploadResultsCompanion(
              linkState: const Value('unknown'),
              linkReason: const Value('interrupted'),
              linkCheckedUtc: Value(clock.now().toUtc().millisecondsSinceEpoch),
              probeGeneration: Value(row.probeGeneration + 1),
              probeHttpStatus: const Value(null),
            ),
          );
        });
        execution._authorized = true;
        _uploadChanges.add(null);
      });

  void _checkRemoteExecution(RemoteDeletionExecution execution) {
    if (!identical(execution._owner, this) ||
        execution._ended ||
        execution._epoch != _executionEpoch ||
        !_activeRemoteDeletionIds.contains(execution.record.id)) {
      throw const UploadQueueFailure('远端删除执行身份已失效。');
    }
  }

  /// Call only after actual transport IO, including raw streams, has settled.
  Future<RemoteDeletionRecord> finishRemoteDeletion(
    RemoteDeletionExecution execution,
    RemoteDeletionOutcome outcome,
  ) async {
    _checkRemoteExecution(execution);
    try {
      return await _serial(() async {
        _checkRemoteExecution(execution);
        if (!outcome.valid ||
            !execution._authorized &&
                outcome.state != RemoteDeletionState.notSent) {
          throw const UploadQueueFailure('删除结果证据无效，已有请求记录保留。');
        }
        final record = _deletionRecord(
          execution.record,
          outcome.state,
          reason: outcome.reason,
          httpStatus: outcome.httpStatus,
          finishedUtc: clock.now().toUtc().millisecondsSinceEpoch,
        );
        await _writeRemoteDeletion(record);
        _uploadChanges.add(null);
        return record;
      }, settling: true);
    } catch (_) {
      throw const UploadQueueFailure('删除结果保存未确认，已有证据保留；请重开核查。');
    } finally {
      execution._ended = true;
      _activeRemoteDeletionIds.remove(execution.record.id);
      _unsettledRemoteDeletionIds.remove(execution.record.id);
      if (_activeRemoteDeletionIds.isEmpty && _remoteDeletionDrain != null) {
        _remoteDeletionDrain!.complete();
        _remoteDeletionDrain = null;
      }
    }
  }

  void retainUnsettledRemoteDeletion(RemoteDeletionExecution execution) {
    if (!identical(execution._owner, this) || execution._ended) return;
    _unsettledRemoteDeletionIds.add(execution.record.id);
    _remoteDeletionDrain?.complete();
    _remoteDeletionDrain = null;
  }

  Future<void> _waitRemoteDeletionDrain() async {
    if (_unsettledRemoteDeletionIds.isEmpty &&
        _activeRemoteDeletionIds.isNotEmpty) {
      await (_remoteDeletionDrain ??= Completer<void>()).future;
    }
    if (_activeRemoteDeletionIds.isNotEmpty ||
        _unsettledRemoteDeletionIds.isNotEmpty) {
      throw const UploadQueueFailure('远端删除真实收尾未确认，未安全关闭或恢复资料库。');
    }
  }

  RemoteDeletionRecord _deletionRecord(
    RemoteDeletionRecord value,
    RemoteDeletionState state, {
    RemoteDeletionReason? reason,
    int? finishedUtc,
    int? httpStatus,
  }) => RemoteDeletionRecord(
    id: value.id,
    resultId: value.resultId,
    attemptId: value.attemptId,
    targetId: value.targetId,
    fingerprint: value.fingerprint,
    targetGeneration: value.targetGeneration,
    state: state,
    createdUtc: value.createdUtc,
    finishedUtc: finishedUtc,
    reason: reason,
    httpStatus: httpStatus,
  );

  Future<void> _writeRemoteDeletion(RemoteDeletionRecord value) => _db
      .into(_db.libraryMetadata)
      .insertOnConflictUpdate(
        LibraryMetadataCompanion.insert(
          key: '$_remoteDeletionPrefix${value.id}',
          value: jsonEncode({
            'formatVersion': 1,
            'id': value.id,
            'resultId': value.resultId,
            'attemptId': value.attemptId,
            'targetId': value.targetId,
            'fingerprint': value.fingerprint,
            'targetGeneration': value.targetGeneration,
            'state': value.state.name,
            'createdUtc': value.createdUtc,
            'finishedUtc': value.finishedUtc,
            'reason': value.reason?.name,
            'httpStatus': value.httpStatus,
          }),
        ),
      )
      .then((_) {});

  RemoteDeletionRecord _readRemoteDeletion(LibraryMetadataData row) {
    try {
      if (row.value.length > 4096) throw const FormatException();
      final raw = jsonDecode(row.value);
      const keys = {
        'formatVersion',
        'id',
        'resultId',
        'attemptId',
        'targetId',
        'fingerprint',
        'targetGeneration',
        'state',
        'createdUtc',
        'finishedUtc',
        'reason',
        'httpStatus',
      };
      if (raw is! Map<String, dynamic> ||
          raw.length != keys.length ||
          !raw.keys.every(keys.contains) ||
          raw['formatVersion'] is! int ||
          raw['formatVersion'] != 1) {
        throw const FormatException();
      }
      for (final key in ['id', 'resultId', 'attemptId', 'targetId']) {
        if (raw[key] is! String ||
            !_replacementUuid.hasMatch(raw[key] as String)) {
          throw const FormatException();
        }
      }
      if (row.key != '$_remoteDeletionPrefix${raw['id']}' ||
          raw['fingerprint'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['fingerprint'] as String) ||
          raw['targetGeneration'] is! int ||
          raw['targetGeneration'] < 0 ||
          raw['createdUtc'] is! int ||
          raw['createdUtc'] < 0 ||
          raw['finishedUtc'] != null &&
              (raw['finishedUtc'] is! int || raw['finishedUtc'] < 0) ||
          raw['httpStatus'] != null &&
              (raw['httpStatus'] is! int ||
                  raw['httpStatus'] < 100 ||
                  raw['httpStatus'] > 599)) {
        throw const FormatException();
      }
      final state = RemoteDeletionState.values.byName(raw['state'] as String);
      final reason = raw['reason'] == null
          ? null
          : RemoteDeletionReason.values.byName(raw['reason'] as String);
      final terminal =
          state == RemoteDeletionState.notSent ||
          state == RemoteDeletionState.unknown;
      if (terminal
          ? reason == null ||
                raw['finishedUtc'] == null ||
                state == RemoteDeletionState.notSent &&
                    raw['httpStatus'] != null
          : reason != null ||
                raw['finishedUtc'] != null ||
                raw['httpStatus'] != null) {
        throw const FormatException();
      }
      return RemoteDeletionRecord(
        id: raw['id'] as String,
        resultId: raw['resultId'] as String,
        attemptId: raw['attemptId'] as String,
        targetId: raw['targetId'] as String,
        fingerprint: raw['fingerprint'] as String,
        targetGeneration: raw['targetGeneration'] as int,
        state: state,
        createdUtc: raw['createdUtc'] as int,
        finishedUtc: raw['finishedUtc'] as int?,
        reason: reason,
        httpStatus: raw['httpStatus'] as int?,
      );
    } catch (_) {
      throw const UploadQueueFailure('远端删除记录格式无法安全读取，原记录已保留。');
    }
  }

  Future<List<RemoteDeletionRecord>> _remoteDeletionRecords() async {
    final rows = await (_db.select(
      _db.libraryMetadata,
    )..where((t) => t.key.like('remote_delete_v1/%'))).get();
    final records = rows
        .where((r) => r.key.startsWith(_remoteDeletionPrefix))
        .map(_readRemoteDeletion)
        .toList();
    records.sort((a, b) {
      final order = b.createdUtc.compareTo(a.createdUtc);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    return records;
  }

  Future<List<RemoteDeletionRecord>> listRemoteDeletions({String? resultId}) =>
      _serial(() async {
        if (resultId != null) _linkIds([resultId]);
        final records = await _remoteDeletionRecords();
        return List.unmodifiable(
          records.where((r) => resultId == null || r.resultId == resultId),
        );
      });

  Future<void> _recoverRemoteDeletions() async {
    final records = await _remoteDeletionRecords();
    await _db.transaction(() async {
      for (final record in records) {
        if (record.state == RemoteDeletionState.prepared ||
            record.state == RemoteDeletionState.sending) {
          await _writeRemoteDeletion(
            _deletionRecord(
              record,
              record.state == RemoteDeletionState.prepared
                  ? RemoteDeletionState.notSent
                  : RemoteDeletionState.unknown,
              reason: RemoteDeletionReason.interrupted,
              finishedUtc: clock.now().toUtc().millisecondsSinceEpoch,
            ),
          );
        }
      }
    });
  }

  Future<void> _clearRemoteDeletionRecords() async {
    for (final record in await _remoteDeletionRecords()) {
      await (_db.delete(
        _db.libraryMetadata,
      )..where((t) => t.key.equals('$_remoteDeletionPrefix${record.id}'))).go();
    }
  }
}
