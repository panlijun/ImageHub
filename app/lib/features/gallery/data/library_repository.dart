import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart' as hashing;
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../core/platform_resource.dart';
import '../../../core/managed_file_store.dart';
import '../../../core/image_inspector.dart';
import '../../../core/text_policy.dart';
import '../../../core/secret_store.dart';
import '../../../core/secret_redactor.dart';
import '../../accounts/domain/account_models.dart';
import '../../upload/domain/upload_queue_models.dart';
import '../../upload/domain/upload_processing_models.dart';
import '../../upload/domain/provider_models.dart';
import '../../upload/domain/queue_policy.dart';
import '../../upload/domain/link_format.dart';
import '../../upload/domain/upload_history.dart';
import '../../links/domain/link_query.dart';
import '../../links/domain/link_availability.dart';
import '../../links/domain/remote_deletion.dart';
import '../domain/library_models.dart';
import '../domain/gallery_query.dart';
import '../domain/organization_models.dart';
import '../domain/recycle_models.dart';
import '../../processing/domain/processing_models.dart';
import '../../processing/domain/output_models.dart';
import '../../processing/application/processing_scheduler.dart';
import '../../settings/domain/device_settings.dart';
import '../../storage/domain/storage_models.dart';
import '../../diagnostics/domain/diagnostic_models.dart';
import '../../diagnostics/application/diagnostic_sanitizer.dart';
import '../../backup/application/backup_snapshot.dart';
import '../../backup/domain/backup_manifest.dart';
import '../../backup/domain/backup_settings.dart';
import '../../backup/domain/backup_restore_plan.dart';
import '../../backup/data/backup_zip_reader.dart';
import 'library_database.dart';

part 'library_organization.dart';
part 'library_recycle.dart';
part 'library_outputs.dart';
part 'library_accounts.dart';
part 'library_uploads.dart';
part 'library_upload_processing.dart';
part 'library_upload_history.dart';
part 'library_links.dart';
part 'library_link_probes.dart';
part 'library_remote_deletions.dart';
part 'library_settings.dart';
part 'library_diagnostics.dart';
part 'library_storage.dart';
part 'library_gallery_remote.dart';
part 'library_backups.dart';
part 'library_restores.dart';
part 'library_replacement_snapshot.dart';
part 'library_replacement_rollback.dart';
part 'library_replacement_restores.dart';

class LibraryRepository {
  LibraryRepository._(
    this._files,
    this._db,
    this._inspector,
    this._faultHook,
    this._outputFaultHook,
    this._secretStore,
    this._accountFaultHook,
    this._historyClearFaultHook,
  );
  final ManagedFileStore _files;
  final LibraryDatabase _db;
  final ImageInspector _inspector;
  final ImportFaultHook? _faultHook;
  final OutputFaultHook? _outputFaultHook;
  final SecretStore _secretStore;
  final AccountFaultHook? _accountFaultHook;
  final UploadHistoryClearFaultHook? _historyClearFaultHook;
  final SecretRedactor _secretRedactor = SecretRedactor();
  final _diagnosticChanges = StreamController<void>.broadcast();
  Stream<void> get diagnosticChanges => _diagnosticChanges.stream;
  String? _diagnosticWarning;
  String? get diagnosticWarning => _diagnosticWarning;
  int _diagnosticMaxBytes = 10000000;
  Duration _diagnosticRetention = const Duration(days: 30);
  List<(_DiagnosticAction, bool)>? _pendingDiagnostics;
  int _ordinaryLinkMaskRevision = -1;
  int _diagnosticMaskRevision = -1;
  final Map<String, String> _sessionCredentials = {};
  final StreamController<String> _accountChanges = StreamController.broadcast();
  Stream<String> get accountChanges => _accountChanges.stream;
  // Display observations do not revoke authorization or cancel other work.
  final _accountHealthChanges = StreamController<void>.broadcast();
  Stream<void> get accountHealthChanges => _accountHealthChanges.stream;
  final StreamController<void> _uploadChanges = StreamController.broadcast();
  Stream<void> get uploadChanges => _uploadChanges.stream;
  int get processingBudgetBytes => _inspector.memoryBudgetBytes;
  DeviceSettings _deviceSettings = DeviceSettings.defaults;
  DeviceSettings get currentDeviceSettings => _deviceSettings;
  final _settingsChanges = StreamController<void>.broadcast(sync: true);
  Stream<void> get settingsChanges => _settingsChanges.stream;
  late final ProcessingScheduler processingScheduler = ProcessingScheduler(
    totalMemoryBudgetBytes: processingBudgetBytes,
    concurrency: _deviceSettings.processingConcurrency,
  );
  final Map<String, Future<File?>> _thumbnailJobs = {};
  final Map<String, Set<String>> _thumbnailHolds = {};
  final _storageChanges = StreamController<void>.broadcast();
  Stream<void> get storageChanges => _storageChanges.stream;
  String? _storageWarning;
  String? get storageWarning => _storageWarning;
  Future<int> Function(Directory)? _availableStorageBytes;
  Future<bool> Function(File, File)? _publishCacheExclusive;
  CacheFaultHook? _cacheFaultHook;
  final String _leaseOwnerId = const Uuid().v4();
  String _executionEpoch = const Uuid().v4();
  static const _executionEpochZoneKey = #imagehostLibraryExecutionEpoch;
  String get executionEpoch => _executionEpoch;

  /// Application actors keep the epoch they were created for. Validate again
  /// inside the writer gate so an accepted callback cannot cross a replacement.
  Future<T> runInExecutionEpoch<T>(String epoch, Future<T> Function() action) {
    if (epoch != _executionEpoch || _closed) {
      return Future.error(
        const UploadQueueFailure('当前任务会话已失效，操作已停止；请重新打开任务页。'),
      );
    }
    return runZoned(action, zoneValues: {_executionEpochZoneKey: epoch});
  }

  final Set<String> _activeLeaseIds = {};
  final Set<String> _activeOutputWrites = {};
  final Set<String> _activeUploadProcessingJobs = {};
  Completer<void>? _leaseDrain;
  final Set<String> _activeLinkProbeIds = {};
  Completer<void>? _linkProbeDrain;
  final Set<String> _unsettledLinkProbeIds = {};
  final Set<String> _activeRemoteDeletionIds = {};
  final Set<String> _unsettledRemoteDeletionIds = {};
  Completer<void>? _remoteDeletionDrain;
  Future<void> _tail = Future.value();
  bool _closed = false;
  Future<void>? _closing;
  Timer? _outputMaintenance;
  bool _restoreRequested = false, _restoreReady = false;
  bool _replacementRecoveryBlocked = false;
  LibraryRestoreHold? _restoreHold;
  Completer<void>? _restoreExecution;
  bool get restoring => _restoreRequested;
  List<RecoveryIssue> _recoveryIssues = const [];
  List<RecoveryIssue> get recoveryIssues => _recoveryIssues;
  int _recoveredImportCount = 0;
  int get recoveredImportCount => _recoveredImportCount;

  static Future<LibraryRepository> open(
    Directory root, {
    int? memoryBudgetBytes,
    ImportFaultHook? faultHook,
    OutputFaultHook? outputFaultHook,
    SecretStore? secretStore,
    AccountFaultHook? accountFaultHook,
    UploadHistoryClearFaultHook? historyClearFaultHook,
    int diagnosticMaxBytes = 10000000,
    Duration diagnosticRetention = const Duration(days: 30),
    Future<int> Function(Directory)? availableStorageBytes,
    Future<bool> Function(File, File)? publishCacheExclusive,
    CacheFaultHook? cacheFaultHook,
  }) async {
    ManagedFileStore? files;
    LibraryDatabase? db;
    try {
      if (diagnosticMaxBytes < 1 || diagnosticRetention <= Duration.zero) {
        throw const LibraryOpenException('诊断留存配置无效，未打开资料库。');
      }
      files = await ManagedFileStore.open(root);
      db = LibraryDatabase(await files.file('library.sqlite'));
      await db.customSelect('SELECT 1').get();
      final repository = LibraryRepository._(
        files,
        db,
        ImageInspector(
          memoryBudgetBytes ??
              ((Platform.isAndroid || Platform.isIOS) ? 256 : 512) *
                  1024 *
                  1024,
        ),
        faultHook,
        outputFaultHook,
        secretStore ?? const UnavailableSecretStore(),
        accountFaultHook,
        historyClearFaultHook,
      );
      repository._diagnosticMaxBytes = diagnosticMaxBytes;
      repository._diagnosticRetention = diagnosticRetention;
      repository._availableStorageBytes = availableStorageBytes;
      repository._publishCacheExclusive = publishCacheExclusive;
      repository._cacheFaultHook = cacheFaultHook;
      // Reject unreadable observation formats before ordinary startup cleanup
      // or account/result recovery can mutate this library.
      await repository._validateAccountHealthObservations();
      // The managed-root exclusive lock proves prior process file workers have
      // ended. Clear only transient leases before retrying an import repair.
      await (db.delete(
        db.fileLeases,
      )..where((t) => t.ownerId.equals(repository._leaseOwnerId).not())).go();
      await (db.delete(
        db.outputLeases,
      )..where((t) => t.ownerId.equals(repository._leaseOwnerId).not())).go();
      // Replacement recovery must precede expiry and credential maintenance:
      // the old rollback files and references must remain untouched until the
      // replacement's durable commit or rollback has been established.
      await repository._recoverRestores();
      await repository._validateAccountHealthObservations();
      repository._deviceSettings = await repository._readDeviceSettings();
      if (repository._replacementRecoveryBlocked) return repository;
      // Validate all audit envelopes before unrelated expiry or recovery can
      // mutate a library whose deletion evidence uses an unreadable format.
      await repository._recoverRemoteDeletions();
      final restoreIssues = repository._recoveryIssues;
      await repository.recover();
      repository._recoveryIssues = List.unmodifiable([
        ...restoreIssues,
        ...repository._recoveryIssues,
      ]);
      await repository._recoverRecycle();
      await repository._recoverOutputs();
      await repository._recoverAccounts();
      await repository._recoverUploads();
      await repository._recoverUploadProcessing();
      await repository._maintainDiagnostics();
      await repository._maintainOutputs();
      await repository._maintainThumbnailCache(recovering: true);
      repository._restartOutputMaintenance();
      return repository;
    } catch (error) {
      await db?.close();
      await files?.close();
      if (error is LibraryOpenException) rethrow;
      // Drift transports setup failures across isolates, so never expose raw strings.
      throw const LibraryOpenException('图库无法安全打开，数据已保留。请检查目录权限、数据库版本或完整性。');
    }
  }

  Future<T> _serial<T>(
    Future<T> Function() action, {
    bool settling = false,
    bool maintenance = false,
    _DiagnosticAction? diagnostic,
  }) {
    final expectedEpoch = Zone.current[_executionEpochZoneKey] as String?;
    if (_replacementRecoveryBlocked && !maintenance) {
      return Future.error(
        BackupSnapshotFailure('替换恢复现场尚未安全结束，已暂停资料库读写。请保留数据并重开核查。'),
      );
    }
    if (expectedEpoch != null && expectedEpoch != _executionEpoch) {
      return Future.error(
        const UploadQueueFailure('当前任务会话已失效，操作已停止；请重新打开任务页。'),
      );
    }
    if (_restoreRequested && !maintenance && !(settling && !_restoreReady)) {
      return Future.error(BackupSnapshotFailure('资料库正在恢复维护，暂不接受新的读写或文件使用。'));
    }
    final predecessor = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      await predecessor;
      try {
        if (_closed) throw StateError('Library is closed');
        if (expectedEpoch != null && expectedEpoch != _executionEpoch) {
          throw const UploadQueueFailure('当前任务会话已失效，操作已停止；请重新打开任务页。');
        }
        final pendingDiagnostics = <(_DiagnosticAction, bool)>[];
        _pendingDiagnostics = pendingDiagnostics;
        try {
          final result = await action();
          if (diagnostic != null && !_restoreRequested) {
            await _noteDiagnostic(diagnostic);
          }
          return result;
        } catch (_) {
          if (diagnostic != null && !_restoreRequested) {
            await _noteDiagnostic(diagnostic, failed: true);
          }
          rethrow;
        } finally {
          _pendingDiagnostics = null;
          // Diagnostics execute after business transactions leave their scope.
          // A diagnostic SQL fault cannot roll back a business transaction.
          if (!_restoreRequested && !_closed) {
            try {
              await _syncDiagnosticMasks();
            } catch (_) {
              _diagnosticWarning = '诊断历史无法确认安全视图，原值保留，导出须重新核查。';
            }
            for (final entry in pendingDiagnostics) {
              await _persistDiagnostic(entry.$1, failed: entry.$2);
            }
          }
        }
      } finally {
        done.complete();
      }
    }();
  }

  void _restartOutputMaintenance() {
    _outputMaintenance?.cancel();
    if (_closed || _closing != null || _restoreRequested) return;
    _outputMaintenance = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_maintainOutputs());
      unawaited(_maintainDiagnostics());
      unawaited(_maintainThumbnailCache());
    });
  }

  Expression<bool> _matches(Assets table, GalleryQuery query) {
    // Preserve local metadata, but never use a known secret value as a search
    // term even if a pre-existing local name happens to contain that value.
    if (_secretRedactor.redactText(query.keyword) != query.keyword) {
      return const Constant(false);
    }
    var predicate = table.recycled.equals(query.recycledOnly);
    predicate = predicate & _galleryRemotePredicate(table, query);
    if (query.favoritesOnly) {
      predicate = predicate & table.favorite.equals(true);
    }
    if (query.uncategorized) predicate = predicate & table.category.isNull();
    if (query.categoryId != null) {
      predicate = predicate & table.category.equals(query.categoryId!);
    }
    if (query.sourceType != null) {
      predicate = predicate & table.sourceType.equals(query.sourceType!);
    }
    if (query.format != null) {
      final formats = _db.selectOnly(_db.versions)
        ..addColumns([_db.versions.id])
        ..where(_db.versions.format.equals(query.format!));
      predicate = predicate & table.versionId.isInQuery(formats);
    }
    if (query.availability != null) {
      final copies = _db.selectOnly(_db.deviceCopies)
        ..addColumns([_db.deviceCopies.versionId])
        ..where(_db.deviceCopies.availability.equals(query.availability!.name));
      predicate = predicate & table.versionId.isInQuery(copies);
    }
    for (final tagId in query.tagIds) {
      final tags = _db.selectOnly(_db.assetTags)
        ..addColumns([_db.assetTags.assetId])
        ..where(_db.assetTags.tagId.equals(tagId));
      predicate = predicate & table.id.isInQuery(tags);
    }
    final keyword = query.normalizedKeyword;
    if (keyword.isNotEmpty) {
      final name = FunctionCallExpression<String>('imagehost_casefold', [
        table.displayName,
      ]);
      Expression<bool> contains(Expression<String> value) =>
          FunctionCallExpression<int>('instr', [
            value,
            Variable<String>(keyword),
          ]).isBiggerThanValue(0);
      final formats = _db.selectOnly(_db.versions)
        ..addColumns([_db.versions.id])
        ..where(
          contains(
            FunctionCallExpression<String>('imagehost_casefold', [
              _db.versions.format,
            ]),
          ),
        );
      final categories = _db.selectOnly(_db.categories)
        ..addColumns([_db.categories.id])
        ..where(contains(_db.categories.nameKey));
      final tags = _db.selectOnly(_db.assetTags)
        ..addColumns([_db.assetTags.assetId])
        ..join([
          innerJoin(_db.tags, _db.tags.id.equalsExp(_db.assetTags.tagId)),
        ])
        ..where(contains(_db.tags.nameKey));
      var keywords =
          contains(name) |
          table.versionId.isInQuery(formats) |
          table.category.isInQuery(categories) |
          table.id.isInQuery(tags) |
          _galleryRemotePredicate(table, query, keyword: keyword) |
          contains(
            FunctionCallExpression<String>('imagehost_casefold', [
              table.sourceType,
            ]),
          );
      if ('系统文件'.contains(keyword)) {
        keywords = keywords | table.sourceType.equals('file');
      }
      if ('系统照片'.contains(keyword)) {
        keywords = keywords | table.sourceType.equals('photo');
      }
      if ('处理结果'.contains(keyword)) {
        keywords = keywords | table.sourceType.equals('processed');
      }
      predicate = predicate & keywords;
    }
    return predicate;
  }

  List<OrderingTerm> _galleryOrder(GalleryQuery query) {
    final mode = query.ascending ? OrderingMode.asc : OrderingMode.desc;
    final Expression expression = switch (query.sort) {
      GallerySort.imported => _db.assets.importedUtc,
      GallerySort.name => FunctionCallExpression<String>('imagehost_casefold', [
        _db.assets.displayName,
      ]),
      GallerySort.size => subqueryExpression<int>(
        _db.selectOnly(_db.versions)
          ..addColumns([_db.versions.byteCount])
          ..where(_db.versions.id.equalsExp(_db.assets.versionId)),
      ),
      GallerySort.uploaded => _latestGalleryConfirmation(_db.assets),
    };
    return [
      if (query.sort == GallerySort.uploaded)
        OrderingTerm.asc(expression.isNull()),
      OrderingTerm(expression: expression, mode: mode),
      OrderingTerm.asc(_db.assets.id),
    ];
  }

  Future<GalleryPage> listAssets({
    int offset = 0,
    int limit = 60,
    GalleryQuery query = const GalleryQuery(),
  }) => _serial(() async {
    if (offset < 0 || limit < 1 || limit > 60) {
      throw ArgumentError('Invalid page');
    }
    await _syncOrdinaryLinkMasks();
    final count = _db.assets.id.count();
    final totalQuery = _db.selectOnly(_db.assets)
      ..addColumns([count])
      ..where(_matches(_db.assets, query));
    final total = (await totalQuery.getSingle()).read(count) ?? 0;
    final pageQuery = _db.select(_db.assets)
      ..where((t) => _matches(t, query))
      ..orderBy(
        _galleryOrder(query)
            .map(
              (order) =>
                  (Assets table) => order,
            )
            .toList(),
      )
      ..limit(limit, offset: offset);
    return GalleryPage(
      await Future.wait((await pageQuery.get()).map(_asset)),
      total,
    );
  });

  Future<List<String>> matchingAssetIds({
    GalleryQuery query = const GalleryQuery(),
  }) => _serial(() async {
    await _syncOrdinaryLinkMasks();
    final ids = _db.selectOnly(_db.assets)
      ..addColumns([_db.assets.id])
      ..where(_matches(_db.assets, query))
      ..orderBy(_galleryOrder(query));
    return List.unmodifiable(
      (await ids.get()).map((row) => row.read(_db.assets.id)!),
    );
  });

  Future<ImageAsset?> getAsset(
    String assetId, {
    bool includeRecycled = false,
  }) => _serial(() async {
    final row =
        await (_db.select(_db.assets)..where(
              (t) =>
                  t.id.equals(assetId) &
                  (includeRecycled
                      ? const Constant(true)
                      : t.recycled.equals(false)),
            ))
            .getSingleOrNull();
    return row == null ? null : await _asset(row);
  });

  Future<ImageAsset> setFavorite(String assetId, bool favorite) => _serial(
    () => _db.transaction(() async {
      final row =
          await (_db.select(_db.assets)
                ..where((t) => t.id.equals(assetId) & t.recycled.equals(false)))
              .getSingleOrNull();
      if (row == null) {
        throw StateError('资产不存在或已位于回收区。');
      }
      await (_db.update(_db.assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          favorite: Value(favorite),
          updatedUtc: Value(clock.now().toUtc().millisecondsSinceEpoch),
        ),
      );
      final updated = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(assetId))).getSingle();
      return _asset(updated);
    }),
  );

  Future<ImageAsset> _asset(AssetRow row) async {
    final v = await (_db.select(
      _db.versions,
    )..where((t) => t.id.equals(row.versionId))).getSingle();
    final c = await (_db.select(
      _db.deviceCopies,
    )..where((t) => t.versionId.equals(v.id))).getSingle();
    final category = row.category == null
        ? null
        : await (_db.select(
            _db.categories,
          )..where((t) => t.id.equals(row.category!))).getSingle();
    final resultCount = _db.remoteUploadResults.id.count();
    final confirmed = _db.remoteUploadResults.confirmedUtc.max();
    final remote =
        await (_db.selectOnly(_db.remoteUploadResults)
              ..addColumns([resultCount, confirmed])
              ..where(
                _db.remoteUploadResults.versionDigest.equals(v.digest) &
                    _db.remoteUploadResults.byteCount.equals(v.byteCount),
              ))
            .getSingle();
    final confirmedUtc = remote.read(confirmed);
    return ImageAsset(
      id: row.id,
      displayName: row.displayName,
      version: ImageVersion(
        id: v.id,
        sha256: v.digest,
        byteCount: v.byteCount,
        format: v.format,
        width: v.width,
        height: v.height,
        frameCount: v.frameCount,
        orientation: v.orientation,
      ),
      deviceCopy: DeviceCopy(
        id: c.id,
        versionId: c.versionId,
        relativePath: c.relativePath,
      ),
      importedAt: DateTime.fromMillisecondsSinceEpoch(
        row.importedUtc,
        isUtc: true,
      ),
      confirmedRemoteResultCount: remote.read(resultCount)!,
      lastConfirmedUploadAt: confirmedUtc == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(confirmedUtc, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.updatedUtc,
        isUtc: true,
      ),
      sourceType: row.sourceType,
      favorite: row.favorite,
      category: category?.name,
      categoryId: row.category,
      tags: await _readTags(row.id),
      recycled: row.recycled,
      recycledAt: row.recycledUtc == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.recycledUtc!, isUtc: true),
    );
  }

  Future<CopyAvailability> verifyCopy(ImageAsset asset) =>
      _serial(() => _verify(asset));
  Future<File> originalFor(ImageAsset asset) => _serial(() async {
    if (await _verify(asset) != CopyAvailability.available) {
      throw const ResourceFailure(FailureKind.sourceMissing);
    }
    return _files.file(asset.deviceCopy.relativePath);
  });
  Future<CopyAvailability> _verify(ImageAsset asset) async {
    try {
      final file = await _files.file(asset.deviceCopy.relativePath);
      if (!await file.exists()) return CopyAvailability.missing;
      final digest = await _files.digest(file);
      return digest.sha256 == asset.version.sha256 &&
              digest.byteCount == asset.version.byteCount
          ? CopyAvailability.available
          : CopyAvailability.damaged;
    } catch (_) {
      return CopyAvailability.inaccessible;
    }
  }

  Future<ImportResult> importResource(
    PlatformResource resource, {
    CancellationToken? cancellation,
    void Function(ImportProgress)? onProgress,
  }) => _serial(() async {
    final result = await _importResource(
      resource,
      cancellation: cancellation,
      onProgress: onProgress,
    );
    await _noteImportDiagnostic(result);
    return result;
  });

  Future<ImportResult> _importResource(
    PlatformResource resource, {
    CancellationToken? cancellation,
    void Function(ImportProgress)? onProgress,
    String? outputId,
  }) async {
    String? operationId;
    ImportResult? confirmed;
    try {
      cancellation?.throwIfCancelled();
      await _requireStorageBytes(0);
      const uuid = Uuid();
      operationId = uuid.v4();
      final createdUtc = clock.now().toUtc().millisecondsSinceEpoch;
      await _db
          .into(_db.importOperations)
          .insert(
            ImportOperationsCompanion.insert(
              id: operationId,
              assetId: uuid.v4(),
              versionId: uuid.v4(),
              copyId: uuid.v4(),
              stagePath: 'staging/$operationId.part',
              finalPath: 'originals/$operationId.original',
              displayName: _safeName(resource.displayName),
              sourceType: _safeSource(resource.sourceType),
              createdUtc: createdUtc,
              phase: 'writing',
              outputId: Value(outputId),
            ),
          );
      onProgress?.call(const ImportProgress('正在取得并复制图片', 0));
      final digest = await _files.copySource(
        resource,
        'staging/$operationId.part',
        cancellation,
        _inspector.memoryBudgetBytes ~/ 4,
        (bytes) => onProgress?.call(ImportProgress('正在取得并复制图片', bytes)),
        beforeWrite: _requireStorageBytes,
      );
      await _fault(ImportBoundary.copy);
      cancellation?.throwIfCancelled();
      onProgress?.call(ImportProgress('正在校验图片', digest.byteCount));
      final metadata = await _inspector.inspect(
        await _files.file('staging/$operationId.part'),
      );
      await _fault(ImportBoundary.verified);
      cancellation?.throwIfCancelled();
      await (_db.update(
        _db.importOperations,
      )..where((t) => t.id.equals(operationId!))).write(
        ImportOperationsCompanion(
          phase: const Value('ready'),
          digest: Value(digest.sha256),
          byteCount: Value(digest.byteCount),
          format: Value(metadata.format),
          width: Value(metadata.width),
          height: Value(metadata.height),
          frameCount: Value(metadata.frameCount),
          orientation: Value(metadata.orientation),
        ),
      );
      await _fault(ImportBoundary.ready);
      final op = await (_db.select(
        _db.importOperations,
      )..where((t) => t.id.equals(operationId!))).getSingle();
      confirmed = await _complete(op, cancellation: cancellation);
      await _fault(ImportBoundary.afterDbCommit);
      return confirmed;
    } catch (error) {
      if (confirmed != null) return confirmed;
      final failure = _failure(error);
      if (failure.kind == FailureKind.cancelled && operationId != null) {
        // A persistent cancellation marker prevents startup from committing this item.
        try {
          await (_db.update(
            _db.importOperations,
          )..where((t) => t.id.equals(operationId!))).write(
            const ImportOperationsCompanion(phase: Value('cancelled')),
          );
          await _discardStage(operationId);
        } catch (_) {
          return const ImportResult(
            ImportStatus.failed,
            failure: ResourceFailure(FailureKind.storage),
          );
        }
      } else if (error is ResourceFailure &&
          operationId != null &&
          [
            FailureKind.invalidImage,
            FailureKind.unsupported,
            FailureKind.resourceBudget,
            FailureKind.permissionDenied,
            FailureKind.sourceMissing,
            FailureKind.unavailable,
            FailureKind.cloudPending,
            FailureKind.activeUse,
            FailureKind.lowSpace,
            FailureKind.storageUnavailable,
          ].contains(failure.kind)) {
        try {
          await _discardStage(operationId);
        } catch (_) {
          /* retain recovery evidence */
        }
      }
      return ImportResult(
        failure.kind == FailureKind.cancelled
            ? ImportStatus.cancelled
            : ImportStatus.failed,
        failure: failure,
      );
    }
  }

  static String _safeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .split(RegExp(r'[/\\]'))
        .last;
    return cleaned.isEmpty ? '未命名图片' : cleaned;
  }

  static String _safeSource(String source) =>
      [
        'file',
        'photo',
        'processed',
        'contentUri',
        'authorizedResource',
      ].contains(source)
      ? source
      : 'authorizedResource';
  ResourceFailure _failure(Object error) {
    if (error is ResourceFailure) return error;
    return const ResourceFailure(FailureKind.storage);
  }

  Future<void> _fault(ImportBoundary boundary) async =>
      _faultHook?.call(boundary);

  Future<void> _discardStage(String id) async {
    final op = await (_db.select(
      _db.importOperations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (op == null) return;
    _validateOperation(op);
    final stageReferences = await (_db.select(
      _db.deviceCopies,
    )..where((t) => t.relativePath.equals(op.stagePath))).get();
    if (stageReferences.isNotEmpty) {
      throw const ResourceFailure(FailureKind.storage);
    }
    await _files.deleteStage(op.stagePath);
    // Only this UUID's unpublished original may be reclaimed. A confirmed copy
    // reference always wins, even when the journal is unexpectedly still present.
    final finalReferences = await (_db.select(
      _db.deviceCopies,
    )..where((t) => t.relativePath.equals(op.finalPath))).get();
    if (finalReferences.isEmpty) {
      final unpublished = await _files.file(op.finalPath);
      if (await unpublished.exists()) await unpublished.delete();
    }
    await (_db.delete(
      _db.importOperations,
    )..where((t) => t.id.equals(id))).go();
  }

  static void _validateOperation(OperationRow op) {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(op.id) ||
        op.stagePath != 'staging/${op.id}.part' ||
        op.finalPath != 'originals/${op.id}.original') {
      throw const ResourceFailure(FailureKind.storage);
    }
  }

  /// Only the known, own-project PNG decoder omission may be corrected by a
  /// newly verified import. Content identity and all frozen users remain intact.
  static bool _pngImportMetadataCorrection(
    VersionRow version,
    OperationRow op,
  ) {
    if (version.format == op.format &&
        version.width == op.width &&
        version.height == op.height &&
        version.frameCount == op.frameCount &&
        version.orientation == op.orientation) {
      return false;
    }
    final direction = op.orientation;
    if (version.format == 'PNG' &&
        op.format == 'PNG' &&
        version.orientation == 1 &&
        direction != null &&
        direction >= 2 &&
        direction <= 8 &&
        version.frameCount == op.frameCount &&
        version.width == (direction >= 5 ? op.height : op.width) &&
        version.height == (direction >= 5 ? op.width : op.height)) {
      return true;
    }
    throw const ResourceFailure(FailureKind.invalidImage);
  }

  Future<void> _correctPngImportMetadata(
    VersionRow version,
    OperationRow op,
  ) async {
    await (_db.update(
      _db.versions,
    )..where((t) => t.id.equals(version.id))).write(
      VersionsCompanion(
        width: Value(op.width!),
        height: Value(op.height!),
        orientation: Value(op.orientation!),
      ),
    );
  }

  Future<ImportResult> _complete(
    OperationRow op, {
    CancellationToken? cancellation,
    bool recovering = false,
  }) async {
    _validateOperation(op);
    cancellation?.throwIfCancelled();
    final version =
        await (_db.select(_db.versions)..where(
              (t) =>
                  t.digest.equals(op.digest!) &
                  t.byteCount.equals(op.byteCount!),
            ))
            .getSingleOrNull();
    ImageAsset? existing;
    CopyRow? retainedCopy;
    var correctMetadata = false;
    if (version != null) {
      try {
        await _rejectPendingPurge([version.id]);
      } on StateError {
        throw const ResourceFailure(FailureKind.activeUse);
      }
      final row =
          await (_db.select(_db.assets)
                ..where((t) => t.versionId.equals(version.id))
                ..orderBy([
                  (t) => OrderingTerm.asc(t.recycled),
                  (t) => OrderingTerm.asc(t.importedUtc),
                  (t) => OrderingTerm.asc(t.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      retainedCopy = await (_db.select(
        _db.deviceCopies,
      )..where((t) => t.versionId.equals(version.id))).getSingle();
      if (row != null) existing = await _asset(row);
      // A recycled duplicate still requires the user's explicit restore, even
      // if this re-import would otherwise qualify for metadata correction.
      if (existing?.recycled == true) {
        await _discardStage(op.id);
        return ImportResult(
          ImportStatus.needsRestore,
          asset: existing,
          failure: const ResourceFailure(FailureKind.needsRestore),
        );
      }
      correctMetadata = _pngImportMetadataCorrection(version, op);
      if (existing != null &&
          await _verify(existing) == CopyAvailability.available) {
        if (correctMetadata) {
          try {
            await _rejectVersionProtection(version.id);
          } on StateError {
            throw const ResourceFailure(FailureKind.activeUse);
          }
          if (!recovering) await _fault(ImportBoundary.beforeDbCommit);
          cancellation?.throwIfCancelled();
        }
        await _db.transaction(() async {
          if (correctMetadata) await _correctPngImportMetadata(version, op);
          await _commitOutputSave(op, version.id);
          await (_db.update(
            _db.importOperations,
          )..where((t) => t.id.equals(op.id))).write(
            ImportOperationsCompanion(
              phase: const Value('committedReuse'),
              assetId: Value(existing!.id),
              versionId: Value(version.id),
              copyId: Value(retainedCopy!.id),
            ),
          );
        });
        final actual = correctMetadata ? await _asset(row!) : existing;
        try {
          await _discardStage(op.id);
        } catch (_) {
          _recoveryIssues = List.unmodifiable([
            ..._recoveryIssues,
            RecoveryIssue(op.id, '图片信息或副本已确认，一项导入暂存清理将于重开时重试。'),
          ]);
        }
        return ImportResult(
          correctMetadata ? ImportStatus.repaired : ImportStatus.duplicate,
          asset: actual,
        );
      }
      if (existing == null &&
          await _verify(_retainedImportAsset(op, version, retainedCopy)) ==
              CopyAvailability.available) {
        if (correctMetadata) {
          try {
            await _rejectVersionProtection(version.id);
          } on StateError {
            throw const ResourceFailure(FailureKind.activeUse);
          }
        }
        if (!recovering) await _fault(ImportBoundary.beforeDbCommit);
        cancellation?.throwIfCancelled();
        await _db.transaction(() async {
          if (correctMetadata) await _correctPngImportMetadata(version, op);
          await _insertImportedAsset(op, version.id);
          await _commitOutputSave(op, version.id);
          await (_db.update(
            _db.importOperations,
          )..where((t) => t.id.equals(op.id))).write(
            ImportOperationsCompanion(
              phase: const Value('committedReuse'),
              versionId: Value(version.id),
              copyId: Value(retainedCopy!.id),
            ),
          );
        });
        // A saved asset survives cleanup failures; its journal retries cleanup.
        try {
          await _discardStage(op.id);
        } catch (_) {
          _recoveryIssues = List.unmodifiable([
            ..._recoveryIssues,
            RecoveryIssue(op.id, '图片已保存，一项导入暂存清理将于重开时重试。'),
          ]);
        }
        final saved = await (_db.select(
          _db.assets,
        )..where((t) => t.id.equals(op.assetId))).getSingle();
        return ImportResult(ImportStatus.saved, asset: await _asset(saved));
      }
      // A worker's source path must remain stable until its file lease ends.
      try {
        await _rejectVersionProtection(version.id);
      } on StateError {
        throw const ResourceFailure(FailureKind.activeUse);
      }
    }
    final finalFile = await _files.file(op.finalPath);
    if (!await finalFile.exists()) {
      await _files.publish(op.stagePath, op.finalPath);
    }
    if (!recovering) await _fault(ImportBoundary.published);
    final publishedDigest = await _files.digest(finalFile);
    if (publishedDigest.sha256 != op.digest ||
        publishedDigest.byteCount != op.byteCount) {
      throw const ResourceFailure(FailureKind.storage);
    }
    cancellation?.throwIfCancelled();
    if (!recovering) await _fault(ImportBoundary.beforeDbCommit);
    cancellation?.throwIfCancelled();
    await _db.transaction(() async {
      final now = clock.now().toUtc().millisecondsSinceEpoch;
      if (retainedCopy != null) {
        if (correctMetadata) await _correctPngImportMetadata(version!, op);
        await (_db.update(
          _db.deviceCopies,
        )..where((t) => t.id.equals(retainedCopy!.id))).write(
          DeviceCopiesCompanion(
            relativePath: Value(op.finalPath),
            availability: const Value('available'),
            verifiedUtc: Value(now),
          ),
        );
        if (existing == null) await _insertImportedAsset(op, version!.id);
      } else {
        await _db
            .into(_db.versions)
            .insert(
              VersionsCompanion.insert(
                id: op.versionId,
                digest: op.digest!,
                byteCount: op.byteCount!,
                format: op.format!,
                width: op.width!,
                height: op.height!,
                frameCount: op.frameCount!,
                orientation: op.orientation!,
              ),
            );
        await _db
            .into(_db.deviceCopies)
            .insert(
              DeviceCopiesCompanion.insert(
                id: op.copyId,
                versionId: op.versionId,
                relativePath: op.finalPath,
                availability: const Value('available'),
                verifiedUtc: Value(now),
              ),
            );
        await _insertImportedAsset(op, op.versionId);
      }
      await _commitOutputSave(op, version?.id ?? op.versionId);
      await (_db.delete(
        _db.importOperations,
      )..where((t) => t.id.equals(op.id))).go();
    });
    final row = await (_db.select(
      _db.assets,
    )..where((t) => t.id.equals(existing?.id ?? op.assetId))).getSingle();
    return ImportResult(
      existing == null ? ImportStatus.saved : ImportStatus.repaired,
      asset: await _asset(row),
    );
  }

  Future<void> _insertImportedAsset(OperationRow op, String versionId) async {
    await _db
        .into(_db.assets)
        .insert(
          AssetsCompanion.insert(
            id: op.assetId,
            displayName: op.displayName,
            versionId: versionId,
            importedUtc: op.createdUtc,
            updatedUtc: op.createdUtc,
            sourceType: op.sourceType,
          ),
        );
  }

  ImageAsset _retainedImportAsset(
    OperationRow op,
    VersionRow version,
    CopyRow copy,
  ) => ImageAsset(
    id: op.assetId,
    displayName: op.displayName,
    version: ImageVersion(
      id: version.id,
      sha256: version.digest,
      byteCount: version.byteCount,
      format: version.format,
      width: version.width,
      height: version.height,
      frameCount: version.frameCount,
      orientation: version.orientation,
    ),
    deviceCopy: DeviceCopy(
      id: copy.id,
      versionId: copy.versionId,
      relativePath: copy.relativePath,
    ),
    importedAt: DateTime.fromMillisecondsSinceEpoch(op.createdUtc, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(op.createdUtc, isUtc: true),
    sourceType: op.sourceType,
  );

  Future<List<RecoveryIssue>> recover() => _serial(() async {
    final issues = <RecoveryIssue>[];
    var recovered = 0;
    final operations =
        await (_db.select(_db.importOperations)..orderBy([
              (t) => OrderingTerm.asc(t.createdUtc),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    for (final op in operations) {
      try {
        _validateOperation(op);
        if (op.phase == 'writing' || op.phase == 'cancelled') {
          await _discardStage(op.id);
          continue;
        }
        if (op.phase == 'committedReuse') {
          final row = await (_db.select(
            _db.assets,
          )..where((t) => t.id.equals(op.assetId))).getSingle();
          final asset = await _asset(row);
          if (row.versionId != op.versionId ||
              asset.deviceCopy.id != op.copyId ||
              asset.version.sha256 != op.digest ||
              asset.version.byteCount != op.byteCount ||
              asset.version.format != op.format ||
              asset.version.width != op.width ||
              asset.version.height != op.height ||
              asset.version.frameCount != op.frameCount ||
              asset.version.orientation != op.orientation ||
              await _verify(asset) != CopyAvailability.available) {
            throw const ResourceFailure(FailureKind.storage);
          }
          await _discardStage(op.id);
          recovered++;
          continue;
        }
        if (op.phase != 'ready') {
          throw const ResourceFailure(FailureKind.storage);
        }
        final target = await _files.file(op.finalPath);
        final candidate = await target.exists()
            ? target
            : await _files.file(op.stagePath);
        final digest = await _files.digest(candidate);
        if (digest.sha256 != op.digest || digest.byteCount != op.byteCount) {
          throw const ResourceFailure(FailureKind.invalidImage);
        }
        final metadata = await _inspector.inspect(candidate);
        if (metadata.format != op.format ||
            metadata.width != op.width ||
            metadata.height != op.height ||
            metadata.frameCount != op.frameCount ||
            metadata.orientation != op.orientation) {
          throw const ResourceFailure(FailureKind.invalidImage);
        }
        final result = await _complete(op, recovering: true);
        if (result.status == ImportStatus.saved ||
            result.status == ImportStatus.repaired) {
          recovered++;
        }
      } catch (_) {
        issues.add(RecoveryIssue(op.id, '一项未完成导入无法校验，已保留现场；请重新选择完整图片。'));
      }
    }
    _recoveryIssues = List.unmodifiable(issues);
    _recoveredImportCount += recovered;
    return _recoveryIssues;
  });

  Future<File?> thumbnailFor(ImageAsset asset, {int frame = 0}) {
    if (frame < 0 || frame >= asset.version.frameCount) {
      throw ArgumentError('预览帧越界。');
    }
    return _thumbnailJobs.putIfAbsent(
      '${asset.version.id}:$frame',
      () =>
          _serial<File?>(() async {
            try {
              final record = await _thumbnailRecord(asset, frame);
              return record == null ? null : await _files.file(record.path);
            } catch (_) {
              _storageWarning = '缩略图未能安全生成，已有图片保留；请检查缓存限制和可用空间后重试。';
              return null;
            }
          }).whenComplete(() {
            // Map.remove returns the cached Future itself. Returning it here
            // would make whenComplete wait on its own completion forever.
            _thumbnailJobs.remove('${asset.version.id}:$frame');
          }),
    );
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _outputMaintenance?.cancel();
    final done = Completer<void>();
    _closing = done.future;
    unawaited(() async {
      try {
        // Restore copies run outside the writer gate. Closing must wait for
        // their real IO and journal cleanup before releasing the root lock.
        await _restoreExecution?.future;
        // Drain calls that already passed the closing check but are still
        // validating files, before inspecting the now-complete lease set.
        await _serial(() async {}, maintenance: true);
        // Do not hold the serial gate while waiting: releases need that gate.
        if (_activeLeaseIds.isNotEmpty) {
          await (_leaseDrain ??= Completer<void>()).future;
        }
        await _waitLinkProbeDrain();
        await _waitRemoteDeletionDrain();
        await processingScheduler.close();
        await _serial(() async {
          _closed = true;
          _executionEpoch = const Uuid().v4();
          _sessionCredentials.clear();
          await _accountChanges.close();
          await _accountHealthChanges.close();
          await _uploadChanges.close();
          await _settingsChanges.close();
          await _diagnosticChanges.close();
          _thumbnailHolds.clear();
          await _storageChanges.close();
          try {
            await _db.close();
          } finally {
            await _files.close();
          }
        }, maintenance: true);
        done.complete();
      } catch (error, stack) {
        _closing = null;
        done.completeError(error, stack);
      }
    }());
    return done.future;
  }
}
