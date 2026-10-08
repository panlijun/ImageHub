part of 'library_repository.dart';

final class DiagnosticSelectionPlan {
  DiagnosticSelectionPlan._(
    this._owner,
    this._epoch,
    this._rows,
    this.contentBytes,
  );
  final LibraryRepository _owner;
  final String _epoch;
  final Map<String, String> _rows;
  final int contentBytes;
  int get count => _rows.length;
}

final class DiagnosticExportDocument {
  DiagnosticExportDocument(List<int> bytes, this.count)
    : bytes = List.unmodifiable(bytes);
  final List<int> bytes;
  final int count;
}

final class _DiagnosticAction {
  const _DiagnosticAction(
    this.kind,
    this.code,
    this.summary,
    this.recoveryAction, {
    this.entityId,
    this.batchId,
    this.attemptId,
  });
  final DiagnosticKind kind;
  final String code, summary, recoveryAction;
  final String? entityId, batchId, attemptId;
}

extension LibraryDiagnostics on LibraryRepository {
  /// Logical UTF-8 event payload bytes; SQLite pages are not this quantity.
  static const maxContentBytes = 10000000;
  static const retention = Duration(days: 30);
  static const _maxEventBytes = 65536;

  DiagnosticSanitizer get _diagnosticSanitizer =>
      DiagnosticSanitizer(_secretRedactor);

  Future<void> _prepareDiagnosticSafety() async {
    try {
      final references = await _db.customSelect(_libraryOwnedSecretsSql).get();
      for (final row in references) {
        final secret = await _secretStore.read(row.read<String>('reference'));
        if (secret == null) throw const DiagnosticFailure();
        _registerManagementSecret(secret);
      }
      for (final secret in _sessionCredentials.values) {
        _secretRedactor.register(secret);
      }
      await _syncOrdinaryLinkMasks();
      await _syncDiagnosticMasks();
    } catch (_) {
      throw const DiagnosticFailure();
    }
  }

  Future<void> _syncDiagnosticMasks() async {
    final revision = _secretRedactor.revision;
    if (_diagnosticMaskRevision == revision) return;
    var changed = false;
    await _db.transaction(() async {
      for (final row in await _diagnosticRows()) {
        final safe = _diagnosticSanitizer.event(_decodeDiagnostic(row));
        final payload = jsonEncode(safe.toJson());
        final size = utf8.encode(payload).length;
        if (size > _maxEventBytes) throw const DiagnosticFailure();
        if (payload != row.payloadJson) {
          changed = true;
          await (_db.update(
            _db.diagnosticRecords,
          )..where((t) => t.id.equals(row.id))).write(
            DiagnosticRecordsCompanion(
              payloadJson: Value(payload),
              contentBytes: Value(utf8.encode(payload).length),
              entityId: Value(safe.entityId),
              batchId: Value(safe.batchId),
              attemptId: Value(safe.attemptId),
            ),
          );
        }
      }
    });
    _diagnosticMaskRevision = revision;
    if (changed && !_diagnosticChanges.isClosed) _diagnosticChanges.add(null);
  }

  Future<void> recordOperation({
    required DiagnosticKind kind,
    required String code,
    required String summary,
    required String recoveryAction,
    String? entityId,
    String? batchId,
    String? attemptId,
    bool failed = false,
  }) => _serial(
    () => _noteDiagnostic(
      _DiagnosticAction(
        kind,
        code,
        summary,
        recoveryAction,
        entityId: entityId,
        batchId: batchId,
        attemptId: attemptId,
      ),
      failed: failed,
    ),
  );

  Future<void> _noteImportDiagnostic(ImportResult result, {String? outputId}) =>
      _noteDiagnostic(
        _DiagnosticAction(
          outputId == null
              ? DiagnosticKind.importImage
              : DiagnosticKind.processing,
          outputId == null
              ? 'import.${result.status.name.toLowerCase()}'
              : 'output.save.${result.status.name.toLowerCase()}',
          switch (result.status) {
            ImportStatus.saved => '独立本机图片副本已确认保存。',
            ImportStatus.duplicate => '已找到相同内容，原有整理保留。',
            ImportStatus.repaired => '已有图片副本已校验修复。',
            ImportStatus.needsRestore => '相同内容位于回收区，等待明确恢复。',
            ImportStatus.cancelled => '导入已取消，已确认图片保持有效。',
            ImportStatus.failed => '导入未确认完成，原有资料保持有效。',
          },
          '请在图库核查副本；失败时检查图片格式、空间与权限后重试。',
          entityId: result.asset?.id ?? outputId,
        ),
        failed: result.status == ImportStatus.failed,
      );

  Future<void> recordDiagnostic(DiagnosticEvent event) => _serial(() async {
    if (_closing != null) throw const DiagnosticFailure();
    await _prepareDiagnosticSafety();
    await _appendDiagnostic(event);
  });

  /// Ordinary failures never turn a committed business action into a failure.
  /// No exception message, filename, account alias or response is interpolated.
  Future<void> _noteDiagnostic(
    _DiagnosticAction action, {
    bool failed = false,
  }) async {
    final pending = _pendingDiagnostics;
    if (pending != null) {
      pending.add((action, failed));
      return;
    }
    await _persistDiagnostic(action, failed: failed);
  }

  Future<void> _persistDiagnostic(
    _DiagnosticAction action, {
    bool failed = false,
  }) async {
    try {
      await _appendDiagnostic(
        DiagnosticEvent(
          id: const Uuid().v4(),
          occurredAt: clock.now().toUtc(),
          kind: action.kind,
          level: failed ? DiagnosticLevel.error : DiagnosticLevel.info,
          code: '${action.code}.${failed ? 'failed' : 'completed'}',
          summary: failed ? '操作未确认完成，已保留可恢复资料。' : action.summary,
          recoveryAction: action.recoveryAction,
          entityId: action.entityId,
          batchId: action.batchId,
          attemptId: action.attemptId,
        ),
      );
    } catch (_) {
      _diagnosticWarning = '部分诊断日志未能保存；业务结果保持有效，请检查存储后重试。';
      if (!_diagnosticChanges.isClosed) _diagnosticChanges.add(null);
    }
  }

  Future<void> _appendDiagnostic(DiagnosticEvent event) async {
    final safe = _diagnosticSanitizer.event(event);
    final payload = jsonEncode(safe.toJson());
    final size = utf8.encode(payload).length;
    if (size > _maxEventBytes || size >= _diagnosticMaxBytes) {
      throw const DiagnosticFailure();
    }
    await _db.transaction(() async {
      await _db
          .into(_db.diagnosticRecords)
          .insert(
            DiagnosticRecordsCompanion.insert(
              id: safe.id,
              occurredUtc: safe.occurredAt.millisecondsSinceEpoch,
              kind: safe.kind.name,
              level: safe.level.name,
              code: safe.code,
              entityId: Value(safe.entityId),
              batchId: Value(safe.batchId),
              attemptId: Value(safe.attemptId),
              payloadJson: payload,
              contentBytes: size,
            ),
          );
      await _trimDiagnostics();
    });
    _diagnosticWarning = null;
    if (!_diagnosticChanges.isClosed) _diagnosticChanges.add(null);
  }

  DiagnosticEvent _decodeDiagnostic(DiagnosticRow row) {
    try {
      if (utf8.encode(row.payloadJson).length != row.contentBytes ||
          row.contentBytes > _maxEventBytes ||
          row.contentBytes <= 0) {
        throw const DiagnosticFailure();
      }
      final event = DiagnosticEvent.fromJson(jsonDecode(row.payloadJson));
      if (event.id != row.id ||
          event.occurredAt.millisecondsSinceEpoch != row.occurredUtc ||
          event.kind.name != row.kind ||
          event.level.name != row.level ||
          event.code != row.code ||
          event.entityId != row.entityId ||
          event.batchId != row.batchId ||
          event.attemptId != row.attemptId) {
        throw const DiagnosticFailure();
      }
      return event;
    } catch (_) {
      throw const DiagnosticFailure();
    }
  }

  Future<List<DiagnosticRow>> _diagnosticRows() =>
      (_db.select(_db.diagnosticRecords)..orderBy([
            (t) => OrderingTerm.asc(t.occurredUtc),
            (t) => OrderingTerm.asc(t.id),
          ]))
          .get();

  Future<void> _trimDiagnostics() async {
    final rows = await _diagnosticRows();
    // Validate before deleting anything: unknown/corrupt evidence is retained.
    for (final row in rows) {
      _decodeDiagnostic(row);
    }
    var total = rows.fold<int>(0, (n, row) => n + row.contentBytes);
    final cutoff = clock
        .now()
        .toUtc()
        .subtract(_diagnosticRetention)
        .millisecondsSinceEpoch;
    final expired = <String>[];
    for (final row in rows) {
      if (row.occurredUtc <= cutoff || total >= _diagnosticMaxBytes) {
        expired.add(row.id);
        total -= row.contentBytes;
      }
    }
    // Avoid SQLite's bound variable limit when the whole window expires.
    for (final id in expired) {
      await (_db.delete(
        _db.diagnosticRecords,
      )..where((t) => t.id.equals(id))).go();
    }
    if (expired.isNotEmpty && !_diagnosticChanges.isClosed) {
      _diagnosticChanges.add(null);
    }
  }

  Future<void> _maintainDiagnostics() async {
    if (_closed || _closing != null || _restoreRequested) return;
    try {
      await _serial(() => _db.transaction(_trimDiagnostics));
    } catch (_) {
      _diagnosticWarning = '诊断留存维护未完成，日志原值已保留，请检查后重试。';
    }
  }

  Expression<bool> _diagnosticMatches(
    DiagnosticRecords t,
    DiagnosticQuery query,
  ) {
    Expression<bool> where = const Constant(true);
    if (query.kind != null) where = where & t.kind.equals(query.kind!.name);
    if (query.level != null) where = where & t.level.equals(query.level!.name);
    if (query.batchId != null) where = where & t.batchId.equals(query.batchId!);
    if (query.attemptId != null) {
      where = where & t.attemptId.equals(query.attemptId!);
    }
    return where;
  }

  Future<DiagnosticPage> loadDiagnostics({
    DiagnosticQuery? query,
    int offset = 0,
    int limit = 50,
  }) => _serial(() async {
    if (offset < 0 || limit < 1 || limit > 200) throw const DiagnosticFailure();
    await _prepareDiagnosticSafety();
    await _db.transaction(_trimDiagnostics);
    final actual = query ?? DiagnosticQuery();
    final count = _db.diagnosticRecords.id.count();
    final bytes = _db.diagnosticRecords.contentBytes.sum();
    final totals =
        await (_db.selectOnly(_db.diagnosticRecords)
              ..addColumns([count, bytes])
              ..where(_diagnosticMatches(_db.diagnosticRecords, actual)))
            .getSingle();
    final rows =
        await (_db.select(_db.diagnosticRecords)
              ..where((t) => _diagnosticMatches(t, actual))
              ..orderBy([
                (t) => OrderingTerm.desc(t.occurredUtc),
                (t) => OrderingTerm.asc(t.id),
              ])
              ..limit(limit, offset: offset))
            .get();
    return DiagnosticPage(
      [
        for (final row in rows)
          _diagnosticSanitizer.event(_decodeDiagnostic(row)),
      ],
      totals.read(count) ?? 0,
      totals.read(bytes) ?? 0,
    );
  });

  Future<DiagnosticSelectionPlan> prepareDiagnosticSelection({
    DiagnosticQuery? query,
  }) => _serial(() async {
    await _prepareDiagnosticSafety();
    await _db.transaction(_trimDiagnostics);
    final rows =
        await (_db.select(_db.diagnosticRecords)
              ..where((t) => _diagnosticMatches(t, query ?? DiagnosticQuery()))
              ..orderBy([
                (t) => OrderingTerm.desc(t.occurredUtc),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    for (final row in rows) {
      _diagnosticSanitizer.event(_decodeDiagnostic(row));
    }
    return DiagnosticSelectionPlan._(
      this,
      _executionEpoch,
      Map.unmodifiable({for (final row in rows) row.id: row.payloadJson}),
      rows.fold<int>(0, (n, row) => n + row.contentBytes),
    );
  });

  Future<List<DiagnosticRow>> _verifyDiagnosticPlan(
    DiagnosticSelectionPlan plan,
  ) async {
    if (_closing != null ||
        !identical(plan._owner, this) ||
        plan._epoch != _executionEpoch) {
      throw const DiagnosticFailure();
    }
    final all = {for (final row in await _diagnosticRows()) row.id: row};
    final result = <DiagnosticRow>[];
    for (final entry in plan._rows.entries) {
      final row = all[entry.key];
      if (row == null) {
        throw const DiagnosticFailure();
      }
      if (row.payloadJson != entry.value &&
          jsonEncode(
                _diagnosticSanitizer
                    .event(DiagnosticEvent.fromJson(jsonDecode(entry.value)))
                    .toJson(),
              ) !=
              row.payloadJson) {
        throw const DiagnosticFailure();
      }
      _decodeDiagnostic(row);
      result.add(row);
    }
    return result;
  }

  /// Clears only the explicitly confirmed frozen selection, never later rows.
  Future<int> clearDiagnostics(DiagnosticSelectionPlan plan) =>
      _serial(() async {
        await _db.transaction(() async {
          final rows = await _verifyDiagnosticPlan(plan);
          for (final row in rows) {
            await (_db.delete(
              _db.diagnosticRecords,
            )..where((t) => t.id.equals(row.id))).go();
          }
        });
        _diagnosticWarning = null;
        _diagnosticChanges.add(null);
        return plan.count;
      });

  Future<DiagnosticExportDocument> diagnosticExport(
    DiagnosticSelectionPlan plan,
  ) => _serial(() async {
    await _prepareDiagnosticSafety();
    final rows = await _verifyDiagnosticPlan(plan);
    // Reapply the current registered-secret boundary at execution, not preview.
    final events = [
      for (final row in rows)
        _diagnosticSanitizer.event(_decodeDiagnostic(row)).toJson(),
    ];
    final bytes = utf8.encode(
      jsonEncode({
        'format': 'imagehost-diagnostics',
        'formatVersion': 1,
        'scope': 'explicit-local-selection',
        'eventCount': events.length,
        'excluded': [
          'images',
          'credentials',
          'managementSecrets',
          'sourcePaths',
          'rawResponses',
        ],
        'events': events,
      }),
    );
    return DiagnosticExportDocument(bytes, rows.length);
  });
}
