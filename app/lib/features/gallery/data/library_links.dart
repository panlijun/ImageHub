part of 'library_repository.dart';

// Pending operations own references even after the ordinary row is removed.
const _libraryOwnedSecretsSql =
    'SELECT secret_reference AS reference FROM provider_targets WHERE secret_reference IS NOT NULL '
    'UNION SELECT secret_reference AS reference FROM remote_upload_results WHERE secret_reference IS NOT NULL '
    'UNION SELECT new_reference AS reference FROM credential_operations WHERE new_reference IS NOT NULL '
    'UNION SELECT old_reference AS reference FROM credential_operations WHERE old_reference IS NOT NULL '
    'UNION SELECT secret_reference AS reference FROM upload_result_operations WHERE secret_reference IS NOT NULL';

final class LinkCopyPlan {
  LinkCopyPlan._(
    this._owner,
    this._epoch,
    this.scope,
    this.format,
    this.batch,
    Iterable<String> resultIds,
    Iterable<String> assetNames,
    Iterable<TargetSnapshot> targets,
    Map<String, String> fingerprints,
  ) : confirmedResultIds = List.unmodifiable(resultIds),
      assetNames = List.unmodifiable(assetNames),
      targets = List.unmodifiable(targets),
      _fingerprints = Map.unmodifiable(fingerprints);
  final LibraryRepository _owner;
  final String _epoch;
  final LinkCopyScope scope;
  final UploadLinkFormat format;
  final FormattedLinkBatch batch;
  final List<String> confirmedResultIds, assetNames;
  final List<TargetSnapshot> targets;
  final Map<String, String> _fingerprints;
}

enum LocalLinkRemovalBoundary {
  intent,
  recordsRemoved,
  secretDeleted,
  complete,
}

typedef LocalLinkRemovalFaultHook = Future<void> Function(
  LocalLinkRemovalBoundary boundary,
);

final _linkIdentity = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

extension LibraryLinks on LibraryRepository {
  Future<void> _syncOrdinaryLinkMasks() async {
    // Registering a new credential may make an earlier ordinary name sensitive.
    // Persist masking before SQL predicates run, rather than returning a hidden
    // name whose unmasked secret still participates in keyword/count queries.
    final revision = _secretRedactor.revision;
    if (_ordinaryLinkMaskRevision == revision) return;
    await _db.transaction(_scrubUploadSnapshots);
    _ordinaryLinkMaskRevision = revision;
  }

  Expression<String> _linkJson(TextColumn column, String field) =>
      FunctionCallExpression<String>('coalesce', [
        FunctionCallExpression<String>('json_extract', [
          column,
          Variable<String>('\$.$field'),
        ]),
        const Variable<String>(''),
      ]);
  Expression<String> _linkKey(Expression<String> field) =>
      FunctionCallExpression<String>('imagehost_casefold', [field]);

  Expression<bool> _linkMatches(
    RemoteUploadResults table,
    LinkResultQuery query,
  ) {
    Expression<bool> match = const Constant(true);
    if (query.targetId != null) {
      match = match & table.targetId.equals(query.targetId!);
    }
    if (query.service != null) {
      match =
          match &
          _linkJson(table.targetJson, 'service').equals(query.service!.name);
    }
    if (query.inputKind != null) {
      match =
          match &
          _linkJson(table.inputJson, 'kind').equals(query.inputKind!.name);
    }
    if (query.availability != null) {
      match = match & table.linkState.equals(query.availability!.name);
    }
    if (query.normalizedKeyword.isNotEmpty) {
      Expression<bool> contains(Expression<String> field) =>
          FunctionCallExpression<int>('instr', [
            _linkKey(field),
            Variable<String>(query.normalizedKeyword),
          ]).isBiggerThanValue(0);
      match =
          match &
          (contains(_linkJson(table.inputJson, 'displayName')) |
              contains(table.directUrl) |
              contains(_linkJson(table.targetJson, 'alias')));
    }
    return match;
  }

  List<OrderingTerm> _linkOrder(LinkResultQuery query) => [
    OrderingTerm(
      expression: switch (query.sort) {
        LinkResultSort.confirmed => _db.remoteUploadResults.confirmedUtc,
        LinkResultSort.name => _linkKey(
          _linkJson(_db.remoteUploadResults.inputJson, 'displayName'),
        ),
        LinkResultSort.target => _linkKey(
          _linkJson(_db.remoteUploadResults.targetJson, 'alias'),
        ),
      },
      mode: query.ascending ? OrderingMode.asc : OrderingMode.desc,
    ),
    OrderingTerm.asc(_db.remoteUploadResults.id),
  ];

  RemoteUploadResult _linkResult(RemoteUploadResultRow row) =>
      RemoteUploadResult(
        id: row.id,
        attemptId: row.attemptId,
        input: _readUploadInput(row.inputJson),
        target: _readUploadTarget(row.targetJson),
        remoteId: _secretRedactor.redactText(row.remoteId),
        directUrl: _safeUploadUrl(Uri.parse(row.directUrl)),
        viewerUrl: row.viewerUrl == null
            ? null
            : _safeUploadUrl(Uri.parse(row.viewerUrl!)),
        confirmedAt: DateTime.fromMillisecondsSinceEpoch(
          row.confirmedUtc,
          isUtc: true,
        ),
        late: row.late,
        managementAvailable: row.managementAvailable,
        availability: _linkAvailability(row),
      );

  Future<LinkResultPage> listLinkResults({
    LinkResultQuery query = const LinkResultQuery(),
    int offset = 0,
    int limit = 50,
  }) => _serial(() async {
    if (offset < 0 || limit < 1) throw const UploadQueueFailure('链接分页范围无效。');
    await _syncOrdinaryLinkMasks();
    final count = _db.remoteUploadResults.id.count();
    final totals = _db.selectOnly(_db.remoteUploadResults)
      ..addColumns([count])
      ..where(_linkMatches(_db.remoteUploadResults, query));
    final total = (await totals.getSingle()).read(count)!;
    final page = _db.select(_db.remoteUploadResults)
      ..where((t) => _linkMatches(t, query))
      ..orderBy(
        _linkOrder(query)
            .map(
              (order) =>
                  (RemoteUploadResults table) => order,
            )
            .toList(),
      )
      ..limit(limit, offset: offset);
    return LinkResultPage((await page.get()).map(_linkResult), total);
  });

  Future<List<TargetSnapshot>> listLinkTargets() => _serial(() async {
    await _syncOrdinaryLinkMasks();
    // Return one frozen descriptor per identity, not every historical result.
    final rows = await _db
        .customSelect(
          'SELECT target_id,target_json FROM ('
          'SELECT target_id,target_json,ROW_NUMBER() OVER ('
          'PARTITION BY target_id ORDER BY confirmed_utc DESC,id ASC) AS ordinal '
          'FROM remote_upload_results) WHERE ordinal=1',
        )
        .get();
    final historical = <String, TargetSnapshot>{};
    for (final row in rows) {
      historical.putIfAbsent(
        row.read<String>('target_id'),
        () => _readUploadTarget(row.read<String>('target_json')),
      );
    }
    final targets = historical.values.toList()
      ..sort((a, b) {
        final name = TextPolicy.key(a.alias).compareTo(TextPolicy.key(b.alias));
        return name == 0 ? a.id.compareTo(b.id) : name;
      });
    return List.unmodifiable(targets);
  });

  List<String> _linkIds(Iterable<String> ids) {
    final unique = ids.toSet().toList();
    if (unique.any((id) => !_linkIdentity.hasMatch(id))) {
      throw const UploadQueueFailure('链接或资产身份无效，请重新选择。');
    }
    return unique;
  }

  String _linkFingerprint(RemoteUploadResult result) => hashing.sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'id': result.id,
            'name': result.input.displayName,
            'url': result.directUrl.toString(),
            'target': result.target.id,
            'alias': result.target.alias,
            'kind': result.input.kind.name,
            'digest': result.input.version.sha256,
            'bytes': result.input.version.byteCount,
          }),
        ),
      )
      .toString();

  Future<List<RemoteUploadResult?>> _linksInOrder(List<String> ids) async {
    // Small lookups avoid SQLite's parameter limit for explicit large scopes.
    final result = <RemoteUploadResult?>[];
    for (final id in ids) {
      final row = await (_db.select(
        _db.remoteUploadResults,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      result.add(row == null ? null : _linkResult(row));
    }
    return result;
  }

  Future<LinkCopyPlan> prepareVisibleLinkCopy(
    List<String> resultIds,
    UploadLinkFormat format,
  ) => _serial(() async {
    await _syncOrdinaryLinkMasks();
    final ids = _linkIds(resultIds);
    final results = await _linksInOrder(ids);
    final targets = <String, TargetSnapshot>{};
    for (final result in results.whereType<RemoteUploadResult>()) {
      targets.putIfAbsent(result.target.id, () => result.target);
    }
    return LinkCopyPlan._(
      this,
      _executionEpoch,
      LinkCopyScope.visibleResults,
      format,
      formatOrdinaryLinks(
        results.map(
          (r) => (
            url: r?.directUrl.toString(),
            name: r?.input.displayName ?? '缺少普通结果',
          ),
        ),
        format,
      ),
      ids,
      const [],
      targets.values,
      {
        for (final r in results.whereType<RemoteUploadResult>())
          r.id: _linkFingerprint(r),
      },
    );
  });

  Future<LinkCopyPlan> prepareAssetLinkCopy(
    List<String> assetIds,
    List<String> targetIds,
    UploadLinkFormat format, {
    UploadInputKind? inputKind,
  }) => _serial(() async {
    await _syncOrdinaryLinkMasks();
    final assets = _linkIds(assetIds), targets = _linkIds(targetIds);
    final names = <String>[], descriptors = <TargetSnapshot>[];
    final slots = <({String? url, String name})>[];
    final results = <RemoteUploadResult>[];
    for (final target in targets) {
      final latest =
          await (_db.select(_db.remoteUploadResults)
                ..where((t) => t.targetId.equals(target))
                ..orderBy([
                  (t) => OrderingTerm.desc(t.confirmedUtc),
                  (t) => OrderingTerm.asc(t.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (latest == null) {
        throw const UploadQueueFailure('历史目标已无结果，请重新选择。');
      }
      descriptors.add(_readUploadTarget(latest.targetJson));
    }
    for (final id in assets) {
      final asset = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      final name = asset == null
          ? '资产记录已缺失'
          : _secretRedactor.redactText(asset.displayName);
      names.add(name);
      final version = asset == null
          ? null
          : await (_db.select(
              _db.versions,
            )..where((t) => t.id.equals(asset.versionId))).getSingleOrNull();
      for (final target in targets) {
        final rows = version == null
            ? <RemoteUploadResultRow>[]
            : await (_db.select(_db.remoteUploadResults)
                    ..where(
                      (t) =>
                          t.targetId.equals(target) &
                          t.versionDigest.equals(version.digest) &
                          t.byteCount.equals(version.byteCount) &
                          (inputKind == null
                              ? const Constant(true)
                              : _linkJson(
                                  t.inputJson,
                                  'kind',
                                ).equals(inputKind.name)),
                    )
                    ..orderBy([
                      (t) => OrderingTerm.desc(t.confirmedUtc),
                      (t) => OrderingTerm.asc(t.id),
                    ]))
                  .get();
        if (rows.isEmpty) {
          slots.add((url: null, name: name));
        }
        for (final row in rows) {
          final result = _linkResult(row);
          results.add(result);
          slots.add((
            url: result.directUrl.toString(),
            name: result.input.displayName,
          ));
        }
      }
    }
    return LinkCopyPlan._(
      this,
      _executionEpoch,
      LinkCopyScope.assetsAndTargets,
      format,
      formatOrdinaryLinks(slots, format),
      results.map((r) => r.id),
      names,
      descriptors,
      {for (final r in results) r.id: _linkFingerprint(r)},
    );
  });

  Future<void> validateLinkCopyPlan(LinkCopyPlan plan) => _serial(() async {
    if (!identical(plan._owner, this) ||
        plan._epoch != _executionEpoch ||
        _secretRedactor.redactText(plan.batch.text) != plan.batch.text) {
      throw const UploadQueueFailure('链接复制范围已失效，请重新确认。');
    }
    for (final id in plan._fingerprints.keys) {
      final row = await (_db.select(
        _db.remoteUploadResults,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null ||
          _linkFingerprint(_linkResult(row)) != plan._fingerprints[id]) {
        throw const UploadQueueFailure('已确认链接发生变化，请重新选择并确认。');
      }
    }
  });

  Future<LocalResultRemovalReport> removeLocalLinkResults(
    List<String> resultIds, {
    required bool confirmLocalRemoval,
    LocalLinkRemovalFaultHook? faultHook,
  }) => _serial(() async {
    if (!confirmLocalRemoval) throw const UploadQueueFailure('本地移除尚未确认，结果保留。');
    if (_activeRemoteDeletionIds.isNotEmpty) {
      throw const UploadQueueFailure('远端删除实际网络尚未收尾，普通结果保留。');
    }
    final ids = _linkIds(resultIds);
    final rows = <RemoteUploadResultRow>[];
    final operations = <UploadResultOperationsCompanion>[];
    for (final id in ids) {
      final row = await (_db.select(
        _db.remoteUploadResults,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) continue;
      if (await (_db.select(_db.uploadResultOperations)
                ..where((t) => t.attemptId.equals(row.attemptId)))
              .getSingleOrNull() !=
          null) {
        throw const UploadQueueFailure('结果仍有未完成的管理操作，请重开核查后重试。');
      }
      String? secretHash;
      if (row.secretReference != null) {
        if (!_replacementUuid.hasMatch(row.secretReference!)) {
          throw const UploadQueueFailure('结果管理引用无效，记录已保留。');
        }
        try {
          final secret = await _secretStore.read(row.secretReference!);
          if (secret != null) {
            _registerManagementSecret(secret);
            secretHash = hashing.sha256.convert(utf8.encode(secret)).toString();
          }
        } catch (_) {
          throw const UploadQueueFailure('系统管理存储暂不可确认，结果保留；请重试。');
        }
      }
      rows.add(row);
      operations.add(
        UploadResultOperationsCompanion.insert(
          id: const Uuid().v4(),
          attemptId: row.attemptId,
          proposalJson: jsonEncode({
            'action': 'remove-local-result-v1',
            'format': 1,
            'resultId': row.id,
            'secretHash': secretHash,
          }),
          secretReference: Value(row.secretReference),
          createdUtc: _uploadNow,
        ),
      );
    }
    try {
      await faultHook?.call(LocalLinkRemovalBoundary.intent);
      await _db.transaction(() async {
        for (final operation in operations) {
          await _db.into(_db.uploadResultOperations).insert(operation);
        }
        for (final row in rows) {
          await (_db.update(_db.uploadPublications)
                ..where((t) => t.resultId.equals(row.id)))
              .write(const UploadPublicationsCompanion(resultId: Value(null)));
          await (_db.delete(
            _db.remoteUploadResults,
          )..where((t) => t.id.equals(row.id))).go();
        }
      });
    } catch (_) {
      throw const UploadQueueFailure('本地移除未提交，结果记录保留；请重试。');
    }
    var pending = 0;
    try {
      await faultHook?.call(LocalLinkRemovalBoundary.recordsRemoved);
      for (final spec in operations) {
        final operation = await (_db.select(
          _db.uploadResultOperations,
        )..where((t) => t.id.equals(spec.id.value))).getSingleOrNull();
        if (operation == null) continue;
        try {
          await _applyLocalLinkRemoval(operation, faultHook: faultHook);
        } catch (_) {
          pending++;
        }
      }
    } catch (_) {
      pending = operations.length;
    }
    _uploadChanges.add(null);
    return LocalResultRemovalReport(
      removed: rows.length,
      missing: ids.length - rows.length,
      cleanupPending: pending,
    );
  });

  Future<void> _applyLocalLinkRemoval(
    UploadResultOperation operation, {
    LocalLinkRemovalFaultHook? faultHook,
  }) async {
    final data = jsonDecode(operation.proposalJson);
    const keys = {'action', 'format', 'resultId', 'secretHash'};
    if (data is! Map ||
        data.length != 4 ||
        !data.keys.every(keys.contains) ||
        data['action'] != 'remove-local-result-v1' ||
        data['format'] != 1 ||
        data['resultId'] is! String ||
        !_linkIdentity.hasMatch(data['resultId'] as String) ||
        !_replacementUuid.hasMatch(operation.id) ||
        (data['secretHash'] != null &&
            (data['secretHash'] is! String ||
                !_replacementHash.hasMatch(data['secretHash'] as String))) ||
        (operation.secretReference != null &&
            !_replacementUuid.hasMatch(operation.secretReference!)) ||
        (operation.secretReference == null && data['secretHash'] != null)) {
      throw const UploadQueueFailure('本地清理证据无效，已保留现场。');
    }
    if (await (_db.select(_db.remoteUploadResults)..where(
              (t) =>
                  t.id.equals(data['resultId'] as String) |
                  t.attemptId.equals(operation.attemptId),
            ))
            .getSingleOrNull() !=
        null) {
      throw const UploadQueueFailure('本地结果仍有关联，不能清除管理能力。');
    }
    final reference = operation.secretReference;
    if (reference != null) {
      final owned = await _db
          .customSelect(
            'SELECT id FROM provider_targets WHERE secret_reference=? UNION SELECT id FROM remote_upload_results WHERE secret_reference=? UNION SELECT id FROM credential_operations WHERE new_reference=? OR old_reference=? UNION SELECT id FROM upload_result_operations WHERE secret_reference=? AND id!=?',
            variables: [
              for (var i = 0; i < 5; i++) Variable<String>(reference),
              Variable<String>(operation.id),
            ],
          )
          .get();
      if (owned.isNotEmpty) throw const UploadQueueFailure('管理能力被其他记录引用，不能清理。');
      final value = await _secretStore.read(reference);
      if (value != null) {
        _registerManagementSecret(value);
        if (data['secretHash'] == null ||
            hashing.sha256.convert(utf8.encode(value)).toString() !=
                data['secretHash']) {
          throw const UploadQueueFailure('系统管理内容已变化，保留清理现场。');
        }
        await _secretStore.delete(reference);
        if (await _secretStore.read(reference) != null) {
          throw const SecretStorageException();
        }
      }
      await faultHook?.call(LocalLinkRemovalBoundary.secretDeleted);
    }
    await faultHook?.call(LocalLinkRemovalBoundary.complete);
    await (_db.delete(
      _db.uploadResultOperations,
    )..where((t) => t.id.equals(operation.id))).go();
  }
}
