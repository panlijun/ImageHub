import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network_state.dart';

import '../../accounts/domain/account_models.dart';
import '../../backup/domain/backup_manifest.dart';
import '../../diagnostics/domain/diagnostic_models.dart' show DiagnosticQuery;
import '../../diagnostics/presentation/diagnostics_screen.dart';
import '../../gallery/data/library_repository.dart';
import '../../gallery/domain/library_models.dart';
import '../../gallery/presentation/gallery_providers.dart';
import '../../processing/domain/output_models.dart';
import '../../processing/domain/processing_models.dart';
import '../domain/upload_processing_models.dart';
import '../domain/provider_models.dart';
import '../domain/link_format.dart';
import '../domain/queue_policy.dart';
import '../domain/upload_queue_models.dart';
import '../domain/upload_history.dart';
import 'upload_exit.dart';
import '../../links/application/link_transfer_coordinator.dart';
import '../../links/presentation/link_results_screen.dart';

/// A review screen. Opening it never grants permission to make a request.
class UploadTasksScreen extends ConsumerStatefulWidget {
  const UploadTasksScreen({
    super.key,
    this.initialOutputIds = const [],
    this.initialAssetIds = const [],
    this.initialOriginal = false,
    this.initialLibraryRevision,
  });
  final List<String> initialOutputIds;
  final List<String> initialAssetIds;
  final bool initialOriginal;
  final int? initialLibraryRevision;

  @override
  ConsumerState<UploadTasksScreen> createState() => _UploadTasksScreenState();
}

class _UploadTasksScreenState extends ConsumerState<UploadTasksScreen> {
  LibrarySession? _session;
  List<ProcessedOutput> _outputs = const [];
  List<ImageAsset> _assets = const [];
  final Map<String, ImageAsset> _selectedAssets = {};
  List<ProviderTarget> _targets = const [];
  List<UploadBatch> _batches = const [];
  List<RemoteUploadResult> _results = const [];
  List<UploadProcessingJob> _processingJobs = const [];
  List<BackupTaskHistory> _importedHistory = const [];
  final _historySelection = <UploadHistoryRef>{};
  bool _clearingHistory = false;
  Completer<bool>? _historyConfirmation;
  DialogRoute<bool>? _historyConfirmationRoute;
  NavigatorState? _historyConfirmationNavigator;
  DialogRoute<String>? _attemptsRoute;
  NavigatorState? _attemptsNavigator;
  bool _readingAttempts = false;
  final _outputIds = <String>{},
      _assetIds = <String>{},
      _targetIds = <String>{};
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _loading = true, _hasLoaded = false, _busy = false, _loadingMore = false;
  bool _original = false, _metadataConfirmed = false, _forceAgain = false;
  bool _automatic = true;
  ProcessingMode _processingMode = ProcessingMode.fidelity;
  ProcessingFormat _processingFormat = ProcessingFormat.png;
  int _processingQuality = 85, _processingLongestSide = 1600;
  bool _processingBackgroundConfirmed = false;
  bool _defaultsApplied = false;
  bool _initialSelectionApplied = false;
  int _revision = 0, _assetTotal = 0;
  String? _loadError;
  String? _shortcutFeedback;
  String _intentId = const Uuid().v4();
  _Submission? _submission;
  Future<void>? _activeMutation;
  late final AppLifecycleListener _lifecycle;

  List<ImageAsset> get _inputAssets {
    final assets = {for (final asset in _assets) asset.id: asset};
    assets.addAll(_selectedAssets);
    return assets.values.toList();
  }

  bool get _entryRevisionCurrent =>
      widget.initialLibraryRevision == null ||
      widget.initialLibraryRevision ==
          ref.read(libraryReplacementRevisionProvider);

  void _discardEntry() {
    _initialSelectionApplied = true;
    _selectedAssets.clear();
    _original = false;
    _automatic = true;
    _metadataConfirmed = false;
    _shortcutFeedback = '资料库已替换，请重新选择图片并确认上传参数。';
  }

  @override
  void initState() {
    super.initState();
    _original = widget.initialOriginal;
    _automatic = !widget.initialOriginal && widget.initialOutputIds.isEmpty;
    if (!_entryRevisionCurrent) _discardEntry();
    _lifecycle = AppLifecycleListener(onExitRequested: _exitRequested);
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      // Force attachment to the newly created queue actor, even though the
      // LibrarySession itself intentionally remains the same object.
      _session = null;
      _closeHistoryConfirmation();
      _closeAttemptsDialog();
      setState(() {
        _outputs = const [];
        _assets = const [];
        _targets = const [];
        _batches = const [];
        _results = const [];
        _processingJobs = const [];
        _importedHistory = const [];
        _historySelection.clear();
        _outputIds.clear();
        _assetIds.clear();
        _selectedAssets.clear();
        _initialSelectionApplied = true;
        _shortcutFeedback = '资料库已替换，请重新选择图片并确认上传参数。';
        _targetIds.clear();
        _submission = null;
        _intentId = const Uuid().v4();
        _metadataConfirmed = false;
        _forceAgain = false;
        _original = false;
        _automatic = true;
        _defaultsApplied = true;
        _hasLoaded = false;
        _assetTotal = 0;
      });
      unawaited(_reload());
    });
    unawaited(_reload());
  }

  @override
  void dispose() {
    _revision++;
    _closeHistoryConfirmation();
    _closeAttemptsDialog();
    _lifecycle.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    // The application owns the queue and library, including during navigation.
    super.dispose();
  }

  Future<AppExitResponse> _exitRequested() async {
    final showingAttempts = _attemptsRoute?.isActive == true;
    if (ModalRoute.of(context)?.isCurrent != true &&
        !_clearingHistory &&
        !showingAttempts) {
      return AppExitResponse.exit;
    }
    _closeAttemptsDialog();
    if (_clearingHistory) _closeHistoryConfirmation();
    await _activeMutation;
    if (!mounted) {
      return AppExitResponse.cancel;
    }
    final session = _session;
    if (session == null) {
      return AppExitResponse.exit;
    }
    return await requestLibraryExit(context, session)
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  void _attach(LibrarySession session) {
    if (identical(_session, session)) {
      return;
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _session = session;
    _subscriptions.add(
      session.repository.uploadChanges.listen((_) {
        unawaited(_reload());
      }),
    );
    _subscriptions.add(
      session.repository.accountChanges.listen((_) {
        unawaited(_reload());
      }),
    );
    _subscriptions.add(
      session.uploads.changes.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
    );
  }

  Future<void> _reload() async {
    final revision = ++_revision;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final session = await ref.read(librarySessionProvider.future);
      if (!mounted || revision != _revision) {
        return;
      }
      _attach(session);
      final repository = session.repository;
      final outputs = await repository.listOutputs();
      final assets = await repository.listAssets(limit: 60);
      final targets = await repository.listTargets();
      final batches = await repository.listUploadBatches();
      final results = await repository.listUploadResults();
      final processingJobs = await repository.listUploadProcessingJobs();
      final importedHistory = await repository.listImportedUploadHistories();
      final applyingInitial = !_initialSelectionApplied;
      final requested = (applyingInitial ? widget.initialAssetIds : _assetIds)
          .toSet();
      final selectedAssets = <String, ImageAsset>{};
      for (final id in requested) {
        final asset = await repository.getAsset(id);
        if (asset != null) selectedAssets[id] = asset;
      }
      if (!mounted || revision != _revision) {
        return;
      }
      setState(() {
        _outputs = outputs
            .where(
              (o) => o.usable && o.availability == CopyAvailability.available,
            )
            .toList();
        _assets = assets.items;
        _assetTotal = assets.total;
        _selectedAssets
          ..clear()
          ..addAll(selectedAssets);
        if (applyingInitial) {
          _initialSelectionApplied = true;
          final missing = requested.length - selectedAssets.length;
          if (!_entryRevisionCurrent) {
            _discardEntry();
          } else if (missing == 0) {
            _assetIds.addAll(requested);
          } else {
            _selectedAssets.clear();
            _shortcutFeedback = '快捷入口中 $missing 张图片已移除或进入回收区，未预选任何图片，请重新选择。';
          }
        }
        _targets = targets
            .where((t) => t.enabled && !t.removed && !t.pendingOperation)
            .toList();
        _batches = batches;
        _results = results;
        _processingJobs = processingJobs;
        _importedHistory = importedHistory;
        if (!_defaultsApplied) {
          _processingQuality = repository.currentDeviceSettings.quality;
          _processingLongestSide = repository.currentDeviceSettings.longestSide;
          _processingMode = repository.currentDeviceSettings.processingMode;
          _targetIds.addAll(
            _targets.where((t) => t.selectedByDefault).map((t) => t.id),
          );
          if (_entryRevisionCurrent) {
            _outputIds.addAll(
              widget.initialOutputIds.where(
                (id) => _outputs.any((o) => o.id == id),
              ),
            );
          }
          _defaultsApplied = true;
        }
        _loading = false;
        _hasLoaded = true;
      });
    } catch (_) {
      if (!mounted || revision != _revision) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = '上传资料读取失败，保留上次有效列表；请重试。';
      });
    }
  }

  Future<void> _loadMore() async {
    final session = _session;
    if (session == null ||
        _loadingMore ||
        _loading ||
        _assets.length >= _assetTotal) {
      return;
    }
    final revision = _revision;
    setState(() => _loadingMore = true);
    try {
      final page = await session.repository.listAssets(
        offset: _assets.length,
        limit: 60,
      );
      if (!mounted || revision != _revision) {
        return;
      }
      if (page.total != _assetTotal) {
        await _reload();
      } else {
        setState(() {
          final ids = _assets.map((a) => a.id).toSet();
          _assets = [..._assets, ...page.items.where((a) => ids.add(a.id))];
        });
      }
    } catch (_) {
      _feedback('下一页读取失败，已加载的原图仍保留。');
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _feedback(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<bool> _confirm(String title, String content, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final operation = _performMutation(action);
    _activeMutation = operation;
    await operation;
    if (identical(_activeMutation, operation)) {
      _activeMutation = null;
    }
  }

  Future<void> _performMutation(Future<void> Function() action) async {
    try {
      await action();
    } on UploadQueueFailure catch (error) {
      _feedback(error.message);
    } catch (_) {
      _feedback('操作未确认完成，请刷新核对后重试。已有记录仍保留。');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  bool get _canSubmit {
    if (_submission != null) {
      return _hasLoaded && !_loading && !_busy;
    }
    final source = _original || _automatic ? _assetIds : _outputIds;
    return _hasLoaded &&
        !_loading &&
        !_busy &&
        source.isNotEmpty &&
        _targetIds.isNotEmpty &&
        _missingTargets.isEmpty &&
        (_original || _automatic ? _missingAssets : _missingOutputs).isEmpty &&
        (!_original || _metadataConfirmed);
  }

  Set<String> get _missingTargets =>
      _targetIds.difference(_targets.map((t) => t.id).toSet());
  Set<String> get _missingAssets =>
      _assetIds.difference(_selectedAssets.keys.toSet());
  Set<String> get _missingOutputs =>
      _outputIds.difference(_outputs.map((o) => o.id).toSet());

  Future<void> _enqueue() => _mutate(() async {
    final session = _session!;
    // Keep the exact draft and UUID after an uncertain local commit. Retrying
    // can only recover that intent, never silently publish a changed draft.
    final submission = _submission ??= _Submission(
      assets: _original ? _assetIds.toList() : const [],
      outputs: _original || _automatic ? const [] : _outputIds.toList(),
      processing: _automatic
          ? [
              for (final id in _assetIds)
                UploadProcessingSelection(
                  assetIds: [id],
                  recipe: ProcessingRecipe(
                    operation: ProcessingOperation.compress,
                    mode: _processingMode,
                    outputFormat: _processingFormat,
                    longestSide: _processingLongestSide,
                    quality: _processingFormat == ProcessingFormat.png
                        ? null
                        : _processingQuality,
                    backgroundConfirmed: _processingBackgroundConfirmed,
                  ),
                ),
            ]
          : const [],
      targets: _targetIds.toList(),
      metadata: _metadataConfirmed,
      force: _forceAgain,
    );
    await session.repository.enqueueUploads(
      intentId: _intentId,
      assetIds: submission.assets,
      outputIds: submission.outputs,
      processing: submission.processing,
      targetIds: submission.targets,
      allowOriginalMetadata: submission.metadata,
      forceAgain: submission.force,
    );
    _intentId = const Uuid().v4();
    _submission = null;
    _forceAgain = false;
    _feedback('上传意图已持久入队。实际网络执行仍受授权及服务能力限制。');
    await _reload();
    await session.uploads.refresh();
  });

  Future<void> _network(bool enabled) async {
    if (_busy || _session == null) {
      return;
    }
    if (enabled &&
        !await _confirm(
          '允许本次会话网络上传？',
          '图片和上传所需凭据会发送给选定的第三方图床。仅本次会话有效；符合设置的网络恢复后会自动继续已确认任务。当前生产服务的精确大小及格式限制尚未核验，任务会等待能力确认，暂不能真正发起请求。',
          '允许上传',
        )) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _mutate(() async {
      await _session!.uploads.setNetworkAllowed(enabled);
      await _reload();
    });
  }

  Future<void> _abandonDraft() async {
    if (_busy || _submission == null) {
      return;
    }
    if (!await _confirm(
      '核对入队记录后重新选择？',
      '先检查本次意图是否已经保存。此操作不会取消任何已保存批次。只有确认尚未保存后才创建新意图；检查失败会继续保留当前选择供重试。',
      '核对记录',
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _mutate(() async {
      final batches = await _session!.repository.listUploadBatches();
      final existing = batches.where((b) => b.intentId == _intentId);
      if (existing.isNotEmpty) {
        _feedback(
          '原批次 ${_short(existing.first.id)} 已保存。请用“重试确认并入队”确认原记录；不会重新发布。',
        );
        await _reload();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _intentId = const Uuid().v4();
        _submission = null;
      });
      _feedback('已确认尚未保存，现可重新选择输入和目标。');
    });
  }

  Future<void> _again(bool enabled) async {
    if (enabled &&
        !await _confirm(
          '明确再次上传？',
          '默认复用相同输入和目标的成功结果。再次上传会创建新的发布项；若远端结果未知，请先核查，重复提交可能生成重复文件。',
          '确认再次上传',
        )) {
      return;
    }
    if (mounted) {
      setState(() => _forceAgain = enabled);
    }
  }

  Future<void> _cancel(UploadBatch batch) async {
    if (!await _confirm(
      '取消此批次？',
      '取消会停止本机继续派发并尝试停止执行。已发送的图片可能已在远端完成，取消不能删除远端文件，晚到确认会独立保留。',
      '确认取消',
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _mutate(() async {
      await _session!.uploads.cancelItems(
        batch.items.where((i) => !i.state.terminal).map((i) => i.id),
      );
      await _reload();
    });
  }

  Future<void> _attempts(UploadPublication item) async {
    final session = _session;
    if (session == null || _attemptsRoute != null || _readingAttempts) return;
    _readingAttempts = true;
    final epoch = session.repository.executionEpoch;
    final replacement = ref.read(libraryReplacementRevisionProvider);
    try {
      final attempts = await session.repository.listUploadAttempts(item.id);
      if (!mounted ||
          !identical(session, _session) ||
          epoch != session.repository.executionEpoch ||
          replacement != ref.read(libraryReplacementRevisionProvider)) {
        return;
      }
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('尝试记录'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: attempts.isEmpty
                    ? [const Text('尚未发起网络尝试。')]
                    : [
                        for (final attempt in attempts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '第 ${attempt.generation} 次 · ${attempt.id}\n'
                                  '开始：${_date(attempt.startedAt)}\n'
                                  '结束：${attempt.endedAt == null ? '尚未记录' : _date(attempt.endedAt!)}\n'
                                  '${attempt.requestMayHaveStarted ? '请求可能已发送，须核查远端副作用。' : '未记录请求已发送。'}\n'
                                  '结果：${_attemptOutcome(attempt.outcome)}',
                                ),
                                TextButton(
                                  key: ValueKey(
                                    'tasks-attempt-diagnostics-${attempt.id}',
                                  ),
                                  onPressed: () =>
                                      Navigator.of(context).pop(attempt.id),
                                  child: const Text('查看此次诊断'),
                                ),
                              ],
                            ),
                          ),
                      ],
              ),
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
      _attemptsRoute = route;
      _attemptsNavigator = navigator;
      final attemptId = await navigator.push(route);
      // The dialog owns this route. Wait until its overlay and transition have
      // actually ended before opening another shared screen.
      await route.completed;
      if (identical(_attemptsRoute, route)) {
        _attemptsRoute = null;
        _attemptsNavigator = null;
      }
      if (attemptId == null ||
          !mounted ||
          !identical(session, _session) ||
          epoch != session.repository.executionEpoch ||
          replacement != ref.read(libraryReplacementRevisionProvider) ||
          !attempts.any((attempt) => attempt.id == attemptId)) {
        return;
      }
      await _openDiagnostics(
        DiagnosticQuery(batchId: item.batchId, attemptId: attemptId),
      );
    } catch (_) {
      _closeAttemptsDialog();
      _feedback('尝试记录暂时无法读取，请重试。');
    } finally {
      _readingAttempts = false;
    }
  }

  void _closeAttemptsDialog() {
    final route = _attemptsRoute;
    final navigator = _attemptsNavigator;
    _attemptsRoute = null;
    _attemptsNavigator = null;
    if (route != null && navigator != null && route.isActive) {
      scheduleMicrotask(() {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
  }

  Future<void> _openDiagnostics(DiagnosticQuery query) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => DiagnosticsScreen(initialQuery: query)),
    );
  }

  Future<void> _copy(RemoteUploadResult result, UploadLinkFormat format) =>
      _mutate(() async {
        final session = _session;
        if (session == null || _loading || _loadError != null) return;
        final replacement = ref.read(libraryReplacementRevisionProvider);
        final plan = await session.repository.prepareVisibleLinkCopy([
          result.id,
        ], format);
        final report = await LinkTransferCoordinator(
          session.repository,
          ref.read(linkTransferGatewayProvider),
        ).copy(plan);
        if (mounted &&
            replacement == ref.read(libraryReplacementRevisionProvider)) {
          _feedback(report.message);
        }
      });

  bool get _historyReady =>
      _hasLoaded &&
      !_loading &&
      _loadError == null &&
      !_busy &&
      _submission == null;

  void _closeHistoryConfirmation() {
    final pending = _historyConfirmation;
    _historyConfirmation = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    final route = _historyConfirmationRoute;
    final navigator = _historyConfirmationNavigator;
    _historyConfirmationRoute = null;
    _historyConfirmationNavigator = null;
    if (route != null && navigator != null && route.isActive) {
      scheduleMicrotask(() {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
  }

  Future<bool> _reviewHistoryClear(UploadHistoryClearPlan plan) async {
    if (!mounted) return false;
    final pending = Completer<bool>();
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理已选历史？'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '可清理 ${plan.eligibleCount} 项；另有 ${plan.preserved.length} 项保留。',
              ),
              const SizedBox(height: 8),
              const Text(
                '仅移除下面的任务摘要和尝试记录。图片、普通链接和账号凭据保留，不请求远端删除。新增完成项不会自动加入本次清理。',
              ),
              for (final item in plan.eligible)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${item.displayName}\n${item.target.alias} · ${_service(item.target.service)} · ${_publishState(item.state)}\n${item.reference.kind == UploadHistoryKind.imported ? '恢复历史' : '本机任务'} · ${_date(item.updatedAt)}',
                  ),
                ),
              for (final item in plan.preserved)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '保留 ${_short(item.reference.id)}：${_historyProtection(item.reason)}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回'),
          ),
          FilledButton(
            key: const Key('upload-history-confirm-clear'),
            onPressed: plan.eligibleCount == 0
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('确认清理历史'),
          ),
        ],
      ),
    );
    _historyConfirmation = pending;
    _historyConfirmationRoute = route;
    _historyConfirmationNavigator = navigator;
    unawaited(
      navigator.push(route).then((accepted) {
        if (!pending.isCompleted) pending.complete(accepted == true);
        if (identical(_historyConfirmation, pending)) {
          _historyConfirmation = null;
          _historyConfirmationRoute = null;
          _historyConfirmationNavigator = null;
        }
      }),
    );
    return pending.future;
  }

  Future<void> _clearSelectedHistory() async {
    if (!_historyReady || _historySelection.isEmpty || _session == null) return;
    final selected = List<UploadHistoryRef>.unmodifiable(_historySelection);
    final session = _session!;
    final replacement = ref.read(libraryReplacementRevisionProvider);
    await _mutate(() async {
      _clearingHistory = true;
      try {
        final plan = await session.repository.prepareUploadHistoryClear(
          publicationIds: selected
              .where((r) => r.kind == UploadHistoryKind.publication)
              .map((r) => r.id),
          importedHistoryIds: selected
              .where((r) => r.kind == UploadHistoryKind.imported)
              .map((r) => r.id),
        );
        if (!mounted ||
            replacement != ref.read(libraryReplacementRevisionProvider)) {
          return;
        }
        if (!await _reviewHistoryClear(plan)) return;
        if (!mounted ||
            replacement != ref.read(libraryReplacementRevisionProvider)) {
          return;
        }
        final result = await session.repository.clearUploadHistory(
          plan,
          confirmHistoryRemoval: true,
        );
        if (!mounted ||
            replacement != ref.read(libraryReplacementRevisionProvider)) {
          return;
        }
        setState(
          () => _historySelection.removeAll(
            plan.eligible.map((item) => item.reference),
          ),
        );
        await _reload();
        _feedback(
          '已清理 ${result.removedCount} 项历史，保留 ${result.preservedCount} 项。图片与普通结果保留。',
        );
      } finally {
        _clearingHistory = false;
      }
    });
  }

  void _selectCompletedHistory() {
    if (!_historyReady) return;
    setState(() {
      _historySelection.addAll([
        for (final batch in _batches)
          for (final item in batch.items)
            if (item.state.terminal)
              UploadHistoryRef(UploadHistoryKind.publication, item.id),
        for (final item in _importedHistory)
          UploadHistoryRef(UploadHistoryKind.imported, item.id),
      ]);
    });
  }

  Widget _historyCheckbox(UploadHistoryRef reference) => CheckboxListTile(
    key: ValueKey('upload-history-${reference.kind.name}-${reference.id}'),
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: const Text('选择此项历史'),
    value: _historySelection.contains(reference),
    onChanged: _historyReady
        ? (selected) => setState(
            () => selected == true
                ? _historySelection.add(reference)
                : _historySelection.remove(reference),
          )
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final editable = !_busy && _submission == null;
    final page = Scaffold(
      appBar: AppBar(
        title: const Text('上传任务'),
        actions: [
          IconButton(
            tooltip: '刷新上传资料',
            onPressed: _loading || _busy
                ? null
                : () => _mutate(() async {
                    try {
                      await _session?.refreshNetwork();
                    } finally {
                      // Observation failure must not skip the independent
                      // library read or hide its last-valid-list feedback.
                      await _reload();
                    }
                  }),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final selection = _selection(editable);
            final records = _records();
            return SingleChildScrollView(
              padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('先确认输入和目标，再创建持久上传意图。离开页面后任务仍由应用管理。'),
                  const SizedBox(height: 12),
                  if (_loading) const LinearProgressIndicator(),
                  if (_loadError != null) _notice(_loadError!),
                  if (_shortcutFeedback != null) _notice(_shortcutFeedback!),
                  if (_session?.uploads.failure case final String failure)
                    _notice(failure),
                  if (_session?.existingUploadProcessing?.failure
                      case final String failure)
                    _notice(failure),
                  const SizedBox(height: 16),
                  if (constraints.maxWidth >= 980)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 360, child: selection),
                        const SizedBox(width: 24),
                        Expanded(child: records),
                      ],
                    )
                  else ...[
                    selection,
                    const SizedBox(height: 24),
                    records,
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
    return PopScope(canPop: !_busy, child: page);
  }

  Widget _selection(bool editable) => _panel('新建上传', [
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('允许本次会话网络上传'),
      subtitle: const Text('仅本次会话有效；网络符合设置后自动继续已确认任务。关闭停止网络执行，保留上传意图。'),
      value: _session?.uploads.networkAllowed ?? false,
      onChanged: _busy || _session == null ? null : _network,
    ),
    Text(
      '当前网络：${_session?.uploads.networkSnapshot.label ?? '网络状态未确认'}。'
      '策略：${_session?.uploads.networkPolicy == NetworkUploadPolicy.anyKnownNetwork ? '所有已识别网络（含移动网络）' : '仅 Wi-Fi / 有线网络'}。',
      key: const ValueKey('tasks-network-status'),
    ),
    if (_session != null && !_session!.uploads.networkEligible)
      _notice('当前网络不符合设置或尚未确认，任务等待；网络恢复后仍需本次会话上传许可。'),
    _notice('Catbox / ImgBB 精确字节及格式能力待核验。当前任务可入队，但暂不能真正请求。'),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('上传前自动处理'),
          selected: _automatic,
          onSelected: editable
              ? (_) => setState(() {
                  _automatic = true;
                  _original = false;
                  _metadataConfirmed = false;
                })
              : null,
        ),
        ChoiceChip(
          label: const Text('已确认处理结果'),
          selected: !_original && !_automatic,
          onSelected: editable
              ? (_) => setState(() {
                  _original = false;
                  _automatic = false;
                  _metadataConfirmed = false;
                })
              : null,
        ),
        ChoiceChip(
          label: const Text('图库原图'),
          selected: _original,
          onSelected: editable
              ? (_) => setState(() {
                  _original = true;
                  _automatic = false;
                  _metadataConfirmed = false;
                })
              : null,
        ),
      ],
    ),
    const SizedBox(height: 12),
    if (_automatic) ...[
      const Text(
        '逐张按确认参数处理并去除位置、设备等元数据。就绪图片可先上传，处理失败不会改用原图。动画或颜色无法保留时停止，请在图片处理工作台明确选择转换。',
      ),
      DropdownButton<ProcessingMode>(
        key: const Key('upload-processing-mode'),
        isExpanded: true,
        isDense: false,
        itemHeight: null,
        value: _processingMode,
        items: const [
          DropdownMenuItem(
            value: ProcessingMode.fidelity,
            child: Text('保真优先：保留尺寸、透明和颜色'),
          ),
          DropdownMenuItem(
            value: ProcessingMode.sizeFirst,
            child: Text('体积优先：按最长边缩小'),
          ),
        ],
        onChanged: editable
            ? (v) => setState(() => _processingMode = v!)
            : null,
      ),
      DropdownButton<ProcessingFormat>(
        key: const Key('upload-processing-format'),
        isExpanded: true,
        isDense: false,
        itemHeight: null,
        value: _processingFormat,
        items: [
          for (final format in ProcessingFormat.values)
            DropdownMenuItem(
              value: format,
              child: Text(format.name.toUpperCase()),
            ),
        ],
        onChanged: editable
            ? (v) => setState(() {
                _processingFormat = v!;
                _processingBackgroundConfirmed = false;
              })
            : null,
      ),
      if (_processingMode == ProcessingMode.sizeFirst) ...[
        Text('最长边：$_processingLongestSide 像素'),
        Slider(
          value: _processingLongestSide.toDouble(),
          min: 1,
          max: 16384,
          onChanged: editable
              ? (v) => setState(() => _processingLongestSide = v.round())
              : null,
        ),
      ],
      if (_processingFormat != ProcessingFormat.png) ...[
        Text('有损质量：$_processingQuality'),
        Slider(
          value: _processingQuality.toDouble(),
          min: 1,
          max: 100,
          onChanged: editable
              ? (v) => setState(() => _processingQuality = v.round())
              : null,
        ),
      ],
      if (_processingFormat == ProcessingFormat.jpeg)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('如存在透明区域，我确认使用白色背景'),
          value: _processingBackgroundConfirmed,
          onChanged: editable
              ? (v) =>
                    setState(() => _processingBackgroundConfirmed = v ?? false)
              : null,
        ),
    ],
    if (_original || _automatic) ...[
      if (_original) ...[
        const Text('原图可能保留位置、设备等元数据。仅选择已经加载的图片。'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('我确认上传原图，可能包含位置、设备等元数据'),
          value: _metadataConfirmed,
          onChanged: editable
              ? (v) => setState(() => _metadataConfirmed = v ?? false)
              : null,
        ),
      ],
      if (_assets.isEmpty) const Text('没有可选原图。'),
      for (final asset in _inputAssets)
        _sourceTile(
          asset.id,
          asset.displayName,
          asset.version,
          _assetIds,
          editable && !_loading,
        ),
      Text('已加载 ${_assets.length} / $_assetTotal 张；已选 ${_assetIds.length} 张'),
      if (_assets.length < _assetTotal)
        TextButton(
          onPressed: editable && !_loading && !_loadingMore ? _loadMore : null,
          child: Text(_loadingMore ? '正在读取…' : '加载更多原图'),
        ),
    ] else ...[
      const Text('只列出 ready 且文件已验证可用的处理结果。共享处理引擎会移除元数据。'),
      if (_outputs.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('没有可用的处理结果。请先在处理工作台确认结果。'),
        ),
      for (final output in _outputs)
        _sourceTile(
          output.id,
          output.displayName,
          output.version!,
          _outputIds,
          editable,
        ),
      Text('已选 ${_outputIds.length} 个处理结果'),
    ],
    const Divider(height: 28),
    if ((_original || _automatic ? _missingAssets : _missingOutputs)
        .isNotEmpty) ...[
      _notice(
        _original || _automatic
            ? '已选 ${_missingAssets.length} 张图片已移除或进入回收区，入队已禁用；请重新加载确认或明确移除。'
            : '当前输入列表之外还保留 ${_missingOutputs.length} 个选择，请重新加载确认或明确移除后提交。',
      ),
      TextButton(
        onPressed: editable
            ? () => setState(() {
                if (_original || _automatic) {
                  _assetIds.removeAll(_missingAssets);
                } else {
                  _outputIds.removeAll(_missingOutputs);
                }
              })
            : null,
        child: const Text('移除当前列表之外的输入选择'),
      ),
    ],
    Text('上传目标', style: Theme.of(context).textTheme.titleSmall),
    if (_targets.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('没有可用账号目标。请先到账号配置添加或启用目标。'),
      ),
    for (final target in _targets)
      CheckboxListTile(
        key: ValueKey('upload-target-${target.id}'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(target.alias),
        subtitle: Text(
          '${_service(target.service)} · ${_short(target.id)}${target.anonymous ? ' · 匿名' : ''}',
        ),
        value: _targetIds.contains(target.id),
        onChanged: editable
            ? (v) => setState(
                () => v == true
                    ? _targetIds.add(target.id)
                    : _targetIds.remove(target.id),
              )
            : null,
      ),
    if (_missingTargets.isNotEmpty) ...[
      _notice('有 ${_missingTargets.length} 个已选目标当前不可选。请核对目标配置，或明确移除这些选择。'),
      TextButton(
        onPressed: editable
            ? () => setState(() => _targetIds.removeAll(_missingTargets))
            : null,
        child: const Text('移除当前不可选的目标选择'),
      ),
    ],
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text('明确再次上传（默认复用成功结果）'),
      value: _forceAgain,
      onChanged: editable ? (v) => _again(v ?? false) : null,
    ),
    if (_submission != null && !_busy)
      _notice('上次入队未确认。保留原选择和同一意图，请重试以核对持久记录。'),
    if (_submission != null)
      TextButton(
        onPressed: _busy ? null : _abandonDraft,
        child: const Text('放弃本次入队意图，重新选择'),
      ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: _canSubmit ? _enqueue : null,
      child: Text(
        _busy
            ? '正在确认…'
            : _submission != null
            ? '重试确认并入队'
            : '确认并入队',
      ),
    ),
  ]);

  Widget _sourceTile(
    String id,
    String name,
    ImageVersion version,
    Set<String> selected,
    bool editable,
  ) => CheckboxListTile(
    key: ValueKey('upload-source-$id'),
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(name),
    subtitle: Text(
      '${version.format.toUpperCase()} · ${_bytes(version.byteCount)} · 版本 ${_short(version.id)}',
    ),
    value: selected.contains(id),
    onChanged: editable
        ? (v) => setState(() {
            if (v == true) {
              if (identical(selected, _assetIds)) {
                final asset = _inputAssets
                    .where((asset) => asset.id == id)
                    .firstOrNull;
                if (asset == null) return;
                _selectedAssets[id] = asset;
              }
              selected.add(id);
            } else {
              selected.remove(id);
            }
          })
        : null,
  );

  Widget _records() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_processingJobs.isNotEmpty) ...[
        _panel('上传前处理', [
          for (final job in _processingJobs)
            ListTile(
              title: Text(
                '处理 ${_short(job.id)} · ${switch (job.state) {
                  UploadProcessingState.queued => '等待处理',
                  UploadProcessingState.running => '正在处理',
                  UploadProcessingState.waiting => '等待修复来源',
                  UploadProcessingState.ready => '结果已确认',
                  UploadProcessingState.failed => '处理失败，依赖已跳过',
                  UploadProcessingState.cancelled => '已取消',
                }}',
              ),
              subtitle: job.message == null ? null : Text(job.message!),
              trailing: job.state != UploadProcessingState.waiting
                  ? null
                  : TextButton(
                      onPressed: _busy
                          ? null
                          : () => _mutate(() async {
                              await _session!.repository
                                  .retryUploadProcessingJob(job.id);
                              await _session!.existingUploadProcessing
                                  ?.refresh();
                              await _reload();
                            }),
                      child: const Text('修复后重试'),
                    ),
            ),
        ]),
        const SizedBox(height: 20),
      ],
      _panel('持久任务', [
        const Text('清理完成历史不会删除图片或普通结果；仍在执行、结果未知或仍有依赖的记录会保留。'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton(
              key: const Key('upload-history-select-completed'),
              onPressed: _historyReady ? _selectCompletedHistory : null,
              child: const Text('选择已结束记录'),
            ),
            TextButton(
              onPressed: !_busy && _historySelection.isNotEmpty
                  ? () => setState(_historySelection.clear)
                  : null,
              child: const Text('清空历史选择'),
            ),
            FilledButton(
              key: const Key('upload-history-clear-selected'),
              onPressed: _historyReady && _historySelection.isNotEmpty
                  ? _clearSelectedHistory
                  : null,
              child: Text('清理已选历史（${_historySelection.length}）'),
            ),
          ],
        ),
        if (!_batches.any((batch) => batch.items.isNotEmpty))
          const Text('还没有上传任务。'),
        for (final batch in _batches.where((batch) => batch.items.isNotEmpty))
          _batch(batch),
      ]),
      const SizedBox(height: 20),
      _panel('恢复的完成历史', [
        const Text('这些记录只供查阅，不会重新上传。'),
        if (_importedHistory.isEmpty) const Text('还没有恢复历史。'),
        for (final item in _importedHistory) _importedRecord(item),
      ]),
      const SizedBox(height: 20),
      _panel('普通结果', [
        const Text('仅在远端确认且本机结果持久提交后列出。管理秘密不会显示或复制。'),
        if (_results.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('还没有已确认结果。'),
          ),
        for (final result in _results)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.input.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${result.target.alias} · ${_service(result.target.service)} · ${_short(result.target.id)}',
                ),
                Text(
                  '${_date(result.confirmedAt)} · 版本 ${_short(result.input.version.id)}',
                ),
                if (result.late) _notice('晚到远端确认：不会覆盖已经记录的取消或中断意图。'),
                if (result.usesInsecureHttp)
                  _notice('此普通链接使用 HTTP，传输可能被观察或篡改。'),
                SelectableText(result.directUrl.toString()),
                PopupMenuButton<UploadLinkFormat>(
                  enabled:
                      _hasLoaded && !_loading && _loadError == null && !_busy,
                  tooltip: '复制普通链接',
                  onSelected: (format) => _copy(result, format),
                  itemBuilder: (context) => [
                    for (final format in UploadLinkFormat.values)
                      PopupMenuItem(
                        value: format,
                        child: Text(switch (format) {
                          UploadLinkFormat.url => '普通直链',
                          UploadLinkFormat.markdown => 'Markdown',
                          UploadLinkFormat.html => 'HTML',
                          UploadLinkFormat.bbcode => 'BBCode',
                        }),
                      ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('复制普通链接 ▾'),
                  ),
                ),
              ],
            ),
          ),
      ]),
    ],
  );

  Widget _batch(UploadBatch batch) {
    final summary = batch.summary;
    final canPause = batch.items.any(
      (i) => i.state != PublishState.unknown && !i.state.terminal,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '批次 ${_short(batch.id)} · ${_batchState(summary.state)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text('${_date(batch.createdAt)}${batch.paused ? ' · 已暂停派发' : ''}'),
          Text(
            '总计 ${summary.total} · 成功 ${summary.succeeded} · 失败 ${summary.failed} · 取消 ${summary.cancelled} · 未知 ${summary.unknown} · 活动 ${summary.active}',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                key: ValueKey('tasks-diagnostics-${batch.id}'),
                onPressed: !_busy
                    ? () => _openDiagnostics(DiagnosticQuery(batchId: batch.id))
                    : null,
                child: const Text('查看批次诊断'),
              ),
              TextButton(
                key: ValueKey('tasks-pause-batch-${batch.id}'),
                onPressed: !_busy && canPause
                    ? () => _mutate(() async {
                        await _session!.uploads.pauseBatch(
                          batch.id,
                          !batch.paused,
                        );
                        await _reload();
                      })
                    : null,
                child: Text(batch.paused ? '恢复派发' : '暂停派发'),
              ),
              TextButton(
                onPressed: !_busy && batch.items.any((i) => !i.state.terminal)
                    ? () => _cancel(batch)
                    : null,
                child: const Text('取消批次'),
              ),
            ],
          ),
          for (final item in batch.items)
            _item(item, batchPaused: batch.paused),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _item(UploadPublication item, {required bool batchPaused}) {
    final activity = _session?.uploads.progress[item.id]?.activity;
    final canPause = switch (item.state) {
      PublishState.queued ||
      PublishState.waiting ||
      PublishState.paused ||
      PublishState.interrupted => true,
      _ => false,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _historyCheckbox(
            UploadHistoryRef(UploadHistoryKind.publication, item.id),
          ),
          Text(
            item.input.displayName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${item.processingPending ? '冻结处理来源，尚未上传 · ' : ''}${item.input.version.format.toUpperCase()} · ${_bytes(item.input.version.byteCount)} · 版本 ${_short(item.input.version.id)}',
          ),
          Text(
            '${item.target.alias} · ${_service(item.target.service)} · ${_short(item.target.id)}',
          ),
          Text('${_publishState(item.state)} · 尝试 ${item.attemptCount} 次'),
          if (item.userPaused && canPause) _notice('本项已单独暂停。恢复整批不会恢复本项。'),
          if (batchPaused && item.state == PublishState.running)
            _notice('整批已暂停后续派发；本项正在运行，允许正常完成。'),
          if (item.input.processingSummary case final String summary)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('处理参数快照'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(summary),
                ),
              ],
            ),
          if (item.waitReason != null) Text(_wait(item.waitReason!)),
          if (item.message != null) Text(item.message!),
          if (item.state == PublishState.unknown)
            _notice('远端结果未知。请先核查；不能普通继续。确认需要重新发布时，选相同输入并明确再次上传。'),
          if (activity != null)
            Text(
              '${activity.direction == UploadActivityDirection.sending ? '已发送' : '已接收'} ${_bytes(activity.bytes)}${activity.totalBytes == null ? '（总量未知）' : ' / ${_bytes(activity.totalBytes!)}'}',
            ),
          if (canPause)
            TextButton(
              key: ValueKey('tasks-pause-item-${item.id}'),
              onPressed: !_busy
                  ? () => _mutate(() async {
                      final paused = !item.userPaused;
                      await _session!.uploads.pauseItem(item.id, paused);
                      await _reload();
                      _feedback(
                        paused
                            ? '本项已暂停后续派发，其他项继续按条件执行。'
                            : batchPaused
                            ? '本项暂停已解除；整批仍暂停，暂不派发。'
                            : '本项暂停已解除；满足网络、授权及退避条件后派发。',
                      );
                    })
                  : null,
              child: Text(item.userPaused ? '继续本项' : '暂停本项'),
            ),
          TextButton(
            key: ValueKey('tasks-attempts-${item.id}'),
            onPressed: () => _attempts(item),
            child: const Text('查看尝试记录'),
          ),
        ],
      ),
    );
  }

  Widget _importedRecord(BackupTaskHistory item) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _historyCheckbox(UploadHistoryRef(UploadHistoryKind.imported, item.id)),
        Text(
          item.input.displayName,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          '${item.target.alias} · ${_service(item.target.service)} · ${_publishState(item.state)}',
        ),
        Text(
          '${item.input.version.format} · ${_bytes(item.input.version.byteCount)} · 版本 ${_short(item.input.version.id)}',
        ),
        Text(
          '记录时间：${_date(DateTime.fromMillisecondsSinceEpoch(item.updatedUtc, isUtc: true))}',
        ),
        if (item.input.processingSummary case final String summary)
          ExpansionTile(
            title: const Text('处理参数快照'),
            children: [SelectableText(summary)],
          ),
        ExpansionTile(
          title: const Text('恢复的尝试记录'),
          children: [
            if (item.attempts.isEmpty) const Text('没有网络尝试记录。'),
            for (final attempt in item.attempts)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '第 ${attempt.generation} 次 · ${_short(attempt.id)}\n开始：${_date(DateTime.fromMillisecondsSinceEpoch(attempt.startedUtc, isUtc: true))}\n结束：${_date(DateTime.fromMillisecondsSinceEpoch(attempt.endedUtc, isUtc: true))}\n结果：${_attemptOutcome(attempt.outcome)}',
                ),
              ),
          ],
        ),
        if (item.message != null) Text(item.message!),
        const Divider(),
      ],
    ),
  );

  Widget _panel(String title, List<Widget> children) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _Submission {
  _Submission({
    required this.assets,
    required this.outputs,
    required this.targets,
    required this.metadata,
    required this.force,
    this.processing = const [],
  });
  final List<String> assets, outputs, targets;
  final bool metadata, force;
  final List<UploadProcessingSelection> processing;
}

String _short(String value) => value.length > 8 ? value.substring(0, 8) : value;
String _service(ImageHostService service) =>
    service == ImageHostService.catbox ? 'Catbox' : 'ImgBB';
String _bytes(int value) => value < 1024
    ? '$value B'
    : value < 1024 * 1024
    ? '${(value / 1024).toStringAsFixed(1)} KiB'
    : '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
String _date(DateTime value) =>
    value.toLocal().toIso8601String().split('.').first.replaceFirst('T', ' ');
String _publishState(PublishState state) => switch (state) {
  PublishState.queued => '已排队',
  PublishState.waiting => '等待条件',
  PublishState.running => '正在执行',
  PublishState.paused => '已暂停',
  PublishState.interrupted => '已中断',
  PublishState.unknown => '结果未知',
  PublishState.succeeded => '已成功',
  PublishState.failed => '已失败',
  PublishState.cancelled => '已取消',
};
String _batchState(BatchState state) => switch (state) {
  BatchState.active => '活动中',
  BatchState.needsConfirmation => '待确认',
  BatchState.succeeded => '全部成功',
  BatchState.partiallySucceeded => '部分成功',
  BatchState.cancelled => '全部取消',
  BatchState.failed => '已失败',
};
String _wait(QueueWaitReason reason) => switch (reason) {
  QueueWaitReason.processing => '等待已确认的上传前处理结果，不会改用原图。',
  QueueWaitReason.network => '等待本次会话上传许可及符合设置的网络。',
  QueueWaitReason.authorization => '等待目标授权恢复。',
  QueueWaitReason.inputUnavailable => '输入文件暂不可用，请核查本机文件。',
  QueueWaitReason.capabilityUnknown => '服务精确大小及格式限制尚未核验，暂不能派发。',
  QueueWaitReason.retry => '等待已记录的重试间隔，不会提前重新发送。',
  QueueWaitReason.system => '等待系统条件恢复。',
};
String _attemptOutcome(String? outcome) => switch (outcome) {
  'succeeded' || 'success' => '远端确认成功',
  'failed' || 'failure' => '失败',
  'cancelled' => '已取消',
  'interrupted' => '已中断',
  'unknown' => '远端结果未知',
  null => '尚未记录',
  _ => '已记录结果，请结合任务状态核查',
};

String _historyProtection(UploadHistoryProtection reason) => switch (reason) {
  UploadHistoryProtection.active => '任务尚未结束或结果未知',
  UploadHistoryProtection.inputInUse => '图片仍在使用，请等待实际操作结束',
  UploadHistoryProtection.pendingResult => '结果关联或管理信息仍在收尾',
  UploadHistoryProtection.retainedDependency => '仍有任务依赖，暂不能清理',
  UploadHistoryProtection.missing => '记录已不存在，请核对选择',
};
