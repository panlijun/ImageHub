import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:clock/clock.dart';
import 'package:uuid/uuid.dart';

import '../../../platform/import_gateway.dart';
import '../../../platform/library_location.dart';
import '../../../core/secret_store.dart';
import '../../../core/network_state.dart';
import '../../../core/memory_pressure.dart';
import '../../../platform/system_network_monitor.dart';
import '../../../platform/system_memory_pressure_monitor.dart';
import '../../../platform/system_secret_store.dart';
import '../../../platform/storage_capacity.dart';
import '../data/library_repository.dart';
import '../domain/library_models.dart';
import '../domain/gallery_query.dart';
import '../domain/organization_models.dart';
import '../../upload/application/upload_coordinator.dart';
import '../../upload/application/upload_processing_coordinator.dart';
import '../../accounts/domain/account_models.dart';
import '../../upload/data/library_upload_queue_store.dart';
import '../../upload/data/provider_adapters.dart';
import '../../links/application/link_probe_coordinator.dart';
import '../../links/data/link_probe_gateway.dart';
import '../../links/application/remote_deletion_coordinator.dart';
import '../../links/data/remote_deletion_gateway.dart';
import '../../diagnostics/application/diagnostic_runtime.dart';
import '../../diagnostics/domain/diagnostic_models.dart';

class LibrarySession {
  factory LibrarySession(
    LibraryRepository repository,
    List<RecoveryIssue> recoveryIssues, {
    UploadCoordinator? uploads,
    NetworkMonitor? networkMonitor,
    MemoryPressureMonitor? memoryPressureMonitor,
    UploadProcessingCoordinator? uploadProcessing,
  }) => LibrarySession._(
    repository,
    recoveryIssues,
    uploads,
    networkMonitor,
    memoryPressureMonitor,
    uploadProcessing,
  );
  LibrarySession._(
    this.repository,
    this.recoveryIssues,
    this._uploads,
    this._networkMonitor,
    this._memoryPressureMonitor,
    UploadProcessingCoordinator? uploadProcessing,
  ) {
    // Reopened confirmed local plans resume without creating a network actor.
    // Existing injected upload actors keep their original optional interface.
    _uploadProcessing =
        uploadProcessing ??
        _uploads?.processing ??
        (_uploads == null ? UploadProcessingCoordinator(repository) : null);
    _uploads?.setConcurrency(
      repository.currentDeviceSettings.uploadConcurrency,
    );
    _uploads?.setNetworkPolicy(
      repository.currentDeviceSettings.networkUploadPolicy,
    );
    final monitor = _networkMonitor;
    if (monitor != null) {
      _uploads?.setNetworkSnapshot(monitor.current);
      _networkChanges = monitor.changes.listen(
        (snapshot) {
          if (!_closingSession) _uploads?.setNetworkSnapshot(snapshot);
        },
        onError: (Object _) {
          _uploads?.setNetworkSnapshot(const NetworkSnapshot.unknown());
        },
      );
      unawaited(
        monitor.start().catchError((Object _) {
          _uploads?.setNetworkSnapshot(const NetworkSnapshot.unknown());
        }),
      );
    }
    _settingsChanges = repository.settingsChanges.listen((_) {
      _uploads?.setConcurrency(
        repository.currentDeviceSettings.uploadConcurrency,
      );
      _uploads?.setNetworkPolicy(
        repository.currentDeviceSettings.networkUploadPolicy,
      );
    });
    final pressureMonitor = _memoryPressureMonitor;
    if (pressureMonitor != null) {
      // Subscribe first: a synchronous event during start must lower the budget
      // before the next processing permit can be granted.
      _memoryPressureChanges = pressureMonitor.events.listen(
        (_) {
          if (!_closingSession) {
            repository.processingScheduler.reportMemoryPressure();
          }
        },
        onError: (Object _) {
          unawaited(_noteMemoryObservationFailure());
        },
      );
      unawaited(
        pressureMonitor.start().catchError((Object _) {
          unawaited(_noteMemoryObservationFailure());
        }),
      );
    }
  }
  final LibraryRepository repository;
  final List<RecoveryIssue> recoveryIssues;
  Future<void> Function()? _detachDiagnostics;
  UploadCoordinator? _uploads;
  UploadProcessingCoordinator? _uploadProcessing;
  UploadProcessingCoordinator? get existingUploadProcessing =>
      _uploadProcessing;
  bool _closingSession = false;
  final NetworkMonitor? _networkMonitor;
  final MemoryPressureMonitor? _memoryPressureMonitor;
  StreamSubscription<void>? _memoryPressureChanges;
  bool _memoryObservationFailureNoted = false;
  StreamSubscription<NetworkSnapshot>? _networkChanges;
  late final StreamSubscription<void> _settingsChanges;
  LinkProbeCoordinator? _linkProbes;
  LinkProbeCoordinator linkProbesWith(LinkProbeGateway gateway) =>
      _linkProbes ??= LinkProbeCoordinator(repository, gateway);
  LinkProbeCoordinator? get existingLinkProbes => _linkProbes;
  RemoteDeletionCoordinator? _remoteDeletions;
  RemoteDeletionCoordinator remoteDeletionsWith(RemoteDeletionGateway gateway) {
    if (_closingSession) throw StateError('资料库会话正在关闭，不能创建删除协调器。');
    return _remoteDeletions ??= RemoteDeletionCoordinator(repository, gateway);
  }

  RemoteDeletionCoordinator? get existingRemoteDeletions => _remoteDeletions;
  UploadCoordinator get uploads {
    final current = _uploads;
    if (current != null) return current;
    if (_closingSession) throw StateError('资料库会话正在关闭，不能创建上传协调器。');
    return _uploads = UploadCoordinator(
      LibraryUploadQueueStore(repository),
      adapters: [CatboxAdapter(), ImgBBAdapter()],
      concurrency: repository.currentDeviceSettings.uploadConcurrency,
      initialNetwork:
          _networkMonitor?.current ?? const NetworkSnapshot.unknown(),
      networkPolicy: repository.currentDeviceSettings.networkUploadPolicy,
      processing: _uploadProcessing ??= UploadProcessingCoordinator(repository),
    );
  }

  UploadCoordinator? get existingUploads => _uploads;
  Future<void> refreshNetwork() async {
    if (_closingSession) throw StateError('资料库会话正在关闭，不能重新观察网络。');
    await _networkMonitor?.refresh();
  }

  Future<void> resetUploadsAfterReplacement() async {
    // The replacement hold has already drained real IO. Close the old actor
    // before a new store can capture the repository's new execution epoch.
    await _uploads?.close();
    _uploads = null;
    await _uploadProcessing?.close();
    // This callback still owns the repository maintenance hold. Portable
    // restores contain no executable intent; new enqueue events start work.
    _uploadProcessing = UploadProcessingCoordinator(
      repository,
      scanOnCreate: false,
    );
    await _linkProbes?.close();
    _linkProbes = null;
    await _remoteDeletions?.close();
    _remoteDeletions = null;
  }

  Future<void> close() async {
    // Stop future dispatch before any asynchronous shutdown preparation.
    _closingSession = true;
    _remoteDeletions?.blockNewRequests();
    _uploadProcessing?.blockForRestore();
    _uploads?.setNetworkSnapshot(const NetworkSnapshot.unknown());
    await _memoryPressureChanges?.cancel();
    try {
      await _memoryPressureMonitor?.close();
    } catch (_) {
      // This optional observer owns no file/network IO. Its failed handle
      // release is recorded, while actual actors and library IO still drain.
      await _noteMemoryObservationFailure(closing: true);
    }
    await _detachDiagnostics?.call();
    _detachDiagnostics = null;
    await _settingsChanges.cancel();
    await _networkChanges?.cancel();
    await _networkMonitor?.close();
    await _linkProbes?.close();
    await _remoteDeletions?.close();
    await _uploads?.close();
    await _uploadProcessing?.close();
    await repository.close();
  }

  Future<void> _noteMemoryObservationFailure({bool closing = false}) async {
    if (!closing && (_closingSession || _memoryObservationFailureNoted)) {
      return;
    }
    if (!closing) _memoryObservationFailureNoted = true;
    try {
      await repository.recordDiagnostic(
        DiagnosticEvent(
          id: const Uuid().v4(),
          occurredAt: clock.now().toUtc(),
          kind: DiagnosticKind.system,
          level: DiagnosticLevel.warning,
          code: closing
              ? 'memory_pressure.cleanup_failed'
              : 'memory_pressure.observer_unavailable',
          summary: closing
              ? '内存观察资源释放未确认，图库关闭仍等待实际文件与任务收尾。'
              : '本机内存压力观察暂不可用，候选处理预算仍保持限制。',
          recoveryAction: '请重开应用后核查；此记录不表示系统已发生低内存。',
        ),
      );
    } catch (_) {
      // Diagnostics cannot alter data closure or expose the native exception.
    }
  }
}

final importGatewayProvider = Provider((ref) => ImportGateway());
final secretStoreProvider = Provider<SecretStore>((ref) => SystemSecretStore());
final libraryLocationProvider = Provider<Future<Directory> Function()>(
  (ref) => locateLibrary,
);

class LibraryReplacementRevision extends Notifier<int> {
  @override
  int build() => 0;
  void committed() => state++;
}

// Local screen drafts and UUID selections must reset after replacement even
// when an incoming asset happens to reuse an old UUID.
final libraryReplacementRevisionProvider =
    NotifierProvider<LibraryReplacementRevision, int>(
      LibraryReplacementRevision.new,
    );

// Loading errors remain errors. No retry loop may reinitialize or replace data.
final librarySessionProvider = FutureProvider<LibrarySession>((ref) async {
  final root = await ref.read(libraryLocationProvider)();
  var disposed = false;
  LibraryRepository? repository;
  LibrarySession? session;
  ref.onDispose(() {
    disposed = true;
    final opened = repository;
    if (opened != null) unawaited(session?.close() ?? opened.close());
  });
  final opened = await LibraryRepository.open(
    root,
    secretStore: ref.read(secretStoreProvider),
    memoryBudgetBytes:
        (Platform.isAndroid || Platform.isIOS ? 256 : 512) * 1024 * 1024,
    availableStorageBytes: const StorageCapacity().availableBytes,
    publishCacheExclusive: const StorageCapacity().publishExclusive,
  );
  repository = opened;
  if (disposed) {
    await opened.close();
    throw StateError('资料库已关闭');
  }
  session = LibrarySession(
    opened,
    List.unmodifiable(opened.recoveryIssues),
    networkMonitor: SystemNetworkMonitor(),
    memoryPressureMonitor: SystemMemoryPressureMonitor(),
  );
  session._detachDiagnostics = DiagnosticRuntime.instance.attach(
    opened.recordDiagnostic,
  );
  return session;
}, retry: (retryCount, error) => null);

class GalleryQueryController extends Notifier<GalleryQuery> {
  @override
  GalleryQuery build() => const GalleryQuery();
  void replace(GalleryQuery query) => state = query;
  void setKeyword(String keyword) => state = state.copyWith(keyword: keyword);
  void setFavoritesOnly(bool value) =>
      state = state.copyWith(favoritesOnly: value);
  void clear() => state = GalleryQuery(recycledOnly: state.recycledOnly);
}

final galleryQueryProvider =
    NotifierProvider<GalleryQueryController, GalleryQuery>(
      GalleryQueryController.new,
    );

final categoriesProvider = FutureProvider<List<LibraryCategory>>(
  (ref) async =>
      (await ref.watch(librarySessionProvider.future)).repository
          .listCategories(),
  retry: (count, error) => null,
);
final tagsProvider = FutureProvider<List<LibraryTag>>(
  (ref) async =>
      (await ref.watch(librarySessionProvider.future)).repository.listTags(),
  retry: (count, error) => null,
);

// Database/account changes invalidate both pages and historical target choices.
// This subscribes to local evidence only; it never creates or authorizes IO.
final galleryRemoteRevisionProvider = StreamProvider<int>((ref) async* {
  final session = await ref.watch(librarySessionProvider.future);
  if (!ref.mounted) return;
  final changes = StreamController<int>();
  var revision = 0;
  final uploads = session.repository.uploadChanges.listen(
    (_) => changes.add(++revision),
  );
  final accounts = session.repository.accountChanges.listen(
    (_) => changes.add(++revision),
  );
  ref.onDispose(() {
    unawaited(uploads.cancel());
    unawaited(accounts.cancel());
    unawaited(changes.close());
  });
  yield revision;
  yield* changes.stream;
});

final galleryRemoteTargetsProvider = FutureProvider<List<TargetSnapshot>>((
  ref,
) async {
  ref.watch(
    galleryRemoteRevisionProvider.select((change) => change.asData?.value ?? 0),
  );
  return (await ref.watch(librarySessionProvider.future)).repository
      .listGalleryRemoteTargets();
}, retry: (count, error) => null);

class GalleryController extends AsyncNotifier<GalleryPage> {
  int _revision = 0;
  bool _loadingMore = false;

  @override
  Future<GalleryPage> build() async {
    _revision++;
    _loadingMore = false;
    final query = ref.watch(galleryQueryProvider);
    ref.watch(
      galleryRemoteRevisionProvider.select(
        (change) => change.asData?.value ?? 0,
      ),
    );
    final session = await ref.watch(librarySessionProvider.future);
    return session.repository.listAssets(query: query);
  }

  Future<void> reload() async {
    final revision = ++_revision;
    _loadingMore = false;
    final query = ref.read(galleryQueryProvider);
    final session = await ref.read(librarySessionProvider.future);
    final previous = state;
    try {
      final page = await session.repository.listAssets(query: query);
      if (ref.mounted && revision == _revision) state = AsyncData(page);
    } catch (error, stack) {
      if (ref.mounted && revision == _revision) state = previous;
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (_loadingMore ||
        state.isLoading ||
        current == null ||
        current.items.length >= current.total) {
      return;
    }
    _loadingMore = true;
    final revision = _revision;
    final query = ref.read(galleryQueryProvider);
    try {
      final session = await ref.read(librarySessionProvider.future);
      final next = await session.repository.listAssets(
        offset: current.items.length,
        query: query,
      );
      // An import may have shifted offsets while this page was queued. Start a
      // fresh snapshot instead of skipping an identity or repeatedly loading it.
      if (next.total != current.total) {
        final refreshed = await session.repository.listAssets(query: query);
        if (ref.mounted && revision == _revision) {
          state = AsyncData(refreshed);
        }
        return;
      }
      if (ref.mounted && revision == _revision) {
        final ids = current.items.map((asset) => asset.id).toSet();
        state = AsyncData(
          GalleryPage([
            ...current.items,
            ...next.items.where((asset) => ids.add(asset.id)),
          ], next.total),
        );
      }
    } finally {
      if (revision == _revision) _loadingMore = false;
    }
  }
}

final galleryProvider = AsyncNotifierProvider<GalleryController, GalleryPage>(
  GalleryController.new,
  retry: (retryCount, error) => null,
);

class AssetPreview {
  const AssetPreview(
    this.availability,
    this.thumbnail, {
    this.bytes,
    this.cacheMessage,
  });
  final CopyAvailability availability;
  final File? thumbnail;
  final Uint8List? bytes;
  final String? cacheMessage;
}

Future<AssetPreview> _loadAssetPreview(
  Ref ref,
  ImageAsset asset,
  int frame,
) async {
  ref.watch(libraryReplacementRevisionProvider);
  ThumbnailLease? lease;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    final current = lease;
    if (current != null) unawaited(current.release());
  });
  try {
    final session = await ref.watch(librarySessionProvider.future);
    final availability = await session.repository.verifyCopy(asset);
    if (availability != CopyAvailability.available || disposed) {
      return AssetPreview(availability, null);
    }
    lease = await session.repository.acquireThumbnailLease(asset, frame: frame);
    if (disposed) {
      await lease?.release();
      return AssetPreview(availability, null);
    }
    final current = lease;
    if (current == null) {
      return AssetPreview(
        availability,
        null,
        cacheMessage: session.repository.storageWarning,
      );
    }
    final bytes = await current.readBytes();
    if (disposed) {
      await current.release();
      return AssetPreview(availability, null);
    }
    return AssetPreview(availability, current.file, bytes: bytes);
  } catch (_) {
    await lease?.release();
    // An invalidated consumer must not publish a close/replacement error or
    // late bytes into its former view. Live consumers still get real failure.
    if (disposed) {
      return const AssetPreview(CopyAvailability.inaccessible, null);
    }
    rethrow;
  }
}

final assetPreviewProvider = FutureProvider.autoDispose
    .family<AssetPreview, ImageAsset>(
      (ref, asset) => _loadAssetPreview(ref, asset, 0),
      retry: (retryCount, error) => null,
    );

final assetFramePreviewProvider = FutureProvider.autoDispose
    .family<AssetPreview, (ImageAsset, int)>(
      (ref, selection) => _loadAssetPreview(ref, selection.$1, selection.$2),
      retry: (_, _) => null,
    );
