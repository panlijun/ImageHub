part of 'library_repository.dart';

/// An internal rollback capability. Paths and database contents stay private.
final class ReplacementSnapshot {
  ReplacementSnapshot._(
    this._owner,
    this._hold,
    this.id,
    this.assetCount,
    this.fileCount,
    this.byteCount,
    this._payload,
  );
  final LibraryRepository _owner;
  final LibraryRestoreHold _hold;
  final String id;
  final int assetCount, fileCount, byteCount;
  final Map<String, Object?> _payload;
  bool _discarded = false;
}

const _replacementTables = <String>{
  'upload_batches',
  'upload_processing_jobs',
  'upload_publications',
  'upload_attempts',
  'remote_upload_results',
  'upload_result_operations',
  'upload_events',
  'provider_targets',
  'credential_operations',
  'versions',
  'assets',
  'device_copies',
  'import_operations',
  'categories',
  'tags',
  'asset_tags',
  'file_leases',
  'version_references',
  'purge_operations',
  'library_metadata',
  'processed_outputs',
  'output_references',
  'output_leases',
  'saved_output_origins',
  'restored_output_origins',
  'imported_upload_histories',
  'restore_operations',
  'diagnostic_records',
};
final _replacementUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _replacementHash = RegExp(r'^[0-9a-f]{64}$');

final class _ReplacementHashSink implements Sink<hashing.Digest> {
  hashing.Digest? digest;
  @override
  void add(hashing.Digest value) => digest = value;
  @override
  void close() {}
}

String _replacementRowsHash(Iterable<Map<String, Object?>> rows) {
  final sink = _ReplacementHashSink();
  final converter = hashing.sha256.startChunkedConversion(sink);
  for (final row in rows) {
    final keys = row.keys.toList()..sort();
    converter.add(
      utf8.encode(
        jsonEncode([
          for (final key in keys) [key, row[key]],
        ]),
      ),
    );
    converter.add([10]);
  }
  converter.close();
  return sink.digest!.toString();
}

extension LibraryReplacementSnapshots on LibraryRepository {
  Future<ReplacementSnapshot> captureReplacementSnapshot({
    required LibraryRestoreHold hold,
    required Future<int> Function(Directory) availableBytes,
    CancellationToken? cancellation,
    void Function(String phase, int done, int total)? onProgress,
  }) async {
    _checkRestoreHold(hold);
    if (_restoreExecution != null) {
      throw BackupSnapshotFailure('资料库维护文件操作尚未结束，不能创建内部快照。');
    }
    final drain = _restoreExecution = Completer<void>();
    final id = const Uuid().v4();
    var journaled = false;
    try {
      _restoreNotCancelled(cancellation);
      final payload = <String, Object?>{
        'format': 1,
        'directory': 'staging/replacement-$id',
        'directoryState': 'unclaimed',
        'database': 'current.sqlite',
        'databaseHash': null,
        'databaseBytes': null,
        'schemaHash': null,
        'tableHashes': null,
        'files': <Map<String, Object?>>[],
      };
      final entries = payload['files'] as List<Map<String, Object?>>;
      var assets = 0;
      await _serial(() async {
        _checkRestoreHold(hold);
        await _replacementCheckLiveSchema();
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
            throw BackupSnapshotFailure('存在未排空的文件使用或操作，不能创建内部快照。');
          }
        }
        if (_activeLeaseIds.isNotEmpty || _activeOutputWrites.isNotEmpty) {
          throw BackupSnapshotFailure('实际文件工作尚未结束，不能创建内部快照。');
        }
        assets =
            (await _db
                    .customSelect('SELECT COUNT(*) AS n FROM assets')
                    .getSingle())
                .read<int>('n');
        final paths = <String>{};
        for (final row in await _db.select(_db.deviceCopies).get()) {
          _validateOriginalPath(row.relativePath);
          paths.add(row.relativePath);
        }
        for (final row in await _db.select(_db.processedOutputs).get()) {
          _validateOutputRow(row);
          paths.add(row.relativePath);
          paths.add('${row.relativePath}.part');
        }
        for (final path in paths) {
          _restoreNotCancelled(cancellation);
          final source = await _files.file(path);
          final type = await FileSystemEntity.type(
            source.path,
            followLinks: false,
          );
          if (type != FileSystemEntityType.file &&
              type != FileSystemEntityType.notFound) {
            throw BackupSnapshotFailure('内部快照来源不是安全普通文件。');
          }
          final digest = type == FileSystemEntityType.file
              ? await _replacementDigest(source, cancellation)
              : null;
          entries.add({
            'source': path,
            'filename': '${const Uuid().v4()}.bin',
            'state': digest == null ? 'missing' : 'pending',
            'hash': digest?.sha256,
            'bytes': digest?.byteCount,
          });
        }
        final pages =
            (await _db.customSelect('PRAGMA page_count').getSingle())
                    .data
                    .values
                    .single
                as int;
        final pageSize =
            (await _db.customSelect('PRAGMA page_size').getSingle())
                    .data
                    .values
                    .single
                as int;
        final required =
            pages * pageSize +
            entries.fold<int>(0, (n, e) => n + (e['bytes'] as int? ?? 0)) +
            1024 * 1024;
        onProgress?.call('预计内部快照空间', 0, required);
        await _restoreCapacity(availableBytes, required);
        _restoreNotCancelled(cancellation);
        final directory = await _replacementDirectory(id);
        if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw BackupSnapshotFailure('内部快照位置已经存在，已保留原目录。');
        }
        await _db
            .into(_db.restoreOperations)
            .insert(
              RestoreOperationsCompanion.insert(
                id: id,
                phase: 'snapshot-writing',
                payloadJson: _replacementPayloadJson(payload),
                createdUtc: clock.now().toUtc().millisecondsSinceEpoch,
              ),
            );
        journaled = true;
        onProgress?.call('内部快照意图已记录', 0, 1);
        if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw BackupSnapshotFailure('内部快照位置已经存在，已保留现场。');
        }
        await directory.create();
        await _replacementDirectory(id);
        if (await FileSystemEntity.type(directory.path, followLinks: false) !=
                FileSystemEntityType.directory ||
            !await directory.list(followLinks: false).isEmpty) {
          throw BackupSnapshotFailure('内部快照目录归属无法确认，已保留现场。');
        }
        // Ownership is durable before any snapshot file is created. If this
        // write fails, recovery preserves the unclaimed directory intact.
        payload['directoryState'] = 'owned';
        await (_db.update(
          _db.restoreOperations,
        )..where((t) => t.id.equals(id))).write(
          RestoreOperationsCompanion(
            payloadJson: Value(_replacementPayloadJson(payload)),
          ),
        );
        _restoreNotCancelled(cancellation);
        final target = await _files.file(
          '${payload['directory']}/current.sqlite',
        );
        // SQLite creates a consistent standalone database without copying WAL
        // files. The source remains WAL + FULL; VACUUM runs outside a transaction.
        await _db.customStatement('VACUUM INTO ?', [target.path]);
        await _restoreNoLinks(target);
        final handle = await target.open(mode: FileMode.append);
        try {
          await handle.flush();
        } finally {
          await handle.close();
        }
        final evidence = await _replacementDatabaseEvidence(
          target,
          compareSource: true,
          cancellation: cancellation,
        );
        payload['schemaHash'] = evidence.$1;
        payload['tableHashes'] = evidence.$2;
        final digest = await _files.digest(target);
        payload['databaseHash'] = digest.sha256;
        payload['databaseBytes'] = digest.byteCount;
      }, maintenance: true);
      var copied = 0;
      final total = entries.where((e) => e['state'] != 'missing').length;
      for (final entry in entries.where((e) => e['state'] != 'missing')) {
        _restoreNotCancelled(cancellation);
        await _restoreCapacity(
          availableBytes,
          (entry['bytes'] as int) + 1024 * 1024,
        );
        final source = await _files.file(entry['source'] as String);
        await _restoreNoLinks(source);
        final digest = await _files.copySource(
          PlatformResource(displayName: '内部快照', openRead: source.openRead),
          '${payload['directory']}/${entry['filename']}',
          cancellation,
          entry['bytes'] as int,
          null,
        );
        final sourceDigest = await _replacementDigest(source, cancellation);
        if (digest.sha256 != entry['hash'] ||
            digest.byteCount != entry['bytes'] ||
            sourceDigest.sha256 != digest.sha256 ||
            sourceDigest.byteCount != digest.byteCount) {
          throw BackupSnapshotFailure('内部快照复制校验失败，当前图库已保留。');
        }
        entry['state'] = 'ready';
        await _serial(
          () =>
              (_db.update(
                _db.restoreOperations,
              )..where((t) => t.id.equals(id))).write(
                RestoreOperationsCompanion(
                  payloadJson: Value(_replacementPayloadJson(payload)),
                ),
              ),
          maintenance: true,
        );
        onProgress?.call('正在保管内部快照', ++copied, total);
      }
      _restoreNotCancelled(cancellation);
      final snapshot = ReplacementSnapshot._(
        this,
        hold,
        id,
        assets,
        total,
        (payload['databaseBytes'] as int) +
            entries.fold<int>(0, (n, e) => n + (e['bytes'] as int? ?? 0)),
        payload,
      );
      await _replacementVerifyBytes(id, payload);
      _restoreNotCancelled(cancellation);
      await _serial(
        () => (_db.update(_db.restoreOperations)..where((t) => t.id.equals(id)))
            .write(
              RestoreOperationsCompanion(
                phase: const Value('snapshot-ready'),
                payloadJson: Value(_replacementPayloadJson(payload)),
              ),
            ),
        maintenance: true,
      );
      return snapshot;
    } catch (_) {
      if (journaled) {
        try {
          await _serial(() async {
            final row = await (_db.select(
              _db.restoreOperations,
            )..where((t) => t.id.equals(id))).getSingleOrNull();
            if (row != null) await _recoverReplacementSnapshot(row);
          }, maintenance: true);
        } catch (_) {
          /* Preserve the journal if safe cleanup cannot complete. */
        }
      }
      throw BackupSnapshotFailure(
        cancellation?.isCancelled == true
            ? '内部快照已取消，当前图库保持有效。'
            : '内部快照未完成，当前图库已保留；请核查空间或恢复现场。',
      );
    } finally {
      _restoreExecution = null;
      drain.complete();
    }
  }

  Future<void> verifyReplacementSnapshot(ReplacementSnapshot snapshot) async {
    _checkReplacementSnapshot(snapshot);
    if (_restoreExecution != null) throw BackupSnapshotFailure('维护文件操作正在执行。');
    final drain = _restoreExecution = Completer<void>();
    try {
      final row = await _serial(
        () => (_db.select(
          _db.restoreOperations,
        )..where((t) => t.id.equals(snapshot.id))).getSingleOrNull(),
        maintenance: true,
      );
      if (row == null ||
          row.phase != 'snapshot-ready' ||
          row.payloadJson != jsonEncode(snapshot._payload)) {
        throw BackupSnapshotFailure('内部快照证据失效，不能进行替换。');
      }
      await _replacementVerifyBytes(snapshot.id, snapshot._payload);
    } catch (_) {
      throw BackupSnapshotFailure('内部快照校验失败，当前图库已保留。');
    } finally {
      _restoreExecution = null;
      drain.complete();
    }
  }

  Future<void> discardReplacementSnapshot(ReplacementSnapshot snapshot) async {
    if (snapshot._discarded && identical(snapshot._owner, this)) return;
    _checkReplacementSnapshot(snapshot);
    if (_restoreExecution != null) {
      throw BackupSnapshotFailure('维护文件操作尚未结束，不能清理快照。');
    }
    final drain = _restoreExecution = Completer<void>();
    try {
      await _serial(() async {
        final row = await (_db.select(
          _db.restoreOperations,
        )..where((t) => t.id.equals(snapshot.id))).getSingleOrNull();
        if (row != null) {
          if (row.payloadJson != jsonEncode(snapshot._payload)) {
            throw BackupSnapshotFailure('内部快照日志已变化，已保留现场。');
          }
          await _recoverReplacementSnapshot(row);
        }
        snapshot._discarded = true;
      }, maintenance: true);
    } catch (_) {
      throw BackupSnapshotFailure('内部快照无法安全清理，证据已保留。');
    } finally {
      _restoreExecution = null;
      drain.complete();
    }
  }

  void _checkReplacementSnapshot(ReplacementSnapshot snapshot) {
    _checkRestoreHold(snapshot._hold);
    if (!identical(snapshot._owner, this) || snapshot._discarded) {
      throw BackupSnapshotFailure('内部快照不属于当前恢复保护。');
    }
  }

  Future<Directory> _replacementDirectory(String id) async {
    if (!_replacementUuid.hasMatch(id)) {
      throw BackupSnapshotFailure('内部快照身份无效。');
    }
    final relative = 'staging/replacement-$id';
    await _files.file('$relative/current.sqlite');
    return _files.directory(relative);
  }

  Future<(String, Map<String, String>)> _replacementDatabaseEvidence(
    File file, {
    bool compareSource = false,
    CancellationToken? cancellation,
  }) async {
    await _restoreNoLinks(file);
    final db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
    try {
      if (db.select('PRAGMA user_version').single.values.single !=
              librarySchemaVersion ||
          db.select('PRAGMA integrity_check').single.values.single != 'ok' ||
          db.select('PRAGMA foreign_key_check').isNotEmpty ||
          db
                  .select(
                    "SELECT value FROM library_metadata WHERE key='text_policy'",
                  )
                  .single
                  .values
                  .single !=
              'unicode-17-nfc-full-cf-v1') {
        throw BackupSnapshotFailure('内部快照数据库校验失败。');
      }
      final tables = db
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .map((r) => r['name'] as String)
          .toSet();
      if (tables.length != _replacementTables.length ||
          !tables.containsAll(_replacementTables)) {
        throw BackupSnapshotFailure('内部快照数据库结构不能识别。');
      }
      const schemaSql =
          "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name";
      final schemaRows = db.select(schemaSql);
      _replacementCheckSchemaRows(schemaRows);
      final schemaHash = _replacementRowsHash(schemaRows);
      if (compareSource) {
        if ((await _db.customSelect('PRAGMA user_version').getSingle())
                    .data
                    .values
                    .single !=
                librarySchemaVersion ||
            _replacementRowsHash(
                  (await _db.customSelect(schemaSql).get()).map((r) => r.data),
                ) !=
                schemaHash) {
          throw BackupSnapshotFailure('内部快照与当前数据库结构不一致。');
        }
      }
      final hashes = <String, String>{};
      for (final table in _replacementTables) {
        _restoreNotCancelled(cancellation);
        final columns = db
            .select('PRAGMA table_info("$table")')
            .map((r) => '"${r['name']}"')
            .toList();
        final sql = 'SELECT * FROM "$table" ORDER BY ${columns.join(',')}';
        final hash = await _replacementPagedRowsHash(
          db,
          sql,
          cancellation: cancellation,
        );
        if (compareSource &&
            await _replacementPagedRowsHash(
                  db,
                  sql,
                  source: true,
                  cancellation: cancellation,
                ) !=
                hash) {
          throw BackupSnapshotFailure('内部快照与当前数据库关系不一致。');
        }
        hashes[table] = hash;
      }
      return (schemaHash, hashes);
    } finally {
      db.close();
    }
  }

  Future<String> _replacementPagedRowsHash(
    sqlite.Database db,
    String sql, {
    bool source = false,
    CancellationToken? cancellation,
  }) async {
    final sink = _ReplacementHashSink();
    final converter = hashing.sha256.startChunkedConversion(sink);
    for (var offset = 0; ; offset += 128) {
      _restoreNotCancelled(cancellation);
      final query = '$sql LIMIT 128 OFFSET $offset';
      final rows = source
          ? (await _db.customSelect(query).get()).map((r) => r.data).toList()
          : db.select(query).map((r) => Map<String, Object?>.from(r)).toList();
      for (final row in rows) {
        final keys = row.keys.toList()..sort();
        converter.add(
          utf8.encode(
            jsonEncode([
              for (final key in keys) [key, row[key]],
            ]),
          ),
        );
        converter.add([10]);
      }
      if (rows.length < 128) break;
      await Future<void>.delayed(Duration.zero);
    }
    converter.close();
    return sink.digest!.toString();
  }

  Future<FileDigest> _replacementDigest(
    File file,
    CancellationToken? cancellation,
  ) async {
    await _restoreNoLinks(file);
    var count = 0;
    final digest = await hashing.sha256
        .bind(
          file.openRead().map((bytes) {
            _restoreNotCancelled(cancellation);
            count += bytes.length;
            return bytes;
          }),
        )
        .first;
    _restoreNotCancelled(cancellation);
    return FileDigest(digest.toString(), count);
  }

  String _replacementPayloadJson(Map<String, Object?> payload) {
    final encoded = jsonEncode(payload);
    if (_secretRedactor.redactText(encoded) != encoded) {
      throw BackupSnapshotFailure('内部快照日志与受保护秘密冲突，已保留当前资料库。');
    }
    return encoded;
  }

  void _replacementCheckSchemaRows(Iterable<Map<String, Object?>> rows) {
    const indexes = {
      'processed_outputs_expiry',
      'assets_import_order',
      'asset_tags_by_tag',
      'diagnostic_records_order',
      'diagnostic_records_batch',
      'diagnostic_records_attempt',
    };
    final expected = {..._replacementTables, ...indexes};
    final seen = <String>{};
    for (final row in rows) {
      final name = row['name'];
      if (name is! String ||
          !expected.contains(name) ||
          !seen.add(name) ||
          (_replacementTables.contains(name)
              ? row['type'] != 'table'
              : row['type'] != 'index')) {
        throw BackupSnapshotFailure('内部快照数据库模式不能识别。');
      }
    }
    if (seen.length != expected.length) {
      throw BackupSnapshotFailure('内部快照数据库模式不完整。');
    }
  }

  Future<void> _replacementCheckLiveSchema() async {
    if ((await _db.customSelect('PRAGMA user_version').getSingle())
                .data
                .values
                .single !=
            librarySchemaVersion ||
        (await _db.customSelect('PRAGMA integrity_check').getSingle())
                .data
                .values
                .single !=
            'ok' ||
        (await _db.customSelect('PRAGMA foreign_key_check').get()).isNotEmpty ||
        (await _db
                    .customSelect(
                      "SELECT value FROM library_metadata WHERE key='text_policy'",
                    )
                    .getSingle())
                .data
                .values
                .single !=
            'unicode-17-nfc-full-cf-v1') {
      throw BackupSnapshotFailure('当前资料库无法安全创建内部快照。');
    }
    final rows = await _db
        .customSelect(
          "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
        )
        .get();
    _replacementCheckSchemaRows(rows.map((r) => r.data));
  }

  Map<String, Object?> _replacementPayload(RestoreOperationRow row) {
    if (!{'snapshot-writing', 'snapshot-ready'}.contains(row.phase) ||
        !_replacementUuid.hasMatch(row.id)) {
      throw BackupSnapshotFailure('内部快照日志阶段无法识别。');
    }
    final raw = jsonDecode(row.payloadJson);
    const keys = {
      'format',
      'directory',
      'directoryState',
      'database',
      'databaseHash',
      'databaseBytes',
      'schemaHash',
      'tableHashes',
      'files',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw['format'] != 1 ||
        raw['directory'] != 'staging/replacement-${row.id}' ||
        !{'unclaimed', 'owned'}.contains(raw['directoryState']) ||
        raw['database'] != 'current.sqlite' ||
        raw['files'] is! List) {
      throw BackupSnapshotFailure('内部快照日志结构无法识别。');
    }
    final payload = Map<String, Object?>.from(raw);
    if (raw['directoryState'] == 'unclaimed' &&
        (row.phase != 'snapshot-writing' ||
            raw['databaseHash'] != null ||
            raw['databaseBytes'] != null ||
            raw['schemaHash'] != null ||
            raw['tableHashes'] != null)) {
      throw BackupSnapshotFailure('未归属内部快照不能包含完成证据。');
    }
    final filenames = <String>{}, sources = <String>{};
    for (final rawEntry in raw['files'] as List) {
      const entryKeys = {'source', 'filename', 'state', 'hash', 'bytes'};
      if (rawEntry is! Map ||
          rawEntry.length != entryKeys.length ||
          !rawEntry.keys.every(entryKeys.contains) ||
          rawEntry['source'] is! String ||
          rawEntry['filename'] is! String ||
          !RegExp(r'^[0-9a-f-]{36}\.bin$')
              .hasMatch(rawEntry['filename'] as String) ||
          !_replacementUuid.hasMatch(
            (rawEntry['filename'] as String).substring(0, 36),
          ) ||
          !filenames.add(rawEntry['filename'] as String) ||
          !sources.add(rawEntry['source'] as String) ||
          !{'pending', 'ready', 'missing'}.contains(rawEntry['state'])) {
        throw BackupSnapshotFailure('内部快照文件日志无效。');
      }
      _replacementSourcePath(rawEntry['source'] as String);
      if (rawEntry['state'] == 'missing') {
        if (rawEntry['hash'] != null || rawEntry['bytes'] != null) {
          throw BackupSnapshotFailure('内部快照缺失记录无效。');
        }
      } else if (rawEntry['hash'] is! String ||
          !_replacementHash.hasMatch(rawEntry['hash'] as String) ||
          rawEntry['bytes'] is! int ||
          (rawEntry['bytes'] as int) < 0) {
        throw BackupSnapshotFailure('内部快照文件摘要无效。');
      }
      if (row.phase == 'snapshot-ready' && rawEntry['state'] == 'pending') {
        throw BackupSnapshotFailure('内部快照尚未完成。');
      }
      if (raw['directoryState'] == 'unclaimed' &&
          rawEntry['state'] == 'ready') {
        throw BackupSnapshotFailure('未归属内部快照不能包含完成文件。');
      }
    }
    final completeDb =
        payload['databaseHash'] != null ||
        payload['databaseBytes'] != null ||
        payload['schemaHash'] != null ||
        payload['tableHashes'] != null;
    if (completeDb || row.phase == 'snapshot-ready') {
      final hashes = payload['tableHashes'];
      if (payload['databaseHash'] is! String ||
          !_replacementHash.hasMatch(payload['databaseHash'] as String) ||
          payload['schemaHash'] is! String ||
          !_replacementHash.hasMatch(payload['schemaHash'] as String) ||
          payload['databaseBytes'] is! int ||
          (payload['databaseBytes'] as int) <= 0 ||
          hashes is! Map ||
          hashes.length != _replacementTables.length ||
          !hashes.keys.every(_replacementTables.contains) ||
          !hashes.values.every(
            (h) => h is String && _replacementHash.hasMatch(h),
          )) {
        throw BackupSnapshotFailure('内部快照数据库证据无效。');
      }
    }
    return payload;
  }

  void _replacementSourcePath(String source) {
    if (source.startsWith('originals/')) {
      _validateOriginalPath(source);
      return;
    }
    final match = RegExp(r'^cache/outputs/([0-9a-f-]{36})\.([a-z]+)(\.part)?$')
        .firstMatch(source);
    if (match == null ||
        !_replacementUuid.hasMatch(match[1]!) ||
        !ProcessingFormat.values.any((format) => format.name == match[2])) {
      throw BackupSnapshotFailure('内部快照管理来源无效。');
    }
  }

  Future<void> _replacementVerifyBytes(
    String id,
    Map<String, Object?> payload,
  ) async {
    final row = RestoreOperationRow(
      id: id,
      phase: 'snapshot-ready',
      payloadJson: jsonEncode(payload),
      createdUtc: 0,
    );
    _replacementPayload(row);
    final directory = await _replacementDirectory(id);
    final allowed = {
      'current.sqlite',
      for (final e in payload['files'] as List)
        if ((e as Map)['state'] != 'missing') e['filename'] as String,
    };
    await for (final child in directory.list(followLinks: false)) {
      if (!allowed.contains(child.uri.pathSegments.last) ||
          await FileSystemEntity.type(child.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw BackupSnapshotFailure('内部快照包含未知文件或链接，不能验证。');
      }
    }
    final dbFile = await _files.file('${payload['directory']}/current.sqlite');
    await _restoreNoLinks(dbFile);
    final digest = await _files.digest(dbFile);
    if (digest.sha256 != payload['databaseHash'] ||
        digest.byteCount != payload['databaseBytes']) {
      throw BackupSnapshotFailure('内部快照数据库字节不一致。');
    }
    final evidence = await _replacementDatabaseEvidence(dbFile);
    if (evidence.$1 != payload['schemaHash'] ||
        jsonEncode(evidence.$2) != jsonEncode(payload['tableHashes'])) {
      throw BackupSnapshotFailure('内部快照数据库关系不一致。');
    }
    for (final raw in payload['files'] as List) {
      final entry = raw as Map;
      final file = await _files.file(
        '${payload['directory']}/${entry['filename']}',
      );
      if (entry['state'] == 'missing') {
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw BackupSnapshotFailure('内部快照缺失证据与字节冲突。');
        }
      } else {
        await _restoreNoLinks(file);
        final digest = await _files.digest(file);
        if (digest.sha256 != entry['hash'] ||
            digest.byteCount != entry['bytes']) {
          throw BackupSnapshotFailure('内部快照文件字节不一致。');
        }
      }
    }
  }

  /// Startup only reclaims this private journal; it never restores current data.
  Future<void> _recoverReplacementSnapshot(RestoreOperationRow row) async {
    final payload = _replacementPayload(row);
    if (payload['directoryState'] == 'unclaimed') {
      // Intent never proves ownership of an existing directory or its bytes.
      await (_db.delete(
        _db.restoreOperations,
      )..where((t) => t.id.equals(row.id))).go();
      return;
    }
    final directory = await _replacementDirectory(row.id);
    final allowed = {
      'current.sqlite',
      for (final e in payload['files'] as List)
        if ((e as Map)['state'] != 'missing') e['filename'] as String,
    };
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw BackupSnapshotFailure('内部快照目录无法安全清理。');
    }
    final existing = <File>[];
    if (type == FileSystemEntityType.directory) {
      // Inspect every child and every journal path before the first deletion.
      await for (final child in directory.list(followLinks: false)) {
        final name = child.uri.pathSegments.last;
        if (!allowed.contains(name) ||
            await FileSystemEntity.type(child.path, followLinks: false) !=
                FileSystemEntityType.file) {
          throw BackupSnapshotFailure('内部快照含未知文件，已保留全部现场。');
        }
        final safe = await _files.file('${payload['directory']}/$name');
        await _restoreNoLinks(safe);
        existing.add(safe);
      }
      for (final filename in allowed) {
        await _files.file('${payload['directory']}/$filename');
      }
      for (final file in existing) {
        await file.delete();
      }
      await directory.delete();
    }
    await (_db.delete(
      _db.restoreOperations,
    )..where((t) => t.id.equals(row.id))).go();
  }
}
