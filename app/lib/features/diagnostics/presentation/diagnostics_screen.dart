import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide DiagnosticLevel;

import '../../../core/platform_resource.dart';
import '../../../platform/export_gateway.dart';
import '../../gallery/data/library_repository.dart';
import '../../gallery/presentation/gallery_providers.dart';
import '../../processing/domain/export_models.dart';
import '../../upload/presentation/upload_exit.dart';
import '../application/diagnostic_exporter.dart';
import '../domain/diagnostic_models.dart';

final diagnosticExportGatewayProvider = Provider(
  (ref) => const ExportGateway(),
);
final diagnosticExporterProvider = Provider(
  (ref) => const DiagnosticExporter(),
);

/// Shared by desktop settings and the M1 settings entry.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key, this.initialQuery});
  final DiagnosticQuery? initialQuery;
  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  final _batch = TextEditingController(), _attempt = TextEditingController();
  DiagnosticKind? _kind;
  DiagnosticLevel? _level;
  DiagnosticQuery? _query;
  DiagnosticQuery? _viewQuery;
  DiagnosticPage? _page;
  LibrarySession? _session;
  StreamSubscription<void>? _changes;
  AppLifecycleListener? _lifecycle;
  Future<void>? _operation;
  CancellationToken? _cancellation;
  Completer<bool>? _confirmation;
  DialogRoute<bool>? _confirmationRoute;
  NavigatorState? _confirmationNavigator;
  int _revision = 0, _offset = 0;
  bool _loading = true, _busy = false;
  String? _error, _feedback;
  static const _limit = 50;

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    _query = query;
    _kind = query?.kind;
    _level = query?.level;
    _batch.text = query?.batchId ?? '';
    _attempt.text = query?.attemptId ?? '';
    _lifecycle = AppLifecycleListener(onExitRequested: _exitRequested);
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      _cancel();
      _revision++;
      _batch.clear();
      _attempt.clear();
      _query = null;
      _viewQuery = null;
      _kind = null;
      _level = null;
      _page = null;
      _offset = 0;
      unawaited(_reload());
    });
    unawaited(_reload());
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
    unawaited(_changes?.cancel());
    _cancel();
    // Cancellation does not discard the running Future or its owned files.
    _batch.dispose();
    _attempt.dispose();
    super.dispose();
  }

  Future<void> _reload({int? offset}) async {
    if (!mounted) return;
    final revision = ++_revision;
    final query = _query;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await ref.read(librarySessionProvider.future);
      if (!mounted || revision != _revision) return;
      if (!identical(_session, session)) {
        unawaited(_changes?.cancel());
        _session = session;
        _changes = session.repository.diagnosticChanges.listen((_) {
          if (mounted && !_busy && !_loading) unawaited(_reload(offset: 0));
        });
      }
      final epoch = session.repository.executionEpoch;
      var actualOffset = offset ?? _offset;
      var page = await session.repository.loadDiagnostics(
        query: query,
        offset: actualOffset,
        limit: _limit,
      );
      if (!mounted ||
          revision != _revision ||
          epoch != session.repository.executionEpoch) {
        return;
      }
      if (actualOffset > 0 &&
          (_page?.total != page.total || actualOffset >= page.total)) {
        actualOffset = 0;
        page = await session.repository.loadDiagnostics(
          query: query,
          limit: _limit,
        );
      }
      if (!mounted ||
          revision != _revision ||
          epoch != session.repository.executionEpoch) {
        return;
      }
      setState(() {
        _page = page;
        _viewQuery = query;
        _offset = actualOffset;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _loading = false;
        _error = '诊断读取失败，最后有效视图保留。请重试。';
      });
    }
  }

  void _filter() {
    try {
      _query = DiagnosticQuery(
        kind: _kind,
        level: _level,
        batchId: _batch.text.trim().isEmpty ? null : _batch.text.trim(),
        attemptId: _attempt.text.trim().isEmpty ? null : _attempt.text.trim(),
      );
      _feedback = null;
      unawaited(_reload(offset: 0));
    } catch (_) {
      setState(() => _feedback = '批次和尝试标识须为完整 UUID；筛选尚未应用。');
    }
  }

  String _scope(DiagnosticQuery? query) => [
    query?.kind == null ? '全部类型' : _kindLabel(query!.kind!),
    query?.level == null ? '全部级别' : _levelLabel(query!.level!),
    if (query?.batchId != null) '批次 ${query!.batchId}',
    if (query?.attemptId != null) '尝试 ${query!.attemptId}',
  ].join(' · ');

  void _cancel() {
    _cancellation?.cancel();
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
      // Resolve first, then remove only our route once the navigator is outside
      // its build/dispose lock. A system exit never waits for user interaction.
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

  Future<bool> _showConfirmation(Widget content, CancellationToken token) {
    if (!mounted || token.isCancelled) return Future.value(false);
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

  void _start(bool export) {
    if (_busy || _loading || _error != null || _page == null) return;
    final token = CancellationToken();
    _cancellation = token;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    _operation = _perform(export, token);
  }

  Future<void> _perform(bool export, CancellationToken token) async {
    final session = _session!;
    final revision = _revision, epoch = session.repository.executionEpoch;
    final scope = _scope(_query);
    try {
      token.throwIfCancelled();
      final plan = await session.repository.prepareDiagnosticSelection(
        query: _query,
      );
      token.throwIfCancelled();
      if (!mounted ||
          revision != _revision ||
          epoch != session.repository.executionEpoch) {
        return;
      }
      if (plan.count == 0) {
        setState(() => _feedback = '当前范围没有诊断记录。');
        return;
      }
      final confirmed = await _showConfirmation(
        AlertDialog(
          title: Text(export ? '确认导出诊断' : '确认清理诊断'),
          content: SingleChildScrollView(
            child: Text(
              '范围：$scope\n已冻结 ${plan.count} 条，UTF-8 内容 ${plan.contentBytes} 字节。'
              '涵盖当前筛选的全部匹配记录，不限于本页；后来新增记录不会加入。\n'
              '${export ? '仅导出本机脱敏 JSON；排除图片、凭据、管理秘密、完整来源路径和原始响应。保存到你选择的本机目录，不自动外发。' : '只清理这些诊断日志，不删除图片、任务、普通结果或远端历史。'}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _resolveConfirmation(false),
              child: const Text('返回'),
            ),
            FilledButton(
              key: const Key('diagnostics-confirm'),
              onPressed: () => _resolveConfirmation(true),
              child: Text(export ? '选择目录并导出' : '仅清理这些日志'),
            ),
          ],
        ),
        token,
      );
      token.throwIfCancelled();
      if (confirmed != true ||
          !mounted ||
          revision != _revision ||
          epoch != session.repository.executionEpoch) {
        return;
      }
      if (export) {
        final gateway = ref.read(diagnosticExportGatewayProvider);
        if (!gateway.supportsDirectoryExport) throw const DiagnosticFailure();
        final destination = await gateway.pickDirectory();
        // Native directory choosers have no cancellation bridge. Wait for the
        // real callback, then reject further work when exit/dispose cancelled.
        token.throwIfCancelled();
        if (destination == null) {
          if (mounted) setState(() => _feedback = '已取消目录选择。');
          return;
        }
        if (!mounted ||
            revision != _revision ||
            epoch != session.repository.executionEpoch) {
          return;
        }
        final exporter = ref.read(diagnosticExporterProvider);
        final document = await session.repository.diagnosticExport(plan);
        token.throwIfCancelled();
        if (!mounted ||
            revision != _revision ||
            epoch != session.repository.executionEpoch) {
          return;
        }
        final result = await exporter.export(
          document,
          destination,
          cancellation: token,
        );
        if (!mounted ||
            revision != _revision ||
            epoch != session.repository.executionEpoch) {
          return;
        }
        setState(
          () => _feedback = switch (result.status) {
            ExportStatus.saved =>
              '已导出 ${document.count} 条：${result.fileName}${result.reason == null ? '' : '。${result.reason}'}',
            ExportStatus.cancelled => '已取消导出，实际文件 IO 已收尾。',
            ExportStatus.failed => '诊断导出未完成，请检查目录和空间后重试。',
          },
        );
      } else {
        token.throwIfCancelled();
        final count = await session.repository.clearDiagnostics(plan);
        if (!mounted ||
            revision != _revision ||
            epoch != session.repository.executionEpoch) {
          return;
        }
        setState(() => _feedback = '已清理 $count 条诊断日志。');
      }
    } catch (failure) {
      if (mounted &&
          revision == _revision &&
          epoch == session.repository.executionEpoch) {
        setState(
          () => _feedback =
              failure is ResourceFailure &&
                  failure.kind == FailureKind.cancelled
              ? '已取消诊断操作，实际 IO 已收尾。'
              : '诊断操作未确认完成，范围或资料库可能已变化；请重新读取后重试。',
        );
      }
    } finally {
      _cancellation = null;
      if (mounted) {
        setState(() => _busy = false);
        if (revision == _revision) await _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref
        .watch(diagnosticExportGatewayProvider)
        .supportsDirectoryExport;
    final enabled = !_busy && !_loading && _error == null && _page != null;
    final page = _page;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('本机诊断')),
        body: ListView(
          key: const Key('diagnostics-list'),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '仅保留本机脱敏诊断。保留 30 天或 UTF-8 内容达到 10 MB，先到即清理最旧记录。内容量不代表数据库物理空间。',
            ),
            const SizedBox(height: 12),
            _loading
                ? const LinearProgressIndicator()
                : const SizedBox.shrink(),
            _error != null ? Text(_error!) : const SizedBox.shrink(),
            _feedback != null
                ? Text(_feedback!, key: const Key('diagnostics-feedback'))
                : const SizedBox.shrink(),
            _session?.repository.diagnosticWarning != null
                ? Text(_session!.repository.diagnosticWarning!)
                : const SizedBox.shrink(),
            InputDecorator(
              decoration: const InputDecoration(labelText: '类型'),
              child: DropdownButton<DiagnosticKind>(
                key: const Key('diagnostics-kind'),
                isExpanded: true,
                value: _kind,
                hint: const Text('全部类型'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部类型')),
                  for (final kind in DiagnosticKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(_kindLabel(kind)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _kind = value),
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: '级别'),
              child: DropdownButton<DiagnosticLevel>(
                key: const Key('diagnostics-level'),
                isExpanded: true,
                value: _level,
                hint: const Text('全部级别'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部级别')),
                  for (final level in DiagnosticLevel.values)
                    DropdownMenuItem(
                      value: level,
                      child: Text(_levelLabel(level)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _level = value),
              ),
            ),
            TextField(
              key: const Key('diagnostics-batch'),
              controller: _batch,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '批次 UUID（可选）'),
            ),
            TextField(
              key: const Key('diagnostics-attempt'),
              controller: _attempt,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '尝试 UUID（可选）'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('diagnostics-filter'),
                  onPressed: !_busy ? _filter : null,
                  child: const Text('应用筛选'),
                ),
                TextButton(
                  key: const Key('diagnostics-reset'),
                  onPressed: !_busy
                      ? () {
                          _batch.clear();
                          _attempt.clear();
                          setState(() {
                            _kind = null;
                            _level = null;
                            _query = null;
                          });
                          unawaited(_reload(offset: 0));
                        }
                      : null,
                  child: const Text('清空筛选'),
                ),
                OutlinedButton(
                  key: const Key('diagnostics-reload'),
                  onPressed: !_busy ? _reload : null,
                  child: const Text('重新读取'),
                ),
                OutlinedButton(
                  key: const Key('diagnostics-clear'),
                  onPressed: enabled ? () => _start(false) : null,
                  child: const Text('清理当前范围'),
                ),
                OutlinedButton(
                  key: const Key('diagnostics-export'),
                  onPressed: enabled && supported ? () => _start(true) : null,
                  child: const Text('导出当前范围 JSON'),
                ),
                if (_cancellation != null)
                  TextButton(
                    key: const Key('diagnostics-cancel'),
                    onPressed: _cancel,
                    child: const Text('取消操作（等待 IO 收尾）'),
                  ),
              ],
            ),
            if (!supported)
              const Text(
                'Android / iOS 原生诊断文件导出尚未接入，导出不可用。',
                key: Key('diagnostics-mobile-disabled'),
              ),
            if (_busy) const Text('正在处理确认范围，请等待实际 IO 完成。'),
            const SizedBox(height: 12),
            Text('已读取范围：${_scope(_viewQuery)}'),
            if (page != null)
              Text(
                '当前筛选共 ${page.total} 条；UTF-8 内容 ${page.contentBytes} 字节。',
                key: const Key('diagnostics-total'),
              ),
            if (page != null && page.items.isEmpty)
              const Text('当前范围暂无诊断记录。', key: Key('diagnostics-empty')),
            if (page != null)
              for (final event in page.items)
                Card(
                  key: ValueKey('diagnostic-${event.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${_kindLabel(event.kind)} · ${_levelLabel(event.level)} · ${event.occurredAt.toIso8601String()}',
                        ),
                        Text(event.code),
                        Text(event.summary),
                        if (event.recoveryAction.isNotEmpty)
                          Text('建议：${event.recoveryAction}'),
                        if (event.entityId != null)
                          Text('对象：${event.entityId}'),
                        if (event.batchId != null) Text('批次：${event.batchId}'),
                        if (event.attemptId != null)
                          Text('尝试：${event.attemptId}'),
                        if (event.details != null)
                          Text(jsonEncode(event.details)),
                      ],
                    ),
                  ),
                ),
            if (page != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text(
                    '本页 ${page.items.isEmpty ? 0 : _offset + 1}–${_offset + page.items.length} / ${page.total}',
                  ),
                  TextButton(
                    key: const Key('diagnostics-previous'),
                    onPressed: enabled && _offset > 0
                        ? () => _reload(offset: _offset - _limit)
                        : null,
                    child: const Text('上一页'),
                  ),
                  TextButton(
                    key: const Key('diagnostics-next'),
                    onPressed:
                        enabled && _offset + page.items.length < page.total
                        ? () => _reload(offset: _offset + _limit)
                        : null,
                    child: const Text('下一页'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _kindLabel(DiagnosticKind kind) => switch (kind) {
  DiagnosticKind.importImage => '导入',
  DiagnosticKind.processing => '处理',
  DiagnosticKind.upload => '上传',
  DiagnosticKind.account => '账号',
  DiagnosticKind.settings => '设置',
  DiagnosticKind.cleanup => '清理',
  DiagnosticKind.backup => '备份',
  DiagnosticKind.restore => '恢复',
  DiagnosticKind.system => '系统',
};
String _levelLabel(DiagnosticLevel level) => switch (level) {
  DiagnosticLevel.info => '信息',
  DiagnosticLevel.warning => '警告',
  DiagnosticLevel.error => '错误',
};
