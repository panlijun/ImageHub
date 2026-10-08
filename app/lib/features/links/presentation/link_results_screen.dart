import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../platform/link_transfer_gateway.dart';
import '../../accounts/domain/account_models.dart';
import '../../gallery/data/library_repository.dart';
import '../../gallery/presentation/gallery_providers.dart';
import '../../upload/domain/link_format.dart';
import '../../upload/domain/upload_queue_models.dart';
import '../../upload/presentation/upload_exit.dart';
import '../application/link_transfer_coordinator.dart';
import '../domain/link_query.dart';
import '../domain/link_transfer.dart';
import '../data/link_probe_gateway.dart';
import '../application/link_probe_coordinator.dart';
import '../domain/link_availability.dart';
import '../domain/remote_deletion.dart';
import '../data/remote_deletion_gateway.dart';
import '../application/remote_deletion_coordinator.dart';

final linkTransferGatewayProvider = Provider<LinkTransferGateway>(
  (ref) => SystemLinkTransferGateway(),
);
final linkProbeGatewayProvider = Provider<LinkProbeGateway>(
  (ref) => DioLinkProbeGateway(),
);
final remoteDeletionGatewayProvider = Provider<RemoteDeletionGateway>(
  (ref) => DioRemoteDeletionGateway(),
);

/// Opening, querying and copying ordinary results never authorize a probe.
class LinkResultsScreen extends ConsumerStatefulWidget {
  const LinkResultsScreen({
    super.key,
    this.embedded = false,
    this.assetIdsInOrder = const [],
    this.active = true,
    this.onBusyChanged,
  });
  final bool embedded, active;
  final List<String> assetIdsInOrder;
  final ValueChanged<bool>? onBusyChanged;
  @override
  ConsumerState<LinkResultsScreen> createState() => _LinkResultsScreenState();
}

class _LinkResultsScreenState extends ConsumerState<LinkResultsScreen> {
  final _search = TextEditingController();
  final _selected = <String>{};
  final _targetOrder = <String>{};
  List<String> _assetOrder = const [];
  LinkResultQuery _query = const LinkResultQuery();
  List<RemoteUploadResult> _items = const [];
  List<TargetSnapshot> _targets = const [];
  List<RemoteDeletionRecord> _remoteDeletionRecords = const [];
  UploadLinkFormat _format = UploadLinkFormat.url;
  LibrarySession? _session;
  StreamSubscription<void>? _changes;
  StreamSubscription<String>? _accountChanges;
  AppLifecycleListener? _lifecycle;
  Future<void>? _localOperation;
  int _revision = 0, _operationGeneration = 0, _total = 0;
  bool _loading = true, _loadingMore = false, _busy = false;
  String? _error;
  String? _feedback;
  bool _probing = false, _probeCancelled = false;
  LinkProbeCoordinator? _probeCoordinator;
  StreamSubscription<void>? _probeChanges;
  bool _deletingRemotely = false, _remoteDeletionCancelled = false;
  RemoteDeletionCoordinator? _remoteDeletionCoordinator;
  StreamSubscription<void>? _remoteDeletionChanges;
  Completer<bool>? _confirmation;
  DialogRoute<bool>? _confirmationRoute;
  NavigatorState? _confirmationNavigator;

  bool get _ready =>
      !_loading &&
      !_loadingMore &&
      !_busy &&
      _error == null &&
      _session != null;
  List<String> get _visibleIds => _items.map((r) => r.id).toList();
  List<String> get _selectedVisible =>
      _items.where((r) => _selected.contains(r.id)).map((r) => r.id).toList();

  @override
  void initState() {
    super.initState();
    _assetOrder = List.unmodifiable(widget.assetIdsInOrder);
    _updateLifecycle();
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      _revision++;
      _operationGeneration++;
      _closeConfirmation();
      _cancelProbe();
      _cancelRemoteDeletion();
      _search.clear();
      setState(() {
        _query = const LinkResultQuery();
        _selected.clear();
        _targetOrder.clear();
        _assetOrder = const [];
        _items = const [];
        _targets = const [];
        _remoteDeletionRecords = const [];
        _total = 0;
        _feedback = null;
      });
      unawaited(_reload());
    });
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(LinkResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (!widget.active) {
        _closeConfirmation();
        _cancelProbe();
        _cancelRemoteDeletion();
      }
      _updateLifecycle();
    }
  }

  void _updateLifecycle() {
    _lifecycle?.dispose();
    _lifecycle = widget.active
        ? AppLifecycleListener(onExitRequested: _exitRequested)
        : null;
  }

  Future<AppExitResponse> _exitRequested() async {
    // A local confirmation dialog also sits above this route. Keep handling
    // exit until its operation settles; navigation is blocked while busy.
    if (!widget.active ||
        (ModalRoute.of(context)?.isCurrent != true && !_busy)) {
      return AppExitResponse.exit;
    }
    _closeConfirmation();
    _cancelProbe();
    _cancelRemoteDeletion();
    await _localOperation;
    if (!mounted) return AppExitResponse.cancel;
    final session = _session;
    return session == null || await requestLibraryExit(context, session)
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  @override
  void dispose() {
    _revision++;
    _operationGeneration++;
    _closeConfirmation();
    _cancelProbe();
    _cancelRemoteDeletion();
    _lifecycle?.dispose();
    unawaited(_changes?.cancel());
    unawaited(_accountChanges?.cancel());
    unawaited(_probeChanges?.cancel());
    unawaited(_remoteDeletionChanges?.cancel());
    _search.dispose();
    super.dispose();
  }

  void _attach(LibrarySession session) {
    if (identical(session, _session)) return;
    unawaited(_changes?.cancel());
    unawaited(_accountChanges?.cancel());
    _session = session;
    _changes = session.repository.uploadChanges.listen(
      (_) => unawaited(_reload()),
    );
    _accountChanges = session.repository.accountChanges.listen(
      (_) => unawaited(_reload()),
    );
  }

  Future<void> _reload() async {
    final revision = ++_revision;
    final query = _query;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final session = await ref.read(librarySessionProvider.future);
      if (!mounted || revision != _revision) return;
      _attach(session);
      final page = await session.repository.listLinkResults(
        query: query,
        limit: 50,
      );
      final targets = await session.repository.listLinkTargets();
      final deletions = await session.repository.listRemoteDeletions();
      if (!mounted || revision != _revision) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _targets = targets;
        _remoteDeletionRecords = deletions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _loading = false;
        _error = '链接读取失败，保留上次有效列表；复制已暂停，请重试。';
      });
    }
  }

  Future<void> _more() async {
    if (!_ready || _items.length >= _total) return;
    final revision = _revision;
    setState(() => _loadingMore = true);
    try {
      final page = await _session!.repository.listLinkResults(
        query: _query,
        offset: _items.length,
        limit: 50,
      );
      if (!mounted || revision != _revision) return;
      if (page.total != _total) {
        await _reload();
        return;
      }
      setState(() {
        final ids = _items.map((r) => r.id).toSet();
        _items = [..._items, ...page.items.where((r) => ids.add(r.id))];
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = '下一页读取失败，已载入链接保留；请重试。');
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _change(LinkResultQuery query) {
    setState(() => _query = query);
    unawaited(_reload());
  }

  void _closeConfirmation() {
    final pending = _confirmation;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    final route = _confirmationRoute, navigator = _confirmationNavigator;
    _confirmation = null;
    _confirmationRoute = null;
    _confirmationNavigator = null;
    if (route != null && navigator != null && route.isActive) {
      scheduleMicrotask(() {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
  }

  Future<bool> _confirm(String title, String text, String action) async {
    if (!mounted) return false;
    final pending = Completer<bool>();
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
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

  void _cancelProbe() {
    if (!_probing) return;
    _probeCancelled = true;
    _closeConfirmation();
    _probeCoordinator?.cancel();
  }

  void _cancelRemoteDeletion() {
    if (!_deletingRemotely) return;
    _remoteDeletionCancelled = true;
    _closeConfirmation();
    _remoteDeletionCoordinator?.cancel();
  }

  Future<void> _deleteRemotely(RemoteUploadResult result) => _run((
    generation,
  ) async {
    _deletingRemotely = true;
    _remoteDeletionCancelled = false;
    try {
      final session = _session!;
      final plan = await session.repository.prepareRemoteDeletion(result.id);
      if (!_current(generation) || _remoteDeletionCancelled) return;
      if (!await _confirm(
        '请求远端删除这个文件？',
        '${plan.result.input.displayName}\n${_targetLabel(plan.result.target)}\n'
            '${plan.result.directUrl}\n\n'
            '仅针对这个文件，使用同一目标 UUID 的当前账号授权。可能失去远端内容。'
            '服务删除响应尚无已核验的确认协议，即使返回 HTTP 200，也会保留删除结果未知。'
            '保留本机原图、普通链接结果和任务历史；不会自动重试。'
            '确认仅授权此次网络删除请求，取消不会发送请求。',
        '确认本次网络与远端删除',
      )) {
        return;
      }
      if (!_current(generation) || _remoteDeletionCancelled) return;
      final coordinator = session.remoteDeletionsWith(
        ref.read(remoteDeletionGatewayProvider),
      );
      _remoteDeletionCoordinator = coordinator;
      await _remoteDeletionChanges?.cancel();
      _remoteDeletionChanges = coordinator.changes.listen((_) {
        if (mounted) setState(() {});
      });
      final report = await coordinator.run(
        plan,
        confirmNetwork: true,
        confirmRemoteDeletion: true,
      );
      if (!_current(generation)) return;
      setState(() => _feedback = report.message);
      await _reload();
    } on UploadQueueFailure catch (error) {
      if (_current(generation)) {
        setState(() => _feedback = error.message);
      }
    } catch (_) {
      if (_current(generation)) {
        setState(() => _feedback = '远端删除请求或收尾未确认，本地图片与链接保留；请刷新核查，不会自动重试。');
      }
    } finally {
      await _remoteDeletionChanges?.cancel();
      _remoteDeletionChanges = null;
      _remoteDeletionCoordinator = null;
      if (mounted) setState(() => _deletingRemotely = false);
    }
  });

  Future<void> _probe(List<String> ids) => _run((generation) async {
    _probing = true;
    _probeCancelled = false;
    try {
      final session = _session!;
      final plan = await session.repository.prepareLinkProbe(
        List.unmodifiable(ids),
      );
      if (!_current(generation) || _probeCancelled) return;
      if (!await _confirm(
        '主动检测已选链接？',
        '仅检测下面明确选择的 ${plan.results.length} 项，不含未加载或筛选外记录。\n'
            '会向链接所属服务发送不带账号凭据的请求，可能计入服务访问。不会自动重试、定期访问、删除历史或重新上传。检测结果只说明当时状态，不能保证永久可用。\n\n'
            '${plan.results.map((r) => '${r.input.displayName}\n${_targetLabel(r.target)}\n${r.directUrl}').join('\n\n')}',
        '确认本次网络检测',
      )) {
        return;
      }
      if (!_current(generation) || _probeCancelled) return;
      final coordinator = session.linkProbesWith(
        ref.read(linkProbeGatewayProvider),
      );
      _probeCoordinator = coordinator;
      await _probeChanges?.cancel();
      _probeChanges = coordinator.changes.listen((_) {
        if (mounted) setState(() {});
      });
      final report = await coordinator.run(plan, confirmNetwork: true);
      if (!_current(generation)) return;
      setState(
        () => _feedback = switch (report.status) {
          LinkProbeBatchStatus.completed =>
            '检测结束：更新 ${report.updated} 项，跳过 ${report.skipped} 项。普通结果与图片保留。',
          LinkProbeBatchStatus.cancelled =>
            '检测已取消，等待实际网络收尾后结束。已更新 ${report.updated} 项，未检测项保留。',
          LinkProbeBatchStatus.failed => '检测或状态保存未完整确认，已有结果保留；请核查后再主动重试。',
          LinkProbeBatchStatus.rejected => '检测范围未获授权或会话已失效，未继续发送请求。',
        },
      );
      await _reload();
    } finally {
      await _probeChanges?.cancel();
      _probeChanges = null;
      _probeCoordinator = null;
      if (mounted) setState(() => _probing = false);
    }
  });

  Future<void> _run(Future<void> Function(int generation) action) async {
    if (!_ready) return;
    final generation = ++_operationGeneration;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    widget.onBusyChanged?.call(true);
    final operation = _perform(action, generation);
    _localOperation = operation;
    await operation;
    if (identical(_localOperation, operation)) _localOperation = null;
  }

  bool _current(int generation) =>
      mounted && generation == _operationGeneration;
  Future<void> _perform(
    Future<void> Function(int) action,
    int generation,
  ) async {
    try {
      await action(generation);
    } catch (_) {
      if (_current(generation)) {
        setState(() => _feedback = '本地操作未确认完成，结果保留；请刷新后重试。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  String _planDescription(LinkCopyPlan plan) {
    final scope = plan.scope == LinkCopyScope.visibleResults
        ? '当前已展示结果，按列表顺序（不含未加载或筛选外结果）'
        : '已确认资产顺序，再按已选历史目标顺序（独立于上方列表筛选）';
    return '范围：$scope\n格式：${_formatLabel(_format)}\n'
        '${plan.scope == LinkCopyScope.assetsAndTargets ? '资产：${plan.assetNames.join(' → ')}\n目标：${plan.targets.map(_targetLabel).join(' → ')}\n' : ''}'
        '确认记录 ${plan.confirmedResultIds.length} 项，输出 ${plan.batch.copied} 项；'
        '跳过 ${plan.batch.skipped} 项，去重 ${plan.batch.duplicates} 项。每项换行。';
  }

  Future<void> _transfer(
    List<String> ids, {
    bool single = false,
    bool share = false,
    LinkShareAnchor? anchor,
    bool assets = false,
  }) => _run((generation) async {
    final repository = _session!.repository;
    final plan = assets
        ? await repository.prepareAssetLinkCopy(
            _assetOrder,
            _targetOrder.toList(),
            _format,
          )
        : await repository.prepareVisibleLinkCopy(ids, _format);
    if (!_current(generation)) return;
    if (!single &&
        !await _confirm(
          share ? '确认分享普通链接' : '确认批量复制',
          _planDescription(plan),
          share ? '调用系统分享' : '复制',
        )) {
      return;
    }
    if (!_current(generation)) return;
    final coordinator = LinkTransferCoordinator(
      repository,
      ref.read(linkTransferGatewayProvider),
    );
    final report = share
        ? await coordinator.share(plan, anchor: anchor)
        : await coordinator.copy(plan);
    if (_current(generation)) setState(() => _feedback = report.message);
  });

  Future<void> _remove(List<String> ids) => _run((generation) async {
    if (!await _confirm(
      '仅移除本地链接记录？',
      '移除明确选定的 ${ids.length} 项普通结果记录及其管理能力。保留本机资产、任务历史及远端文件；不会请求远端删除。',
      '移除本地记录',
    )) {
      return;
    }
    if (!_current(generation)) return;
    final report = await _session!.repository.removeLocalLinkResults(
      ids,
      confirmLocalRemoval: true,
    );
    if (!_current(generation)) return;
    setState(() {
      _selected.removeAll(ids);
      _feedback =
          '已移除 ${report.removed} 项，已不存在 ${report.missing} 项，管理秘密待清理 ${report.cleanupPending} 项。';
    });
    await _reload();
  });

  LinkShareAnchor? _anchor(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return LinkShareAnchor(
      left: origin.dx,
      top: origin.dy,
      width: box.size.width,
      height: box.size.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.embedded)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    '成功链接',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                ),
              const Text(
                '仅显示已确认的普通链接。链接存在 ≠ 当前可达；只有明确确认才主动检测。第三方保留规则不能替代本机备份；既有匿名历史仅供本地查看与移除。',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('links-search'),
                enabled: !_busy,
                controller: _search,
                onChanged: (v) => _change(_query.copyWith(keyword: v)),
                decoration: const InputDecoration(
                  labelText: '名称、普通 URL、历史目标',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              _filters(),
              if (_probing)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(
                      '检测进度：${_probeCoordinator?.completed ?? 0} / ${_probeCoordinator?.total ?? 0}',
                    ),
                    TextButton(
                      key: const Key('links-cancel-probe'),
                      onPressed: _cancelProbe,
                      child: const Text('取消检测'),
                    ),
                  ],
                ),
              if (_deletingRemotely)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Text('远端删除请求处理中；取消后仍等待实际网络收尾。'),
                    TextButton(
                      key: const Key('links-cancel-remote-deletion'),
                      onPressed: _cancelRemoteDeletion,
                      child: const Text('取消删除请求'),
                    ),
                  ],
                ),
              if (_assetOrder.isNotEmpty) _assetScope(),
              const SizedBox(height: 12),
              Text(
                '已展示 ${_items.length} / $_total 项；选择 ${_selected.length} 项，其中当前展示 ${_selectedVisible.length} 项。筛选和翻页不会自动增加选择。',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('links-select-visible'),
                    onPressed: _ready && _items.isNotEmpty
                        ? () => setState(() => _selected.addAll(_visibleIds))
                        : null,
                    child: const Text('选择已展示结果'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(_selected.clear),
                    child: const Text('清空选择'),
                  ),
                  FilledButton(
                    key: const Key('links-copy-visible'),
                    onPressed: _ready && _items.isNotEmpty
                        ? () => _transfer(_visibleIds)
                        : null,
                    child: const Text('复制已展示结果'),
                  ),
                  OutlinedButton(
                    key: const Key('links-copy-selected'),
                    onPressed: _ready && _selectedVisible.isNotEmpty
                        ? () => _transfer(_selectedVisible)
                        : null,
                    child: const Text('复制当前展示的选中项'),
                  ),
                  Builder(
                    builder: (context) => OutlinedButton(
                      key: const Key('links-share-selected'),
                      onPressed: _ready && _selectedVisible.isNotEmpty
                          ? () => _transfer(
                              _selectedVisible,
                              share: true,
                              anchor: _anchor(context),
                            )
                          : null,
                      child: const Text('分享当前展示的选中项'),
                    ),
                  ),
                  TextButton(
                    key: const Key('links-remove-selected'),
                    onPressed: _ready && _selectedVisible.isNotEmpty
                        ? () => _remove(_selectedVisible)
                        : null,
                    child: const Text('移除当前展示的选中项'),
                  ),
                  OutlinedButton(
                    key: const Key('links-probe-selected'),
                    onPressed: _ready && _selectedVisible.isNotEmpty
                        ? () => _probe(_selectedVisible)
                        : null,
                    child: const Text('检测当前展示的选中项'),
                  ),
                ],
              ),
              if (_loading || _loadingMore || _busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!),
                      TextButton(
                        key: const Key('links-retry'),
                        onPressed: _busy ? null : _reload,
                        child: const Text('重试读取'),
                      ),
                    ],
                  ),
                ),
              if (_feedback != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_feedback!, key: const Key('links-feedback')),
                ),
              if (!_loading && _error == null && _items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(_query.filtered ? '没有匹配的已确认链接。' : '暂无已确认普通链接。'),
                ),
              for (final result in _items) _result(result),
              if (_items.length < _total)
                OutlinedButton(
                  key: const Key('links-load-more'),
                  onPressed: _ready ? _more : null,
                  child: const Text('读取下一页'),
                ),
            ],
          ),
        ),
      ],
    );
    final guarded = PopScope(canPop: !_busy, child: body);
    return widget.embedded
        ? guarded
        : Scaffold(
            appBar: AppBar(
              title: const Text('成功链接'),
              actions: [
                IconButton(
                  onPressed: _busy ? null : _reload,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新链接',
                ),
              ],
            ),
            body: SafeArea(child: guarded),
          );
  }

  Widget _filters() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 600 ? constraints.maxWidth : 240.0;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: width,
            child: DropdownButtonFormField<String>(
              key: ValueKey('target-${_query.targetId}-${_targets.length}'),
              initialValue: _query.targetId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '历史目标身份'),
              items: [
                const DropdownMenuItem(value: null, child: Text('全部历史目标')),
                for (final t in _targets)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      _targetLabel(t),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_query.targetId != null &&
                    !_targets.any((t) => t.id == _query.targetId))
                  DropdownMenuItem(
                    value: _query.targetId,
                    child: Text('已无结果的历史目标 · ${_query.targetId}'),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) => _change(_query.copyWith(targetId: v)),
            ),
          ),
          SizedBox(
            width: width,
            child: DropdownButtonFormField<ImageHostService>(
              key: ValueKey('service-${_query.service}'),
              initialValue: _query.service,
              decoration: const InputDecoration(labelText: '图床服务'),
              items: [
                const DropdownMenuItem(value: null, child: Text('全部服务')),
                for (final s in ImageHostService.values)
                  DropdownMenuItem(
                    value: s,
                    child: Text(
                      s == ImageHostService.catbox ? 'Catbox' : 'ImgBB',
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) => _change(_query.copyWith(service: v)),
            ),
          ),
          SizedBox(
            width: width,
            child: DropdownButtonFormField<UploadInputKind>(
              key: ValueKey('input-${_query.inputKind}'),
              initialValue: _query.inputKind,
              decoration: const InputDecoration(labelText: '上传输入'),
              items: const [
                DropdownMenuItem(value: null, child: Text('原图与处理结果')),
                DropdownMenuItem(
                  value: UploadInputKind.original,
                  child: Text('原图'),
                ),
                DropdownMenuItem(
                  value: UploadInputKind.processed,
                  child: Text('处理结果'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (v) => _change(_query.copyWith(inputKind: v)),
            ),
          ),
          SizedBox(
            width: width,
            child: DropdownButtonFormField<LinkResultSort>(
              key: ValueKey('sort-${_query.sort}'),
              initialValue: _query.sort,
              decoration: const InputDecoration(labelText: '排序'),
              items: const [
                DropdownMenuItem(
                  value: LinkResultSort.confirmed,
                  child: Text('确认时间'),
                ),
                DropdownMenuItem(
                  value: LinkResultSort.name,
                  child: Text('结果名称'),
                ),
                DropdownMenuItem(
                  value: LinkResultSort.target,
                  child: Text('历史目标'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) _change(_query.copyWith(sort: v));
                    },
            ),
          ),
          SizedBox(
            width: width,
            child: DropdownButtonFormField<LinkAvailability>(
              key: ValueKey('links-availability-${_query.availability}'),
              initialValue: _query.availability,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '链接检测状态'),
              items: [
                const DropdownMenuItem(value: null, child: Text('全部检测状态')),
                for (final state in LinkAvailability.values)
                  DropdownMenuItem(
                    value: state,
                    child: Text(_availabilityLabel(state)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => _change(_query.copyWith(availability: value)),
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _change(_query.copyWith(ascending: !_query.ascending)),
            child: Text(_query.ascending ? '升序 ↑' : '降序 ↓'),
          ),
          SizedBox(
            width: width,
            child: DropdownButtonFormField<UploadLinkFormat>(
              initialValue: _format,
              decoration: const InputDecoration(labelText: '复制 / 分享格式'),
              items: [
                for (final f in UploadLinkFormat.values)
                  DropdownMenuItem(value: f, child: Text(_formatLabel(f))),
              ],
              onChanged: _busy
                  ? null
                  : (f) {
                      if (f != null) setState(() => _format = f);
                    },
            ),
          ),
        ],
      );
    },
  );

  Widget _assetScope() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('来自图库的 ${_assetOrder.length} 张资产，保持选择顺序。此复制范围独立于列表筛选。'),
          const Text('仅复制资产当前永久版本的链接。其他处理版本请选另存的资产，或在普通结果列表中选择。'),
          const Text('请选择历史目标；勾选顺序就是目标顺序。未命中的资产 / 目标组合会报告跳过。'),
          for (final id in _targetOrder.where(
            (id) => !_targets.any((t) => t.id == id),
          ))
            InputChip(
              label: Text('已无历史结果的选定目标 · $id'),
              onDeleted: _busy
                  ? null
                  : () => setState(() => _targetOrder.remove(id)),
            ),
          for (final target in _targets)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _targetOrder.contains(target.id),
              onChanged: !_ready
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        _targetOrder.add(target.id);
                      } else {
                        _targetOrder.remove(target.id);
                      }
                    }),
              title: Text(
                '${_targetOrder.contains(target.id) ? '${_targetOrder.toList().indexOf(target.id) + 1}. ' : ''}${_targetLabel(target)}',
              ),
            ),
          FilledButton(
            key: const Key('links-copy-assets'),
            onPressed:
                _ready &&
                    _targetOrder.isNotEmpty &&
                    _targetOrder.every((id) => _targets.any((t) => t.id == id))
                ? () => _transfer(const [], assets: true)
                : null,
            child: const Text('按资产与目标顺序复制'),
          ),
        ],
      ),
    ),
  );

  Widget _result(RemoteUploadResult result) => Card(
    key: ValueKey(result.id),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: _selected.contains(result.id),
                onChanged: _ready
                    ? (v) => setState(() {
                        if (v == true) {
                          _selected.add(result.id);
                        } else {
                          _selected.remove(result.id);
                        }
                      })
                    : null,
              ),
              Expanded(
                child: Text(
                  result.input.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Text(
            '${result.input.kind == UploadInputKind.original ? '原图' : '处理结果'} · ${_targetLabel(result.target)}',
          ),
          Text(
            '确认于 ${result.confirmedAt.toLocal()}${result.late ? ' · 取消后晚到的独立确认' : ''}',
          ),
          if (result.usesInsecureHttp) const Text('HTTP 链接：传输未加密。'),
          Text(
            _availabilityLabel(result.availability.state),
            key: ValueKey('links-state-${result.id}'),
          ),
          if (result.availability.reason != null)
            Text(_probeReason(result.availability.reason!)),
          if (result.availability.checkedAt != null)
            Text('检测记录：${result.availability.checkedAt!.toLocal()}'),
          if (result.availability.lastAccessibleAt != null &&
              result.availability.state != LinkAvailability.accessible)
            Text('上次可访问：${result.availability.lastAccessibleAt!.toLocal()}'),
          SelectableText(result.directUrl.toString()),
          for (final audit in _lastRemoteDeletion(result.id))
            Text(
              '远端删除审计：${audit.message}',
              key: ValueKey('links-remote-deletion-state-${result.id}'),
            ),
          if (_remoteDeletionUnavailable(result) case final String reason)
            Text(reason),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _ready
                    ? () => _transfer([result.id], single: true)
                    : null,
                child: Text('复制${_formatLabel(_format)}'),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: _ready
                      ? () => _transfer(
                          [result.id],
                          single: true,
                          share: true,
                          anchor: _anchor(context),
                        )
                      : null,
                  child: const Text('系统分享'),
                ),
              ),
              TextButton(
                onPressed: _ready ? () => _remove([result.id]) : null,
                child: const Text('移除本地记录'),
              ),
              OutlinedButton(
                key: ValueKey('links-remote-delete-${result.id}'),
                onPressed: _ready && _remoteDeletionUnavailable(result) == null
                    ? () => _deleteRemotely(result)
                    : null,
                child: const Text('请求远端删除'),
              ),
              TextButton(
                key: ValueKey('links-probe-${result.id}'),
                onPressed: _ready ? () => _probe([result.id]) : null,
                child: const Text('主动检测'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Iterable<RemoteDeletionRecord> _lastRemoteDeletion(String resultId) {
    final records =
        _remoteDeletionRecords
            .where((record) => record.resultId == resultId)
            .toList()
          ..sort((a, b) {
            final time = b.createdUtc.compareTo(a.createdUtc);
            return time == 0 ? b.id.compareTo(a.id) : time;
          });
    return records.take(1);
  }
}

String? _remoteDeletionUnavailable(RemoteUploadResult result) {
  if (result.target.service == ImageHostService.imgbb) {
    return 'ImgBB 公开 API 无通用远端删除能力；可移除本地记录。';
  }
  if (result.target.anonymous) {
    return 'Catbox 匿名文件无已核验删除授权；可移除本地记录。';
  }
  final url = result.directUrl;
  if (url.scheme != 'https' ||
      url.host != 'files.catbox.moe' ||
      url.hasPort ||
      url.userInfo.isNotEmpty ||
      url.hasQuery ||
      url.hasFragment ||
      url.pathSegments.length != 1 ||
      !CatboxDeletionRequest.validFilename(url.pathSegments.single) ||
      url.path != '/${url.pathSegments.single}' ||
      url.toString() != 'https://files.catbox.moe/${result.remoteId}') {
    return '此链接不符合 Catbox 单文件删除条件；可移除本地记录。';
  }
  return null;
}

String _targetLabel(TargetSnapshot t) =>
    '${t.alias} · ${t.service == ImageHostService.catbox ? 'Catbox' : 'ImgBB'} · ${t.id.length > 8 ? t.id.substring(0, 8) : t.id}${t.anonymous ? ' · 匿名' : ''}';

String _availabilityLabel(LinkAvailability state) => switch (state) {
  LinkAvailability.recorded => '链接已记录，尚未主动检测',
  LinkAvailability.accessible => '可访问（检测时）',
  LinkAvailability.deleted => '远端已删除（服务报告）',
  LinkAvailability.unknown => '未能确认',
};
String _probeReason(LinkProbeReason reason) => switch (reason) {
  LinkProbeReason.reachable => '服务在检测时确认图片地址可访问；不保证永久可用。',
  LinkProbeReason.gone => '服务返回 HTTP 410，报告资源不再提供；本地历史仍保留。',
  LinkProbeReason.unconfirmed => '未取得可靠的可访问或已删除证据；一次失败不删除历史。',
  LinkProbeReason.cancelled => '检测已取消，未能确认当前状态。',
  LinkProbeReason.timeout => '检测超时，未能确认当前状态。',
  LinkProbeReason.unsupported => '此地址不符合当前服务的安全检测条件，未发送请求。',
  LinkProbeReason.interrupted => '检测尚未完成或曾中断，请主动重新确认。',
};
String _formatLabel(UploadLinkFormat f) => switch (f) {
  UploadLinkFormat.url => 'URL',
  UploadLinkFormat.markdown => 'Markdown',
  UploadLinkFormat.html => 'HTML',
  UploadLinkFormat.bbcode => 'BBCode',
};
