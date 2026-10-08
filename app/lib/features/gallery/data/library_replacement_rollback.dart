part of 'library_repository.dart';

/// A disposable, independently rebuilt library. Ownership stays in memory: a
/// crash never grants permission to discover or delete arbitrary temp folders.
final class _ReplacementRecoveryScratch {
  _ReplacementRecoveryScratch(this.root);
  final Directory root;
  final Set<String> files = {};
  final Set<String> directories = {};
  String key(String path) => File(path).absolute.uri.toFilePath();

  Future<void> checkRoot() async {
    var ancestor = root.absolute;
    while (true) {
      if (await FileSystemEntity.type(ancestor.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw BackupSnapshotFailure('恢复证明临时目录包含链接或未知类型。');
      }
      if (ancestor.parent.path == ancestor.path) break;
      ancestor = ancestor.parent;
    }
  }

  Future<File> file(String relative) async {
    await checkRoot();
    final segments = relative.split('/');
    if (segments.any((s) => s.isEmpty || s == '.' || s == '..') ||
        relative.contains('\\') ||
        relative.contains(':')) {
      throw BackupSnapshotFailure('恢复证明位置无效。');
    }
    var parent = root;
    for (final segment in segments.take(segments.length - 1)) {
      parent = Directory('${parent.path}/$segment');
      final type = await FileSystemEntity.type(parent.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        await parent.create();
        directories.add(key(parent.path));
      } else if (type != FileSystemEntityType.directory ||
          !directories.contains(key(parent.path))) {
        throw BackupSnapshotFailure('恢复证明目录含未知内容。');
      }
    }
    final target = File('${root.path}/$relative');
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw BackupSnapshotFailure('恢复证明文件位置已被占用。');
    }
    // Successful exclusive creation is the ownership evidence. An occupied
    // location is not added to cleanup's allowlist after a failed create.
    await target.create(exclusive: true);
    files.add(key(target.path));
    return target;
  }

  Future<void> remove() async {
    await checkRoot();
    final existingFiles = <File>[];
    final existingDirectories = <Directory>[];
    Future<void> inspect(Directory directory) async {
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw BackupSnapshotFailure('恢复证明目录归属失效，已保留现场。');
      }
      await for (final child in directory.list(followLinks: false)) {
        final type = await FileSystemEntity.type(
          child.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file &&
            files.contains(key(child.path))) {
          existingFiles.add(File(child.path));
        } else if (type == FileSystemEntityType.directory &&
            directories.contains(key(child.path))) {
          await inspect(Directory(child.path));
          existingDirectories.add(Directory(child.path));
        } else {
          throw BackupSnapshotFailure('恢复证明含未知文件或链接，已保留全部现场。');
        }
      }
    }

    // Inspect the entire tree before deleting even one known file.
    await inspect(root);
    for (final file in existingFiles) {
      await file.delete();
    }
    for (final directory in existingDirectories) {
      await directory.delete();
    }
    await root.delete();
  }
}

extension LibraryReplacementRecovery on LibraryRepository {
  Future<void> proveReplacementSnapshotRecovery(
    ReplacementSnapshot snapshot, {
    required Future<int> Function(Directory) availableBytes,
    CancellationToken? cancellation,
  }) async {
    _checkReplacementSnapshot(snapshot);
    if (_restoreExecution != null) {
      throw BackupSnapshotFailure('维护文件操作正在执行，不能证明内部快照恢复。');
    }
    final drain = _restoreExecution = Completer<void>();
    _ReplacementRecoveryScratch? scratch;
    try {
      _restoreNotCancelled(cancellation);
      final row = await _serial(() async {
        _checkReplacementSnapshot(snapshot);
        return (_db.select(
          _db.restoreOperations,
        )..where((t) => t.id.equals(snapshot.id))).getSingleOrNull();
      }, maintenance: true);
      if (row == null ||
          row.phase != 'snapshot-ready' ||
          row.payloadJson != jsonEncode(snapshot._payload)) {
        throw BackupSnapshotFailure('内部快照证据已失效。');
      }
      final payload = _replacementPayload(row);
      if (payload['directoryState'] != 'owned') {
        throw BackupSnapshotFailure('内部快照目录未确认归属。');
      }
      await _replacementVerifyBytes(snapshot.id, payload);
      _restoreNotCancelled(cancellation);
      // The runtime's platform temporary root may use an Android system alias.
      // Resolve that trusted root before adding our private namespace; all
      // subsequently created children still undergo the strict no-link checks.
      final temporaryRoot = Directory(
        await Directory.systemTemp.resolveSymbolicLinks(),
      );
      final directory = await temporaryRoot.createTemp(
        'imagehost-recovery-proof-',
      );
      scratch = _ReplacementRecoveryScratch(directory);
      await scratch.checkRoot();
      var remaining =
          (payload['databaseBytes'] as int) * 2 +
          (payload['files'] as List).fold<int>(
            0,
            (n, e) => n + ((e as Map)['bytes'] as int? ?? 0),
          ) +
          1024 * 1024;
      Future<void> capacity() async {
        _restoreNotCancelled(cancellation);
        if (await availableBytes(directory) < remaining) {
          throw BackupSnapshotFailure('恢复证明临时卷空间不足。');
        }
        _restoreNotCancelled(cancellation);
      }

      await capacity();
      final rebuiltFile = await scratch.file('library.sqlite');
      for (final suffix in ['-journal', '-wal', '-shm']) {
        scratch.files.add(scratch.key('${rebuiltFile.path}$suffix'));
      }
      final source = await _files.file(
        '${payload['directory']}/current.sqlite',
      );
      await _replacementRebuildDatabase(
        source,
        rebuiltFile,
        snapshot.id,
        cancellation,
      );
      remaining -= payload['databaseBytes'] as int;
      for (final raw in payload['files'] as List) {
        final entry = raw as Map;
        await capacity();
        if (entry['state'] == 'missing') continue;
        final target = await scratch.file(entry['source'] as String);
        final bytes = await _files.file(
          '${payload['directory']}/${entry['filename']}',
        );
        await _replacementRecoveryCopy(bytes, target, entry, cancellation);
        remaining -= entry['bytes'] as int;
      }
      // Reopen the actual rebuilt SQLite database, then resolve the registered
      // paths below the new root and independently read every recovered byte.
      final evidence = await _replacementDatabaseEvidence(
        rebuiltFile,
        cancellation: cancellation,
      );
      final expected = payload['tableHashes'] as Map;
      if (evidence.$1 != payload['schemaHash'] ||
          _replacementTables
              .where((t) => t != 'restore_operations')
              .any((table) => evidence.$2[table] != expected[table])) {
        throw BackupSnapshotFailure('实际重建的资料库关系不一致。');
      }
      final rebuilt = sqlite.sqlite3.open(
        rebuiltFile.path,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        if (rebuilt.select('SELECT * FROM restore_operations').isNotEmpty) {
          throw BackupSnapshotFailure('恢复证明不能复活快照自身日志。');
        }
        _replacementRecoveryCheckRegisteredPaths(rebuilt, payload);
      } finally {
        rebuilt.close();
      }
      for (final raw in payload['files'] as List) {
        _restoreNotCancelled(cancellation);
        final entry = raw as Map;
        final file = File('${directory.path}/${entry['source']}');
        if (entry['state'] == 'missing') {
          if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            throw BackupSnapshotFailure('重建资料库未保留缺失状态。');
          }
        } else {
          final digest = await _replacementDigest(file, cancellation);
          if (digest.sha256 != entry['hash'] ||
              digest.byteCount != entry['bytes']) {
            throw BackupSnapshotFailure('实际重建路径的字节不一致。');
          }
        }
      }
      _restoreNotCancelled(cancellation);
    } catch (_) {
      throw BackupSnapshotFailure(
        cancellation?.isCancelled == true
            ? '内部快照恢复证明已取消，当前资料库已保留。'
            : '内部快照实际恢复证明失败，不能确认替换。',
      );
    } finally {
      try {
        await scratch?.remove();
      } finally {
        _restoreExecution = null;
        drain.complete();
      }
    }
  }

  Future<void> _replacementRebuildDatabase(
    File source,
    File target,
    String snapshotId,
    CancellationToken? cancellation,
  ) async {
    await _restoreNoLinks(source);
    await _restoreNoLinks(target);
    final original = sqlite.sqlite3.open(
      source.path,
      mode: sqlite.OpenMode.readOnly,
    );
    sqlite.Database? rebuilt;
    try {
      rebuilt = sqlite.sqlite3.open(target.path);
      rebuilt.execute('PRAGMA foreign_keys=ON');
      rebuilt.execute('PRAGMA synchronous=FULL');
      rebuilt.execute('PRAGMA journal_mode=DELETE');
      final schema = original.select(
        "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
      );
      _replacementCheckSchemaRows(schema);
      rebuilt.execute('BEGIN IMMEDIATE');
      try {
        for (final type in ['table', 'index']) {
          for (final row in schema.where((row) => row['type'] == type)) {
            _restoreNotCancelled(cancellation);
            rebuilt.execute(row['sql'] as String);
          }
        }
        rebuilt.execute('PRAGMA user_version=$librarySchemaVersion');
        rebuilt.execute('PRAGMA defer_foreign_keys=ON');
        for (final table in _replacementTables) {
          final columns = original
              .select('PRAGMA table_info("$table")')
              .map((r) => '"${r['name']}"')
              .toList();
          for (var offset = 0; ; offset += 128) {
            _restoreNotCancelled(cancellation);
            final rows = original.select(
              'SELECT * FROM "$table" ORDER BY ${columns.join(',')} LIMIT 128 OFFSET $offset',
            );
            for (final row in rows) {
              if (table == 'restore_operations' && row['id'] == snapshotId) {
                continue;
              }
              rebuilt.execute(
                'INSERT INTO "$table" (${columns.join(',')}) VALUES (${List.filled(columns.length, '?').join(',')})',
                row.values.toList(),
              );
            }
            if (rows.length < 128) break;
            await Future<void>.delayed(Duration.zero);
          }
        }
        if (rebuilt.select('PRAGMA foreign_key_check').isNotEmpty) {
          throw BackupSnapshotFailure('重建资料库外键无效。');
        }
        rebuilt.execute('COMMIT');
      } catch (_) {
        rebuilt.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      rebuilt?.close();
      original.close();
    }
    final handle = await target.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  void _replacementRecoveryCheckRegisteredPaths(
    sqlite.Database db,
    Map<String, Object?> payload,
  ) {
    final registered = <String>{};
    for (final row in db.select('SELECT relative_path FROM device_copies')) {
      final path = row['relative_path'] as String;
      _replacementSourcePath(path);
      registered.add(path);
    }
    for (final row in db.select(
      'SELECT relative_path FROM processed_outputs',
    )) {
      final path = row['relative_path'] as String;
      _replacementSourcePath(path);
      _replacementSourcePath('$path.part');
      registered.addAll([path, '$path.part']);
    }
    final logged = (payload['files'] as List)
        .map((e) => (e as Map)['source'] as String)
        .toSet();
    if (registered.length != logged.length || !registered.containsAll(logged)) {
      throw BackupSnapshotFailure('快照登记字节与数据库位置不一致。');
    }
  }

  Future<void> _replacementRecoveryCopy(
    File source,
    File target,
    Map entry,
    CancellationToken? cancellation,
  ) async {
    await _restoreNoLinks(source);
    await _restoreNoLinks(target);
    final writer = await target.open(mode: FileMode.writeOnly);
    var count = 0;
    try {
      await for (final chunk in source.openRead()) {
        _restoreNotCancelled(cancellation);
        count += chunk.length;
        if (count > (entry['bytes'] as int)) {
          throw BackupSnapshotFailure('恢复证明字节超出登记范围。');
        }
        await writer.writeFrom(chunk);
      }
      _restoreNotCancelled(cancellation);
      await writer.flush();
    } finally {
      await writer.close();
    }
    final digest = await _replacementDigest(target, cancellation);
    if (digest.sha256 != entry['hash'] || digest.byteCount != entry['bytes']) {
      throw BackupSnapshotFailure('恢复证明复制字节不一致。');
    }
  }

  /// Caller owns the writer/maintenance gate and has drained all actual IO.
  /// This never touches current files or the protected credential backend.
  Future<void> _rollbackReplacementMetadata(
    RestoreOperationRow snapshotRow, {
    required String operationId,
  }) async {
    final current = await (_db.select(
      _db.restoreOperations,
    )..where((t) => t.id.equals(operationId))).getSingleOrNull();
    final liveSnapshot = await (_db.select(
      _db.restoreOperations,
    )..where((t) => t.id.equals(snapshotRow.id))).getSingleOrNull();
    if (current == null ||
        !_replacementUuid.hasMatch(operationId) ||
        !{'replace-writing', 'replace-rollback'}.contains(current.phase) ||
        snapshotRow.phase != 'snapshot-ready' ||
        liveSnapshot == null ||
        liveSnapshot.phase != snapshotRow.phase ||
        liveSnapshot.payloadJson != snapshotRow.payloadJson) {
      throw BackupSnapshotFailure('替换回滚日志阶段或身份无效。');
    }
    final journal = jsonDecode(current.payloadJson);
    const keys = {'format', 'snapshotId', 'manifest', 'copies', 'secrets'};
    if (journal is! Map ||
        journal.length != keys.length ||
        !journal.keys.every(keys.contains) ||
        journal['format'] != 1 ||
        journal['snapshotId'] != snapshotRow.id) {
      throw BackupSnapshotFailure('替换回滚日志关联无效。');
    }
    final payload = _replacementPayload(snapshotRow);
    if (payload['directoryState'] != 'owned') {
      throw BackupSnapshotFailure('快照目录归属无效。');
    }
    await _replacementVerifyBytes(snapshotRow.id, payload);
    final source = await _files.file('${payload['directory']}/current.sqlite');
    final original = sqlite.sqlite3.open(
      source.path,
      mode: sqlite.OpenMode.readOnly,
    );
    try {
      _replacementRecoveryCheckRegisteredPaths(original, payload);
    } finally {
      original.close();
    }
    // A precommit replacement only adds new positions. Refuse rollback if any
    // old raw bytes have changed or a formerly missing location has appeared.
    for (final raw in payload['files'] as List) {
      final entry = raw as Map;
      final file = await _files.file(entry['source'] as String);
      if (entry['state'] == 'missing') {
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw BackupSnapshotFailure('回滚缺失位置出现新内容，已保留现场。');
        }
      } else {
        final digest = await _replacementDigest(file, null);
        if (digest.sha256 != entry['hash'] ||
            digest.byteCount != entry['bytes']) {
          throw BackupSnapshotFailure('回滚原始字节已变化，已保留现场。');
        }
      }
    }
    final schemaRows = await _db
        .customSelect(
          "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
        )
        .get();
    _replacementCheckSchemaRows(schemaRows.map((r) => r.data));
    if (_replacementRowsHash(schemaRows.map((r) => r.data)) !=
        payload['schemaHash']) {
      throw BackupSnapshotFailure('当前数据库结构不支持安全回滚。');
    }
    final uri = Uri.file(source.absolute.path)
        .replace(query: 'mode=ro')
        .toString();
    final liveFile = await _files.file('library.sqlite');
    await _restoreNoLinks(liveFile);
    // Drift's background connection does not enable URI filenames. This
    // narrowly scoped connection enables read-only ATTACH without changing
    // the shared database setup; the caller exclusively owns the writer gate.
    final database = sqlite.sqlite3.open(
      liveFile.path,
      mode: sqlite.OpenMode.readWrite,
      uri: true,
    );
    var attached = false, transaction = false;
    try {
      database.execute('PRAGMA foreign_keys=ON');
      database.execute('PRAGMA journal_mode=WAL');
      database.execute('PRAGMA synchronous=FULL');
      for (final pragma in {
        'foreign_keys': 1,
        'synchronous': 2,
        'journal_mode': 'wal',
      }.entries) {
        if (database.select('PRAGMA ${pragma.key}').single.values.single !=
            pragma.value) {
          throw BackupSnapshotFailure('回滚数据库保护配置未生效。');
        }
      }
      database.execute('ATTACH DATABASE ? AS replacement_rollback', [uri]);
      attached = true;
      database.execute('BEGIN IMMEDIATE');
      transaction = true;
      try {
        database.execute('PRAGMA defer_foreign_keys=ON');
        final operation = database.select(
          'SELECT phase,payload_json FROM restore_operations WHERE id=?',
          [operationId],
        );
        final snapshot = database.select(
          'SELECT phase,payload_json FROM restore_operations WHERE id=?',
          [snapshotRow.id],
        );
        if (operation.length != 1 ||
            operation.single['phase'] != current.phase ||
            operation.single['payload_json'] != current.payloadJson ||
            snapshot.length != 1 ||
            snapshot.single['phase'] != 'snapshot-ready' ||
            snapshot.single['payload_json'] != snapshotRow.payloadJson) {
          throw BackupSnapshotFailure('回滚事务开始前证据已改变。');
        }
        for (final table in _replacementTables.toList().reversed.where(
          (t) => t != 'restore_operations',
        )) {
          database.execute('DELETE FROM "$table"');
        }
        for (final table in _replacementTables.where(
          (t) => t != 'restore_operations',
        )) {
          database.execute(
            'INSERT INTO main."$table" SELECT * FROM replacement_rollback."$table"',
          );
        }
        if (database.select('PRAGMA main.foreign_key_check').isNotEmpty) {
          throw BackupSnapshotFailure('回滚资料库外键关系无效。');
        }
        final expected = payload['tableHashes'] as Map;
        for (final table in _replacementTables.where(
          (t) => t != 'restore_operations',
        )) {
          if (_replacementRecoveryTableHash(database, table) !=
              expected[table]) {
            throw BackupSnapshotFailure('回滚资料库业务关系不一致。');
          }
        }
        database.execute('DELETE FROM restore_operations WHERE id=?', [
          operationId,
        ]);
        if (database.updatedRows != 1) {
          throw BackupSnapshotFailure('回滚操作日志不能确认。');
        }
        database.execute('COMMIT');
        transaction = false;
      } catch (_) {
        if (transaction) {
          database.execute('ROLLBACK');
          transaction = false;
        }
        rethrow;
      }
    } finally {
      try {
        if (transaction) database.execute('ROLLBACK');
        if (attached) database.execute('DETACH DATABASE replacement_rollback');
      } finally {
        database.close();
      }
    }
  }

  /// Bounded synchronous pages keep this dedicated connection's transaction
  /// wholly within one isolate turn. Hash encoding matches snapshot capture.
  String _replacementRecoveryTableHash(sqlite.Database database, String table) {
    final columns = database
        .select('PRAGMA table_info("$table")')
        .map((row) => '"${row['name']}"')
        .join(',');
    final sink = _ReplacementHashSink();
    final converter = hashing.sha256.startChunkedConversion(sink);
    for (var offset = 0; ; offset += 128) {
      final rows = database.select(
        'SELECT * FROM "$table" ORDER BY $columns LIMIT 128 OFFSET $offset',
      );
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
    }
    converter.close();
    return sink.digest!.toString();
  }
}
