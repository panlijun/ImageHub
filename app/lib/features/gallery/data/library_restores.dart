part of 'library_repository.dart';

enum RestoreBoundary {
  intent,
  copied,
  prepared,
  published,
  beforeCommit,
  metadataWritten,
  committed,
}

typedef RestoreFaultHook = Future<void> Function(RestoreBoundary boundary);

/// Only this repository can mint a hold. Normal APIs cannot bypass maintenance.
final class LibraryRestoreHold {
  LibraryRestoreHold._(this._owner);
  final LibraryRepository _owner;
  bool _released = false;
  Future<void> release() => _owner._releaseRestoreHold(this);
}

final class MergeRestorePreparation {
  MergeRestorePreparation._(this._hold, this._backup, this.plan, this.settings);
  final LibraryRestoreHold _hold;
  final ValidatedBackup _backup;
  final BackupRestorePlan plan;
  final BackupSettingsRestorePlan settings;
  bool _used = false;
}

final class MergeRestoreReport {
  const MergeRestoreReport({
    required this.addedAssets,
    required this.addedResults,
    required this.importedHistories,
    required this.savedCopies,
    required this.metadataOnly,
    required this.conflicts,
    required this.cleanupPending,
    this.settings,
  });
  final int addedAssets,
      addedResults,
      importedHistories,
      savedCopies,
      conflicts;
  final bool metadataOnly, cleanupPending;
  final BackupSettingsRestorePlan? settings;
}

extension LibraryRestores on LibraryRepository {
  Future<LibraryRestoreHold> acquireRestoreHold({
    CancellationToken? cancellation,
  }) async {
    if (_restoreRequested || _closed || _closing != null) {
      throw BackupSnapshotFailure('资料库已有维护或正在关闭，不能开始恢复。');
    }
    _restoreRequested = true;
    _outputMaintenance?.cancel();
    try {
      // First drain everything accepted before the synchronous barrier.
      await _serial(() async {}, maintenance: true);
      if (_activeLeaseIds.isNotEmpty) {
        await (_leaseDrain ??= Completer<void>()).future;
      }
      await _waitLinkProbeDrain();
      await _waitRemoteDeletionDrain();
      // Finalizers need the writer gate, so the wait above never holds it.
      await _serial(() async {
        _restoreNotCancelled(cancellation);
        if (_closed ||
            _closing != null ||
            _activeLeaseIds.isNotEmpty ||
            _activeLinkProbeIds.isNotEmpty ||
            _activeRemoteDeletionIds.isNotEmpty) {
          throw BackupSnapshotFailure('本机文件使用未安全结束，已阻止恢复。');
        }
        for (final table in [
          'file_leases',
          'output_leases',
          'import_operations',
          'purge_operations',
          'credential_operations',
          'upload_result_operations',
          'restore_operations',
        ]) {
          final count =
              (await _db
                      .customSelect('SELECT COUNT(*) AS n FROM $table')
                      .getSingle())
                  .read<int>('n');
          if (count != 0) {
            throw BackupSnapshotFailure('存在未完成操作或未清理保护，请重开核查后再恢复。');
          }
        }
        final running = await (_db.select(
          _db.uploadPublications,
        )..where((t) => t.state.equals('running'))).get();
        if (running.isNotEmpty) {
          throw BackupSnapshotFailure('上传尝试尚未安全结束，已阻止恢复。');
        }
        await _db.transaction(() async {
          final active =
              await (_db.select(_db.uploadPublications)..where(
                    (t) =>
                        t.state.isNotIn(['succeeded', 'failed', 'cancelled']),
                  ))
                  .get();
          for (final batchId in active.map((r) => r.batchId).toSet()) {
            await (_db.update(_db.uploadBatches)
                  ..where((t) => t.id.equals(batchId)))
                .write(const UploadBatchesCompanion(paused: Value(true)));
          }
          for (final item in active.where(
            (r) => {'queued', 'waiting', 'interrupted'}.contains(r.state),
          )) {
            await _setUploadState(
              item.id,
              PublishState.paused,
              reason: item.waitReason == null
                  ? null
                  : QueueWaitReason.values.byName(item.waitReason!),
              retryDelay: item.retryDelayMicros == null
                  ? null
                  : Duration(microseconds: item.retryDelayMicros!),
            );
          }
        });
        _restoreReady = true;
      }, maintenance: true);
      return _restoreHold = LibraryRestoreHold._(this);
    } catch (_) {
      _restoreReady = false;
      _restoreRequested = false;
      _restartOutputMaintenance();
      rethrow;
    }
  }

  void _checkRestoreHold(LibraryRestoreHold hold) {
    if (!identical(hold._owner, this) ||
        !identical(_restoreHold, hold) ||
        hold._released ||
        !_restoreReady ||
        !_restoreRequested ||
        _closed ||
        _closing != null) {
      throw BackupSnapshotFailure('恢复保护已失效，不能继续提交。');
    }
  }

  Future<void> _releaseRestoreHold(LibraryRestoreHold hold) async {
    if (hold._released) return;
    if (!identical(hold._owner, this) || !identical(_restoreHold, hold)) {
      throw BackupSnapshotFailure('恢复保护不属于当前资料库。');
    }
    if (_restoreExecution != null) {
      throw BackupSnapshotFailure('恢复文件操作尚未结束，不能提前释放保护。');
    }
    if (_replacementRecoveryBlocked && !_closed) {
      throw BackupSnapshotFailure('替换恢复现场尚待核查，维护保护已保留。');
    }
    if (_closed) {
      hold._released = true;
      _restoreHold = null;
      _restoreReady = false;
      _restoreRequested = false;
      return;
    }
    await _serial(() async {
      hold._released = true;
      _restoreHold = null;
      _restoreReady = false;
      _restoreRequested = false;
    }, maintenance: true);
    _restartOutputMaintenance();
  }

  Future<MergeRestorePreparation> prepareMergeRestore({
    required LibraryRestoreHold hold,
    required ValidatedBackup backup,
  }) async {
    _checkRestoreHold(hold);
    if (_restoreExecution != null) {
      throw BackupSnapshotFailure('资料库维护操作正在执行，不能同时准备恢复。');
    }
    final drain = _restoreExecution = Completer<void>();
    try {
      await _requireRestoreJournalEmpty();
      return await _prepareMergeRestore(hold: hold, backup: backup);
    } finally {
      _restoreExecution = null;
      drain.complete();
    }
  }

  Future<void> _requireRestoreJournalEmpty() => _serial(() async {
    final count =
        (await _db
                .customSelect('SELECT COUNT(*) AS n FROM restore_operations')
                .getSingle())
            .read<int>('n');
    if (count != 0) {
      throw BackupSnapshotFailure('存在未完成的恢复或内部快照，请先安全清理或重开核查。');
    }
  }, maintenance: true);

  Future<MergeRestorePreparation> _prepareMergeRestore({
    required LibraryRestoreHold hold,
    required ValidatedBackup backup,
  }) async {
    _checkRestoreHold(hold);
    final snapshot = await _captureBackupSnapshot(
      mode: BackupMode.metadata,
      maintenance: true,
    );
    try {
      final active = await _serial(() async {
        return (_db.select(_db.uploadPublications)..where(
              (t) => t.state.isNotIn(['succeeded', 'failed', 'cancelled']),
            ))
            .get();
      }, maintenance: true);
      final attempts = await _serial(() async {
        return (_db.select(
          _db.uploadAttempts,
        )..where((t) => t.itemId.isIn(active.map((r) => r.id)))).get();
      }, maintenance: true);
      final localOutputIds = await _serial(() async {
        return (await _db.select(_db.processedOutputs).get())
            .map((o) => o.id)
            .toSet();
      }, maintenance: true);
      final plan = BackupRestorePlanner.plan(
        current: snapshot.manifest,
        incoming: backup.manifest,
        activeTaskIds: active.map((r) => r.id).toSet(),
        activeAttemptIds: attempts.map((r) => r.id).toSet(),
        localOutputIds: localOutputIds,
        activePositions: active
            .map((r) => jsonEncode([r.batchId, r.position]))
            .toSet(),
      );
      return MergeRestorePreparation._(
        hold,
        backup,
        plan,
        await _checkedBackupSettingsPlan(backup.manifest.settings),
      );
    } finally {
      await snapshot.release();
    }
  }

  Future<Directory> backupRestoreTemporaryParent() => _serial(() async {
    await _files.file('staging/.guard');
    return _files.directory('staging');
  });

  Future<MergeRestoreReport> commitMergeRestore({
    required MergeRestorePreparation preparation,
    required Future<int> Function(Directory) availableBytes,
    required Future<bool> Function(File source, File destination)
    publishExclusive,
    CancellationToken? cancellation,
    void Function(String phase, int done, int total)? onProgress,
    RestoreFaultHook? faultHook,
  }) async {
    _checkRestoreHold(preparation._hold);
    if (_restoreExecution != null) {
      throw BackupSnapshotFailure('恢复操作正在执行，不能重复提交。');
    }
    final drain = _restoreExecution = Completer<void>();
    try {
      await _requireRestoreJournalEmpty();
      return await _commitMergeRestore(
        preparation: preparation,
        availableBytes: availableBytes,
        publishExclusive: publishExclusive,
        cancellation: cancellation,
        onProgress: onProgress,
        faultHook: faultHook,
      );
    } finally {
      _restoreExecution = null;
      drain.complete();
    }
  }

  Future<MergeRestoreReport> _commitMergeRestore({
    required MergeRestorePreparation preparation,
    required Future<int> Function(Directory) availableBytes,
    required Future<bool> Function(File source, File destination)
    publishExclusive,
    CancellationToken? cancellation,
    void Function(String phase, int done, int total)? onProgress,
    RestoreFaultHook? faultHook,
  }) async {
    _checkRestoreHold(preparation._hold);
    if (preparation._used || !preparation.plan.canCommit) {
      throw BackupSnapshotFailure('恢复提议存在阻断冲突或已经使用，未修改资料库。');
    }
    preparation._used = true;
    final metadata = preparation.plan.metadata!;
    final operationId = const Uuid().v4();
    final copies = <Map<String, Object?>>[];
    var committed = false, cleanupPending = false;
    var addedAssets = 0, addedResults = 0, importedHistories = 0;
    try {
      _restoreNotCancelled(cancellation);
      await _serial(
        () => _verifyRestoreSettings(preparation.settings),
        maintenance: true,
      );
      final manifestBytes = metadata.encode(redactor: _secretRedactor);
      final safeMetadata = BackupManifest.decode(manifestBytes);
      final currentCopies = await _serial(
        () => _db.select(_db.deviceCopies).get(),
        maintenance: true,
      );
      final byVersion = {
        for (final copy in currentCopies) copy.versionId: copy,
      };
      final incomingVersions = {
        for (final v in preparation._backup.manifest.versions) v.id: v,
      };
      final targetVersions = {for (final v in safeMetadata.versions) v.id: v};
      for (final incoming in incomingVersions.values) {
        final targetId = preparation.plan.versionIds[incoming.id]!;
        final version = targetVersions[targetId]!;
        final previous = byVersion[targetId];
        if (previous != null) _validateOriginalPath(previous.relativePath);
        if (previous != null &&
            await _restoreValidFile(
              await _files.file(previous.relativePath),
              version,
            )) {
          continue;
        }
        if (preparation._backup.manifest.mode == BackupMode.metadata &&
            previous != null) {
          continue; // Metadata never removes or repairs existing local bytes.
        }
        if (previous != null) {
          await _serial(
            () => _rejectVersionProtection(targetId),
            maintenance: true,
          );
        }
        final physicalId = const Uuid().v4();
        copies.add({
          'versionId': targetId,
          'incomingId': incoming.id,
          'copyId': previous?.id ?? const Uuid().v4(),
          'stagePath': 'staging/$physicalId.part',
          'finalPath': 'originals/$physicalId.original',
          'oldPath': previous?.relativePath,
          'bytes': preparation._backup.manifest.mode == BackupMode.full,
          'publication': 'pending',
        });
      }
      final copiedBytes = copies
          .where((c) => c['bytes'] == true)
          .fold<int>(
            0,
            (n, c) => n + incomingVersions[c['incomingId']]!.byteCount,
          );
      final requiredBytes =
          copiedBytes + manifestBytes.length * 3 + 1024 * 1024;
      onProgress?.call('预计所需空间', 0, requiredBytes);
      await _restoreCapacity(availableBytes, requiredBytes);
      final payload = {
        'manifest': jsonDecode(utf8.decode(manifestBytes)),
        'copies': copies,
      };
      String payloadJson() {
        final json = jsonEncode(payload);
        if (_secretRedactor.redactText(json) != json) {
          throw BackupSnapshotFailure('恢复操作不能安全记录，未修改资料库。');
        }
        return json;
      }

      await _serial(
        () => _db
            .into(_db.restoreOperations)
            .insert(
              RestoreOperationsCompanion.insert(
                id: operationId,
                phase: 'writing',
                payloadJson: payloadJson(),
                createdUtc: clock.now().toUtc().millisecondsSinceEpoch,
              ),
            ),
        maintenance: true,
      );
      await faultHook?.call(RestoreBoundary.intent);
      var copied = 0;
      for (final copy in copies.where((c) => c['bytes'] == true)) {
        _restoreNotCancelled(cancellation);
        final incoming = incomingVersions[copy['incomingId']]!;
        final source = preparation._backup.imageFiles[incoming.id];
        if (source == null) throw BackupSnapshotFailure('备份永久图片缺失，未提交恢复。');
        await _restoreNoLinks(source);
        final digest = await _files.copySource(
          PlatformResource(displayName: '备份图片', openRead: source.openRead),
          copy['stagePath']! as String,
          cancellation,
          incoming.byteCount,
          null,
        );
        final stage = await _files.file(copy['stagePath']! as String);
        if (digest.sha256 != incoming.sha256 ||
            digest.byteCount != incoming.byteCount ||
            !await _restoreValidFile(stage, incoming)) {
          throw BackupSnapshotFailure('备份图片复制后校验失败，未提交恢复。');
        }
        copied += incoming.byteCount;
        onProgress?.call('正在保管永久图片', copied, copiedBytes);
        await _restoreCapacity(
          availableBytes,
          copiedBytes - copied + 1024 * 1024,
        );
      }
      await faultHook?.call(RestoreBoundary.copied);
      _restoreNotCancelled(cancellation);
      await _serial(
        () =>
            (_db.update(
              _db.restoreOperations,
            )..where((t) => t.id.equals(operationId))).write(
              RestoreOperationsCompanion(
                phase: const Value('prepared'),
                payloadJson: Value(payloadJson()),
              ),
            ),
        maintenance: true,
      );
      await faultHook?.call(RestoreBoundary.prepared);
      for (final copy in copies.where((c) => c['bytes'] == true)) {
        _restoreNotCancelled(cancellation);
        copy['publication'] = 'publishing';
        await _serial(
          () =>
              (_db.update(
                _db.restoreOperations,
              )..where((t) => t.id.equals(operationId))).write(
                RestoreOperationsCompanion(payloadJson: Value(payloadJson())),
              ),
          maintenance: true,
        );
        final stage = await _files.file(copy['stagePath']! as String);
        final target = await _files.file(copy['finalPath']! as String);
        if (!await publishExclusive(stage, target)) {
          copy['publication'] = 'conflict';
          await _serial(
            () =>
                (_db.update(
                  _db.restoreOperations,
                )..where((t) => t.id.equals(operationId))).write(
                  RestoreOperationsCompanion(payloadJson: Value(payloadJson())),
                ),
            maintenance: true,
          );
          throw BackupSnapshotFailure('永久副本发布位置已存在，未覆盖原文件或提交恢复。');
        }
        copy['publication'] = 'published';
        await _serial(
          () =>
              (_db.update(
                _db.restoreOperations,
              )..where((t) => t.id.equals(operationId))).write(
                RestoreOperationsCompanion(payloadJson: Value(payloadJson())),
              ),
          maintenance: true,
        );
        final version = incomingVersions[copy['incomingId']]!;
        if (!await _restoreValidFile(target, version)) {
          throw BackupSnapshotFailure('发布后的永久副本校验失败，未提交恢复。');
        }
      }
      await faultHook?.call(RestoreBoundary.published);
      _restoreNotCancelled(cancellation);
      await faultHook?.call(RestoreBoundary.beforeCommit);
      _restoreNotCancelled(cancellation);
      onProgress?.call('正在提交恢复关系', 0, 1);
      final counts = await _serial(() async {
        _checkRestoreHold(preparation._hold);
        return _db.transaction(() async {
          final counts = await _applyRestoreMetadata(safeMetadata, copies);
          await _writeRestoredSettings(preparation.settings);
          await faultHook?.call(RestoreBoundary.metadataWritten);
          _restoreNotCancelled(cancellation);
          await (_db.update(
            _db.restoreOperations,
          )..where((t) => t.id.equals(operationId))).write(
            const RestoreOperationsCompanion(phase: Value('committed')),
          );
          return counts;
        });
      }, maintenance: true);
      committed = true;
      _activateRestoredSettings(preparation.settings);
      addedAssets = counts.$1;
      addedResults = counts.$2;
      importedHistories = counts.$3;
      await faultHook?.call(RestoreBoundary.committed);
    } catch (_) {
      if (!committed) {
        try {
          await _serial(() => _cleanupRestore(operationId), maintenance: true);
        } catch (_) {
          /* Persistent evidence remains, and no old records changed. */
        }
        throw BackupSnapshotFailure(
          cancellation?.isCancelled == true
              ? '恢复已取消，当前图库数据保持有效。'
              : '恢复未提交，当前图库已保留；请核查空间、保护或重开后的恢复记录。',
        );
      }
      // The transaction has confirmed success. A later callback cannot undo it.
    }
    try {
      await _serial(() => _cleanupRestore(operationId), maintenance: true);
    } catch (_) {
      cleanupPending = true;
    }
    try {
      onProgress?.call('合并恢复已提交', 1, 1);
    } catch (_) {
      // A display callback cannot turn committed data into failure.
    }
    return MergeRestoreReport(
      addedAssets: addedAssets,
      addedResults: addedResults,
      importedHistories: importedHistories,
      savedCopies: copies.where((c) => c['bytes'] == true).length,
      metadataOnly: preparation._backup.manifest.mode == BackupMode.metadata,
      conflicts:
          preparation.plan.permanent.issues.length +
          preparation.plan.relationIssues.length,
      cleanupPending: cleanupPending,
      settings: preparation.settings,
    );
  }

  Future<bool> _restoreValidFile(File file, ImageVersion version) async {
    try {
      final digest = await _files.digest(file);
      if (digest.sha256 != version.sha256 ||
          digest.byteCount != version.byteCount) {
        return false;
      }
      final image = await _inspector.inspect(file);
      return image.format == version.format &&
          image.width == version.width &&
          image.height == version.height &&
          image.frameCount == version.frameCount &&
          image.orientation == version.orientation;
    } catch (_) {
      return false;
    }
  }

  Future<void> _restoreCapacity(
    Future<int> Function(Directory) available,
    int required,
  ) async {
    final bytes = await available(_files.root);
    if (bytes < required) {
      throw BackupSnapshotFailure('本机空间不足，未提交恢复。');
    }
  }

  void _restoreNotCancelled(CancellationToken? cancellation) {
    if (cancellation?.isCancelled == true) {
      throw BackupSnapshotFailure('恢复已取消，当前图库保持有效。');
    }
  }

  Future<void> _restoreNoLinks(File file) async {
    var path = file.absolute.path;
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw BackupSnapshotFailure('备份暂存图片不能安全读取。');
    }
    while (true) {
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw BackupSnapshotFailure('备份暂存位置包含链接，不能恢复。');
      }
      final parent = File(path).parent.path;
      if (parent == path) break;
      path = parent;
    }
  }

  Future<(int, int, int)> _applyRestoreMetadata(
    BackupManifest metadata,
    List<Map<String, Object?>> copies,
  ) async {
    var assetsAdded = 0, resultsAdded = 0, historyAdded = 0;
    for (final version in metadata.versions) {
      final existing = await (_db.select(
        _db.versions,
      )..where((t) => t.id.equals(version.id))).getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_db.versions)
            .insert(
              VersionsCompanion.insert(
                id: version.id,
                digest: version.sha256,
                byteCount: version.byteCount,
                format: version.format,
                width: version.width,
                height: version.height,
                frameCount: version.frameCount,
                orientation: version.orientation,
              ),
            );
      } else if (existing.digest != version.sha256 ||
          existing.byteCount != version.byteCount ||
          existing.format != version.format ||
          existing.width != version.width ||
          existing.height != version.height ||
          existing.frameCount != version.frameCount ||
          existing.orientation != version.orientation) {
        throw BackupSnapshotFailure('当前版本与恢复提议不一致，已阻止提交。');
      }
    }
    for (final copy in copies) {
      await _db
          .into(_db.deviceCopies)
          .insertOnConflictUpdate(
            DeviceCopiesCompanion.insert(
              id: copy['copyId']! as String,
              versionId: copy['versionId']! as String,
              relativePath: copy['finalPath']! as String,
              availability: Value(
                copy['bytes'] == true ? 'available' : 'missing',
              ),
              verifiedUtc: copy['bytes'] == true
                  ? Value(clock.now().toUtc().millisecondsSinceEpoch)
                  : const Value.absent(),
            ),
          );
    }
    for (final name in metadata.categories) {
      final existing = await (_db.select(
        _db.categories,
      )..where((t) => t.id.equals(name.id))).getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: name.id,
                name: name.name,
                nameKey: TextPolicy.key(name.name),
              ),
            );
      }
      // Existing names are local data. The portable snapshot may mask a
      // credential substring; that safe view cannot rename the original.
    }
    for (final name in metadata.tags) {
      final existing = await (_db.select(
        _db.tags,
      )..where((t) => t.id.equals(name.id))).getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_db.tags)
            .insert(
              TagsCompanion.insert(
                id: name.id,
                name: name.name,
                nameKey: TextPolicy.key(name.name),
              ),
            );
      }
    }
    for (final asset in metadata.assets) {
      final existing = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(asset.id))).getSingleOrNull();
      if (existing != null && existing.versionId != asset.versionId) {
        throw BackupSnapshotFailure('当前资产内容已变化，已阻止恢复覆盖。');
      }
      if (existing == null) assetsAdded++;
      await _db
          .into(_db.assets)
          .insertOnConflictUpdate(
            AssetsCompanion.insert(
              id: asset.id,
              displayName:
                  existing != null && existing.displayName.trim().isNotEmpty
                  ? existing.displayName
                  : asset.displayName,
              versionId: asset.versionId,
              importedUtc: existing?.importedUtc ?? asset.importedUtc,
              updatedUtc: existing?.updatedUtc ?? asset.updatedUtc,
              sourceType: existing?.sourceType ?? asset.sourceType,
              favorite: Value(asset.favorite),
              category: Value(existing?.category ?? asset.categoryId),
              recycled: Value(existing?.recycled ?? asset.recycled),
              recycledUtc: Value(
                existing != null ? existing.recycledUtc : asset.recycledUtc,
              ),
            ),
          );
      await (_db.delete(
        _db.assetTags,
      )..where((t) => t.assetId.equals(asset.id))).go();
      for (var i = 0; i < asset.tagIds.length; i++) {
        await _db
            .into(_db.assetTags)
            .insert(
              AssetTagsCompanion.insert(
                assetId: asset.id,
                tagId: asset.tagIds[i],
                position: i,
              ),
            );
      }
    }
    for (final account in metadata.accounts) {
      final existing = await (_db.select(
        _db.providerTargets,
      )..where((t) => t.id.equals(account.id))).getSingleOrNull();
      if (existing != null) {
        continue; // Existing configuration/credentials stay local.
      }
      await _db
          .into(_db.providerTargets)
          .insert(
            ProviderTargetsCompanion.insert(
              id: account.id,
              service: account.service.name,
              alias: account.alias,
              enabled: false,
              selectedByDefault: false,
              anonymous: account.anonymous,
              health: AccountHealth.unconfigured.name,
              createdUtc: metadata.createdUtc,
              modifiedUtc: metadata.createdUtc,
            ),
          );
    }
    for (final origin in metadata.origins) {
      final native = await (_db.select(
        _db.savedOutputOrigins,
      )..where((t) => t.outputId.equals(origin.outputId))).getSingleOrNull();
      final archived = await (_db.select(
        _db.restoredOutputOrigins,
      )..where((t) => t.outputId.equals(origin.outputId))).getSingleOrNull();
      if (native != null || archived != null) continue;
      final fragment = _restoreFragment(metadata, origins: [origin]);
      await _db
          .into(_db.restoredOutputOrigins)
          .insert(
            RestoredOutputOriginsCompanion.insert(
              outputId: origin.outputId,
              versionId: origin.versionId,
              snapshotJson: utf8.decode(
                fragment.encode(redactor: _secretRedactor),
              ),
            ),
          );
    }
    for (final result in metadata.results) {
      final existing =
          await (_db.select(_db.remoteUploadResults)..where(
                (t) =>
                    t.id.equals(result.id) |
                    t.attemptId.equals(result.attemptId),
              ))
              .getSingleOrNull();
      if (existing != null) continue;
      await _db
          .into(_db.remoteUploadResults)
          .insert(
            RemoteUploadResultsCompanion.insert(
              id: result.id,
              attemptId: result.attemptId,
              inputJson: jsonEncode(_inputSnapshot(result.input)),
              targetJson: jsonEncode(_targetSnapshot(result.target)),
              targetId: result.target.id,
              versionDigest: result.input.version.sha256,
              byteCount: result.input.version.byteCount,
              policyKey: result.input.policyKey,
              remoteId: result.remoteId,
              directUrl: _safeUploadUrl(result.directUrl).toString(),
              viewerUrl: Value(
                result.viewerUrl == null
                    ? null
                    : _safeUploadUrl(result.viewerUrl!).toString(),
              ),
              confirmedUtc: result.confirmedUtc,
              late: result.late,
              // There is deliberately no secret reference or restored management flag.
            ),
          );
      resultsAdded++;
    }
    for (final history in metadata.history) {
      final native = await (_db.select(
        _db.uploadPublications,
      )..where((t) => t.id.equals(history.id))).getSingleOrNull();
      final archived = await (_db.select(
        _db.importedUploadHistories,
      )..where((t) => t.id.equals(history.id))).getSingleOrNull();
      if (native != null || archived != null) continue;
      final fragment = _restoreFragment(metadata, history: [history]);
      await _db
          .into(_db.importedUploadHistories)
          .insert(
            ImportedUploadHistoriesCompanion.insert(
              id: history.id,
              batchId: history.batchId,
              position: history.position,
              snapshotJson: utf8.decode(
                fragment.encode(redactor: _secretRedactor),
              ),
            ),
          );
      historyAdded++;
    }
    return (assetsAdded, resultsAdded, historyAdded);
  }

  BackupManifest _restoreFragment(
    BackupManifest metadata, {
    List<BackupOrigin> origins = const [],
    List<BackupTaskHistory> history = const [],
  }) => BackupManifest(
    packageId: metadata.packageId,
    createdUtc: metadata.createdUtc,
    mode: BackupMode.metadata,
    versions: metadata.versions.where(
      (v) => origins.any((o) => o.versionId == v.id),
    ),
    assets: const [],
    categories: const [],
    tags: const [],
    origins: origins,
    accounts: const [],
    results: const [],
    history: history,
    images: const [],
  );

  BackupManifest _readRestoreFragment(String json) =>
      BackupManifest.decode(utf8.encode(json));

  Future<List<BackupTaskHistory>> listImportedUploadHistories() => _serial(
    () async => List.unmodifiable(
      (await _db.select(_db.importedUploadHistories).get()).expand(
        (row) => _readRestoreFragment(row.snapshotJson).history,
      ),
    ),
  );

  Future<List<BackupOrigin>> restoredOutputOrigins(String versionId) => _serial(
    () async => List.unmodifiable(
      (await (_db.select(
        _db.restoredOutputOrigins,
      )..where((t) => t.versionId.equals(versionId))).get()).expand(
        (row) => _readRestoreFragment(row.snapshotJson).origins,
      ),
    ),
  );

  Future<void> _cleanupRestore(String id) async {
    final row = await (_db.select(
      _db.restoreOperations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    if (!{'writing', 'prepared', 'committed'}.contains(row.phase)) {
      throw BackupSnapshotFailure('恢复日志阶段不能识别，已保留现场。');
    }
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    if (payload.length != 2 ||
        !payload.containsKey('manifest') ||
        !payload.containsKey('copies')) {
      throw BackupSnapshotFailure('恢复日志结构不能识别，已保留现场。');
    }
    final metadata = BackupManifest.fromJson(payload['manifest']);
    final versions = {for (final v in metadata.versions) v.id: v};
    final copies = (payload['copies'] as List).cast<Map>();
    final seenPaths = <String>{},
        seenVersions = <String>{},
        seenCopies = <String>{};
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    const keys = {
      'versionId',
      'incomingId',
      'copyId',
      'stagePath',
      'finalPath',
      'oldPath',
      'bytes',
      'publication',
    };
    // Validate every log entry before deleting any file. A malformed later
    // entry must not leave a partially cleaned, unreviewable operation.
    for (final copy in copies) {
      final stagePath = copy['stagePath'] as String;
      final finalPath = copy['finalPath'] as String;
      final match = RegExp(
        r'^staging/([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.part$',
      ).firstMatch(stagePath);
      if (copy.length != 8 ||
          !copy.keys.every(keys.contains) ||
          match == null ||
          finalPath != 'originals/${match[1]}.original' ||
          !seenPaths.add(finalPath) ||
          copy['versionId'] is! String ||
          !seenVersions.add(copy['versionId'] as String) ||
          copy['copyId'] is! String ||
          !uuid.hasMatch(copy['copyId'] as String) ||
          !seenCopies.add(copy['copyId'] as String) ||
          copy['incomingId'] is! String ||
          !uuid.hasMatch(copy['incomingId'] as String) ||
          !versions.containsKey(copy['versionId']) ||
          !{
            'pending',
            'publishing',
            'published',
            'conflict',
          }.contains(copy['publication']) ||
          copy['bytes'] is! bool) {
        throw BackupSnapshotFailure('恢复日志位置不能安全验证，已保留现场。');
      }
      if (copy['bytes'] == false && copy['publication'] != 'pending') {
        throw BackupSnapshotFailure('元数据恢复日志不能包含文件发布，已保留现场。');
      }
      final oldPath = copy['oldPath'];
      if (oldPath != null) {
        if (oldPath is! String) {
          throw BackupSnapshotFailure('恢复日志旧副本不能安全验证，已保留现场。');
        }
        _validateOriginalPath(oldPath);
        if (oldPath == finalPath || seenPaths.contains(oldPath)) {
          throw BackupSnapshotFailure('恢复日志位置冲突，已保留数据。');
        }
      }
    }
    if (copies.any(
      (c) => c['oldPath'] != null && seenPaths.contains(c['oldPath']),
    )) {
      throw BackupSnapshotFailure('恢复日志位置冲突，已保留数据。');
    }
    for (final copy in copies) {
      final stagePath = copy['stagePath'] as String;
      final finalPath = copy['finalPath'] as String;
      final stage = await _files.file(stagePath);
      final finalFile = await _files.file(finalPath);
      if (row.phase != 'committed' && copy['bytes'] == true) {
        if (copy['publication'] == 'publishing' &&
            !await stage.exists() &&
            await finalFile.exists()) {
          // Publication returned no durable ownership confirmation. Never
          // guess that an existing permanent file may safely be deleted.
          throw BackupSnapshotFailure('永久副本发布归属未确认，恢复现场已保留待核查。');
        }
        if (copy['publication'] == 'published' && await finalFile.exists()) {
          final references = await (_db.select(
            _db.deviceCopies,
          )..where((t) => t.relativePath.equals(finalPath))).get();
          if (references.isNotEmpty ||
              !await _restoreValidFile(
                finalFile,
                versions[copy['versionId']]!,
              )) {
            throw BackupSnapshotFailure('恢复半成品不能安全回收，已保留保护现场。');
          }
          await finalFile.delete();
        }
      }
      if (await stage.exists()) await _files.deleteStage(stagePath);
      final oldPath = copy['oldPath'];
      if (row.phase == 'committed' &&
          copy['bytes'] == true &&
          oldPath is String) {
        _validateOriginalPath(oldPath);
        final current =
            await (_db.select(_db.deviceCopies)
                  ..where((t) => t.id.equals(copy['copyId'] as String)))
                .getSingleOrNull();
        if (current == null ||
            current.versionId != copy['versionId'] ||
            current.relativePath != finalPath) {
          throw BackupSnapshotFailure('恢复提交的副本身份不能确认，已保留旧字节。');
        }
        final references = await (_db.select(
          _db.deviceCopies,
        )..where((t) => t.relativePath.equals(oldPath))).get();
        if (references.isEmpty) {
          final old = await _files.file(oldPath);
          if (await old.exists()) await old.delete();
        }
      }
    }
    await (_db.delete(
      _db.restoreOperations,
    )..where((t) => t.id.equals(id))).go();
  }

  Future<void> _recoverRestores() => _serial(() async {
    var replacementBlocked = false;
    final rows = await _db.select(_db.restoreOperations).get();
    rows.sort(
      (a, b) => (a.phase.startsWith('replace-') ? 0 : 1).compareTo(
        b.phase.startsWith('replace-') ? 0 : 1,
      ),
    );
    for (final row in rows) {
      try {
        final current = await (_db.select(
          _db.restoreOperations,
        )..where((t) => t.id.equals(row.id))).getSingleOrNull();
        if (current == null) continue;
        if (row.phase.startsWith('replace-')) {
          await _recoverReplacementRestore(current);
        } else if (row.phase == 'snapshot-writing' ||
            row.phase == 'snapshot-ready') {
          if (await _hasReplacementJournal()) continue;
          await _recoverReplacementSnapshot(row);
        } else {
          await _cleanupRestore(row.id);
        }
      } catch (_) {
        if (row.phase.startsWith('replace-') &&
            row.phase != 'replace-committed' &&
            row.phase != 'replace-cleaned') {
          replacementBlocked = true;
        }
        _recoveryIssues = List.unmodifiable([
          ..._recoveryIssues,
          RecoveryIssue(row.id, '一项恢复现场不能安全清理，已保留当前图库；请核查后重试。'),
        ]);
      }
    }
    // A later valid journal must not un-block an earlier unsafe recovery.
    _replacementRecoveryBlocked = replacementBlocked;
  });
}
