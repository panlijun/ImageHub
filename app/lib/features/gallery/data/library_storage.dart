part of 'library_repository.dart';

/// A visible preview protects its cache; an actual read also protects shutdown.
final class ThumbnailLease {
  ThumbnailLease._(this.file, this._read, this._release);
  final File file;
  final Future<Uint8List> Function() _read;
  final void Function() _release;
  Future<Uint8List>? _reading;
  Future<void>? _releasing;
  bool _released = false;
  Future<Uint8List> readBytes() {
    if (_released) throw const StorageFailure('预览使用已结束，请重新读取。');
    return _reading ??= _read();
  }

  Future<void> release() => _releasing ??= () async {
    _released = true;
    try {
      await _reading;
    } catch (_) {
      /* The reader reports its own error. */
    }
    _release();
  }();
}

final class ThumbnailCleanupPlan {
  ThumbnailCleanupPlan._(
    this._owner,
    this._epoch,
    Map<String, String> rows,
    this.bytes,
    this.protectedCount,
    this.untrackedBytes,
  ) : _rows = Map.unmodifiable(rows);
  final LibraryRepository _owner;
  final String _epoch;
  final Map<String, String> _rows;
  final int bytes, protectedCount, untrackedBytes;
  int get count => _rows.length;
}

final class _ThumbnailRecord {
  _ThumbnailRecord({
    this.formatVersion = 2,
    required this.id,
    required this.versionId,
    required this.frame,
    required this.sourceSha,
    required this.sourceBytes,
    required this.state,
    required this.lastUsedUtc,
    required this.lastUseOrder,
    required this.stageOwned,
    this.sha,
    this.bytes,
  });
  final String id, versionId, sourceSha, state;
  final int formatVersion, frame, sourceBytes, lastUsedUtc, lastUseOrder;
  final bool stageOwned;
  final String? sha;
  final int? bytes;
  String get key => '${LibraryStorage._cachePrefix}$id';
  String get path => 'cache/thumbnails/$id.png';
  String get stage => '$path.part';
  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'id': id,
    'versionId': versionId,
    'frame': frame,
    'sourceSha': sourceSha,
    'sourceBytes': sourceBytes,
    'state': state,
    'lastUsedUtc': lastUsedUtc,
    'lastUseOrder': lastUseOrder,
    'stageOwned': stageOwned,
    'sha': sha,
    'bytes': bytes,
  };
  factory _ThumbnailRecord.decode(String key, String value) {
    try {
      final raw = jsonDecode(value);
      const keys = {
        'formatVersion',
        'id',
        'versionId',
        'frame',
        'sourceSha',
        'sourceBytes',
        'state',
        'lastUsedUtc',
        'lastUseOrder',
        'stageOwned',
        'sha',
        'bytes',
      };
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      final digest = RegExp(r'^[0-9a-f]{64}$');
      if (raw is! Map ||
          raw.length != keys.length ||
          !keys.containsAll(raw.keys) ||
          raw['formatVersion'] is! int ||
          !{1, 2}.contains(raw['formatVersion']) ||
          raw['id'] is! String ||
          !uuid.hasMatch(raw['id'] as String) ||
          raw['versionId'] is! String ||
          !uuid.hasMatch(raw['versionId'] as String) ||
          key != '${LibraryStorage._cachePrefix}${raw['id']}' ||
          raw['sourceSha'] is! String ||
          !digest.hasMatch(raw['sourceSha'] as String) ||
          raw['sourceBytes'] is! int ||
          (raw['sourceBytes'] as int) < 1 ||
          raw['frame'] is! int ||
          (raw['frame'] as int) < 0 ||
          raw['lastUsedUtc'] is! int ||
          (raw['lastUsedUtc'] as int) < 0 ||
          raw['lastUseOrder'] is! int ||
          (raw['lastUseOrder'] as int) < 1 ||
          raw['stageOwned'] is! bool ||
          !{
            'writing',
            'prepared',
            'published',
            'ready',
            'deleting',
          }.contains(raw['state'])) {
        throw const StorageFailure('缩略图登记无法安全识别，记录和文件已保留。');
      }
      if (raw['state'] != 'writing' &&
          (raw['sha'] is! String ||
              !digest.hasMatch(raw['sha'] as String) ||
              raw['bytes'] is! int ||
              (raw['bytes'] as int) < 1 ||
              (raw['bytes'] as int) > LibraryStorage._thumbnailMaxBytes)) {
        throw const StorageFailure('缩略图登记无法安全识别，记录和文件已保留。');
      }
      if (raw['state'] == 'writing' &&
          (raw['sha'] != null || raw['bytes'] != null)) {
        throw const StorageFailure('缩略图登记无法安全识别，记录和文件已保留。');
      }
      return _ThumbnailRecord(
        formatVersion: raw['formatVersion'] as int,
        id: raw['id'] as String,
        versionId: raw['versionId'] as String,
        frame: raw['frame'] as int,
        sourceSha: raw['sourceSha'] as String,
        sourceBytes: raw['sourceBytes'] as int,
        state: raw['state'] as String,
        lastUsedUtc: raw['lastUsedUtc'] as int,
        lastUseOrder: raw['lastUseOrder'] as int,
        stageOwned: raw['stageOwned'] as bool,
        sha: raw['sha'] as String?,
        bytes: raw['bytes'] as int?,
      );
    } catch (_) {
      throw const StorageFailure('缩略图登记无法安全识别，记录和文件已保留。');
    }
  }
  _ThumbnailRecord change({
    String? state,
    bool? stageOwned,
    String? sha,
    int? bytes,
    int? lastUsedUtc,
    int? lastUseOrder,
  }) => _ThumbnailRecord(
    formatVersion: formatVersion,
    id: id,
    versionId: versionId,
    frame: frame,
    sourceSha: sourceSha,
    sourceBytes: sourceBytes,
    state: state ?? this.state,
    stageOwned: stageOwned ?? this.stageOwned,
    sha: sha ?? this.sha,
    bytes: bytes ?? this.bytes,
    lastUsedUtc: lastUsedUtc ?? this.lastUsedUtc,
    lastUseOrder: lastUseOrder ?? this.lastUseOrder,
  );
}

extension LibraryStorage on LibraryRepository {
  static const _cachePrefix = 'thumbnail_cache_v1/';
  static const _thumbnailMaxBytes = 2 * 1024 * 1024;
  static const _writeMargin = 32 * 1024 * 1024;
  int get thumbnailCacheLimitBytes =>
      _deviceSettings.cacheLimitMiB * 1024 * 1024;

  /// Production always injects a real platform probe. Low-level file tests may
  /// omit it; their reads report unknown and do not claim disk preflight.
  Future<void> _requireStorageBytes(int bytes) async {
    if (bytes < 0) throw const ResourceFailure(FailureKind.storage);
    final probe = _availableStorageBytes;
    if (probe == null) return;
    int available;
    try {
      available = await probe(_files.root);
    } catch (_) {
      throw const ResourceFailure(FailureKind.storageUnavailable);
    }
    if (available < 0) {
      throw const ResourceFailure(FailureKind.storageUnavailable);
    }
    if (available < bytes + _writeMargin) {
      throw const ResourceFailure(FailureKind.lowSpace);
    }
  }

  Future<List<_ThumbnailRecord>> _cacheRecords() async {
    final rows = await _db
        .customSelect(
          'SELECT key, value FROM library_metadata WHERE substr(key, 1, ?) = ?',
          variables: [
            Variable<int>(_cachePrefix.length),
            Variable<String>(_cachePrefix),
          ],
        )
        .get();
    return rows
        .map(
          (r) => _ThumbnailRecord.decode(
            r.read<String>('key'),
            r.read<String>('value'),
          ),
        )
        .toList();
  }

  Future<void> _putCache(_ThumbnailRecord record) => _db
      .into(_db.libraryMetadata)
      .insertOnConflictUpdate(
        LibraryMetadataCompanion.insert(
          key: record.key,
          value: jsonEncode(record.toJson()),
        ),
      )
      .then((_) {});
  Future<void> _forgetCache(_ThumbnailRecord record) => (_db.delete(
    _db.libraryMetadata,
  )..where((t) => t.key.equals(record.key))).go().then((_) {});
  int _nextCacheUse(List<_ThumbnailRecord> entries) =>
      entries.fold<int>(0, (n, r) => n > r.lastUseOrder ? n : r.lastUseOrder) +
      1;
  bool _cacheProtected(String id) => _thumbnailHolds[id]?.isNotEmpty ?? false;
  void _changedStorage() {
    if (!_storageChanges.isClosed) _storageChanges.add(null);
  }

  Future<bool> _cacheFileMatches(_ThumbnailRecord record, File file) async {
    if (record.sha == null || record.bytes == null) return false;
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() != record.bytes) {
      return false;
    }
    final digest = await _files.digest(file);
    return digest.sha256 == record.sha && digest.byteCount == record.bytes;
  }

  Future<void> _recoverThumbnailCache() async {
    // A ready cache is checked when used or deleted. Only interrupted journal
    // states need recovery IO; revisiting every ready path makes a grid O(n²).
    for (var record in (await _cacheRecords()).where(
      (r) => r.state != 'ready',
    )) {
      final stage = await _files.file(record.stage);
      final target = await _files.file(record.path);
      final stageType = await FileSystemEntity.type(
        stage.path,
        followLinks: false,
      );
      final targetType = await FileSystemEntity.type(
        target.path,
        followLinks: false,
      );
      if (record.state == 'writing') {
        if (targetType != FileSystemEntityType.notFound ||
            (!record.stageOwned &&
                stageType != FileSystemEntityType.notFound)) {
          throw const StorageFailure('缩略图发布归属未确认，现场已保留，新增缓存暂停。');
        }
        // The exclusive root lock proves the previous writer ended; only its
        // durably acknowledged, exclusively created half-file can be removed.
        if (stageType != FileSystemEntityType.notFound) {
          if (stageType != FileSystemEntityType.file) {
            throw const StorageFailure('缩略图暂存异常，现场保留。');
          }
          await stage.delete();
        }
        await _forgetCache(record);
      } else if (record.state == 'prepared') {
        if (targetType == FileSystemEntityType.notFound) {
          if (stageType != FileSystemEntityType.notFound &&
              !await _cacheFileMatches(record, stage)) {
            throw const StorageFailure('缩略图暂存校验失败，现场已保留。');
          }
          if (stageType == FileSystemEntityType.file) await stage.delete();
          await _forgetCache(record);
        } else {
          // Digest equality cannot prove publication ownership. This includes
          // a crash after the native call but before its durable acknowledgement.
          throw const StorageFailure('缩略图发布归属未确认，现场已保留，新增缓存暂停。');
        }
      } else if (record.state == 'published') {
        if (!await _cacheFileMatches(record, target)) {
          throw const StorageFailure('缩略图发布校验失败，现场已保留。');
        }
        if (stageType != FileSystemEntityType.notFound) {
          if (!await _cacheFileMatches(record, stage)) {
            throw const StorageFailure('缩略图暂存校验失败，现场已保留。');
          }
          await stage.delete();
        }
        record = record.change(state: 'ready', stageOwned: false);
        await _putCache(record);
      } else if (record.state == 'deleting') {
        await _deleteCacheRecord(record);
      }
    }
  }

  Future<({Map<String, int> files, bool hasLinks})> _storageFiles() async {
    final files = <String, int>{};
    var links = false;
    Future<void> walk(Directory directory) async {
      await for (final entity in directory.list(followLinks: false)) {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link) {
          links = true;
          continue;
        }
        if (type == FileSystemEntityType.directory) {
          await walk(Directory(entity.path));
        } else if (type == FileSystemEntityType.file) {
          final relative = p
              .relative(entity.path, from: _files.root.path)
              .split(p.separator)
              .join('/');
          final safe = await _files.file(relative);
          files[relative] = await safe.length();
        } else if (type != FileSystemEntityType.notFound) {
          links = true;
        }
      }
    }

    await walk(_files.root);
    return (files: files, hasLinks: links);
  }

  Future<
    ({
      List<_ThumbnailRecord> entries,
      Map<String, int> sizes,
      int untracked,
      bool unsafeUnknown,
    })
  >
  _cacheInventory() async {
    final entries = await _cacheRecords();
    final sizes = <String, int>{};
    final known = <String>{
      for (final r in entries) r.path,
      for (final r in entries)
        if (r.stageOwned &&
            {'writing', 'prepared', 'published'}.contains(r.state))
          r.stage,
    };
    var untracked = 0;
    var unsafeUnknown = false;
    Future<void> walk(Directory directory) async {
      await for (final entity in directory.list(followLinks: false)) {
        final relative = p
            .relative(entity.path, from: _files.root.path)
            .split(p.separator)
            .join('/');
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file) {
          final length = await (await _files.file(relative)).length();
          sizes[relative] = length;
          if (!known.contains(relative)) untracked += length;
        } else if (type == FileSystemEntityType.directory) {
          await walk(Directory(entity.path));
        } else if (type != FileSystemEntityType.notFound) {
          // An unknown link has no safely measurable target. Do not invent bytes.
          unsafeUnknown = true;
        }
      }
    }

    await walk(_files.directory('cache/thumbnails'));
    return (
      entries: entries,
      sizes: sizes,
      untracked: untracked,
      unsafeUnknown: unsafeUnknown,
    );
  }

  Future<bool> _enforceThumbnailLimit({int incomingBytes = 0}) async {
    final inventory = await _cacheInventory();
    final candidates = [
      for (final entry in inventory.entries)
        CacheCandidate(
          entry.id,
          inventory.sizes[entry.path] ?? 0,
          entry.lastUseOrder,
          protected: _cacheProtected(entry.id) || entry.state != 'ready',
        ),
    ];
    final plan = const CachePolicy().evaluate(
      entries: candidates,
      limitBytes: thumbnailCacheLimitBytes,
      incomingBytes: incomingBytes,
      untrackedBytes: inventory.untracked,
    );
    var remaining = candidates.fold(inventory.untracked, (n, e) => n + e.bytes);
    for (final id in plan.evictIds) {
      final entry = inventory.entries.firstWhere((e) => e.id == id);
      try {
        if (await _deleteCacheRecord(entry)) {
          remaining -= inventory.sizes[entry.path] ?? 0;
        }
      } catch (_) {
        _storageWarning = '一项缓存清理未确认，原文件和登记保留；新增缓存须等待足够空间。';
      }
    }
    final admitted =
        !inventory.unsafeUnknown &&
        remaining + incomingBytes <= thumbnailCacheLimitBytes;
    if (!admitted) _storageWarning = '缩略图达到容量限制，受保护或未登记文件保留，已停止新增缓存；可在空间管理核对。';
    return admitted;
  }

  Future<bool> _deleteCacheRecord(_ThumbnailRecord record) async {
    if (_cacheProtected(record.id)) return false;
    final target = await _files.file(record.path);
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        !await _cacheFileMatches(record, target)) {
      throw const StorageFailure('缓存内容已变化，未删除，现场和登记保留。');
    }
    final stage = await _files.file(record.stage);
    if (await FileSystemEntity.type(stage.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const StorageFailure('缓存仍有未结束暂存，未删除。');
    }
    await _putCache(record.change(state: 'deleting'));
    await _cacheFaultHook?.call(CacheBoundary.beforeDelete);
    if (type != FileSystemEntityType.notFound) {
      // Recheck immediately before removal; an external same-size replacement
      // must not turn an approved cache row into permission to erase other data.
      if (!await _cacheFileMatches(record, await _files.file(record.path))) {
        throw const StorageFailure('缓存内容已变化，未删除，现场和登记保留。');
      }
      await target.delete();
    }
    await _forgetCache(record);
    _changedStorage();
    return true;
  }

  Future<void> _maintainThumbnailCache({bool recovering = false}) async {
    if (_closed || _closing != null || _restoreRequested) return;
    try {
      await _serial(() async {
        if (recovering) await _recoverThumbnailCache();
        await _enforceThumbnailLimit();
      });
    } catch (_) {
      _storageWarning = '缓存维护无法安全完成，现场保留；永久图片不受清理影响，请重试。';
    }
  }

  Future<_ThumbnailRecord?> _thumbnailRecord(
    ImageAsset asset,
    int frame,
  ) async {
    if (_closing != null) throw const StorageFailure('资料库正在关闭，未创建新预览。');
    // Thumbnail generation stays inside the writer gate, so any preceding
    // journal belongs to an ended operation. Resolve it before accepting more
    // writes; unknown publication ownership must actually pause new caches.
    await _recoverThumbnailCache();
    if (await _verify(asset) != CopyAvailability.available) return null;
    final records = await _cacheRecords();
    for (final record in records.where(
      (r) =>
          r.formatVersion == 2 &&
          r.state == 'ready' &&
          r.versionId == asset.version.id &&
          r.sourceSha == asset.version.sha256 &&
          r.sourceBytes == asset.version.byteCount &&
          r.frame == frame,
    )) {
      final file = await _files.file(record.path);
      if (await _cacheFileMatches(record, file)) {
        final touched = record.change(
          lastUsedUtc: clock.now().toUtc().millisecondsSinceEpoch,
          lastUseOrder: _nextCacheUse(records),
        );
        await _putCache(touched);
        return touched;
      }
      _storageWarning = '一项缩略图缺失或变化，登记保留；可重新生成，永久图片保持不变。';
    }
    if (!await _enforceThumbnailLimit()) return null;
    await _requireStorageBytes(_thumbnailMaxBytes);
    var record = _ThumbnailRecord(
      id: const Uuid().v4(),
      versionId: asset.version.id,
      frame: frame,
      sourceSha: asset.version.sha256,
      sourceBytes: asset.version.byteCount,
      state: 'writing',
      lastUsedUtc: clock.now().toUtc().millisecondsSinceEpoch,
      lastUseOrder: _nextCacheUse(records),
      stageOwned: false,
    );
    await _putCache(record);
    await _cacheFaultHook?.call(CacheBoundary.intent);
    final stage = await _files.file(record.stage);
    await stage.create(exclusive: true);
    record = record.change(stageOwned: true);
    await _putCache(record);
    await _cacheFaultHook?.call(CacheBoundary.stageOwned);
    await _inspector.thumbnail(
      await _files.file(asset.deviceCopy.relativePath),
      stage,
      frame: frame,
    );
    final digest = await _files.digest(stage);
    final metadata = await _inspector.inspect(stage);
    if (digest.byteCount < 1 ||
        digest.byteCount > _thumbnailMaxBytes ||
        metadata.format != 'PNG' ||
        metadata.width > 480 ||
        metadata.height > 480 ||
        metadata.frameCount != 1) {
      throw const StorageFailure('缩略图校验失败，未报告为可用。');
    }
    record = record.change(
      state: 'prepared',
      sha: digest.sha256,
      bytes: digest.byteCount,
    );
    await _putCache(record);
    await _cacheFaultHook?.call(CacheBoundary.prepared);
    if (!await _enforceThumbnailLimit(incomingBytes: digest.byteCount)) {
      if (await _cacheFileMatches(record, stage)) await stage.delete();
      await _forgetCache(record);
      return null;
    }
    await _requireStorageBytes(0);
    final target = await _files.file(record.path);
    final publish = _publishCacheExclusive;
    if (publish != null) {
      if (!await publish(stage, target)) {
        throw const StorageFailure('缓存目标已存在，未覆盖。');
      }
    } else {
      // Low-level Dart tests exercise journal/hash semantics. Production injects
      // the native exclusive same-volume primitive instead of this test fallback.
      await _files.publish(record.stage, record.path);
    }
    record = record.change(state: 'published');
    await _putCache(record);
    await _cacheFaultHook?.call(CacheBoundary.published);
    if (!await _cacheFileMatches(record, target)) {
      throw const StorageFailure('缩略图发布校验失败，现场已保留。');
    }
    if (await FileSystemEntity.type(stage.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      if (!await _cacheFileMatches(record, stage)) {
        throw const StorageFailure('缩略图暂存变化，现场已保留。');
      }
      await stage.delete();
    }
    record = record.change(state: 'ready', stageOwned: false);
    await _putCache(record);
    await _cacheFaultHook?.call(CacheBoundary.ready);
    _changedStorage();
    return record;
  }

  Future<ThumbnailLease?> acquireThumbnailLease(
    ImageAsset asset, {
    int frame = 0,
  }) {
    if (frame < 0 || frame >= asset.version.frameCount) {
      throw ArgumentError('预览帧越界。');
    }
    return _serial(() async {
      final record = await _thumbnailRecord(asset, frame);
      if (record == null) return null;
      final token = const Uuid().v4(), epoch = _executionEpoch;
      (_thumbnailHolds[record.id] ??= {}).add(token);
      return ThumbnailLease._(
        await _files.file(record.path),
        () => _readThumbnail(record, token, epoch),
        () {
          _thumbnailHolds[record.id]?.remove(token);
          if (_thumbnailHolds[record.id]?.isEmpty ?? false) {
            _thumbnailHolds.remove(record.id);
          }
          _changedStorage();
        },
      );
    });
  }

  Future<Uint8List> _readThumbnail(
    _ThumbnailRecord record,
    String token,
    String epoch,
  ) async {
    final leaseId = 'thumbnail-read:$token';
    // The acquired cache token already prevents deletion. Register actual IO
    // synchronously before the first await, without queuing a read behind all
    // subsequent thumbnail writes. This mutates only in-process protection;
    // database and file publication still use the single writer gate.
    if (_closing != null ||
        _closed ||
        _restoreRequested ||
        epoch != _executionEpoch ||
        !(_thumbnailHolds[record.id]?.contains(token) ?? false)) {
      throw const StorageFailure('预览会话已失效，请重新读取。');
    }
    _activeLeaseIds.add(leaseId);
    _leaseDrain ??= Completer<void>();
    try {
      final file = await _files.file(record.path);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        await _cacheFaultHook?.call(CacheBoundary.reading);
        if (bytes.length + chunk.length > _thumbnailMaxBytes) {
          throw const StorageFailure('预览内容异常，已停止读取。');
        }
        bytes.add(chunk);
      }
      final value = bytes.takeBytes();
      if (value.length != record.bytes ||
          hashing.sha256.convert(value).toString() != record.sha) {
        throw const StorageFailure('预览内容已变化，请重建预览；永久图片保留。');
      }
      return value;
    } catch (_) {
      throw const StorageFailure('预览无法安全读取，请重建预览；永久图片保留。');
    } finally {
      _activeLeaseIds.remove(leaseId);
      if (_activeLeaseIds.isEmpty) {
        _leaseDrain?.complete();
        _leaseDrain = null;
      }
    }
  }

  Future<StorageReport> loadStorageReport() => _serial(() async {
    try {
      final inventory = await _cacheInventory();
      final scan = await _storageFiles();
      final known = <String, StorageCategory>{};
      final assets = await _db.select(_db.assets).get();
      for (final copy in await _db.select(_db.deviceCopies).get()) {
        await _files.file(copy.relativePath);
        final linked = assets
            .where((a) => a.versionId == copy.versionId)
            .toList();
        known[copy.relativePath] = linked.any((a) => !a.recycled)
            ? StorageCategory.permanent
            : linked.isNotEmpty
            ? StorageCategory.recycled
            : StorageCategory.retained;
      }
      for (final row in await _db.select(_db.processedOutputs).get()) {
        _validateOutputRow(row);
        known[row.relativePath] = StorageCategory.temporaryResults;
        known['${row.relativePath}.part'] = StorageCategory.temporaryResults;
      }
      for (final record in inventory.entries) {
        if (record.stageOwned &&
            {'writing', 'prepared', 'published'}.contains(record.state)) {
          known[record.stage] = StorageCategory.staging;
        }
      }
      final bytes = {for (final kind in StorageCategory.values) kind: 0};
      for (final file in scan.files.entries) {
        final kind =
            known[file.key] ??
            (file.key.startsWith('cache/thumbnails/')
                ? StorageCategory.thumbnails
                : file.key.startsWith('staging/')
                ? StorageCategory.staging
                : {
                    'library.sqlite',
                    'library.sqlite-wal',
                    'library.sqlite-shm',
                    '.library.lock',
                  }.contains(file.key)
                ? StorageCategory.database
                : StorageCategory.untracked);
        bytes[kind] = bytes[kind]! + file.value;
      }
      var logBytes = 0;
      for (final row in await _diagnosticRows()) {
        _decodeDiagnostic(row);
        logBytes += row.contentBytes;
      }
      int? available;
      String? warning = _storageWarning;
      if (_availableStorageBytes != null) {
        try {
          final value = await _availableStorageBytes!(_files.root);
          if (value < 0) throw const StorageFailure('可用空间未知。');
          available = value;
        } catch (_) {
          warning = '系统可用空间无法确认，不能把未知显示为零或可用。';
        }
      } else {
        warning ??= '系统可用空间未接入，未进行可用空间预检。';
      }
      if (scan.hasLinks) warning = '检测到未登记链接或无法计量项目，未读取其目标，现场保留。';
      return StorageReport(
        fileBytes: bytes,
        diagnosticContentBytes: logBytes,
        cacheLimitBytes: thumbnailCacheLimitBytes,
        protectedThumbnailBytes: inventory.entries
            .where((e) => _cacheProtected(e.id))
            .fold(0, (n, e) => n + (inventory.sizes[e.path] ?? 0)),
        untrackedThumbnailBytes: inventory.untracked,
        availableBytes: available,
        observedAt: clock.now().toUtc(),
        warning: warning,
      );
    } catch (_) {
      throw const StorageFailure('空间统计无法安全读取，保留上次有效结果，请重试。');
    }
  });

  Future<ThumbnailCleanupPlan> prepareThumbnailCleanup() => _serial(() async {
    final inventory = await _cacheInventory();
    final rows = <String, String>{};
    var bytes = 0, protected = 0;
    for (final record in inventory.entries) {
      if (_cacheProtected(record.id) || record.state != 'ready') {
        protected++;
        continue;
      }
      final file = await _files.file(record.path);
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          !await _cacheFileMatches(record, file)) {
        protected++;
        continue;
      }
      rows[record.id] = jsonEncode(record.toJson());
      bytes += inventory.sizes[record.path] ?? 0;
    }
    return ThumbnailCleanupPlan._(
      this,
      _executionEpoch,
      rows,
      bytes,
      protected,
      inventory.untracked,
    );
  });

  Future<ThumbnailCleanupResult> clearThumbnails(
    ThumbnailCleanupPlan plan,
  ) => _serial(() async {
    if (_closing != null ||
        !identical(plan._owner, this) ||
        plan._epoch != _executionEpoch) {
      throw const StorageFailure('清理范围已失效，请重新查看并确认；原文件保留。');
    }
    final current = {for (final r in await _cacheRecords()) r.id: r};
    // Reading a preview changes its LRU identity. Reconfirm instead of silently
    // deleting a now-visible image after an earlier confirmation.
    for (final entry in plan._rows.entries) {
      if (current[entry.key] == null ||
          jsonEncode(current[entry.key]!.toJson()) != entry.value) {
        throw const StorageFailure('已确认缓存发生变化，请重新核对；未扩大清理范围。');
      }
    }
    var removed = 0, bytes = 0, protected = plan.protectedCount, failed = 0;
    for (final id in plan._rows.keys) {
      final record = current[id]!;
      try {
        if (_cacheProtected(id)) {
          protected++;
          continue;
        }
        final file = await _files.file(record.path);
        final length = await file.exists() ? await file.length() : 0;
        if (await _deleteCacheRecord(record)) {
          removed++;
          bytes += length;
        } else {
          protected++;
        }
      } catch (_) {
        failed++;
      }
    }
    if (failed > 0) _storageWarning = '部分缩略图清理未确认，文件和登记保留，请重新核对后重试。';
    await _noteDiagnostic(
      _DiagnosticAction(
        DiagnosticKind.cleanup,
        'cache.clear',
        '已核对明确范围的缩略图清理，永久图片及任务保持有效。',
        '无法清理的保护项须等实际读取结束；未登记或变化文件请保留并核查。',
      ),
      failed: failed > 0,
    );
    return ThumbnailCleanupResult(
      removed: removed,
      removedBytes: bytes,
      protected: protected,
      failed: failed,
    );
  });
}
