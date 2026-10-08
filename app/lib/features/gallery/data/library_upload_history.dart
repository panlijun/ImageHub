part of 'library_repository.dart';

/// A confirmation is scoped to this repository session and the exact selected
/// records. Preserved entries are never promoted to deletions by execution.
final class UploadHistoryClearPlan {
  UploadHistoryClearPlan._(
    this._owner,
    this._epoch,
    Iterable<UploadHistoryClearEntry> eligible,
    Iterable<UploadHistoryPreserved> preserved,
    Map<UploadHistoryRef, String> fingerprints,
  ) : eligible = List.unmodifiable(eligible),
      preserved = List.unmodifiable(preserved),
      _fingerprints = Map.unmodifiable(fingerprints);

  final LibraryRepository _owner;
  final String _epoch;
  final Map<UploadHistoryRef, String> _fingerprints;
  final List<UploadHistoryClearEntry> eligible;
  final List<UploadHistoryPreserved> preserved;
  int get eligibleCount => eligible.length;
  int get preservedCount => preserved.length;
}

final class _UploadHistoryEvidence {
  const _UploadHistoryEvidence(this.fingerprint, this.entry, this.protection);
  final String fingerprint;
  final UploadHistoryClearEntry? entry;
  final UploadHistoryProtection? protection;
}

extension LibraryUploadHistory on LibraryRepository {
  List<String> _historyIds(Iterable<String> ids) {
    final result = ids.toSet().toList();
    if (result.any((id) => !_linkIdentity.hasMatch(id))) {
      throw const UploadQueueFailure('任务历史身份无效，请重新选择。');
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _historyRows(
    String sql,
    List<String> parameters,
  ) async =>
      (await _db
              .customSelect(
                sql,
                variables: parameters
                    .map((value) => Variable<String>(value))
                    .toList(),
              )
              .get())
          .map((row) => row.data)
          .toList();

  String _historyFingerprint(Object evidence) =>
      hashing.sha256.convert(utf8.encode(jsonEncode(evidence))).toString();

  Future<_UploadHistoryEvidence> _historyEvidence(UploadHistoryRef ref) async {
    if (ref.kind == UploadHistoryKind.imported) {
      final row = await (_db.select(
        _db.importedUploadHistories,
      )..where((t) => t.id.equals(ref.id))).getSingleOrNull();
      if (row == null) {
        return const _UploadHistoryEvidence(
          'missing',
          null,
          UploadHistoryProtection.missing,
        );
      }
      final fragment = _readRestoreFragment(row.snapshotJson);
      if (fragment.history.length != 1 ||
          fragment.history.single.id != row.id ||
          fragment.history.single.batchId != row.batchId ||
          fragment.history.single.position != row.position ||
          !fragment.history.single.state.terminal) {
        throw const UploadQueueFailure('恢复历史结构无法安全读取，记录保留。');
      }
      final history = fragment.history.single;
      return _UploadHistoryEvidence(
        _historyFingerprint(row.toJson()),
        UploadHistoryClearEntry(
          reference: ref,
          displayName: _secretRedactor.redactText(history.input.displayName),
          target: TargetSnapshot(
            history.target.id,
            history.target.service,
            _secretRedactor.redactText(history.target.alias),
            history.target.anonymous,
          ),
          state: history.state,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            history.updatedUtc,
            isUtc: true,
          ),
        ),
        null,
      );
    }

    final row = await (_db.select(
      _db.uploadPublications,
    )..where((t) => t.id.equals(ref.id))).getSingleOrNull();
    if (row == null) {
      return const _UploadHistoryEvidence(
        'missing',
        null,
        UploadHistoryProtection.missing,
      );
    }
    final item = _publication(row), input = item.input;
    if (row.processingJobId != null &&
        _activeUploadProcessingJobs.contains(row.processingJobId)) {
      return _UploadHistoryEvidence(
        'processing-active',
        null,
        UploadHistoryProtection.inputInUse,
      );
    }
    if (!_linkIdentity.hasMatch(row.batchId) ||
        !_linkIdentity.hasMatch(input.referenceId) ||
        !_linkIdentity.hasMatch(input.version.id) ||
        !_linkIdentity.hasMatch(item.target.id) ||
        item.target.id != row.targetId ||
        input.version.sha256 != row.versionDigest ||
        input.version.byteCount != row.byteCount ||
        input.policyKey != row.policyKey) {
      throw const UploadQueueFailure('任务历史关系无法安全读取，记录保留。');
    }
    final attempts = await _historyRows(
      'SELECT * FROM upload_attempts WHERE item_id=? ORDER BY id',
      [ref.id],
    );
    if (row.currentAttemptId != null &&
        !attempts.any((attempt) => attempt['id'] == row.currentAttemptId)) {
      throw const UploadQueueFailure('任务尝试关系无法安全读取，记录保留。');
    }
    final events = await _historyRows(
      'SELECT * FROM upload_events WHERE item_id=? ORDER BY id',
      [ref.id],
    );
    final leases = input.kind == UploadInputKind.original
        ? await _historyRows(
            'SELECT * FROM file_leases WHERE version_id=? ORDER BY id',
            [input.version.id],
          )
        : await _historyRows(
            'SELECT * FROM output_leases WHERE output_id=? ORDER BY id',
            [input.referenceId],
          );
    final versionRefs = await _historyRows(
      "SELECT * FROM version_references WHERE owner_type='task' AND owner_id=? ORDER BY id",
      [ref.id],
    );
    final outputRefs = await _historyRows(
      "SELECT * FROM output_references WHERE owner_type='task' AND owner_id=? ORDER BY id",
      [ref.id],
    );
    final results = row.resultId == null
        ? <Map<String, Object?>>[]
        : await _historyRows(
            'SELECT * FROM remote_upload_results WHERE id=? ORDER BY id',
            [row.resultId!],
          );
    if (row.resultId != null && results.isEmpty) {
      throw const UploadQueueFailure('任务普通结果关系无法安全读取，记录保留。');
    }
    for (final result in results) {
      final resultInput = _readUploadInput(result['input_json'] as String);
      final resultTarget = _readUploadTarget(result['target_json'] as String);
      if (result['version_digest'] != row.versionDigest ||
          result['byte_count'] != row.byteCount ||
          result['target_id'] != row.targetId ||
          result['policy_key'] != row.policyKey ||
          resultInput.version.sha256 != result['version_digest'] ||
          resultInput.version.byteCount != result['byte_count'] ||
          resultInput.policyKey != result['policy_key'] ||
          resultTarget.id != result['target_id']) {
        throw const UploadQueueFailure('任务普通结果关系无法安全读取，记录保留。');
      }
      // Same-content reuse may name another asset and an independent attempt.
      // Neither identity is required to belong to this publication.
    }
    final operations = await _historyRows(
      'SELECT * FROM upload_result_operations WHERE attempt_id IN '
      '(SELECT id FROM upload_attempts WHERE item_id=?) OR attempt_id IN '
      '(SELECT attempt_id FROM remote_upload_results WHERE id=?) ORDER BY id',
      [ref.id, row.resultId ?? ''],
    );
    final fingerprint = _historyFingerprint([
      row.toJson(),
      attempts,
      events,
      leases,
      versionRefs,
      outputRefs,
      results,
      operations,
    ]);
    final protection = !item.state.terminal
        ? UploadHistoryProtection.active
        : attempts.any((attempt) => attempt['ended_utc'] == null) ||
              leases.isNotEmpty
        ? UploadHistoryProtection.inputInUse
        : operations.isNotEmpty
        ? UploadHistoryProtection.pendingResult
        : versionRefs.isNotEmpty || outputRefs.isNotEmpty
        ? UploadHistoryProtection.retainedDependency
        : null;
    return _UploadHistoryEvidence(
      fingerprint,
      UploadHistoryClearEntry(
        reference: ref,
        displayName: item.input.displayName,
        target: item.target,
        state: item.state,
        updatedAt: item.updatedAt,
      ),
      protection,
    );
  }

  Future<UploadHistoryClearPlan> prepareUploadHistoryClear({
    required Iterable<String> publicationIds,
    required Iterable<String> importedHistoryIds,
  }) => _serial(() async {
    if (_closing != null) {
      throw const UploadQueueFailure('图库正在关闭，不能确认新的任务历史范围。');
    }
    try {
      final refs = [
        for (final id in _historyIds(publicationIds))
          UploadHistoryRef(UploadHistoryKind.publication, id),
        for (final id in _historyIds(importedHistoryIds))
          UploadHistoryRef(UploadHistoryKind.imported, id),
      ];
      await _syncOrdinaryLinkMasks();
      final eligible = <UploadHistoryClearEntry>[],
          preserved = <UploadHistoryPreserved>[];
      final fingerprints = <UploadHistoryRef, String>{};
      for (final ref in refs) {
        final evidence = await _historyEvidence(ref);
        fingerprints[ref] = evidence.fingerprint;
        if (evidence.protection case final UploadHistoryProtection reason) {
          preserved.add(UploadHistoryPreserved(ref, reason));
        } else {
          eligible.add(evidence.entry!);
        }
      }
      return UploadHistoryClearPlan._(
        this,
        _executionEpoch,
        eligible,
        preserved,
        fingerprints,
      );
    } catch (_) {
      throw const UploadQueueFailure('任务历史范围无法安全确认，记录保留；请重新加载。');
    }
  });

  Future<UploadHistoryClearResult> clearUploadHistory(
    UploadHistoryClearPlan plan, {
    required bool confirmHistoryRemoval,
  }) => _serial(() async {
    if (!confirmHistoryRemoval) {
      throw const UploadQueueFailure('任务历史清理尚未确认，记录保留。');
    }
    if (!identical(plan._owner, this) ||
        plan._epoch != _executionEpoch ||
        _closing != null) {
      throw const UploadQueueFailure('任务历史确认已失效，请重新选择并确认。');
    }
    try {
      await _syncOrdinaryLinkMasks();
      final eligibleRefs = plan.eligible
          .map((entry) => entry.reference)
          .toSet();
      // Revalidate inside the same gate and transaction as all deletions.
      await _db.transaction(() async {
        for (final ref in plan._fingerprints.keys) {
          final evidence = await _historyEvidence(ref);
          if (evidence.fingerprint != plan._fingerprints[ref]) {
            throw const UploadQueueFailure('任务历史已变化，请重新选择并确认。');
          }
          final eligible = eligibleRefs.contains(ref);
          if (eligible != (evidence.protection == null)) {
            throw const UploadQueueFailure('任务历史保护已变化，请重新选择并确认。');
          }
        }
        for (final entry in plan.eligible) {
          final ref = entry.reference;
          if (ref.kind != UploadHistoryKind.publication) continue;
          await (_db.delete(
            _db.uploadEvents,
          )..where((t) => t.itemId.equals(ref.id))).go();
          await (_db.delete(
            _db.uploadAttempts,
          )..where((t) => t.itemId.equals(ref.id))).go();
          await (_db.delete(
            _db.uploadPublications,
          )..where((t) => t.id.equals(ref.id))).go();
        }
        for (final entry in plan.eligible) {
          final ref = entry.reference;
          if (ref.kind != UploadHistoryKind.imported) continue;
          await (_db.delete(
            _db.importedUploadHistories,
          )..where((t) => t.id.equals(ref.id))).go();
        }
        await _historyClearFaultHook?.call(
          UploadHistoryClearBoundary.recordsDeleted,
        );
        // Empty batches intentionally retain intentId idempotence receipts.
      });
    } catch (_) {
      throw const UploadQueueFailure('任务历史清理未提交，记录保留；请重新加载并确认。');
    }
    _uploadChanges.add(null);
    return UploadHistoryClearResult(
      publicationRemoved: plan.eligible
          .where(
            (entry) => entry.reference.kind == UploadHistoryKind.publication,
          )
          .length,
      importedRemoved: plan.eligible
          .where((entry) => entry.reference.kind == UploadHistoryKind.imported)
          .length,
      preservedCount: plan.preservedCount,
    );
  });
}
