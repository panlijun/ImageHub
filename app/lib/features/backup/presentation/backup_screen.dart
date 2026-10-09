import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/platform_resource.dart';
import '../../../platform/export_gateway.dart';
import '../../../platform/backup_import_gateway.dart';
import '../../../platform/mobile_file_workspace.dart';
import '../../../platform/storage_capacity.dart';
import '../../gallery/data/library_repository.dart';
import '../../diagnostics/domain/diagnostic_models.dart';
import '../../gallery/domain/gallery_query.dart';
import '../../gallery/domain/library_models.dart';
import '../../gallery/presentation/asset_widgets.dart' show formatBytes;
import '../../gallery/presentation/gallery_providers.dart';
import '../../processing/domain/export_models.dart';
import '../../upload/presentation/upload_exit.dart';
import '../application/backup_coordinator.dart';
import '../application/backup_snapshot.dart';
import '../application/restore_coordinator.dart';
import '../domain/backup_manifest.dart';
import '../domain/backup_merge_plan.dart';
import '../domain/backup_restore_plan.dart';
import '../domain/backup_settings.dart';

final backupExportGatewayProvider = Provider<ExportGateway>(
  (ref) => const ExportGateway(),
);
final backupStorageCapacityProvider = Provider<StorageCapacity>(
  (ref) => const StorageCapacity(),
);
final backupImportGatewayProvider = Provider<BackupImportGateway>(
  (ref) => const BackupImportGateway(),
);
final backupTransferWorkspaceProvider =
    Provider<Future<MobileFileWorkspace> Function()>(
      (_) =>
          () => MobileFileWorkspace.create(),
    );

// Count committed assets without capturing/validating the image byte snapshot.
// This ignores the gallery's current search and includes the recycle area.
final backupAssetCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final repository = (await ref.watch(librarySessionProvider.future))
      .repository;
  final active = await repository.listAssets(limit: 1);
  final recycled = await repository.listAssets(
    limit: 1,
    query: const GalleryQuery(recycledOnly: true),
  );
  return active.total + recycled.total;
}, retry: (_, _) => null);

/// Desktop and M1 share the same real snapshot/archive coordinator. Native
/// directory publication is enabled only where the platform bridge exists.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  late final AppLifecycleListener _lifecycle;
  CancellationToken? _cancellation;
  Future<void>? _activeOperation;
  Completer<bool>? _confirmation;
  DialogRoute<bool>? _confirmationRoute;
  NavigatorState? _confirmationNavigator;
  bool _restoring = false;
  bool _busy = false;
  bool _leaving = false;
  String _progress = '';
  String? _feedback;
  List<String> _affectedVersions = const [];
  BackupExportReport? _report;
  ({
    BackupMode mode,
    int assets,
    int versions,
    int byteCount,
    String name,
    String uri,
    String? warning,
  })?
  _mobileReport;
  RestoreOutcome? _restoreReport;

  @override
  void initState() {
    super.initState();
    // Re-entering within the same session must refresh even when an earlier
    // provider disposal is still queued by the host scheduler.
    ref.invalidate(backupAssetCountProvider);
    _lifecycle = AppLifecycleListener(onExitRequested: _exitRequested);
  }

  @override
  void dispose() {
    // Disposing signals cancellation; the coordinator still owns its source
    // leases until its actual IO and cleanup finish.
    _cancellation?.cancel();
    _closeConfirmation();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<bool> _stopForExit() async {
    if (!_busy) return true;
    if (_confirmation != null) {
      _cancel();
      await _activeOperation;
      return mounted;
    }
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_restoring ? '恢复尚未结束' : '备份尚未结束'),
        content: const Text('停止尚未提交的操作并等待结束？已经提交的内容会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续操作'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('停止并等待'),
          ),
        ],
      ),
    );
    if (stop != true) return false;
    _cancel();
    await _activeOperation;
    return mounted;
  }

  Future<AppExitResponse> _exitRequested() async {
    if (_leaving) return AppExitResponse.cancel;
    _leaving = true;
    try {
      if (!await _stopForExit() || !mounted) return AppExitResponse.cancel;
      final session = ref.read(librarySessionProvider).asData?.value;
      if (session != null && !await requestLibraryExit(context, session)) {
        return AppExitResponse.cancel;
      }
      return AppExitResponse.exit;
    } finally {
      _leaving = false;
    }
  }

  Future<void> _back() async {
    if (_leaving) return;
    _leaving = true;
    try {
      if (!await _stopForExit() || !mounted) return;
      // PopScope updates after the completed real export has cleared busy.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    } finally {
      _leaving = false;
    }
  }

  void _cancel() {
    _cancellation?.cancel();
    _closeConfirmation();
    if (mounted && _busy) {
      setState(() => _progress = '正在停止，请等待操作结束…');
    }
  }

  Future<void> _export(BackupMode mode) async {
    if (_busy) return;
    final session = ref.read(librarySessionProvider);
    final gateway = ref.read(backupExportGatewayProvider);
    final capacity = ref.read(backupStorageCapacityProvider);
    if (!session.hasValue ||
        session.isLoading ||
        session.hasError ||
        !gateway.supportsFileExport ||
        !capacity.supportsPlatform) {
      return;
    }
    final token = CancellationToken();
    _cancellation = token;
    setState(() {
      _busy = true;
      _restoring = false;
      _progress = gateway.supportsDirectoryExport ? '等待选择备份目录' : '正在准备备份';
      _feedback = null;
      _report = null;
      _mobileReport = null;
      _restoreReport = null;
      _affectedVersions = const [];
    });
    final operation = _performExport(mode, token);
    _activeOperation = operation;
    await operation;
    if (identical(_activeOperation, operation)) _activeOperation = null;
  }

  void _closeConfirmation() {
    final pending = _confirmation;
    _confirmation = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    final route = _confirmationRoute;
    final navigator = _confirmationNavigator;
    _confirmationRoute = null;
    _confirmationNavigator = null;
    if (route != null && navigator != null && route.isActive) {
      // Dispose may occur while the navigator is rebuilding. The confirmation
      // future is already resolved, independently of removing its route.
      scheduleMicrotask(() {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
  }

  Future<bool> _confirmRestore(
    BackupManifest manifest,
    BackupRestorePlan plan,
    BackupSettingsRestorePlan settings,
  ) async {
    return _showRestoreConfirmation(
      _RestoreConfirmation(manifest: manifest, plan: plan, settings: settings),
    );
  }

  Future<bool> _confirmReplacement(ReplacementRestorePreparation prepared) =>
      _showRestoreConfirmation(_ReplacementConfirmation(preparation: prepared));

  Future<bool> _showRestoreConfirmation(Widget content) async {
    if (!mounted || _cancellation?.isCancelled == true) return false;
    final pending = Completer<bool>();
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => content,
    );
    _confirmation = pending;
    _confirmationNavigator = navigator;
    _confirmationRoute = route;
    unawaited(
      navigator.push(route).then((accepted) {
        if (!pending.isCompleted) pending.complete(accepted == true);
        if (identical(_confirmation, pending)) {
          _confirmation = null;
          _confirmationRoute = null;
          _confirmationNavigator = null;
        }
      }),
    );
    return pending.future;
  }

  Future<void> _restore({bool replacement = false}) async {
    if (_busy) return;
    final session = ref.read(librarySessionProvider).asData?.value;
    final gateway = ref.read(backupImportGatewayProvider);
    final capacity = ref.read(backupStorageCapacityProvider);
    if (session == null ||
        !gateway.supportsPlatform ||
        !capacity.supportsPlatform) {
      return;
    }
    final token = CancellationToken();
    _cancellation = token;
    setState(() {
      _busy = true;
      _restoring = true;
      _progress = '等待选择备份文件';
      _feedback = null;
      _report = null;
      _mobileReport = null;
      _restoreReport = null;
      _affectedVersions = const [];
    });
    final operation = _performRestore(session, token, replacement: replacement);
    _activeOperation = operation;
    await operation;
    if (identical(_activeOperation, operation)) _activeOperation = null;
  }

  Future<void> _performRestore(
    LibrarySession session,
    CancellationToken token, {
    required bool replacement,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    BackupSource? selected;
    try {
      final gateway = ref.read(backupImportGatewayProvider);
      selected = await gateway.acquireBackup(cancellation: token);
      if (selected == null) {
        if (mounted) setState(() => _feedback = '已取消选择备份，当前资料库没有变化。');
        return;
      }
      if (!mounted || token.isCancelled) return;
      final parent = await gateway.temporaryParent();
      final capacity = ref.read(backupStorageCapacityProvider);
      final coordinator = RestoreCoordinator(
        repository: session.repository,
        pauseUploads: session.uploads.holdForRestore,
        availableBytes: capacity.availableBytes,
        publishExclusive: capacity.publishExclusive,
        afterReplacement: session.resetUploadsAfterReplacement,
      );
      void progress(String phase, int done, int total) {
        if (mounted && !token.isCancelled) {
          setState(
            () => _progress = switch (phase) {
              '正在暂停上传并等待文件操作结束' => '正在准备恢复，请等待…',
              '预计所需空间' => '预计所需空间约 ${formatBytes(total)}',
              '正在保管永久图片' =>
                '正在恢复图片 · ${formatBytes(done)} / ${formatBytes(total)}',
              _ => '$phase · $done/$total',
            },
          );
        }
      }

      final outcome = replacement
          ? await coordinator.replace(
              selected.file,
              parent,
              confirm: _confirmReplacement,
              cancellation: token,
              onProgress: progress,
            )
          : await coordinator.merge(
              selected.file,
              parent,
              confirm: (manifest, plan) => _confirmRestore(
                manifest,
                plan,
                session.repository.planBackupSettings(manifest.settings),
              ),
              cancellation: token,
              onProgress: progress,
            );
      if (outcome != null) {
        // Capture the app scope before awaiting IO. A disposed backup route
        // can still have surviving gallery/account/task consumers to reset.
        // A disposed scope has no consumers; its read rejection is harmless
        // and must never turn a durable commit into a reported restore failure.
        try {
          if (outcome.replaced) {
            container
                .read(galleryQueryProvider.notifier)
                .replace(const GalleryQuery());
            container
                .read(libraryReplacementRevisionProvider.notifier)
                .committed();
          }
          container.invalidate(galleryProvider);
          container.invalidate(categoriesProvider);
          container.invalidate(tagsProvider);
          container.invalidate(assetPreviewProvider);
          container.invalidate(assetFramePreviewProvider);
          container.invalidate(backupAssetCountProvider);
        } catch (_) {
          // The scope may have been disposed while actual commit IO ended.
        }
      }
      if (!mounted) return;
      setState(() {
        _restoreReport = outcome;
        if (outcome == null) {
          _feedback = replacement
              ? '已取消替换恢复，当前资料库没有变化。已暂停的上传任务须手动恢复。'
              : '已取消合并恢复，当前资料库没有变化。已暂停的上传任务须手动恢复。';
        }
      });
    } on BackupSnapshotFailure catch (error) {
      if (mounted) setState(() => _feedback = error.message);
    } on BackupFailure catch (error) {
      if (mounted) setState(() => _feedback = error.message);
    } on ResourceFailure catch (error) {
      if (mounted) {
        setState(
          () => _feedback = error.kind == FailureKind.cancelled
              ? '已取消读取备份，当前资料库没有变化。'
              : '无法完整取得备份文件；请检查文件授权、本机空间和来源是否已下载。当前资料库保留。',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _feedback = '恢复未确认提交，当前资料库保留。请检查备份文件后重试。');
    } finally {
      _closeConfirmation();
      try {
        await selected?.release?.call();
      } catch (_) {
        if (mounted) {
          setState(
            () => _feedback =
                '${_feedback == null ? '' : '${_feedback!}\n'}'
                '备份读取暂存或授权收尾未确认，现场已保留；已提交的恢复结果保留。',
          );
        }
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _performExport(BackupMode mode, CancellationToken token) async {
    MobileFileWorkspace? workspace;
    try {
      final gateway = ref.read(backupExportGatewayProvider);
      final directory = gateway.supportsDirectoryExport
          ? await gateway.pickDirectory()
          : (workspace = await ref.read(
              backupTransferWorkspaceProvider,
            )()).directory;
      if (directory == null) {
        if (mounted) setState(() => _feedback = '已取消选择目录，没有生成备份文件。');
        return;
      }
      if (token.isCancelled || !mounted) {
        if (mounted) setState(() => _feedback = '备份已取消，没有生成备份文件。');
        return;
      }
      final repository = (await ref.read(librarySessionProvider.future))
          .repository;
      final capacity = ref.read(backupStorageCapacityProvider);
      final coordinator = BackupCoordinator(
        recordCompletion: workspace == null
            ? (completed) => repository.recordOperation(
                kind: DiagnosticKind.backup,
                code: 'backup.export',
                summary: '用户明确选择的备份已写入并独占发布。',
                recoveryAction: '导出未确认时检查目标空间和权限；原有资料与备份保留。',
                failed: !completed,
              )
            : null,
        capture: (mode, token, progress) => repository.captureBackupSnapshot(
          mode: mode,
          cancellation: token,
          onVerification: progress,
        ),
        availableBytes: capacity.availableBytes,
        publishExclusive: capacity.publishExclusive,
      );
      final report = await coordinator.export(
        directory,
        mode,
        cancellation: token,
        onProgress: (phase, done, total) {
          if (mounted && !token.isCancelled) {
            setState(
              () => _progress = switch (phase) {
                '预计所需空间' => '预计所需空间约 ${formatBytes(total)}',
                '写入备份' =>
                  '$phase · ${formatBytes(done)} / ${formatBytes(total)}',
                '提交备份' when workspace != null => '正在校验备份暂存',
                _ => '$phase · $done/$total',
              },
            );
          }
        },
      );
      if (workspace == null) {
        if (mounted) setState(() => _report = report);
      } else {
        await workspace.registerClosed(report.file);
        token.throwIfCancelled();
        if (!mounted) return;
        setState(() => _progress = '等待选择保存位置并完成写入');
        final results = await gateway.exportFiles([
          ExportInput(
            id: const Uuid().v4(),
            source: report.file,
            displayName: p.basename(report.file.path),
            expectedSha256: await fileSha256(report.file),
            expectedByteCount: report.byteCount,
          ),
        ], cancellation: token);
        final result = results.single;
        final saved = gateway.confirmsSystemFileSave(result);
        // The private closed ZIP is preparation only. User-export completion
        // is recorded only after the real destination has been confirmed.
        try {
          await repository.recordOperation(
            kind: DiagnosticKind.backup,
            code: 'backup.export',
            summary: saved ? '用户选择的系统位置已确认保存备份。' : '系统备份保存尚未确认完成。',
            recoveryAction: '未确认时核查保存位置、权限和空间；原资料库与已有备份保留。',
            failed: !saved,
          );
        } catch (_) {
          // A diagnostic failure never changes a confirmed user publication.
        }
        if (mounted) {
          setState(() {
            if (saved) {
              _mobileReport = (
                mode: report.mode,
                assets: report.assets,
                versions: report.versions,
                byteCount: report.byteCount,
                name: result.fileName!,
                uri: result.destinationUri!,
                warning: report.cleanupMessage == null
                    ? result.reason
                    : '${report.cleanupMessage!}${result.reason == null ? '' : '\n${result.reason!}'}',
              );
            } else {
              _feedback = result.status == ExportStatus.cancelled
                  ? '已取消系统保存，没有确认新的用户备份。'
                  : result.reason ?? '系统尚未确认备份保存，请核查目标位置后重试。';
            }
          });
        }
      }
    } on BackupSnapshotFailure catch (error) {
      if (mounted) {
        setState(() {
          _feedback = error.message;
          _affectedVersions = error.affectedVersions;
        });
      }
    } on BackupFailure catch (error) {
      if (mounted) setState(() => _feedback = error.message);
    } on ExportFailure catch (error) {
      if (mounted) setState(() => _feedback = error.message);
    } on ResourceFailure catch (error) {
      if (mounted) {
        setState(
          () => _feedback = error.kind == FailureKind.cancelled
              ? '已取消备份，实际文件 IO 已结束。'
              : '备份写入未确认，请检查本机空间与保存权限后重试。',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _feedback = '备份未确认提交，原资料库和已有备份保留。请检查目标目录后重试。');
      }
    } finally {
      try {
        await workspace?.close();
      } catch (_) {
        if (mounted) {
          setState(
            () => _feedback =
                '${_feedback == null ? '' : '${_feedback!}\n'}'
                '备份私有暂存清理未确认，现场已保留；已确认保存的备份保留。',
          );
        }
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(librarySessionProvider);
    final count = ref.watch(backupAssetCountProvider);
    final supported =
        ref.watch(backupExportGatewayProvider).supportsFileExport &&
        ref.watch(backupStorageCapacityProvider).supportsPlatform;
    final loaded =
        session.hasValue &&
        !session.isLoading &&
        !session.hasError &&
        count.hasValue &&
        !count.isLoading &&
        !count.hasError;
    final enabled = loaded && supported && !_busy;
    final restoreSupported =
        ref.watch(backupImportGatewayProvider).supportsPlatform &&
        ref.watch(backupStorageCapacityProvider).supportsPlatform;
    final restoreEnabled = loaded && restoreSupported && !_busy;
    final report = _report;
    final mobileReport = _mobileReport;
    final restored = _restoreReport;
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('备份与恢复')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (session.hasError || count.hasError)
                      const Text('资料库读取失败，不能开始备份。已有资料库保留，请返回图库检查后重试。')
                    else if (!loaded) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text('正在读取资料库…'),
                    ] else
                      Text(
                        count.value == 0
                            ? '当前没有资产。仍可备份资料库中的其他有效记录。'
                            : '资料库已载入：${count.value} 个资产（包含回收区）。',
                      ),
                    const SizedBox(height: 20),
                    _panel('导出备份', [
                      const Text(
                        '完整备份包含永久图片副本与资料库记录。导出前会校验副本；缺失或损坏时停止，不自动跳过或改为元数据备份。',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '元数据备份包含整理信息、图床账号的去敏标识、已确认的普通链接和可用设置等记录，不含图片字节，不能恢复图片内容。仅保留去敏终态历史，待执行任务不进入备份。两种备份均不包含凭据、秘密管理链接、来源路径、缩略图或临时处理结果。',
                      ),
                      if (!supported) ...[
                        const SizedBox(height: 12),
                        const Text('此平台的原生备份导出尚未接入，暂不能选择目录或生成备份。'),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: enabled
                                ? () => unawaited(_export(BackupMode.full))
                                : null,
                            icon: const Icon(Icons.backup_outlined),
                            label: const Text('导出完整备份'),
                          ),
                          OutlinedButton.icon(
                            onPressed: enabled
                                ? () => unawaited(_export(BackupMode.metadata))
                                : null,
                            icon: const Icon(Icons.description_outlined),
                            label: const Text('导出元数据备份'),
                          ),
                        ],
                      ),
                    ]),
                    if (_busy) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(_progress),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _cancellation?.isCancelled == true
                              ? null
                              : _cancel,
                          child: Text(_restoring ? '取消恢复' : '取消备份'),
                        ),
                      ),
                    ],
                    if (_feedback != null) ...[
                      const SizedBox(height: 16),
                      Text(_feedback!),
                    ],
                    if (_affectedVersions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '受影响的永久内容版本：${_affectedVersions.length} 个。请返回图库检查或重新取得完整原图。',
                      ),
                      for (final id in _affectedVersions)
                        SelectableText('版本 UUID：$id'),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: enabled
                              ? () => unawaited(_export(BackupMode.metadata))
                              : null,
                          child: const Text('改为元数据备份'),
                        ),
                      ),
                    ],
                    if (report != null) ...[
                      const SizedBox(height: 16),
                      _panel('备份已提交', [
                        Text(
                          report.mode == BackupMode.full
                              ? '完整备份'
                              : '元数据备份（不能恢复图片内容）',
                        ),
                        Text(
                          '${report.assets} 个资产 · ${report.versions} 个内容版本 · ${formatBytes(report.byteCount)}',
                        ),
                        SelectableText(p.basename(report.file.path)),
                        if (report.cleanupPending)
                          Text(
                            report.cleanupMessage ??
                                '备份已提交，但暂存或保护记录清理尚未完成。请保留资料库并重开核查。',
                          ),
                      ]),
                    ],
                    if (mobileReport != null) ...[
                      const SizedBox(height: 16),
                      _panel('备份已保存', [
                        Text(
                          mobileReport.mode == BackupMode.full
                              ? '完整备份'
                              : '元数据备份（不能恢复图片内容）',
                        ),
                        Text(
                          '${mobileReport.assets} 个资产 · ${mobileReport.versions} 个内容版本 · ${formatBytes(mobileReport.byteCount)}',
                        ),
                        SelectableText(mobileReport.name),
                        if (mobileReport.warning != null)
                          Text(mobileReport.warning!),
                      ]),
                    ],
                    const SizedBox(height: 20),
                    _panel('恢复备份', [
                      const Text(
                        '默认合并到当前资料库。选择 ZIP 后先校验备份并展示合并提议，确认后才提交。当前整理和回收状态保留。',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '备份内当前平台可用的设置会覆盖本机对应值；不适用项保留本机值并报告跳过。凭据、默认目标选择和本次会话上传许可不从备份恢复。',
                      ),
                      if (!restoreSupported) ...[
                        const SizedBox(height: 12),
                        const Text('此平台的原生备份恢复尚未接入，暂不能选择备份或恢复。'),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: restoreEnabled
                                ? () => unawaited(_restore())
                                : null,
                            icon: const Icon(Icons.restore_outlined),
                            label: const Text('选择备份并合并恢复'),
                          ),
                          OutlinedButton(
                            onPressed: restoreEnabled
                                ? () => unawaited(_restore(replacement: true))
                                : null,
                            child: const Text('选择备份并替换恢复'),
                          ),
                        ],
                      ),
                    ]),
                    if (restored != null) ...[
                      const SizedBox(height: 16),
                      _panel(restored.replaced ? '替换恢复已提交' : '合并恢复已提交', [
                        Text(
                          '${restored.replaced ? '新资料库包含' : '新增'} ${restored.report.addedAssets} 个资产 · ${restored.report.addedResults} 个普通结果 · ${restored.report.importedHistories} 条历史 · 保存 ${restored.report.savedCopies} 个图片副本',
                        ),
                        if (restored.replaced)
                          Text(
                            '已取消 ${restored.cancelledOldItems} 个旧上传意图。网络上传权限已重置，历史记录不能执行。',
                          ),
                        if (restored.report.metadataOnly)
                          const Text('本次为元数据恢复，不恢复图片字节；没有可用副本的图片显示缺失。'),
                        if (restored.report.settings case final settings?)
                          _SettingsRestoreSummary(settings, confirmed: true),
                        const Text('恢复账号保持禁用，须重新配置；已暂停的上传任务须手动恢复。'),
                        if (restored.cleanupPending)
                          const Text('恢复已提交，部分暂存或保护尚待清理。请保留资料库并重开核查。'),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(String title, List<Widget> children) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _ReplacementConfirmation extends StatefulWidget {
  const _ReplacementConfirmation({required this.preparation});
  final ReplacementRestorePreparation preparation;

  @override
  State<_ReplacementConfirmation> createState() =>
      _ReplacementConfirmationState();
}

class _ReplacementConfirmationState extends State<_ReplacementConfirmation> {
  bool _acceptedRisk = false;

  @override
  Widget build(BuildContext context) {
    final prepared = widget.preparation;
    final manifest = prepared.metadata;
    return AlertDialog(
      title: const Text('确认替换恢复'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '当前资料库：${prepared.currentAssets} 个资产 · ${prepared.currentFiles} 个已登记文件 · ${formatBytes(prepared.currentBytes)} 实际字节。已验证内部安全快照可用于恢复。',
              ),
              const SizedBox(height: 12),
              Text(
                manifest.mode == BackupMode.full
                    ? '模式：完整备份 → 替换恢复'
                    : '模式：元数据备份 → 替换恢复',
              ),
              Text(
                '替换后包含 ${manifest.assets.length} 个资产、${manifest.versions.length} 个永久版本、${manifest.results.length} 个普通结果、${manifest.history.length} 条终态历史。',
              ),
              const SizedBox(height: 12),
              const Text('当前整理信息、账号与凭据关联、临时处理结果将被替换，旧图片选择和操作草稿会清空。外部来源文件保留。'),
              const SizedBox(height: 8),
              Text(
                '将取消 ${prepared.cancelledOldItems} 个旧上传意图；历史记录不会成为待执行任务。上传须重新允许，暂停的任务不会自动恢复。',
              ),
              const SizedBox(height: 8),
              const Text('导入账号均保持禁用，须重新配置凭据；普通链接不恢复秘密管理能力。'),
              const SizedBox(height: 8),
              _SettingsRestoreSummary(prepared.settings),
              if (manifest.mode == BackupMode.metadata) ...[
                const SizedBox(height: 8),
                const Text('元数据备份不包含图片字节。替换后的图片副本记为缺失，不能沿用旧图片内容。'),
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('replacement-risk-consent'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _acceptedRisk,
                onChanged: (value) =>
                    setState(() => _acceptedRisk = value == true),
                title: const Text('我已了解替换风险，确认以此备份替换当前资料库。'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消恢复'),
        ),
        FilledButton(
          onPressed: _acceptedRisk ? () => Navigator.pop(context, true) : null,
          child: const Text('确认替换恢复'),
        ),
      ],
    );
  }
}

class _SettingsRestoreSummary extends StatelessWidget {
  const _SettingsRestoreSummary(this.plan, {this.confirmed = false});
  final BackupSettingsRestorePlan plan;
  final bool confirmed;

  String _value(BackupSetting setting) {
    final values = plan.values;
    return switch (setting) {
      BackupSetting.uploadConcurrency => '${values.uploadConcurrency}',
      BackupSetting.processingConcurrency => '${values.processingConcurrency}',
      BackupSetting.quality => '${values.quality}',
      BackupSetting.longestSide => '${values.longestSide} 像素',
      BackupSetting.processingMode =>
        values.processingMode.name == 'fidelity' ? '保真优先' : '体积优先',
      BackupSetting.cacheLimitMiB => '${values.cacheLimitMiB} MiB',
      BackupSetting.defaultOutputRetention =>
        switch (values.defaultOutputRetention.name) {
          'hour' => '1 小时',
          'day' => '24 小时',
          _ => '7 天',
        },
      BackupSetting.networkUploadPolicy =>
        values.networkUploadPolicy.name == 'wifiAndEthernet'
            ? '仅 Wi-Fi / 有线网络'
            : '所有已识别网络（含移动网络）',
    };
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        plan.included
            ? '${confirmed ? '已恢复' : '将覆盖'} ${plan.restored.length} 项可用设置；跳过 ${plan.skipped.length} 项。'
            : '此备份未包含设置，保留当前本机设置。',
      ),
      for (final setting in plan.restored)
        Text('${setting.label}：${_value(setting)}'),
      if (plan.included && plan.skipped.isNotEmpty)
        Text('当前平台不适用，保留本机值：${plan.skipped.map((s) => s.label).join('、')}。'),
      if (!confirmed) const Text('设置只在恢复成功后生效；不会改变已冻结任务的输入或授予上传许可。'),
    ],
  );
}

class _RestoreConfirmation extends StatefulWidget {
  const _RestoreConfirmation({
    required this.manifest,
    required this.plan,
    required this.settings,
  });
  final BackupManifest manifest;
  final BackupRestorePlan plan;
  final BackupSettingsRestorePlan settings;

  @override
  State<_RestoreConfirmation> createState() => _RestoreConfirmationState();
}

class _RestoreConfirmationState extends State<_RestoreConfirmation> {
  static const _pageSize = 20;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final manifest = widget.manifest;
    final plan = widget.plan;
    final permanent = plan.permanent.issues;
    final relations = plan.relationIssues;
    final count = permanent.length + relations.length;
    final blocking =
        permanent.where((i) => i.blocking).length +
        relations.where((i) => i.blocking).length;
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, count);
    return AlertDialog(
      title: const Text('确认合并恢复'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                manifest.mode == BackupMode.full
                    ? '模式：完整备份 → 合并恢复'
                    : '模式：元数据备份 → 合并恢复',
              ),
              const SizedBox(height: 8),
              Text(
                '备份包含 ${manifest.assets.length} 个资产、${manifest.versions.length} 个永久版本、${manifest.results.length} 个普通结果、${manifest.history.length} 条终态历史。',
              ),
              if (manifest.mode == BackupMode.metadata) ...[
                const SizedBox(height: 8),
                const Text('元数据备份不恢复图片字节。新增副本记为缺失；已有可用图片副本保留。'),
              ],
              const SizedBox(height: 8),
              const Text('当前已有整理和回收状态保留，不自动恢复回收图片。账号恢复为禁用待配置，不包含凭据或秘密管理链接。'),
              const SizedBox(height: 8),
              const Text('活动上传任务已暂停，完成或取消后均须手动恢复；备份历史不会变成待执行任务。'),
              const SizedBox(height: 8),
              _SettingsRestoreSummary(widget.settings),
              const SizedBox(height: 12),
              Text('合并提示：$count 条；阻断冲突：$blocking 条。'),
              if (!plan.canCommit) const Text('存在阻断冲突，不能确认恢复。请取消并处理冲突后重试。'),
              if (count > 0) ...[
                const SizedBox(height: 8),
                const Text('重映射或拒绝单条关联的提示不会覆盖当前记录；没有阻断冲突时可继续。'),
                for (var index = start; index < end; index++)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _issue(index, permanent.length),
                  ),
                const SizedBox(height: 8),
                Text('提示 ${start + 1}–$end / $count'),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _page > 0
                          ? () => setState(() => _page--)
                          : null,
                      child: const Text('上一页提示'),
                    ),
                    TextButton(
                      onPressed: end < count
                          ? () => setState(() => _page++)
                          : null,
                      child: const Text('下一页提示'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消恢复'),
        ),
        FilledButton(
          onPressed: plan.canCommit ? () => Navigator.pop(context, true) : null,
          child: const Text('确认合并恢复'),
        ),
      ],
    );
  }

  Widget _issue(int index, int permanentCount) {
    final BackupMergeIssue? permanentIssue = index < permanentCount
        ? widget.plan.permanent.issues[index]
        : null;
    final relationIssue = index >= permanentCount
        ? widget.plan.relationIssues[index - permanentCount]
        : null;
    final blocking = permanentIssue?.blocking ?? relationIssue!.blocking;
    final message = permanentIssue?.message ?? relationIssue!.message;
    final incomingId = permanentIssue?.incomingId ?? relationIssue!.incomingId;
    final targetId = permanentIssue?.targetId ?? relationIssue!.targetId;
    final extra = switch (permanentIssue?.kind) {
      BackupMergeIssueKind.tagLimitConflict => _tagLimitConflictDetails(
        permanentIssue!,
      ),
      BackupMergeIssueKind.versionDescriptionConflict =>
        _versionDescriptionConflictDetails(permanentIssue!),
      _ => const SizedBox.shrink(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${blocking ? '阻断' : '提示'}：$message'),
        if (permanentIssue?.kind == BackupMergeIssueKind.tagLimitConflict ||
            permanentIssue?.kind ==
                BackupMergeIssueKind.versionDescriptionConflict)
          Padding(padding: const EdgeInsets.only(top: 8), child: extra),
        SelectableText('恢复项 UUID：$incomingId\n当前 / 目标 UUID：$targetId'),
      ],
    );
  }

  Widget _tagLimitConflictDetails(BackupMergeIssue issue) {
    BackupAsset? findAsset(Iterable<BackupAsset> assets, String id) {
      for (final asset in assets) {
        if (asset.id == id) return asset;
      }
      return null;
    }

    String namesFor(Iterable<String> ids, Map<String, String> names) {
      final values = <String>[];
      var missing = false;
      for (final id in ids) {
        final name = names[id];
        if (name == null) {
          missing = true;
        } else {
          values.add(name);
        }
      }
      if (missing) return '标签名称资料不完整';
      return values.isEmpty ? '无' : values.join('、');
    }

    final incomingAsset = findAsset(widget.manifest.assets, issue.incomingId);
    final currentAsset = findAsset(
      widget.plan.permanent.assets,
      issue.targetId,
    );
    final incomingNames = {
      for (final tag in widget.manifest.tags) tag.id: tag.name,
    };
    final plannedNames = {
      for (final tag in widget.plan.permanent.tags) tag.id: tag.name,
    };
    final incomingTagIds = incomingAsset?.tagIds;
    final currentTagIds = currentAsset?.tagIds;
    final mappedIncomingIds = incomingTagIds
        ?.map((id) => widget.plan.permanent.tagIds[id])
        .toList();
    final unionCount =
        incomingTagIds != null &&
            currentTagIds != null &&
            mappedIncomingIds!.every((id) => id != null)
        ? <String>{...currentTagIds, ...mappedIncomingIds.cast<String>()}.length
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('规则：${issue.ruleIds.join(' / ')}。恢复来源与本机保留值：'),
        Text(
          '备份来源「${incomingAsset?.displayName ?? '资产名称资料不可用'}」：${incomingTagIds?.length ?? '数量不可用'} 个标签（${incomingTagIds == null ? '标签资料不可用' : namesFor(incomingTagIds, incomingNames)}）',
        ),
        Text(
          '本机保留值「${currentAsset?.displayName ?? '资产名称资料不可用'}」：${currentTagIds?.length ?? '数量不可用'} 个标签（${currentTagIds == null ? '标签资料不可用' : namesFor(currentTagIds, plannedNames)}）',
        ),
        Text(
          unionCount == null
              ? '并集数量无法从当前计划资料确认。'
              : '按 UUID 映射去重后的并集：$unionCount 个（上限 50 个）。',
        ),
        const SizedBox(height: 6),
        const Text(
          '请先取消本次恢复，在图库按当前名称和 UUID 核对本机标签；在本机或备份来源整理确认不需要的标签，使合并后标签不超过 50 个。整理备份来源后，请重新导出备份并预检。恢复不会截断标签、覆盖当前值或自动继续。',
        ),
      ],
    );
  }

  Widget _versionDescriptionConflictDetails(BackupMergeIssue issue) {
    ImageVersion? findVersion(Iterable<ImageVersion> versions, String id) {
      for (final version in versions) {
        if (version.id == id) return version;
      }
      return null;
    }

    String description(ImageVersion? version) => version == null
        ? '版本描述资料不可用'
        : '格式 ${version.format}，尺寸 ${version.width} × ${version.height}，方向 ${version.orientation}，SHA-256 ${version.sha256}，${version.byteCount} 字节';

    final incoming = findVersion(widget.manifest.versions, issue.incomingId);
    final current = findVersion(widget.plan.permanent.versions, issue.targetId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('备份来源版本：${description(incoming)}'),
        Text('本机保留版本：${description(current)}'),
        const SizedBox(height: 6),
        const Text(
          '请取消本次恢复，核对同 SHA-256 和字节数版本的格式、尺寸及方向，再重新导出有效备份包并预检。不要修改清单内容来凑成可提交。',
        ),
      ],
    );
  }
}
