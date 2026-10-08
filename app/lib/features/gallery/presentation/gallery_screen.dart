import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform_resource.dart';
import '../application/import_batch.dart';
import '../domain/library_models.dart';
import 'gallery_providers.dart';
import 'asset_widgets.dart';
import 'mobile_gallery.dart';
import 'desktop_gallery.dart';
import '../../processing/presentation/processing_workbench.dart';
import '../../accounts/presentation/accounts_screen.dart';
import '../../upload/presentation/upload_tasks_screen.dart';
import '../../upload/presentation/upload_exit.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../links/presentation/link_results_screen.dart';
import '../../settings/presentation/settings_screen.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});
  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  CancellationToken? _cancellation;
  Future<void>? _activeImport;
  AppLifecycleListener? _lifecycle;
  final List<(String, ImportResult)> _results = [];
  List<PlatformResource> _lostPhotos = [];
  bool _busy = false;
  bool _awaitingSelection = false;
  bool _loadingMore = false;
  bool _linksVisible = false;
  String? _feedback;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _exitRequested);
    unawaited(_retrieveLostSelection());
  }

  Future<void> _retrieveLostSelection() async {
    try {
      final photos = await ref.read(importGatewayProvider).retrieveLostPhotos();
      if (mounted && photos.isNotEmpty) setState(() => _lostPhotos = photos);
    } on ResourceFailure catch (error) {
      if (mounted) setState(() => _feedback = error.message);
    }
  }

  Future<AppExitResponse> _exitRequested() async {
    if (ModalRoute.of(context)?.isCurrent != true && !_busy) {
      return AppExitResponse.exit;
    }
    if (_busy) {
      final stop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入尚未结束'),
          content: const Text('停止尚未提交的图片并退出？已经保存的图片会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续导入'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('停止并退出'),
            ),
          ],
        ),
      );
      if (stop != true) return AppExitResponse.cancel;
      _stopImport();
      await _activeImport;
    }
    if (!mounted) return AppExitResponse.cancel;
    final session = ref.read(librarySessionProvider).asData?.value;
    if (session != null && !await requestLibraryExit(context, session)) {
      return AppExitResponse.cancel;
    }
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _pick(bool photos) => _startImport(() {
    final gateway = ref.read(importGatewayProvider);
    return photos ? gateway.pickPhotos() : gateway.pickFiles();
  });

  Future<void> _startImport(
    Future<List<PlatformResource>> Function() acquire, {
    bool selecting = true,
    bool recovered = false,
  }) {
    if (_busy) return Future.value();
    final token = CancellationToken();
    setState(() {
      _busy = true;
      _awaitingSelection = selecting;
      _cancellation = token;
      _feedback = null;
      _progress = selecting ? '等待选择图片' : '准备导入图片';
      if (recovered) _lostPhotos = [];
    });
    // Track acquisition, error handling and real import cleanup as one unit.
    // Defer its start so even a synchronously failing picker has an owner before
    // exit can observe it. A stop cannot dismiss the native picker itself.
    final operation = Future<void>.microtask(
      () => _acquireAndImport(acquire, token, recovered: recovered),
    );
    _activeImport = operation;
    return operation;
  }

  Future<void> _acquireAndImport(
    Future<List<PlatformResource>> Function() acquire,
    CancellationToken token, {
    required bool recovered,
  }) async {
    try {
      final resources = await acquire();
      if (!mounted) return;
      _awaitingSelection = false;
      if (token.isCancelled) {
        setState(() => _feedback = '已停止导入，图库没有变化。');
        return;
      }
      if (resources.isEmpty) {
        setState(() => _feedback = '已取消选择，图库没有变化。');
        return;
      }
      setState(() => _progress = '准备导入图片');
      await _import(resources, token);
    } on ResourceFailure catch (error) {
      if (mounted) setState(() => _feedback = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _feedback = recovered
              ? '恢复导入未完成，请重新选择图片。已保存图片仍保留。'
              : '导入未完成，请重新选择或重启后检查恢复结果。已保存图片仍保留。',
        );
      }
    } finally {
      _activeImport = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _awaitingSelection = false;
          _cancellation = null;
          _progress = '';
        });
      }
    }
  }

  Future<void> _openProcessing() => _openPage(const ProcessingWorkbench());
  Future<void> _openAccounts() => _openPage(const AccountsScreen());
  Future<void> _openTasks() => _openPage(const UploadTasksScreen());
  Future<void> _openBackup() => _openPage(const BackupScreen());
  Future<void> _openSettings() => _openPage(const SettingsScreen());
  Future<void> _openLinks([List<String> ids = const []]) =>
      _openPage(LinkResultsScreen(assetIdsInOrder: ids));

  void _linksVisibility(bool visible) {
    _linksVisible = visible;
    _lifecycle?.dispose();
    _lifecycle = visible || ModalRoute.of(context)?.isCurrent != true
        ? null
        : AppLifecycleListener(onExitRequested: _exitRequested);
  }

  Future<void> _openPage(Widget page) async {
    if (_busy || !ref.read(librarySessionProvider).hasValue) return;
    // Only the visible page handles exit; two independent listeners can close
    // the library before the workbench has safely stopped its actual readers.
    _lifecycle?.dispose();
    _lifecycle = null;
    try {
      await Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => page));
      if (mounted) {
        await ref.read(galleryProvider.notifier).reload();
        ref.invalidate(assetPreviewProvider);
      }
    } catch (_) {
      if (mounted) setState(() => _feedback = '图库刷新失败，请重试。已保存结果仍保留。');
    } finally {
      if (mounted && !_linksVisible) {
        _lifecycle = AppLifecycleListener(onExitRequested: _exitRequested);
      }
    }
  }

  Future<void> _import(
    List<PlatformResource> resources,
    CancellationToken token,
  ) async {
    final repository = (await ref.read(librarySessionProvider.future))
        .repository;
    _results.clear();
    await ImportBatch(repository).run(
      resources,
      cancellation: token,
      onProgress: (index, progress) {
        if (mounted && !token.isCancelled) {
          setState(
            () => _progress =
                '${index + 1}/${resources.length} · ${progress.phase} · ${formatBytes(progress.bytesCopied)}',
          );
        }
      },
      onResult: (index, result) {
        if (mounted) {
          setState(() => _results.add((resources[index].displayName, result)));
        }
      },
    );
    if (mounted) {
      await ref.read(galleryProvider.notifier).reload();
      ref.invalidate(assetPreviewProvider);
    }
    if (mounted) {
      final counts = <ImportStatus, int>{};
      for (final item in _results) {
        counts.update(item.$2.status, (value) => value + 1, ifAbsent: () => 1);
      }
      setState(
        () => _feedback =
            '导入结束：${counts[ImportStatus.saved] ?? 0} 已保存，'
            '${counts[ImportStatus.duplicate] ?? 0} 重复，${counts[ImportStatus.repaired] ?? 0} 已修复，'
            '${(counts[ImportStatus.failed] ?? 0) + (counts[ImportStatus.needsRestore] ?? 0)} 未保存，'
            '${counts[ImportStatus.cancelled] ?? 0} 已停止。',
      );
    }
  }

  void _stopImport() {
    final token = _cancellation;
    if (token == null || token.isCancelled) return;
    token.cancel();
    if (mounted) {
      setState(
        () => _progress = _awaitingSelection
            ? '正在停止，等待图片选择结束…'
            : '正在停止，等待来源读取和本机写入结束…',
      );
    }
  }

  Future<void> _resumeLostPhotos() {
    final photos = _lostPhotos;
    return _startImport(() async => photos, selecting: false, recovered: true);
  }

  void _showResults() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('逐项导入结果'),
      content: SizedBox(
        width: 600,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (name, result) in _results)
              ListTile(
                title: Text(name),
                subtitle: Text(
                  result.failure?.message ??
                      switch (result.status) {
                        ImportStatus.saved => '独立副本已永久保存',
                        ImportStatus.duplicate => '复用已有图片，整理信息保留',
                        ImportStatus.repaired => '已修复图片信息或本机副本，身份保留',
                        _ => '尚未保存',
                      },
                ),
                leading: Icon(
                  result.persisted
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(librarySessionProvider);
    final gallery = ref.watch(galleryProvider);
    final ready = session.hasValue && gallery.hasValue;
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      return MobileGallery(
        onAssetLinks: (ids) => unawaited(_openLinks(ids)),
        onLinksVisibility: _linksVisibility,
        onProcessing: () => unawaited(_openProcessing()),
        onAccounts: () => unawaited(_openAccounts()),
        onTasks: () => unawaited(_openTasks()),
        onBackup: () => unawaited(_openBackup()),
        onSettings: () => unawaited(_openSettings()),
        gallery: gallery,
        session: session,
        busy: _busy,
        loadingMore: _loadingMore,
        supportsPhotos: Platform.isAndroid || Platform.isIOS,
        onImport: _pick,
        onRetry: () {
          ref.invalidate(librarySessionProvider);
          ref.invalidate(galleryProvider);
        },
        onRefresh: () async {
          try {
            await ref.read(galleryProvider.notifier).reload();
            ref.invalidate(assetPreviewProvider);
          } catch (_) {
            if (mounted) setState(() => _feedback = '刷新失败，已载入记录仍保留，请重试。');
          }
        },
        onLoadMore: () async {
          if (_loadingMore) return;
          setState(() => _loadingMore = true);
          try {
            await ref.read(galleryProvider.notifier).loadMore();
          } catch (_) {
            if (mounted) setState(() => _feedback = '读取下一页失败，请重试。');
          } finally {
            if (mounted) setState(() => _loadingMore = false);
          }
        },
        notices: [
          if (_lostPhotos.isNotEmpty)
            _Notice(
              message: '系统找回 ${_lostPhotos.length} 张尚未导入的选择。',
              action: TextButton(
                onPressed: ready && !_busy ? _resumeLostPhotos : null,
                child: const Text('继续导入'),
              ),
            ),
          for (final issue
              in session.asData?.value.recoveryIssues ??
                  const <RecoveryIssue>[])
            _Notice(message: issue.message),
          if ((session.asData?.value.repository.recoveredImportCount ?? 0) > 0)
            _Notice(
              message:
                  '已校验并恢复 ${session.asData!.value.repository.recoveredImportCount} 项未完成导入。',
            ),
          if (_busy) ...[
            _Notice(
              message: _progress,
              action: TextButton(
                onPressed: _cancellation == null || _cancellation!.isCancelled
                    ? null
                    : _stopImport,
                child: const Text('停止后续导入'),
              ),
            ),
            const LinearProgressIndicator(),
          ],
          if (_feedback != null)
            _Notice(
              message: _feedback!,
              action: _results.isNotEmpty
                  ? TextButton(
                      onPressed: _showResults,
                      child: const Text('查看逐项结果'),
                    )
                  : null,
            ),
        ],
      );
    }
    return DesktopGallery(
      onAssetLinks: (ids) => unawaited(_openLinks(ids)),
      onNavigate: (destination) {
        if (destination == DesktopDestination.processing) {
          unawaited(_openProcessing());
        } else if (destination == DesktopDestination.accounts) {
          unawaited(_openAccounts());
        } else if (destination == DesktopDestination.tasks) {
          unawaited(_openTasks());
        } else if (destination == DesktopDestination.links) {
          unawaited(_openLinks());
        } else if (destination == DesktopDestination.settings) {
          unawaited(_openSettings());
        } else if (destination == DesktopDestination.backup) {
          unawaited(_openBackup());
        }
      },
      gallery: gallery,
      session: session,
      busy: _busy,
      loadingMore: _loadingMore,
      onImport: _pick,
      onRetry: () {
        ref.invalidate(librarySessionProvider);
        ref.invalidate(galleryProvider);
      },
      onRefresh: () async {
        await ref.read(galleryProvider.notifier).reload();
        ref.invalidate(assetPreviewProvider);
      },
      onLoadMore: () async {
        if (_loadingMore) return;
        setState(() => _loadingMore = true);
        try {
          await ref.read(galleryProvider.notifier).loadMore();
        } catch (_) {
          if (mounted) setState(() => _feedback = '读取下一页失败，请重试。');
        } finally {
          if (mounted) setState(() => _loadingMore = false);
        }
      },
      notices: [
        if (_lostPhotos.isNotEmpty)
          _Notice(
            message: '系统找回 ${_lostPhotos.length} 张尚未导入的选择。',
            action: TextButton(
              onPressed: ready && !_busy ? _resumeLostPhotos : null,
              child: const Text('继续导入'),
            ),
          ),
        for (final issue
            in session.asData?.value.recoveryIssues ?? const <RecoveryIssue>[])
          _Notice(message: issue.message),
        if ((session.asData?.value.repository.recoveredImportCount ?? 0) > 0)
          _Notice(
            message:
                '已校验并恢复 ${session.asData!.value.repository.recoveredImportCount} 项未完成导入。',
          ),
        if (_busy) ...[
          _Notice(
            message: _progress,
            action: TextButton(
              onPressed: _cancellation == null || _cancellation!.isCancelled
                  ? null
                  : _stopImport,
              child: const Text('停止后续导入'),
            ),
          ),
          const LinearProgressIndicator(),
        ],
        if (_feedback != null)
          _Notice(
            message: _feedback!,
            action: _results.isNotEmpty
                ? TextButton(
                    onPressed: _showResults,
                    child: const Text('查看逐项结果'),
                  )
                : null,
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.action});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffedf1ff),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            ?action,
          ],
        ),
      ),
    ),
  );
}
