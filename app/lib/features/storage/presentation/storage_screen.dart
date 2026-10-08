import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../diagnostics/presentation/diagnostics_screen.dart';
import '../../gallery/data/library_repository.dart';
import '../../gallery/presentation/gallery_providers.dart';
import '../../upload/presentation/upload_exit.dart';
import '../domain/storage_models.dart';

/// The same physical storage view is used by desktop and M1 settings.
class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  LibrarySession? _session;
  StorageReport? _report;
  AppLifecycleListener? _lifecycle;
  Future<void>? _operation;
  Completer<bool>? _confirmation;
  DialogRoute<bool>? _confirmationRoute;
  NavigatorState? _confirmationNavigator;
  int _revision = 0;
  bool _loading = true, _busy = false, _cancelRequested = false;
  String? _error, _feedback;

  bool get _enabled => !_loading && !_busy && _error == null && _report != null;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _exitRequested);
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      unawaited(_afterReplacement());
    });
    unawaited(_reload());
  }

  Future<void> _afterReplacement() async {
    final revision = ++_revision;
    _cancel();
    setState(() {
      _report = null;
      _feedback = null;
      _error = null;
      _loading = true;
    });
    // A commit already started must settle before using the replacement view.
    await _operation;
    if (mounted && revision == _revision) await _reload();
  }

  Future<AppExitResponse> _exitRequested() async {
    if (ModalRoute.of(context)?.isCurrent != true && !_busy) {
      return AppExitResponse.exit;
    }
    _cancel();
    await _operation;
    if (!mounted) return AppExitResponse.cancel;
    final session = _session;
    return session == null || await requestLibraryExit(context, session)
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  @override
  void dispose() {
    _revision++;
    _lifecycle?.dispose();
    _cancel();
    // Keep the real cleanup Future alive; navigation never releases file IO.
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await ref.read(librarySessionProvider.future);
      if (!mounted || revision != _revision) return;
      _session = session;
      final epoch = session.repository.executionEpoch;
      final report = await session.repository.loadStorageReport();
      if (!mounted ||
          revision != _revision ||
          epoch != session.repository.executionEpoch) {
        return;
      }
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _loading = false;
        _error = '空间读取失败，最后有效视图保留；请重新读取。';
      });
    }
  }

  void _cancel() {
    _cancelRequested = true;
    _closeConfirmation();
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
      scheduleMicrotask(() {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
  }

  void _resolveConfirmation(bool accepted) {
    final pending = _confirmation;
    if (pending != null && !pending.isCompleted) pending.complete(accepted);
    _closeConfirmation();
  }

  Future<bool> _confirm({required String title, required String scope}) {
    if (!mounted || _cancelRequested) return Future.value(false);
    final pending = Completer<bool>();
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(scope)),
        actions: [
          TextButton(
            key: const Key('storage-confirm-cancel'),
            onPressed: () => _resolveConfirmation(false),
            child: const Text('返回'),
          ),
          FilledButton(
            key: const Key('storage-confirm'),
            onPressed: () => _resolveConfirmation(true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );
    _confirmation = pending;
    _confirmationRoute = route;
    _confirmationNavigator = navigator;
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

  void _start(bool thumbnails) {
    if (!_enabled) return;
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _feedback = null;
    });
    _operation = _perform(thumbnails);
  }

  Future<void> _perform(bool thumbnails) async {
    final session = _session!;
    final revision = _revision, epoch = session.repository.executionEpoch;
    bool current() =>
        mounted &&
        revision == _revision &&
        epoch == session.repository.executionEpoch;
    try {
      if (thumbnails) {
        final plan = await session.repository.prepareThumbnailCleanup();
        if (!current() || _cancelRequested) return;
        if (plan.count == 0) {
          setState(() => _feedback = '没有可安全清理的已登记缩略图；受保护和未登记文件保留。');
          return;
        }
        final accepted = await _confirm(
          title: '确认清理缩略图缓存',
          scope:
              '已冻结 ${plan.count} 个缩略图，${_bytes(plan.bytes)}。'
              '后来新增文件不会加入。\n'
              '${plan.protectedCount} 个受保护项和 ${_bytes(plan.untrackedBytes)} 未登记文件保留；'
              '执行时重新核对，篡改或新增保护的项不删除。\n'
              '仅清理可再生缩略图，不删除原图、永久副本、临时输出或诊断日志。',
        );
        if (!accepted || !current() || _cancelRequested) return;
        // Once accepted, wait for actual repository IO even on exit/dispose.
        final result = await session.repository.clearThumbnails(plan);
        if (!current()) return;
        setState(
          () => _feedback =
              '已清理 ${result.removed} 个缩略图，释放 ${_bytes(result.removedBytes)}；'
              '受保护保留 ${result.protected} 个，失败保留 ${result.failed} 个。',
        );
      } else {
        final accepted = await _confirm(
          title: '确认清理到期临时输出',
          scope:
              '只清理执行时已经到期且没有保护引用的临时处理输出。'
              '尚未到期、正在使用或被任务引用的输出保留。\n'
              '不删除永久图片、缩略图、诊断日志或远端图片。',
        );
        if (!accepted || !current() || _cancelRequested) return;
        final result = await session.repository.cleanupOutputs();
        if (!current()) return;
        setState(
          () => _feedback =
              '已清理 ${result.removed} 个到期临时输出；'
              '受保护保留 ${result.protected} 个，失败保留 ${result.failedIds.length} 个。',
        );
      }
    } catch (_) {
      if (current()) {
        setState(() => _feedback = '清理未确认全部完成，未安全清理的文件保留；请重新读取后重试。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (current()) await _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('空间管理')),
        body: ListView(
          key: const Key('storage-list'),
          padding: const EdgeInsets.all(16),
          children: [
            const Text('按资料库实际文件统计。缩略图可再生成，不能替代原图。'),
            const SizedBox(height: 12),
            _loading
                ? const LinearProgressIndicator()
                : const SizedBox.shrink(),
            _error == null ? const SizedBox.shrink() : Text(_error!),
            _feedback == null
                ? const SizedBox.shrink()
                : Text(_feedback!, key: const Key('storage-feedback')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('storage-reload'),
                  onPressed: !_busy && !_loading ? _reload : null,
                  child: const Text('重新读取'),
                ),
                OutlinedButton(
                  key: const Key('storage-clear-thumbnails'),
                  onPressed: _enabled ? () => _start(true) : null,
                  child: const Text('清理缩略图缓存'),
                ),
                OutlinedButton(
                  key: const Key('storage-clear-outputs'),
                  onPressed: _enabled ? () => _start(false) : null,
                  child: const Text('清理到期临时输出'),
                ),
                OutlinedButton(
                  key: const Key('storage-diagnostics'),
                  onPressed: !_busy
                      ? () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const DiagnosticsScreen(),
                          ),
                        )
                      : null,
                  child: const Text('打开本机诊断（独立清理）'),
                ),
                if (_busy)
                  TextButton(
                    key: const Key('storage-cancel'),
                    onPressed: _cancel,
                    child: const Text('取消待确认操作（等待 IO 收尾）'),
                  ),
              ],
            ),
            if (_busy) const Text('正在处理，请等待实际清理 IO 收尾。'),
            const SizedBox(height: 16),
            if (report != null) ...[
              Text(
                '文件合计：${_bytes(report.totalFileBytes)}',
                key: const Key('storage-total'),
              ),
              Text(
                '当前可用空间：${report.availableBytes == null ? '未知（平台未提供）' : _bytes(report.availableBytes!)}',
                key: const Key('storage-available'),
              ),
              Text('观察时间：${report.observedAt.toLocal().toIso8601String()}'),
              const SizedBox(height: 12),
              for (final category in StorageCategory.values)
                Card(
                  key: ValueKey('storage-category-${category.name}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${_categoryLabel(category)}：${_bytes(report.fileBytes[category] ?? 0)}',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                '诊断 UTF-8 逻辑内容：${_bytes(report.diagnosticContentBytes)}；已包含于数据库文件，不重复计入文件合计。',
                key: const Key('storage-diagnostic-content'),
              ),
              Text(
                '缩略图缓存上限：${_bytes(report.cacheLimitBytes)}',
                key: const Key('storage-cache-limit'),
              ),
              Text(
                '受保护缩略图：${_bytes(report.protectedThumbnailBytes)}',
                key: const Key('storage-protected'),
              ),
              Text(
                '未登记缩略图：${_bytes(report.untrackedThumbnailBytes)}；保留现场，不自动删除。',
                key: const Key('storage-untracked'),
              ),
              if (report.warning != null)
                Text(report.warning!, key: const Key('storage-warning')),
            ],
            const SizedBox(height: 16),
            const Text(
              '缩略图、临时输出和诊断日志分别清理。到期输出清理不能清除尚未到期或受保护的结果；回收站到期只提示，永久字节须另行明确确认。',
            ),
          ],
        ),
      ),
    );
  }
}

String _bytes(int value) =>
    '$value 字节（${(value / (1024 * 1024)).toStringAsFixed(2)} MiB）';
String _categoryLabel(StorageCategory category) => switch (category) {
  StorageCategory.permanent => '活跃永久图片',
  StorageCategory.recycled => '回收中永久图片',
  StorageCategory.retained => '仅清记录后保留的永久字节',
  StorageCategory.thumbnails => '缩略图缓存',
  StorageCategory.temporaryResults => '临时处理输出',
  StorageCategory.staging => '操作暂存文件',
  StorageCategory.database => '数据库、WAL 与辅助文件',
  StorageCategory.untracked => '未登记文件',
};
