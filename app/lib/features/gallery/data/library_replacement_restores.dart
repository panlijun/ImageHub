part of 'library_repository.dart';

/// Only a proved current snapshot can mint this replacement capability.
final class ReplacementRestorePreparation {
  ReplacementRestorePreparation._(
    this._hold,
    this._backup,
    this._snapshot,
    this.metadata,
    this._secrets,
    this.cancelledOldItems,
    this.settings,
  );
  final LibraryRestoreHold _hold;
  final ValidatedBackup _backup;
  final ReplacementSnapshot _snapshot;
  final BackupManifest metadata;
  final List<Map<String, Object?>> _secrets;
  final int cancelledOldItems;
  final BackupSettingsRestorePlan settings;
  int get currentAssets => _snapshot.assetCount;
  int get currentFiles => _snapshot.fileCount;
  int get currentBytes => _snapshot.byteCount;
  bool _used = false;
}

extension LibraryReplacementRestores on LibraryRepository {
  Future<ReplacementRestorePreparation> prepareReplacementRestore({
    required LibraryRestoreHold hold,
    required ValidatedBackup backup,
    required Future<int> Function(Directory) availableBytes,
    CancellationToken? cancellation,
    void Function(String, int, int)? onProgress,
  }) async {
    _checkRestoreHold(hold);
    if (_restoreExecution != null) {
      throw BackupSnapshotFailure('资料库维护操作正在执行，不能准备替换。');
    }
    await _requireRestoreJournalEmpty();
    ReplacementSnapshot? snapshot;
    try {
      final settings = await _checkedBackupSettingsPlan(
        backup.manifest.settings,
      );
      final secrets = await _serial(_replacementSecrets, maintenance: true);
      final metadata = BackupManifest.decode(
        backup.manifest.encode(redactor: _secretRedactor),
      );
      final pending = await _serial(
        () async =>
            (await _db
                    .customSelect(
                      "SELECT COUNT(*) AS n FROM upload_publications WHERE state NOT IN ('succeeded','failed','cancelled')",
                    )
                    .getSingle())
                .read<int>('n'),
        maintenance: true,
      );
      snapshot = await captureReplacementSnapshot(
        hold: hold,
        availableBytes: availableBytes,
        cancellation: cancellation,
        onProgress: onProgress,
      );
      onProgress?.call('正在验证当前快照可恢复', 0, 1);
      await proveReplacementSnapshotRecovery(
        snapshot,
        availableBytes: availableBytes,
        cancellation: cancellation,
      );
      _checkRestoreHold(hold);
      _restoreNotCancelled(cancellation);
      return ReplacementRestorePreparation._(
        hold,
        backup,
        snapshot,
        metadata,
        secrets,
        pending,
        settings,
      );
    } catch (_) {
      if (snapshot != null) {
        try {
          await discardReplacementSnapshot(snapshot);
        } catch (_) {
          /* preserve evidence */
        }
      }
      throw BackupSnapshotFailure(
        cancellation?.isCancelled == true
            ? '替换准备已取消，当前资料库保留；暂停任务须手动恢复。'
            : '当前快照或替换备份无法安全验证，未替换资料库；请检查空间、文件或安全存储后重试。',
      );
    }
  }

  Future<List<Map<String, Object?>>> _replacementSecrets() async {
    final refs = (await _db.customSelect(_libraryOwnedSecretsSql).get())
        .map((r) => r.read<String>('reference'))
        .toSet();
    final result = <Map<String, Object?>>[];
    for (final reference in refs) {
      if (!_replacementUuid.hasMatch(reference)) {
        throw BackupSnapshotFailure('当前安全存储关联无法确认。');
      }
      final value = await _secretStore.read(reference);
      if (value != null) _registerManagementSecret(value);
      result.add({
        'reference': reference,
        'hash': value == null
            ? null
            : hashing.sha256.convert(utf8.encode(value)).toString(),
      });
    }
    return result;
  }

  Future<void> discardReplacementPreparation(
    ReplacementRestorePreparation preparation,
  ) async {
    if (!identical(preparation._hold._owner, this)) {
      throw BackupSnapshotFailure('替换准备不属于当前资料库。');
    }
    if (preparation._snapshot._discarded) return;
    if (await _serial(_hasReplacementJournal, maintenance: true)) {
      throw BackupSnapshotFailure('替换恢复仍有未完成证据，不能清除当前快照。');
    }
    await discardReplacementSnapshot(preparation._snapshot);
  }

  Future<bool> _hasReplacementJournal() async => (await (_db.select(
    _db.restoreOperations,
  )..where((t) => t.phase.like('replace-%'))).get()).isNotEmpty;

  Future<MergeRestoreReport> commitReplacementRestore({
    required ReplacementRestorePreparation preparation,
    required Future<int> Function(Directory) availableBytes,
    required Future<bool> Function(File, File) publishExclusive,
    CancellationToken? cancellation,
    void Function(String, int, int)? onProgress,
    RestoreFaultHook? faultHook,
  }) async {
    _checkRestoreHold(preparation._hold);
    if (!identical(preparation._snapshot._owner, this) ||
        preparation._used ||
        _restoreExecution != null) {
      throw BackupSnapshotFailure('替换准备已失效或正在执行，不能重复提交。');
    }
    final id = const Uuid().v4();
    final metadata = preparation.metadata;
    final copies = <Map<String, Object?>>[
      for (final version in metadata.versions)
        _replacementCopy(version, metadata.mode),
    ];
    final payload = <String, Object?>{
      'format': 1,
      'snapshotId': preparation._snapshot.id,
      'manifest': metadata.toJson(redactor: _secretRedactor),
      'copies': copies,
      'secrets': preparation._secrets,
    };
    final drain = _restoreExecution = Completer<void>();
    preparation._used = true;
    var journaled = false, committed = false, cleanupPending = false;
    try {
      _restoreNotCancelled(cancellation);
      await _replacementVerifyBytes(
        preparation._snapshot.id,
        preparation._snapshot._payload,
      );
      await _replacementOldFilesMatch(preparation._snapshot._payload);
      await _checkReplacementSecretValues(preparation._secrets);
      await _serial(() async {
        _checkRestoreHold(preparation._hold);
        await _verifyRestoreSettings(preparation.settings);
        final logs = await _db.select(_db.restoreOperations).get();
        if (logs.length != 1 ||
            logs.single.id != preparation._snapshot.id ||
            logs.single.phase != 'snapshot-ready' ||
            logs.single.payloadJson !=
                jsonEncode(preparation._snapshot._payload)) {
          throw BackupSnapshotFailure('当前快照证据已变化，不能替换。');
        }
        await _db
            .into(_db.restoreOperations)
            .insert(
              RestoreOperationsCompanion.insert(
                id: id,
                phase: 'replace-writing',
                payloadJson: _replacementJournalJson(payload),
                createdUtc: clock.now().toUtc().millisecondsSinceEpoch,
              ),
            );
      }, maintenance: true);
      journaled = true;
      await faultHook?.call(RestoreBoundary.intent);
      final versions = {for (final v in metadata.versions) v.id: v};
      final total = metadata.mode == BackupMode.full
          ? metadata.versions.fold<int>(0, (n, v) => n + v.byteCount)
          : 0;
      await _restoreCapacity(availableBytes, total + 1024 * 1024);
      var done = 0;
      for (final copy in copies.where((c) => c['bytes'] == true)) {
        _restoreNotCancelled(cancellation);
        final v = versions[copy['versionId']]!;
        final source = preparation._backup.imageFiles[v.id];
        if (source == null) throw BackupSnapshotFailure('备份图片缺失，未替换资料库。');
        await _copyReplacementImage(id, payload, copy, source, v, cancellation);
        done += v.byteCount;
        onProgress?.call('正在保管永久图片', done, total);
        await _restoreCapacity(availableBytes, total - done + 1024 * 1024);
      }
      await faultHook?.call(RestoreBoundary.copied);
      _restoreNotCancelled(cancellation);
      await faultHook?.call(RestoreBoundary.prepared);
      for (final copy in copies.where((c) => c['bytes'] == true)) {
        _restoreNotCancelled(cancellation);
        final stage = await _files.file(copy['stagePath'] as String);
        final target = await _files.file(copy['finalPath'] as String);
        copy['publication'] = 'publishing';
        await _writeReplacementPayload(id, payload);
        if (!await publishExclusive(stage, target)) {
          copy['publication'] = 'conflict';
          await _writeReplacementPayload(id, payload);
          throw BackupSnapshotFailure('图片位置已被占用，未覆盖文件或替换资料库。');
        }
        copy['publication'] = 'published';
        await _writeReplacementPayload(id, payload);
        if (!await _restoreValidFile(target, versions[copy['versionId']]!)) {
          throw BackupSnapshotFailure('新副本校验失败，未替换资料库。');
        }
      }
      await faultHook?.call(RestoreBoundary.published);
      _restoreNotCancelled(cancellation);
      await _replacementOldFilesMatch(preparation._snapshot._payload);
      await faultHook?.call(RestoreBoundary.beforeCommit);
      _restoreNotCancelled(cancellation);
      onProgress?.call('正在提交替换关系', 0, 1);
      await _serial(() async {
        _checkRestoreHold(preparation._hold);
        await _db.transaction(() async {
          await _db.customStatement('PRAGMA defer_foreign_keys=ON');
          for (final table in _replacementTables.where(
            (t) =>
                t != 'restore_operations' &&
                t != 'library_metadata' &&
                t != 'diagnostic_records',
          )) {
            await _db.customStatement('DELETE FROM "$table"');
          }
          await _clearRemoteDeletionRecords();
          await _clearAccountHealthObservations();
          await _applyRestoreMetadata(metadata, copies);
          await _writeRestoredSettings(preparation.settings);
          await faultHook?.call(RestoreBoundary.metadataWritten);
          _restoreNotCancelled(cancellation);
          if ((await _db.customSelect('PRAGMA foreign_key_check').get())
              .isNotEmpty) {
            throw BackupSnapshotFailure('替换关联校验失败。');
          }
          await (_db.update(
            _db.restoreOperations,
          )..where((t) => t.id.equals(id))).write(
            const RestoreOperationsCompanion(phase: Value('replace-committed')),
          );
        });
      }, maintenance: true);
      committed = true;
      _activateReplacementEpoch();
      _activateRestoredSettings(preparation.settings);
      await faultHook?.call(RestoreBoundary.committed);
    } catch (_) {
      // A returned exception is not evidence that SQLite failed to COMMIT.
      if (journaled && !committed) {
        try {
          final row = await _serial(
            () => (_db.select(
              _db.restoreOperations,
            )..where((t) => t.id.equals(id))).getSingleOrNull(),
            maintenance: true,
          );
          committed = row?.phase == 'replace-committed';
          if (committed) {
            _activateReplacementEpoch();
            _activateRestoredSettings(preparation.settings);
          }
        } catch (_) {
          _replacementRecoveryBlocked = true;
        }
      }
      if (!committed) {
        if (journaled) {
          try {
            await _serial(() async {
              final row = await (_db.select(
                _db.restoreOperations,
              )..where((t) => t.id.equals(id))).getSingleOrNull();
              if (row != null) await _recoverReplacementRestore(row);
            }, maintenance: true);
          } catch (_) {
            _replacementRecoveryBlocked = true;
          }
        }
        throw BackupSnapshotFailure(
          _replacementRecoveryBlocked
              ? '替换未确认完成，回滚现场已保留并暂停读写；请保留资料库并重开核查。'
              : cancellation?.isCancelled == true
              ? '替换已取消，原资料库已恢复；暂停任务须手动恢复。'
              : '替换未提交，原资料库已恢复；请检查空间或文件后重试。',
        );
      }
    } finally {
      // Actual copies and metadata work settle before close can release locks.
      if (!committed) {
        _restoreExecution = null;
        drain.complete();
      }
    }
    try {
      await _serial(() async {
        final row = await (_db.select(
          _db.restoreOperations,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row != null) await _recoverReplacementRestore(row);
      }, maintenance: true);
      preparation._snapshot._discarded = true;
    } catch (_) {
      cleanupPending = true;
    } finally {
      _restoreExecution = null;
      if (!drain.isCompleted) drain.complete();
    }
    try {
      onProgress?.call('替换恢复已提交', 1, 1);
    } catch (_) {
      /* committed */
    }
    return MergeRestoreReport(
      addedAssets: metadata.assets.length,
      addedResults: metadata.results.length,
      importedHistories: metadata.history.length,
      savedCopies: copies.where((c) => c['bytes'] == true).length,
      metadataOnly: metadata.mode == BackupMode.metadata,
      conflicts: 0,
      cleanupPending: cleanupPending,
      settings: preparation.settings,
    );
  }

  void _activateReplacementEpoch() {
    _executionEpoch = const Uuid().v4();
    _sessionCredentials.clear();
    _thumbnailJobs.clear();
  }

  Map<String, Object?> _replacementCopy(ImageVersion v, BackupMode mode) {
    final physical = const Uuid().v4();
    return {
      'versionId': v.id,
      'incomingId': v.id,
      'copyId': const Uuid().v4(),
      'stagePath': 'staging/$physical.part',
      'finalPath': 'originals/$physical.original',
      'oldPath': null,
      'bytes': mode == BackupMode.full,
      'publication': 'pending',
      'stageOwned': false,
      'stageHash': null,
      'stageBytes': null,
    };
  }

  String _replacementJournalJson(Map<String, Object?> payload) {
    final json = jsonEncode(payload);
    if (_secretRedactor.redactText(json) != json) {
      throw BackupSnapshotFailure('替换操作无法安全记录，已保留资料库。');
    }
    return json;
  }

  Future<void> _writeReplacementPayload(
    String id,
    Map<String, Object?> payload,
  ) => _serial(
    () => (_db.update(_db.restoreOperations)..where((t) => t.id.equals(id)))
        .write(
          RestoreOperationsCompanion(
            payloadJson: Value(_replacementJournalJson(payload)),
          ),
        ),
    maintenance: true,
  );

  Future<void> _copyReplacementImage(
    String id,
    Map<String, Object?> payload,
    Map<String, Object?> copy,
    File source,
    ImageVersion v,
    CancellationToken? cancellation,
  ) async {
    await _restoreNoLinks(source);
    final stage = await _files.file(copy['stagePath'] as String);
    await stage.create(exclusive: true);
    copy['stageOwned'] = true;
    await _writeReplacementPayload(id, payload);
    final writer = await stage.open(mode: FileMode.writeOnly);
    Object? failure;
    var bytes = 0;
    try {
      await for (final chunk in source.openRead()) {
        _restoreNotCancelled(cancellation);
        bytes += chunk.length;
        if (bytes > v.byteCount) throw BackupSnapshotFailure('备份图片大小变化，停止复制。');
        await writer.writeFrom(chunk);
      }
      _restoreNotCancelled(cancellation);
      await writer.flush();
    } catch (error) {
      failure = error;
    } finally {
      await writer.close();
    }
    await _restoreNoLinks(stage);
    final digest = await _files.digest(stage);
    copy['stageHash'] = digest.sha256;
    copy['stageBytes'] = digest.byteCount;
    await _writeReplacementPayload(id, payload);
    if (failure != null ||
        digest.sha256 != v.sha256 ||
        digest.byteCount != v.byteCount ||
        !await _restoreValidFile(stage, v)) {
      throw BackupSnapshotFailure('备份图片未安全复制，停止替换。');
    }
  }

  Future<void> _replacementOldFilesMatch(Map<String, Object?> snapshot) async {
    for (final raw in snapshot['files'] as List) {
      final entry = raw as Map;
      final file = await _files.file(entry['source'] as String);
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (entry['state'] == 'missing') {
        if (type != FileSystemEntityType.notFound) {
          throw BackupSnapshotFailure('旧文件缺失证据已变化，保留现场。');
        }
      } else {
        await _restoreNoLinks(file);
        final digest = await _files.digest(file);
        if (digest.sha256 != entry['hash'] ||
            digest.byteCount != entry['bytes']) {
          throw BackupSnapshotFailure('原文件已变化，不能确认当前快照回滚。');
        }
      }
    }
  }

  Future<void> _checkReplacementSecretValues(
    List<Map<String, Object?>> secrets,
  ) async {
    for (final entry in secrets) {
      final value = await _secretStore.read(entry['reference'] as String);
      final hash = value == null
          ? null
          : hashing.sha256.convert(utf8.encode(value)).toString();
      if (hash != entry['hash']) {
        throw BackupSnapshotFailure('当前安全存储已变化，不能确认旧快照回滚。');
      }
    }
  }

  (Map<String, Object?>, BackupManifest, List<Map>, List<Map>)
  _readReplacementJournal(RestoreOperationRow row) {
    if (!{
          'replace-writing',
          'replace-rollback',
          'replace-committed',
          'replace-cleaned',
        }.contains(row.phase) ||
        !_replacementUuid.hasMatch(row.id)) {
      throw BackupSnapshotFailure('替换日志阶段无效。');
    }
    final raw = jsonDecode(row.payloadJson);
    const keys = {'format', 'snapshotId', 'manifest', 'copies', 'secrets'};
    if (raw is! Map ||
        raw.length != 5 ||
        !raw.keys.every(keys.contains) ||
        raw['format'] != 1 ||
        raw['snapshotId'] is! String ||
        !_replacementUuid.hasMatch(raw['snapshotId'] as String) ||
        raw['snapshotId'] == row.id ||
        raw['copies'] is! List ||
        raw['secrets'] is! List) {
      throw BackupSnapshotFailure('替换日志结构无效。');
    }
    final metadata = BackupManifest.fromJson(raw['manifest']);
    final versions = {for (final v in metadata.versions) v.id: v};
    final copies = (raw['copies'] as List).cast<Map>();
    final secrets = (raw['secrets'] as List).cast<Map>();
    const copyKeys = {
      'versionId',
      'incomingId',
      'copyId',
      'stagePath',
      'finalPath',
      'oldPath',
      'bytes',
      'publication',
      'stageOwned',
      'stageHash',
      'stageBytes',
    };
    final paths = <String>{},
        ids = <String>{},
        versionIds = <String>{},
        refs = <String>{};
    for (final c in copies) {
      final match = c['stagePath'] is String
          ? RegExp(r'^staging/([0-9a-f-]{36})\.part$')
                .firstMatch(c['stagePath'] as String)
          : null;
      if (c.length != 11 ||
          !c.keys.every(copyKeys.contains) ||
          match == null ||
          !_replacementUuid.hasMatch(match[1]!) ||
          c['finalPath'] != 'originals/${match[1]}.original' ||
          !paths.add(c['finalPath'] as String) ||
          c['copyId'] is! String ||
          !_replacementUuid.hasMatch(c['copyId'] as String) ||
          !ids.add(c['copyId'] as String) ||
          !versions.containsKey(c['versionId']) ||
          !versionIds.add(c['versionId'] as String) ||
          c['incomingId'] != c['versionId'] ||
          c['oldPath'] != null ||
          c['bytes'] != (metadata.mode == BackupMode.full) ||
          c['stageOwned'] is! bool ||
          !{
            'pending',
            'publishing',
            'published',
            'conflict',
          }.contains(c['publication'])) {
        throw BackupSnapshotFailure('替换文件日志无效。');
      }
      if ((c['stageHash'] != null || c['stageBytes'] != null) &&
          (c['stageOwned'] != true ||
              c['stageHash'] is! String ||
              !_replacementHash.hasMatch(c['stageHash'] as String) ||
              c['stageBytes'] is! int ||
              (c['stageBytes'] as int) < 0 ||
              (c['stageBytes'] as int) > versions[c['versionId']]!.byteCount)) {
        throw BackupSnapshotFailure('替换暂存证据无效。');
      }
      if ((c['publication'] != 'pending' && c['stageOwned'] != true) ||
          (c['bytes'] == false &&
              (c['publication'] != 'pending' ||
                  c['stageOwned'] != false ||
                  c['stageHash'] != null))) {
        throw BackupSnapshotFailure('替换发布证据无效。');
      }
      if ((row.phase == 'replace-committed' ||
              row.phase == 'replace-cleaned') &&
          c['bytes'] == true &&
          (c['publication'] != 'published' ||
              c['stageHash'] != versions[c['versionId']]!.sha256 ||
              c['stageBytes'] != versions[c['versionId']]!.byteCount)) {
        throw BackupSnapshotFailure('替换已提交副本证据不完整。');
      }
    }
    if (copies.length != versions.length) {
      throw BackupSnapshotFailure('替换版本关联不完整。');
    }
    for (final s in secrets) {
      if (s.length != 2 ||
          !s.containsKey('reference') ||
          !s.containsKey('hash') ||
          s['reference'] is! String ||
          !_replacementUuid.hasMatch(s['reference'] as String) ||
          !refs.add(s['reference'] as String) ||
          (s['hash'] != null &&
              (s['hash'] is! String ||
                  !_replacementHash.hasMatch(s['hash'] as String)))) {
        throw BackupSnapshotFailure('替换安全引用证据无效。');
      }
    }
    return (Map<String, Object?>.from(raw), metadata, copies, secrets);
  }

  Future<void> _recoverReplacementRestore(RestoreOperationRow row) async {
    final (payload, metadata, copies, secrets) = _readReplacementJournal(row);
    final snapshotRow =
        await (_db.select(_db.restoreOperations)
              ..where((t) => t.id.equals(payload['snapshotId'] as String)))
            .getSingleOrNull();
    if (row.phase == 'replace-cleaned') {
      if (snapshotRow != null) await _recoverReplacementSnapshot(snapshotRow);
      await (_db.delete(
        _db.restoreOperations,
      )..where((t) => t.id.equals(row.id))).go();
      return;
    }
    if (snapshotRow == null || snapshotRow.phase != 'snapshot-ready') {
      throw BackupSnapshotFailure('替换当前快照缺失，保留现场。');
    }
    final snapshot = _replacementPayload(snapshotRow);
    await _replacementVerifyBytes(snapshotRow.id, snapshot);
    // Validate all resources, references and ownership before the first delete.
    final oldPaths = (snapshot['files'] as List)
        .map((e) => (e as Map)['source'] as String)
        .toSet();
    final oldSecretRefs = await _snapshotSecretReferences(snapshot);
    if (secrets.length != oldSecretRefs.length ||
        !secrets.every((s) => oldSecretRefs.contains(s['reference']))) {
      throw BackupSnapshotFailure('旧安全存储归属无法确认。');
    }
    for (final c in copies) {
      if (oldPaths.contains(c['finalPath']) ||
          oldPaths.contains(c['stagePath'])) {
        throw BackupSnapshotFailure('新旧文件位置冲突，保留现场。');
      }
      final stage = await _files.file(c['stagePath'] as String),
          target = await _files.file(c['finalPath'] as String);
      if (c['stageOwned'] == true && await stage.exists()) {
        await _restoreNoLinks(stage);
        if (c['stageHash'] != null) {
          final digest = await _files.digest(stage);
          if (digest.sha256 != c['stageHash'] ||
              digest.byteCount != c['stageBytes']) {
            throw BackupSnapshotFailure('暂存字节已变化，保留现场。');
          }
        }
      }
      if (row.phase != 'replace-committed') {
        if (c['publication'] == 'publishing' &&
            !await stage.exists() &&
            await target.exists()) {
          throw BackupSnapshotFailure('发布归属未确认，保留回滚现场。');
        }
        if (c['publication'] == 'published' && await target.exists()) {
          if ((await (_db.select(_db.deviceCopies)..where(
                        (t) => t.relativePath.equals(c['finalPath'] as String),
                      ))
                      .get())
                  .isNotEmpty ||
              !await _restoreValidFile(
                target,
                metadata.versions.firstWhere((v) => v.id == c['versionId']),
              )) {
            throw BackupSnapshotFailure('新副本不能安全回收，保留现场。');
          }
        }
      }
    }
    if (row.phase != 'replace-committed') {
      await _replacementOldFilesMatch(snapshot);
      for (final c in copies) {
        final target = await _files.file(c['finalPath'] as String),
            stage = await _files.file(c['stagePath'] as String);
        if (c['publication'] == 'published' && await target.exists()) {
          await target.delete();
        }
        if (c['stageOwned'] == true && await stage.exists()) {
          await stage.delete();
        }
      }
      await _rollbackReplacementMetadata(snapshotRow, operationId: row.id);
      _replacementRecoveryBlocked = false;
      return;
    }
    // A committed transaction never rolls back. Only old unreferenced owned
    // resources are reclaimed; current rows/leases retain their protection.
    for (final raw in snapshot['files'] as List) {
      final e = raw as Map;
      final file = await _files.file(e['source'] as String);
      if (e['state'] == 'missing') {
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw BackupSnapshotFailure('旧缺失位置出现未知字节，保留现场。');
        }
      } else if (await file.exists()) {
        await _restoreNoLinks(file);
        final digest = await _files.digest(file);
        if (digest.sha256 != e['hash'] || digest.byteCount != e['bytes']) {
          throw BackupSnapshotFailure('旧字节已变化，不能安全清理。');
        }
        final refs = await _db
            .customSelect(
              'SELECT relative_path FROM device_copies WHERE relative_path=? UNION SELECT relative_path FROM processed_outputs WHERE relative_path=? OR relative_path || \'.part\'=?',
              variables: [
                Variable<String>(e['source'] as String),
                Variable<String>(e['source'] as String),
                Variable<String>(e['source'] as String),
              ],
            )
            .get();
        if (refs.isNotEmpty) throw BackupSnapshotFailure('旧字节被当前资料引用，不能清理。');
      }
    }
    for (final s in secrets) {
      final reference = s['reference'] as String;
      final refs = await _db
          .customSelect(
            'SELECT reference FROM ($_libraryOwnedSecretsSql) WHERE reference=?',
            variables: [Variable<String>(reference)],
          )
          .get();
      if (refs.isNotEmpty) throw BackupSnapshotFailure('旧安全引用仍在使用，不能清理。');
      final value = await _secretStore.read(reference);
      if (value != null &&
          (s['hash'] == null ||
              hashing.sha256.convert(utf8.encode(value)).toString() !=
                  s['hash'])) {
        throw BackupSnapshotFailure('安全存储内容变化，保留清理现场。');
      }
    }
    for (final raw in snapshot['files'] as List) {
      final e = raw as Map;
      if (e['state'] == 'missing') continue;
      final file = await _files.file(e['source'] as String);
      if (await file.exists()) await file.delete();
    }
    for (final s in secrets) {
      final reference = s['reference'] as String;
      if (await _secretStore.read(reference) != null) {
        await _secretStore.delete(reference);
      }
      if (await _secretStore.read(reference) != null) {
        throw BackupSnapshotFailure('安全存储清理尚未确认。');
      }
    }
    for (final c in copies) {
      final stage = await _files.file(c['stagePath'] as String);
      if (c['stageOwned'] == true && await stage.exists()) await stage.delete();
    }
    // The marker survives partially deleted snapshot files or its removed row.
    await (_db.update(
      _db.restoreOperations,
    )..where((t) => t.id.equals(row.id))).write(
      const RestoreOperationsCompanion(phase: Value('replace-cleaned')),
    );
    await _recoverReplacementSnapshot(snapshotRow);
    await (_db.delete(
      _db.restoreOperations,
    )..where((t) => t.id.equals(row.id))).go();
  }

  Future<Set<String>> _snapshotSecretReferences(
    Map<String, Object?> payload,
  ) async {
    final file = await _files.file('${payload['directory']}/current.sqlite');
    final db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
    try {
      return db
          .select(_libraryOwnedSecretsSql)
          .map((r) => r['reference'] as String)
          .toSet();
    } finally {
      db.close();
    }
  }
}
