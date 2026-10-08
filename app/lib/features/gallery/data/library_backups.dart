part of 'library_repository.dart';

extension LibraryBackups on LibraryRepository {
  /// Captures the committed business graph and permanent source leases under
  /// the sole writer gate. Long pixel/hash work runs after leaving that gate.
  Future<BackupSnapshotLease> captureBackupSnapshot({
    required BackupMode mode,
    BackupBudgets budgets = const BackupBudgets(),
    CancellationToken? cancellation,
    void Function(int verified, int total)? onVerification,
  }) => _captureBackupSnapshot(
    mode: mode,
    budgets: budgets,
    cancellation: cancellation,
    onVerification: onVerification,
  );

  Future<BackupSnapshotLease> _captureBackupSnapshot({
    required BackupMode mode,
    BackupBudgets budgets = const BackupBudgets(),
    CancellationToken? cancellation,
    void Function(int verified, int total)? onVerification,
    bool maintenance = false,
  }) async {
    BackupSnapshotLease? captured;
    try {
      final capture = await _serial<BackupSnapshotLease>(() async {
        _backupNotCancelled(cancellation);
        if (_closing != null) {
          throw BackupSnapshotFailure('资料库正在关闭，不能开始备份。');
        }
        final leaseIds = <String>[];
        final sourceFiles = <String, File>{};
        final snapshot = await _db.transaction(() async {
          // Conservative early row budget. This prevents an unbounded SELECT
          // before the manifest's more precise nested-record validation.
          const tables = [
            'versions',
            'assets',
            'categories',
            'tags',
            'asset_tags',
            'saved_output_origins',
            'restored_output_origins',
            'imported_upload_histories',
            'provider_targets',
            'remote_upload_results',
            'upload_publications',
            'upload_attempts',
          ];
          var rows = 0;
          for (final table in tables) {
            rows +=
                (await _db
                        .customSelect('SELECT COUNT(*) AS n FROM $table')
                        .getSingle())
                    .read<int>('n');
            if (rows > budgets.maxRecords) {
              throw const BackupFailure(BackupFailureKind.resourceBudget);
            }
          }
          final versions = await _db.select(_db.versions).get();
          final assets = await _db.select(_db.assets).get();
          final categories = await _db.select(_db.categories).get();
          final tags = await _db.select(_db.tags).get();
          final assetTags =
              await (_db.select(_db.assetTags)..orderBy([
                    (t) => OrderingTerm.asc(t.assetId),
                    (t) => OrderingTerm.asc(t.position),
                  ]))
                  .get();
          final tagsByAsset = <String, List<String>>{};
          for (final link in assetTags) {
            (tagsByAsset[link.assetId] ??= []).add(link.tagId);
          }
          final origins = await _db.select(_db.savedOutputOrigins).get();
          final restoredOrigins = await _db
              .select(_db.restoredOutputOrigins)
              .get();
          final importedHistories = await _db
              .select(_db.importedUploadHistories)
              .get();
          final targets = await _db.select(_db.providerTargets).get();
          final results = await _db.select(_db.remoteUploadResults).get();
          final credentialOperations = await _db
              .select(_db.credentialOperations)
              .get();
          final resultOperations = await _db
              .select(_db.uploadResultOperations)
              .get();

          // Register all references owned by this library before producing an
          // ordinary portable view. No readAll or other application's keys.
          final references = <String>{
            for (final row in targets)
              if (row.secretReference != null) row.secretReference!,
            for (final row in credentialOperations) ...[
              if (row.newReference != null) row.newReference!,
              if (row.oldReference != null) row.oldReference!,
            ],
            for (final row in results)
              if (row.secretReference != null) row.secretReference!,
            for (final row in resultOperations)
              if (row.secretReference != null) row.secretReference!,
          };
          for (final reference in references) {
            final secret = await _secretStore.read(reference);
            if (secret == null) {
              throw BackupSnapshotFailure(
                '无法确认本库凭据或管理秘密的安全视图，未生成备份；请到账号或链接页核查受保护存储后重试。',
              );
            }
            _registerManagementSecret(secret);
          }
          for (final secret in _sessionCredentials.values) {
            _secretRedactor.register(secret);
          }

          final terminal =
              await (_db.select(_db.uploadPublications)..where(
                    (t) => t.state.isIn(['succeeded', 'failed', 'cancelled']),
                  ))
                  .get();
          final attempts =
              await (_db.select(_db.uploadAttempts)
                    ..where((t) => t.itemId.isIn(terminal.map((row) => row.id)))
                    ..orderBy([(t) => OrderingTerm.asc(t.generation)]))
                  .get();
          final attemptsByItem = <String, List<UploadAttempt>>{};
          for (final attempt in attempts) {
            (attemptsByItem[attempt.itemId] ??= []).add(attempt);
          }
          final histories = <BackupTaskHistory>[];
          for (final row in terminal) {
            final ownAttempts = attemptsByItem[row.id] ?? const [];
            // A terminal cancellation intent with actual IO still alive is not
            // a completed portable history. Independent confirmations remain.
            if (ownAttempts.any((attempt) => attempt.endedUtc == null)) {
              continue;
            }
            if (row.processingJobId != null &&
                _activeUploadProcessingJobs.contains(row.processingJobId)) {
              continue;
            }
            histories.add(
              BackupTaskHistory(
                id: row.id,
                batchId: row.batchId,
                position: row.position,
                input: _readUploadInput(row.inputJson),
                target: _readUploadTarget(row.targetJson),
                state: PublishState.values.byName(row.state),
                attempts: ownAttempts.map(
                  (attempt) => BackupAttemptHistory(
                    id: attempt.id,
                    generation: attempt.generation,
                    startedUtc: attempt.startedUtc,
                    endedUtc: attempt.endedUtc!,
                    outcome: attempt.outcome,
                  ),
                ),
                createdUtc: row.createdUtc,
                updatedUtc: row.updatedUtc,
                message: row.message,
              ),
            );
          }

          final descriptions =
              versions
                  .map(
                    (row) => ImageVersion(
                      id: row.id,
                      sha256: row.digest,
                      byteCount: row.byteCount,
                      format: row.format,
                      width: row.width,
                      height: row.height,
                      frameCount: row.frameCount,
                      orientation: row.orientation,
                    ),
                  )
                  .toList()
                ..sort((a, b) => a.id.compareTo(b.id));
          final images = <BackupImageEntry>[];
          if (mode == BackupMode.full) {
            await _rejectPendingPurge(descriptions.map((v) => v.id));
            final copies = await _db.select(_db.deviceCopies).get();
            final byVersion = {for (final copy in copies) copy.versionId: copy};
            final missing = descriptions
                .where((v) => !byVersion.containsKey(v.id))
                .map((v) => v.id)
                .toList();
            if (missing.isNotEmpty) {
              throw BackupSnapshotFailure(
                '必要永久副本缺失，未生成完整备份；请修复、取消或明确选择元数据备份。',
                affectedVersions: missing,
              );
            }
            for (final version in descriptions) {
              final copy = byVersion[version.id]!;
              _validateOriginalPath(copy.relativePath);
              sourceFiles[version.id] = await _files.file(copy.relativePath);
              images.add(
                BackupImageEntry(
                  versionId: version.id,
                  name: 'images/${version.id}.${version.format.toLowerCase()}',
                  byteCount: version.byteCount,
                  sha256: version.sha256,
                ),
              );
            }
          }
          final manifest = BackupManifest(
            settings: BackupDeviceSettings(values: await _readDeviceSettings()),
            packageId: const Uuid().v4(),
            createdUtc: clock.now().toUtc().millisecondsSinceEpoch,
            mode: mode,
            versions: descriptions,
            assets: assets.map(
              (row) => BackupAsset(
                id: row.id,
                versionId: row.versionId,
                displayName: row.displayName,
                sourceType: row.sourceType,
                importedUtc: row.importedUtc,
                updatedUtc: row.updatedUtc,
                favorite: row.favorite,
                categoryId: row.category,
                recycled: row.recycled,
                recycledUtc: row.recycledUtc,
                tagIds: tagsByAsset[row.id] ?? const [],
              ),
            ),
            categories: categories.map(
              (row) => BackupName(id: row.id, name: row.name),
            ),
            tags: tags.map((row) => BackupName(id: row.id, name: row.name)),
            origins: [
              ...origins.map(
                (row) => BackupOrigin(
                  outputId: row.outputId,
                  versionId: row.versionId,
                  createdUtc: row.createdUtc,
                  processing: _portableProcessing(row.requestJson),
                ),
              ),
              ...restoredOrigins.expand(
                (row) => _readRestoreFragment(row.snapshotJson).origins,
              ),
            ],
            accounts: targets.map(
              (row) => BackupAccount(
                id: row.id,
                service: ImageHostService.values.byName(row.service),
                alias: row.alias,
                anonymous: row.anonymous,
              ),
            ),
            results: results.map(
              (row) => BackupRemoteResult(
                id: row.id,
                attemptId: row.attemptId,
                input: _readUploadInput(row.inputJson),
                target: _readUploadTarget(row.targetJson),
                remoteId: row.remoteId,
                directUrl: _safeUploadUrl(Uri.parse(row.directUrl)),
                viewerUrl: row.viewerUrl == null
                    ? null
                    : _safeUploadUrl(Uri.parse(row.viewerUrl!)),
                confirmedUtc: row.confirmedUtc,
                late: row.late,
              ),
            ),
            history: [
              ...histories,
              ...importedHistories.expand(
                (row) => _readRestoreFragment(row.snapshotJson).history,
              ),
            ],
            images: images,
          );
          final bytes = manifest.encode(
            redactor: _secretRedactor,
            budgets: budgets,
          );
          final safeManifest = BackupManifest.decode(bytes, budgets: budgets);
          _backupNotCancelled(cancellation);
          for (final version in descriptions) {
            if (mode != BackupMode.full) break;
            final id = const Uuid().v4();
            await _db
                .into(_db.fileLeases)
                .insert(
                  FileLeasesCompanion.insert(
                    id: id,
                    versionId: version.id,
                    ownerId: _leaseOwnerId,
                    purpose: 'backup',
                    createdUtc: clock.now().toUtc().millisecondsSinceEpoch,
                  ),
                );
            leaseIds.add(id);
          }
          return (manifest: safeManifest, bytes: bytes);
        });
        _activeLeaseIds.addAll(leaseIds);
        if (leaseIds.isNotEmpty) _leaseDrain ??= Completer<void>();
        return BackupSnapshotLease(
          manifest: snapshot.manifest,
          manifestBytes: snapshot.bytes,
          permanentFiles: sourceFiles,
          onRelease: () => leaseIds.isEmpty
              ? Future.value()
              : _serial(() async {
                  try {
                    await (_db.delete(_db.fileLeases)..where(
                          (t) =>
                              t.ownerId.equals(_leaseOwnerId) &
                              t.id.isIn(leaseIds),
                        ))
                        .go();
                  } catch (_) {
                    throw BackupSnapshotFailure('备份文件使用已结束，但保护记录清理失败；请重开后核查。');
                  } finally {
                    _activeLeaseIds.removeAll(leaseIds);
                    if (_activeLeaseIds.isEmpty) {
                      _leaseDrain?.complete();
                      _leaseDrain = null;
                    }
                  }
                }, settling: true),
        );
      }, maintenance: maintenance);

      captured = capture;
      final invalid = <String>[];
      var verified = 0;
      for (final version in capture.manifest.versions) {
        if (mode != BackupMode.full) break;
        _backupNotCancelled(cancellation);
        try {
          final file = capture.permanentFiles[version.id]!;
          final digest = await _files.digest(file);
          final metadata = await _inspector.inspect(file);
          if (digest.sha256 != version.sha256 ||
              digest.byteCount != version.byteCount ||
              metadata.format != version.format ||
              metadata.width != version.width ||
              metadata.height != version.height ||
              metadata.frameCount != version.frameCount ||
              metadata.orientation != version.orientation) {
            invalid.add(version.id);
          }
        } catch (_) {
          invalid.add(version.id);
        }
        onVerification?.call(++verified, capture.manifest.versions.length);
      }
      _backupNotCancelled(cancellation);
      if (invalid.isNotEmpty) {
        throw BackupSnapshotFailure(
          '必要永久副本不可读或校验失败，未生成完整备份；请修复、取消或明确选择元数据备份。',
          affectedVersions: invalid,
        );
      }
      return capture;
    } catch (error) {
      await captured?.release();
      if (error is BackupFailure || error is BackupSnapshotFailure) rethrow;
      throw BackupSnapshotFailure('无法安全取得备份视图，原资料库已保留。');
    }
  }

  void _backupNotCancelled(CancellationToken? cancellation) {
    if (cancellation?.isCancelled == true) {
      throw BackupSnapshotFailure('备份已取消，原资料库保持有效。');
    }
  }

  BackupProcessingSnapshot _portableProcessing(String source) {
    final request = jsonDecode(source) as Map<String, dynamic>;
    const fields = [
      'operation',
      'mode',
      'outputFormat',
      'longestSide',
      'quality',
      'crop',
      'layout',
      'gap',
      'backgroundArgb',
      'backgroundConfirmed',
      'explicitStaticConversion',
    ];
    return BackupProcessingSnapshot.fromJson({
      for (final key in fields) key: request[key],
      'inputs': [
        for (final input in (request['inputs'] as List).cast<Map>())
          {
            'assetId': input['assetId'],
            'version': input['version'],
            'selectedFrame': input['selectedFrame'],
          },
      ],
    });
  }
}
