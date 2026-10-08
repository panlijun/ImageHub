part of 'library_repository.dart';

extension LibraryRecycling on LibraryRepository {
  Future<List<ImageAsset>> removeAssets(Iterable<String> assetIds) => _serial(
    () => _db.transaction(() async {
      final rows = await _recycleRows(assetIds);
      await _rejectPendingPurge(rows.map((row) => row.versionId));
      final now = clock.now().toUtc().millisecondsSinceEpoch;
      for (final row in rows.where((row) => !row.recycled)) {
        await (_db.update(_db.assets)..where((t) => t.id.equals(row.id))).write(
          AssetsCompanion(
            recycled: const Value(true),
            recycledUtc: Value(now),
            updatedUtc: Value(now),
          ),
        );
      }
      return _recycleAssets(rows.map((row) => row.id));
    }),
  );

  Future<List<ImageAsset>> restoreAssets(Iterable<String> assetIds) => _serial(
    () => _db.transaction(() async {
      final rows = await _recycleRows(assetIds);
      await _rejectPendingPurge(rows.map((row) => row.versionId));
      final now = clock.now().toUtc().millisecondsSinceEpoch;
      for (final row in rows.where((row) => row.recycled)) {
        await (_db.update(_db.assets)..where((t) => t.id.equals(row.id))).write(
          AssetsCompanion(
            recycled: const Value(false),
            recycledUtc: const Value(null),
            updatedUtc: Value(now),
          ),
        );
      }
      return _recycleAssets(rows.map((row) => row.id));
    }),
  );

  Future<int> recycledDueCount() => _serial(() async {
    final cutoff = clock
        .now()
        .toUtc()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final count = _db.assets.id.count();
    final query = _db.selectOnly(_db.assets)
      ..addColumns([count])
      ..where(
        _db.assets.recycled.equals(true) &
            _db.assets.recycledUtc.isSmallerOrEqualValue(cutoff),
      );
    return (await query.getSingle()).read(count) ?? 0;
  });

  Future<LibraryPurgeResult> purgeAssets(
    Iterable<String> assetIds, {
    bool confirmRecords = false,
    bool confirmCopies = false,
  }) => _serial(
    () async {
      if (!confirmRecords && !confirmCopies) {
        throw ArgumentError('清除记录和图片副本必须分别确认。');
      }
      final rows = await _recycleRows(assetIds);
      final ids = rows.map((row) => row.id).toList();
      final versions = rows.map((row) => row.versionId).toSet();
      await _rejectPendingPurge(versions);
      for (final version in versions) {
        await _rejectVersionProtection(version);
        if (confirmCopies) await _rejectSharedVersion(version, ids);
      }
      if (confirmRecords && rows.any((row) => !row.recycled)) {
        throw StateError('只有回收区资产才能永久清除记录。');
      }
      if (!confirmCopies) {
        await _db.transaction(() => _deleteAssetRecords(ids));
        // The independent permanent bytes, versions and copies are retained.
        return LibraryPurgeResult(recordsRemoved: ids.length, copiesRemoved: 0);
      }
      final operations = <PurgeOperation>[];
      for (final version in versions) {
        final copy = await (_db.select(
          _db.deviceCopies,
        )..where((t) => t.versionId.equals(version))).getSingle();
        _validateOriginalPath(copy.relativePath);
        await _files.file(copy.relativePath);
        operations.add(
          PurgeOperation(
            id: const Uuid().v4(),
            versionId: version,
            relativePath: copy.relativePath,
            assetIdsJson: jsonEncode(
              rows
                  .where((row) => row.versionId == version)
                  .map((row) => row.id)
                  .toList(),
            ),
            removeRecords: confirmRecords,
            createdUtc: clock.now().toUtc().millisecondsSinceEpoch,
          ),
        );
      }
      await _db.transaction(() async {
        for (final op in operations) {
          await _db.into(_db.purgeOperations).insert(op.toCompanion(true));
        }
      });
      for (final op in operations) {
        // An IO/DB failure leaves the confirmed intent and prevents success.
        await _completePurge(op);
      }
      return LibraryPurgeResult(
        recordsRemoved: confirmRecords ? ids.length : 0,
        copiesRemoved: operations.length,
      );
    },
    diagnostic: const _DiagnosticAction(
      DiagnosticKind.cleanup,
      'library.purge',
      '明确确认的本机清除操作已完成。',
      '清理失败时保留现场，检查保护引用与空间权限后重试。',
    ),
  );

  Future<LibraryFileLease> acquireAssetLease(
    Iterable<String> assetIds, {
    required String purpose,
    // Test fault boundary: default callers do not pause or inject work here.
    Future<void> Function()? beforeLeaseCommit,
    bool typedSourceFailures = false,
  }) => _serial(() async {
    if (_closing != null) throw StateError('图库正在关闭，不再接受新的文件使用。');
    final label = purpose.trim();
    if (label.isEmpty ||
        label.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(label)) {
      throw ArgumentError('文件使用目的无效。');
    }
    final rows = await _recycleRows(assetIds);
    if (rows.isEmpty || rows.any((row) => row.recycled)) {
      if (typedSourceFailures) {
        throw const ResourceFailure(FailureKind.unavailable);
      }
      throw StateError('文件使用需要有效图库资产。');
    }
    await _rejectPendingPurge(rows.map((row) => row.versionId));
    final assets = await Future.wait(rows.map(_asset));
    final paths = <String, String>{};
    for (final asset in assets) {
      if (paths.containsKey(asset.version.id)) continue;
      if (await _verify(asset) != CopyAvailability.available) {
        if (typedSourceFailures) {
          throw const ResourceFailure(FailureKind.unavailable);
        }
        throw StateError('副本缺失、损坏或无法读取，不能开始文件使用。');
      }
      paths[asset.version.id] = (await _files.file(
        asset.deviceCopy.relativePath,
      )).path;
    }
    await beforeLeaseCommit?.call();
    final leases = <String>[];
    await _db.transaction(() async {
      for (final version in paths.keys) {
        final id = const Uuid().v4();
        await _db
            .into(_db.fileLeases)
            .insert(
              FileLeasesCompanion.insert(
                id: id,
                versionId: version,
                ownerId: _leaseOwnerId,
                purpose: label,
                createdUtc: clock.now().toUtc().millisecondsSinceEpoch,
              ),
            );
        leases.add(id);
      }
    });
    _activeLeaseIds.addAll(leases);
    _leaseDrain ??= Completer<void>();
    return LibraryFileLease(
      assets: assets,
      pathsByVersion: paths,
      onRelease: () => _serial(() async {
        try {
          await _db.transaction(() async {
            await (_db.delete(_db.fileLeases)..where(
                  (t) => t.ownerId.equals(_leaseOwnerId) & t.id.isIn(leases),
                ))
                .go();
          });
        } finally {
          // release certifies actual IO ended. A failed DB cleanup keeps its
          // protective row, but shutdown must not wait for a nonexistent
          // worker. Retry/reopen can clear the stale transient protection.
          _activeLeaseIds.removeAll(leases);
          if (_activeLeaseIds.isEmpty) {
            _leaseDrain?.complete();
            _leaseDrain = null;
          }
        }
      }, settling: true),
    );
  });

  Future<void> registerProtection({
    required String ownerType,
    required String ownerId,
    required Iterable<String> versionIds,
  }) => _serial(
    () => _db.transaction(() async {
      _validateProtectionOwner(ownerType, ownerId);
      final versions = versionIds.toSet();
      await _rejectPendingPurge(versions);
      for (final id in versions) {
        final version = await (_db.select(
          _db.versions,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (version == null) throw StateError('保护引用的内容版本不存在。');
      }
      for (final id in versions) {
        await _db
            .into(_db.versionReferences)
            .insert(
              VersionReferencesCompanion.insert(
                id: const Uuid().v4(),
                versionId: id,
                ownerType: ownerType,
                ownerId: ownerId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }),
  );

  Future<void> releaseProtection({
    required String ownerType,
    required String ownerId,
  }) => _serial(() async {
    _validateProtectionOwner(ownerType, ownerId);
    await (_db.delete(_db.versionReferences)..where(
          (t) => t.ownerType.equals(ownerType) & t.ownerId.equals(ownerId),
        ))
        .go();
  });

  void _validateProtectionOwner(String type, String id) {
    if (!const {
          'processing',
          'output',
          'task',
          'export',
          'backup',
          'restore',
        }.contains(type) ||
        id.trim().isEmpty ||
        id.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(id)) {
      throw ArgumentError('保护引用所属对象无效。');
    }
  }

  Future<List<AssetRow>> _recycleRows(Iterable<String> assetIds) async {
    final ids = assetIds.toSet().toList();
    final rows = await (_db.select(
      _db.assets,
    )..where((t) => t.id.isIn(ids))).get();
    if (rows.length != ids.length) throw StateError('部分资产已不存在，未执行此批操作。');
    final byId = {for (final row in rows) row.id: row};
    return ids.map((id) => byId[id]!).toList();
  }

  Future<List<ImageAsset>> _recycleAssets(Iterable<String> ids) async =>
      List.unmodifiable(
        await Future.wait((await _recycleRows(ids)).map(_asset)),
      );

  Future<void> _rejectPendingPurge(Iterable<String> versions) async {
    final pending =
        await (_db.select(_db.purgeOperations)
              ..where((t) => t.versionId.isIn(versions.toSet()))
              ..limit(1))
            .get();
    if (pending.isNotEmpty) throw StateError('此内容有未完成清除，需先完成恢复检查。');
  }

  Future<void> _rejectVersionProtection(String version) async {
    final leases =
        await (_db.select(_db.fileLeases)
              ..where((t) => t.versionId.equals(version))
              ..limit(1))
            .get();
    final references =
        await (_db.select(_db.versionReferences)
              ..where((t) => t.versionId.equals(version))
              ..limit(1))
            .get();
    if (leases.isNotEmpty || references.isNotEmpty) {
      throw StateError('内容仍有文件使用或保护引用，不能永久清除。');
    }
  }

  Future<void> _rejectSharedVersion(
    String version,
    List<String> selected,
  ) async {
    final other =
        await (_db.select(_db.assets)
              ..where(
                (t) => t.versionId.equals(version) & t.id.isNotIn(selected),
              )
              ..limit(1))
            .get();
    if (other.isNotEmpty) throw StateError('内容仍被其他资产引用，不能清除共享副本。');
  }

  Future<void> _deleteAssetRecords(List<String> ids) async {
    await (_db.delete(_db.assetTags)..where((t) => t.assetId.isIn(ids))).go();
    await (_db.delete(_db.assets)..where((t) => t.id.isIn(ids))).go();
  }

  void _validateOriginalPath(String path) {
    if (!RegExp(
      r'^originals/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.original$',
    ).hasMatch(path)) {
      throw StateError('永久副本路径无效，已保留清除现场。');
    }
  }

  Future<void> _completePurge(PurgeOperation op) async {
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    if (!uuid.hasMatch(op.id) ||
        !uuid.hasMatch(op.versionId) ||
        op.createdUtc < 0) {
      throw StateError('清除日志身份无效。');
    }
    _validateOriginalPath(op.relativePath);
    final decoded = jsonDecode(op.assetIdsJson);
    if (decoded is! List ||
        decoded.isEmpty ||
        decoded.any((id) => id is! String || !uuid.hasMatch(id))) {
      throw StateError('清除日志资产集合无效。');
    }
    final ids = decoded.cast<String>();
    if (ids.toSet().length != ids.length) throw StateError('清除日志资产重复。');
    final intents = await (_db.select(
      _db.purgeOperations,
    )..where((t) => t.versionId.equals(op.versionId))).get();
    if (intents.length != 1 || intents.single != op) {
      throw StateError('清除日志冲突。');
    }
    final rows = await _recycleRows(ids);
    if (rows.any(
      (row) =>
          row.versionId != op.versionId || (op.removeRecords && !row.recycled),
    )) {
      throw StateError('清除日志与资产不一致。');
    }
    final copy = await (_db.select(
      _db.deviceCopies,
    )..where((t) => t.versionId.equals(op.versionId))).getSingle();
    if (copy.relativePath != op.relativePath) throw StateError('清除日志与副本不一致。');
    await _rejectVersionProtection(op.versionId);
    await _rejectSharedVersion(op.versionId, ids);
    final file = await _files.file(op.relativePath);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw StateError('清除目标不是普通管理文件。');
    }
    if (type == FileSystemEntityType.file) await file.delete();
    await _db.transaction(() async {
      await (_db.update(
        _db.deviceCopies,
      )..where((t) => t.id.equals(copy.id))).write(
        DeviceCopiesCompanion(
          availability: const Value('missing'),
          verifiedUtc: Value(clock.now().toUtc().millisecondsSinceEpoch),
        ),
      );
      if (op.removeRecords) await _deleteAssetRecords(ids);
      await (_db.delete(
        _db.purgeOperations,
      )..where((t) => t.id.equals(op.id))).go();
    });
  }

  Future<void> _recoverRecycle() => _serial(() async {
    // Only reached after this process acquired the exclusive managed-root lock.
    await (_db.delete(
      _db.fileLeases,
    )..where((t) => t.ownerId.equals(_leaseOwnerId).not())).go();
    final issues = [..._recoveryIssues];
    final intents =
        await (_db.select(_db.purgeOperations)..orderBy([
              (t) => OrderingTerm.asc(t.createdUtc),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    for (final op in intents) {
      try {
        await _completePurge(op);
      } catch (_) {
        issues.add(RecoveryIssue(op.id, '一项已确认清除未能安全完成，已保留现场；请检查副本与保护引用。'));
      }
    }
    _recoveryIssues = List.unmodifiable(issues);
  });
}
