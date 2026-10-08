import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/library_repository.dart';
import '../domain/gallery_query.dart';
import '../domain/library_models.dart';
import 'asset_widgets.dart';
import 'gallery_providers.dart';
import 'library_organization_editor.dart';
import 'library_failure_view.dart';
import 'gallery_filter_controls.dart';
import 'original_preview_screen.dart';

enum DesktopDestination {
  gallery,
  processing,
  tasks,
  links,
  accounts,
  backup,
  settings,
}

/// Desktop A stays a desktop composition at narrow widths. Platform routing is
/// owned by GalleryScreen; width only collapses navigation and the inspector.
class DesktopGallery extends ConsumerStatefulWidget {
  const DesktopGallery({
    super.key,
    required this.gallery,
    required this.session,
    required this.busy,
    required this.loadingMore,
    required this.onImport,
    required this.onRetry,
    required this.onRefresh,
    required this.onLoadMore,
    required this.notices,
    this.onNavigate,
    this.onAssetLinks,
  });
  final AsyncValue<GalleryPage> gallery;
  final AsyncValue<LibrarySession> session;
  final bool busy;
  final bool loadingMore;
  final Future<void> Function(bool photos) onImport;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final List<Widget> notices;
  final ValueChanged<DesktopDestination>? onNavigate;
  final ValueChanged<List<String>>? onAssetLinks;
  @override
  ConsumerState<DesktopGallery> createState() => _DesktopGalleryState();
}

class _DesktopGalleryState extends ConsumerState<DesktopGallery> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final Set<String> _selection = {};
  Timer? _debounce;
  bool _searchPending = false;
  bool _working = false;
  bool _awaitingDialog = false;
  bool _selecting = false;
  String? _feedback;
  String? _copyProgress;
  ImageAsset? _focused;
  int? _dueCount;

  bool get _ready =>
      widget.session.hasValue &&
      !widget.session.isLoading &&
      !widget.session.hasError &&
      widget.gallery.hasValue &&
      !widget.gallery.isLoading &&
      !widget.gallery.hasError &&
      !_searchPending;
  bool get _blocked => widget.busy || _working;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(galleryQueryProvider).keyword;
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      _debounce?.cancel();
      _search.clear();
      setState(() {
        _selection.clear();
        _selecting = false;
        _searchPending = false;
        _focused = null;
        _dueCount = null;
        _feedback = null;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    setState(() => _searchPending = true);
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      ref.read(galleryQueryProvider.notifier).setKeyword(value);
      setState(() => _searchPending = false);
    });
  }

  void _clearQuery() {
    _debounce?.cancel();
    _search.clear();
    ref.read(galleryQueryProvider.notifier).clear();
    setState(() => _searchPending = false);
  }

  Future<void> _switchRecycle(bool recycle) async {
    if (_blocked) return;
    _debounce?.cancel();
    _search.clear();
    ref
        .read(galleryQueryProvider.notifier)
        .replace(GalleryQuery(recycledOnly: recycle));
    setState(() {
      _searchPending = false;
      _focused = null;
      _dueCount = null;
    });
    if (recycle) {
      try {
        final count = await widget.session.requireValue.repository
            .recycledDueCount();
        if (mounted) setState(() => _dueCount = count);
      } catch (error) {
        if (mounted) setState(() => _feedback = '到期提示读取失败：$error');
      }
    }
  }

  Future<void> _reload() async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(tagsProvider);
    await widget.onRefresh();
    if (!mounted) return;
    ref.invalidate(assetPreviewProvider);
    final focused = _focused;
    if (focused != null) {
      final updated = await widget.session.requireValue.repository.getAsset(
        focused.id,
        includeRecycled: true,
      );
      if (mounted) setState(() => _focused = updated);
    }
    if (ref.read(galleryQueryProvider).recycledOnly) {
      final count = await widget.session.requireValue.repository
          .recycledDueCount();
      if (mounted) setState(() => _dueCount = count);
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_blocked || !_ready) return;
    setState(() {
      _working = true;
      _feedback = null;
    });
    try {
      await action();
      if (!mounted) return;
      await _reload();
      if (mounted) setState(() => _feedback = success);
    } catch (error) {
      if (!mounted) return;
      final reason = error is FormatException
          ? error.message
          : error.toString();
      ref.invalidate(assetPreviewProvider);
      try {
        await _reload();
        if (mounted) {
          setState(() => _feedback = '操作未全部完成：$reason。已重新读取实际图库，请核对结果。');
        }
      } catch (refreshError) {
        if (mounted) {
          setState(
            () => _feedback =
                '操作未全部完成：$reason。重新读取也失败：$refreshError。已载入记录保留，请重试刷新。',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _copyProgress = null;
        });
      }
    }
  }

  Future<void> _selectMatching() async {
    if (_blocked || !_ready) return;
    final query = ref.read(galleryQueryProvider);
    setState(() => _working = true);
    try {
      final ids = await widget.session.requireValue.repository.matchingAssetIds(
        query: query,
      );
      if (mounted && _selecting) setState(() => _selection.addAll(ids));
    } catch (error) {
      if (mounted) setState(() => _feedback = '选择结果读取失败，已有选择保留：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _review() async {
    if (_blocked || !_ready || _selection.isEmpty) return;
    final ids = List<String>.unmodifiable(_selection);
    final repository = widget.session.requireValue.repository;
    final lookup = Future.wait(
      ids.map((id) => repository.getAsset(id, includeRecycled: true)),
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('核对已选 ${ids.length} 张'),
        content: SizedBox(
          width: 520,
          height: 340,
          child: FutureBuilder<List<ImageAsset?>>(
            future: lookup,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('无法核对所选记录：${snapshot.error}');
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final assets = snapshot.requireData;
              return ListView(
                children: [
                  const Text('选择按稳定身份保留，包含当前筛选之外及其他分页的图片。'),
                  for (var i = 0; i < ids.length; i++)
                    ListTile(
                      title: Text(assets[i]?.displayName ?? '记录已不存在'),
                      subtitle: Text(
                        '${ids[i]}${assets[i]?.recycled == true ? ' · 回收区' : ''}',
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(_selection.clear);
            },
            child: const Text('清空选择'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('核对完成'),
          ),
        ],
      ),
    );
  }

  Future<void> _organize(Iterable<String> ids) async {
    if (_blocked || !_ready) return;
    setState(() {
      _working = true;
      _awaitingDialog = true;
    });
    try {
      final saved = await showLibraryOrganizationEditor(context, ids);
      if (mounted) setState(() => _awaitingDialog = false);
      if (saved && mounted) {
        await _reload();
        if (mounted) setState(() => _feedback = '整理已保存。');
      }
    } catch (error) {
      if (mounted) setState(() => _feedback = '整理结果刷新失败，请重新读取图库：$error');
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _awaitingDialog = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(String id) => _run(() async {
    final repository = widget.session.requireValue.repository;
    final latest = await repository.getAsset(id);
    if (latest == null) throw StateError('图片已不在图库中，请重新核对。');
    await repository.setFavorites([id], !latest.favorite);
  }, '收藏状态已更新。');

  Future<void> _remove(Iterable<String> selected) async {
    final ids = List<String>.unmodifiable(selected);
    if (_blocked || !_ready || ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('将 ${ids.length} 张图片移入回收区？'),
        content: const Text(
          '仅移除图库中的资产，可恢复原身份、整理与历史。本机副本、外部原图与远程文件保留；30 天到期也只提示。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移入回收区'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run(() async {
      await widget.session.requireValue.repository.removeAssets(ids);
      if (mounted) {
        setState(() {
          _selection.removeAll(ids);
          if (ids.contains(_focused?.id)) _focused = null;
        });
      }
    }, '已将 ${ids.length} 张图片移入回收区，副本保留。');
  }

  Future<void> _restore(Iterable<String> selected) async {
    final ids = List<String>.unmodifiable(selected);
    await _run(() async {
      await widget.session.requireValue.repository.restoreAssets(ids);
      if (mounted) {
        setState(() {
          _selection.removeAll(ids);
          if (ids.contains(_focused?.id)) _focused = null;
        });
      }
    }, '已恢复 ${ids.length} 张图片，身份、整理与历史保留。');
  }

  Future<void> _purge(Iterable<String> selected) async {
    final ids = List<String>.unmodifiable(selected);
    if (_blocked || !_ready || ids.isEmpty) return;
    var mode = 0;
    var records = false;
    var copies = false;
    final confirmed = await showDialog<(bool, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('永久清除 ${ids.length} 张回收图片'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '仅作用于所选回收资产。外部来源与远程文件不删除；活跃依赖或仍被有效资产引用的共享副本会阻止清除。',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: '清除对象'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('只清记录')),
                      DropdownMenuItem(value: 1, child: Text('只清副本')),
                      DropdownMenuItem(value: 2, child: Text('同时清除')),
                    ],
                    onChanged: (value) => update(() {
                      mode = value!;
                      records = false;
                      copies = false;
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (mode != 1)
                    CheckboxListTile(
                      key: const Key('purge-confirm-records'),
                      contentPadding: EdgeInsets.zero,
                      value: records,
                      onChanged: (value) => update(() => records = value!),
                      title: Text('确认永久清除 ${ids.length} 张资产记录'),
                      subtitle: const Text(
                        '删除这些资产的名称、整理、历史关联与远程链接记录，之后不能恢复。只清记录时独立字节保留。',
                      ),
                    ),
                  if (mode != 0)
                    CheckboxListTile(
                      key: const Key('purge-confirm-copies'),
                      contentPadding: EdgeInsets.zero,
                      value: copies,
                      onChanged: (value) => update(() => copies = value!),
                      title: Text('确认永久清除 ${ids.length} 张资产的本机副本'),
                      subtitle: const Text(
                        '副本字节不可恢复。只清副本时资产、整理与远程链接保留，副本状态变为缺失。',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('purge-execute'),
              onPressed: (mode == 1 || records) && (mode == 0 || copies)
                  ? () => Navigator.pop(context, (mode != 1, mode != 0))
                  : null,
              child: const Text('执行永久清除'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed == null) return;
    await _run(
      () async {
        final repository = widget.session.requireValue.repository;
        for (final id in ids) {
          final asset = await repository.getAsset(id, includeRecycled: true);
          if (asset == null || !asset.recycled) {
            throw StateError(
              asset == null
                  ? '所选记录已不存在，请重新核对选择。'
                  : '“${asset.displayName}”仍在图库中。此入口只清除回收资产，请核对选择。',
            );
          }
        }
        await repository.purgeAssets(
          ids,
          confirmRecords: confirmed.$1,
          confirmCopies: confirmed.$2,
        );
        if (mounted) {
          setState(() {
            _selection.removeAll(ids);
            if (ids.contains(_focused?.id)) _focused = null;
          });
        }
      },
      '永久清除已完成：${confirmed.$1 ? '已清记录' : '记录保留'}，${confirmed.$2 ? '已清副本' : '副本保留'}。',
    );
  }

  Future<void> _verifyCopies() async => _run(() async {
    await widget.session.requireValue.repository.refreshCopyStatuses(
      onProgress: (done, total) {
        if (mounted) setState(() => _copyProgress = '已校验 $done / $total 个本机副本');
      },
    );
  }, '全部副本校验结束，可用性筛选已更新。');

  void _openAsset(ImageAsset asset, bool inspector) {
    setState(() => _focused = asset);
    if (!inspector) {
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 480,
            child: _AssetInspector(
              asset: asset,
              dialog: true,
              enabled: _ready && !_blocked,
              onFavorite: () => _toggleFavorite(asset.id),
              onOrganize: () => _organize([asset.id]),
              onRemove: () => _remove([asset.id]),
              onRestore: () => _restore([asset.id]),
              onPurge: () => _purge([asset.id]),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(galleryQueryProvider);
    if (!_searchPending && _search.text != query.keyword) {
      _search.text = query.keyword;
    }
    final recycle = query.recycledOnly;
    final page = widget.gallery.asData?.value;
    final focused =
        page?.items.where((asset) => asset.id == _focused?.id).firstOrNull ??
        _focused;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fullNav = constraints.maxWidth >= 760;
            final inspector = constraints.maxWidth >= 1180;
            return Row(
              children: [
                _DesktopSidebar(
                  expanded: fullNav,
                  recycle: recycle,
                  enabled: _ready && !_blocked,
                  onGallery: () => _switchRecycle(false),
                  onRecycle: () => _switchRecycle(true),
                  onNavigate: widget.onNavigate,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: fullNav ? 24 : 12,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '本机图库  ›  ${recycle ? '回收区' : '我的图库'}',
                              ),
                            ),
                            const Tooltip(
                              message: '本地模式 · 无需登录',
                              child: Icon(Icons.computer_outlined, size: 18),
                            ),
                            if (fullNav) const Text('  本地模式'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(fullNav ? 24 : 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  Text(
                                    recycle ? '回收区' : '我的图库',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  FilledButton.icon(
                                    key: const Key('import-files'),
                                    onPressed: _ready && !_blocked && !recycle
                                        ? () => widget.onImport(false)
                                        : null,
                                    icon: const Icon(Icons.add),
                                    label: const Text('导入图片'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      key: const Key('desktop-search'),
                                      controller: _search,
                                      enabled: !_blocked,
                                      onChanged: _searchChanged,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        prefixIcon: Icon(Icons.search),
                                        hintText:
                                            '搜索名称、来源、格式、分类、标签、图床、历史账号与普通 URL',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: const Key('desktop-filters'),
                                    tooltip: '组合筛选与排序',
                                    onPressed: _ready && !_blocked
                                        ? () => showDialog<void>(
                                            context: context,
                                            builder: (_) =>
                                                const GalleryFilterDialog(),
                                          )
                                        : null,
                                    icon: const Icon(Icons.tune),
                                  ),
                                  IconButton(
                                    tooltip: '清空条件',
                                    onPressed: _blocked ? null : _clearQuery,
                                    icon: const Icon(
                                      Icons.filter_alt_off_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  FilterChip(
                                    key: const Key('desktop-favorites'),
                                    label: const Text('仅收藏'),
                                    selected: query.favoritesOnly,
                                    onSelected: _blocked
                                        ? null
                                        : (value) => ref
                                              .read(
                                                galleryQueryProvider.notifier,
                                              )
                                              .setFavoritesOnly(value),
                                  ),
                                  TextButton(
                                    onPressed: _ready && !_blocked
                                        ? () => setState(() {
                                            _selecting = !_selecting;
                                            if (!_selecting) _selection.clear();
                                          })
                                        : null,
                                    child: Text(_selecting ? '结束多选' : '多选'),
                                  ),
                                  IconButton(
                                    tooltip: '重新读取图库',
                                    onPressed: _ready && !_blocked
                                        ? () => _run(() async {}, '已重新读取图库。')
                                        : null,
                                    icon: const Icon(Icons.refresh),
                                  ),
                                  TextButton(
                                    onPressed: _ready && !_blocked
                                        ? _verifyCopies
                                        : null,
                                    child: const Text('校验全部副本'),
                                  ),
                                ],
                              ),
                              if (!query.isUnfiltered)
                                Text(
                                  '组合筛选中 · ${page?.total ?? '…'} 张匹配 · 条件按交集应用',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (recycle)
                                Text(
                                  '30 天到期仅提示，未经确认持续保留。${_dueCount == null ? '' : '当前 $_dueCount 张可清理。'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (_selecting) _selectionBar(recycle),
                              if (widget.notices.isNotEmpty ||
                                  _feedback != null ||
                                  _copyProgress != null)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 130,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ...widget.notices,
                                        if (_feedback != null)
                                          _InfoNotice(_feedback!),
                                        if (_copyProgress != null)
                                          _InfoNotice(_copyProgress!),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_working && !_awaitingDialog)
                                const LinearProgressIndicator(),
                              const SizedBox(height: 10),
                              Expanded(
                                child: widget.gallery.when(
                                  skipLoadingOnRefresh: false,
                                  skipLoadingOnReload: false,
                                  loading: () =>
                                      const Center(child: Text('正在打开本机图库…')),
                                  error: (error, _) => LibraryFailureView(
                                    error: error,
                                    onRetry: widget.onRetry,
                                  ),
                                  data: (page) => page.items.isEmpty
                                      ? _empty(query)
                                      : Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Text(
                                                    '${page.total} 张 · 已载入 ${page.items.length} 张',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Expanded(
                                                    child: GridView.builder(
                                                      key: const Key(
                                                        'desktop-grid',
                                                      ),
                                                      controller: _scroll,
                                                      gridDelegate:
                                                          const SliverGridDelegateWithMaxCrossAxisExtent(
                                                            maxCrossAxisExtent:
                                                                260,
                                                            mainAxisExtent: 255,
                                                            crossAxisSpacing:
                                                                16,
                                                            mainAxisSpacing: 16,
                                                          ),
                                                      itemCount:
                                                          page.items.length,
                                                      itemBuilder: (context, index) {
                                                        final asset =
                                                            page.items[index];
                                                        return _DesktopAssetCard(
                                                          asset: asset,
                                                          selected: _selecting
                                                              ? _selection
                                                                    .contains(
                                                                      asset.id,
                                                                    )
                                                              : focused?.id ==
                                                                    asset.id,
                                                          selecting: _selecting,
                                                          onSelect: _blocked
                                                              ? null
                                                              : () => setState(() {
                                                                  if (!_selection
                                                                      .add(
                                                                        asset
                                                                            .id,
                                                                      )) {
                                                                    _selection
                                                                        .remove(
                                                                          asset
                                                                              .id,
                                                                        );
                                                                  }
                                                                }),
                                                          onOpen: () =>
                                                              _openAsset(
                                                                asset,
                                                                inspector,
                                                              ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  if (page.items.length <
                                                      page.total)
                                                    TextButton(
                                                      onPressed:
                                                          _ready &&
                                                              !_blocked &&
                                                              !widget
                                                                  .loadingMore
                                                          ? widget.onLoadMore
                                                          : null,
                                                      child: Text(
                                                        widget.loadingMore
                                                            ? '正在读取…'
                                                            : '加载更多',
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            if (inspector) ...[
                                              const SizedBox(width: 24),
                                              SizedBox(
                                                width: 285,
                                                child: focused == null
                                                    ? const Center(
                                                        child: Text(
                                                          '选择图片，查看副本与元信息。',
                                                        ),
                                                      )
                                                    : _AssetInspector(
                                                        asset: focused,
                                                        enabled:
                                                            _ready && !_blocked,
                                                        onFavorite: () =>
                                                            _toggleFavorite(
                                                              focused.id,
                                                            ),
                                                        onOrganize: () =>
                                                            _organize([
                                                              focused.id,
                                                            ]),
                                                        onRemove: () => _remove(
                                                          [focused.id],
                                                        ),
                                                        onRestore: () =>
                                                            _restore([
                                                              focused.id,
                                                            ]),
                                                        onPurge: () => _purge([
                                                          focused.id,
                                                        ]),
                                                      ),
                                              ),
                                            ],
                                          ],
                                        ),
                                ),
                              ),
                              if (fullNav)
                                const Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text(
                                    '永久副本与来源独立；卸载或清除应用数据可能移除副本。',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xff626d7a),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _selectionBar(bool recycle) => Container(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text('已选 ${_selection.length} 张'),
        TextButton(
          key: const Key('desktop-select-matching'),
          onPressed: _ready && !_blocked ? _selectMatching : null,
          child: const Text('选中全部匹配'),
        ),
        TextButton(
          onPressed: _blocked ? null : () => setState(_selection.clear),
          child: const Text('清空选择'),
        ),
        TextButton(
          key: const Key('desktop-review-selection'),
          onPressed: _selection.isNotEmpty && _ready && !_blocked
              ? _review
              : null,
          child: const Text('核对选择'),
        ),
        if (!recycle) ...[
          TextButton(
            key: const Key('desktop-copy-links'),
            onPressed:
                _selection.isNotEmpty &&
                    _ready &&
                    !_blocked &&
                    widget.onAssetLinks != null
                ? () => widget.onAssetLinks!(
                    List<String>.unmodifiable(_selection),
                  )
                : null,
            child: const Text('复制链接'),
          ),
          TextButton(
            onPressed: _selection.isNotEmpty && _ready && !_blocked
                ? () => _organize(List.of(_selection))
                : null,
            child: const Text('批量整理'),
          ),
          PopupMenuButton<bool>(
            enabled: _selection.isNotEmpty && _ready && !_blocked,
            tooltip: '批量收藏',
            onSelected: (favorite) {
              final ids = List<String>.of(_selection);
              _run(
                () async => widget.session.requireValue.repository.setFavorites(
                  ids,
                  favorite,
                ),
                '已${favorite ? '收藏' : '取消收藏'} ${ids.length} 张。',
              );
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('收藏所选')),
              PopupMenuItem(value: false, child: Text('取消所选收藏')),
            ],
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Text('批量收藏'),
            ),
          ),
          TextButton(
            onPressed: _selection.isNotEmpty && _ready && !_blocked
                ? () => _remove(List.of(_selection))
                : null,
            child: const Text('移入回收区'),
          ),
        ],
        if (recycle) ...[
          TextButton(
            onPressed: _selection.isNotEmpty && _ready && !_blocked
                ? () => _restore(List.of(_selection))
                : null,
            child: const Text('恢复所选'),
          ),
          TextButton(
            onPressed: _selection.isNotEmpty && _ready && !_blocked
                ? () => _purge(List.of(_selection))
                : null,
            child: const Text('永久清除所选'),
          ),
        ],
      ],
    ),
  );
  Widget _empty(GalleryQuery query) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 48,
            color: Color(0xff626d7a),
          ),
          const SizedBox(height: 16),
          Text(
            query.isUnfiltered
                ? (query.recycledOnly ? '回收区为空' : '图库还是空的')
                : '没有匹配的图片',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            query.isUnfiltered
                ? (query.recycledOnly ? '移除的资产可在这里恢复。' : '导入图片后，这里会保留独立的本机副本。')
                : '调整条件后重试，已有选择仍保留。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (query.isUnfiltered && !query.recycledOnly)
            OutlinedButton(
              onPressed: _ready && !_blocked
                  ? () => widget.onImport(false)
                  : null,
              child: const Text('选择图片'),
            ),
          if (!query.isUnfiltered)
            TextButton(onPressed: _clearQuery, child: const Text('清空筛选')),
        ],
      ),
    ),
  );
}

class _InfoNotice extends StatelessWidget {
  const _InfoNotice(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xffedf1ff),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message),
  );
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.expanded,
    required this.recycle,
    required this.enabled,
    required this.onGallery,
    required this.onRecycle,
    this.onNavigate,
  });
  final bool expanded, recycle, enabled;
  final VoidCallback onGallery, onRecycle;
  final ValueChanged<DesktopDestination>? onNavigate;
  @override
  Widget build(BuildContext context) => Container(
    width: expanded ? 190 : 62,
    padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 4, vertical: 24),
    child: Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expanded)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'ImageHost',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
              ),
            )
          else
            const Tooltip(
              message: 'ImageHost',
              child: Icon(Icons.photo_library_outlined),
            ),
          const SizedBox(height: 24),
          _entry('图库', Icons.grid_view, !recycle, enabled ? onGallery : null),
          for (final entry in [
            (DesktopDestination.processing, '图片处理', Icons.crop),
            (DesktopDestination.tasks, '上传任务', Icons.checklist),
            (DesktopDestination.links, '成功链接', Icons.link),
            (DesktopDestination.accounts, '图床账号', Icons.cloud_outlined),
            (DesktopDestination.backup, '备份与恢复', Icons.backup_outlined),
            (DesktopDestination.settings, '设置', Icons.settings_outlined),
          ])
            _entry(
              entry.$2,
              entry.$3,
              false,
              enabled && onNavigate != null
                  ? () => onNavigate!(entry.$1)
                  : null,
            ),
          const Spacer(),
          _entry(
            '回收区',
            Icons.delete_outline,
            recycle,
            enabled ? onRecycle : null,
          ),
          if (expanded)
            const Padding(
              padding: EdgeInsets.only(top: 16, left: 4),
              child: Text(
                '本机图库 · 无需登录',
                style: TextStyle(color: Color(0xff626d7a), fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );
  Widget _entry(
    String name,
    IconData icon,
    bool selected,
    VoidCallback? action,
  ) => Tooltip(
    message: action == null && !selected ? '$name尚未接入或当前不可操作' : name,
    child: expanded
        ? ListTile(
            dense: true,
            selected: selected,
            selectedTileColor: const Color(0xffedf1ff),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            enabled: action != null,
            leading: Icon(icon, size: 22),
            title: Text(name),
            onTap: action,
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: IconButton(
              onPressed: action,
              icon: Icon(
                icon,
                color: selected ? const Color(0xff315de6) : null,
              ),
            ),
          ),
  );
}

class _DesktopAssetCard extends StatelessWidget {
  const _DesktopAssetCard({
    required this.asset,
    required this.selected,
    required this.selecting,
    required this.onOpen,
    this.onSelect,
  });
  final ImageAsset asset;
  final bool selected, selecting;
  final VoidCallback onOpen;
  final VoidCallback? onSelect;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${selecting ? '选择' : '查看'} ${asset.displayName}',
    selected: selecting ? selected : null,
    child: InkWell(
      key: Key('desktop-asset-${asset.id}'),
      onTap: selecting ? onSelect : onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xff315de6) : const Color(0xffe2e6ec),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(9),
                    ),
                    child: AssetPreviewImage(asset: asset),
                  ),
                  if (selecting)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Checkbox(
                        value: selected,
                        onChanged: onSelect == null ? null : (_) => onSelect!(),
                      ),
                    ),
                  if (asset.favorite)
                    const Positioned(
                      top: 10,
                      right: 10,
                      child: Icon(Icons.star, color: Color(0xffffb300)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${asset.version.format.toUpperCase()} · ${formatBytes(asset.version.byteCount)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff626d7a),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          asset.category ?? '未分类',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (selecting)
                        IconButton(
                          tooltip: '查看图片详情',
                          onPressed: onOpen,
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.info_outline),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AssetInspector extends ConsumerStatefulWidget {
  const _AssetInspector({
    required this.asset,
    required this.enabled,
    required this.onFavorite,
    required this.onOrganize,
    required this.onRemove,
    required this.onRestore,
    required this.onPurge,
    this.dialog = false,
  });
  final ImageAsset asset;
  final bool enabled, dialog;
  final Future<void> Function() onFavorite,
      onOrganize,
      onRemove,
      onRestore,
      onPurge;
  @override
  ConsumerState<_AssetInspector> createState() => _AssetInspectorState();
}

class _AssetInspectorState extends ConsumerState<_AssetInspector> {
  bool _acting = false;
  ImageAsset? _current;
  String? _error;
  bool _removed = false;
  @override
  void initState() {
    super.initState();
    _current = widget.asset;
  }

  @override
  void didUpdateWidget(covariant _AssetInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _current = widget.asset;
      _removed = false;
      _error = null;
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      final repository = (await ref.read(librarySessionProvider.future))
          .repository;
      final latest = await repository.getAsset(
        widget.asset.id,
        includeRecycled: true,
      );
      if (mounted) {
        setState(() {
          _current = latest;
          _removed = latest == null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '详情刷新失败，请关闭后重新打开：$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(galleryProvider).asData?.value;
    final asset =
        page?.items.where((asset) => asset.id == widget.asset.id).firstOrNull ??
        _current ??
        widget.asset;
    final dialog = widget.dialog;
    final enabled = widget.enabled && !_acting;
    final preview = ref.watch(assetPreviewProvider(asset));
    if (_removed) {
      return const Center(child: Text('该资产记录已永久清除。'));
    }
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(dialog ? 20 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '图片详情',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (dialog)
                  IconButton(
                    tooltip: '关闭详情',
                    onPressed: _acting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            SizedBox(height: 200, child: AssetPreviewImage(asset: asset)),
            TextButton.icon(
              key: const Key('desktop-original-preview'),
              onPressed: !enabled || asset.recycled
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OriginalPreviewScreen(asset: asset),
                      ),
                    ),
              icon: Icon(
                asset.version.isAnimated
                    ? Icons.play_circle_outline
                    : Icons.zoom_in,
              ),
              label: Text(asset.version.isAnimated ? '查看原图与播放动画' : '查看原图'),
            ),
            if (_acting) const Text('等待操作结果…'),
            if (_error != null) Text(_error!),
            const SizedBox(height: 12),
            SelectableText(
              asset.displayName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              preview.hasError
                  ? '副本校验失败，请重试预览。'
                  : preview.asData == null
                  ? '正在校验本机副本…'
                  : copyLabel(preview.requireValue.availability),
            ),
            const SizedBox(height: 8),
            if (!asset.recycled)
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    key: const Key('desktop-favorite'),
                    onPressed: enabled ? () => _act(widget.onFavorite) : null,
                    icon: Icon(asset.favorite ? Icons.star : Icons.star_border),
                    label: Text(asset.favorite ? '取消收藏' : '收藏'),
                  ),
                  TextButton(
                    onPressed: enabled ? () => _act(widget.onOrganize) : null,
                    child: const Text('整理图片'),
                  ),
                  TextButton(
                    onPressed: enabled ? () => _act(widget.onRemove) : null,
                    child: const Text('移入回收区'),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: enabled ? () => _act(widget.onRestore) : null,
                    child: const Text('恢复图片'),
                  ),
                  TextButton(
                    onPressed: enabled ? () => _act(widget.onPurge) : null,
                    child: const Text('永久清除'),
                  ),
                ],
              ),
            const Divider(height: 24),
            for (final row in [
              ('分类', asset.category ?? '未分类'),
              (
                '标签',
                asset.tags.isEmpty
                    ? '暂无标签'
                    : asset.tags.map((tag) => tag.name).join('、'),
              ),
              ('格式', asset.version.format.toUpperCase()),
              ('尺寸', '${asset.version.width} × ${asset.version.height}'),
              ('大小', formatBytes(asset.version.byteCount)),
              (
                '导入时间',
                DateFormat('yyyy-MM-dd HH:mm:ss')
                    .format(asset.importedAt.toLocal()),
              ),
              ('来源', '${sourceLabel(asset.sourceType)} · 独立副本'),
              ('内容版本', asset.version.id),
              if (asset.recycledAt != null)
                (
                  '回收时间',
                  DateFormat('yyyy-MM-dd HH:mm')
                      .format(asset.recycledAt!.toLocal()),
                ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.$1,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff626d7a),
                      ),
                    ),
                    SelectableText(row.$2),
                  ],
                ),
              ),
            Text(
              '当前永久版本：${asset.confirmedRemoteResultCount} 项已确认普通链接。',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              asset.lastConfirmedUploadAt == null
                  ? '尚无确认上传时间。'
                  : '最近确认上传：${DateFormat('yyyy-MM-dd HH:mm:ss').format(asset.lastConfirmedUploadAt!.toLocal())}',
              style: const TextStyle(fontSize: 12),
            ),
            const Text(
              '其他处理版本请在链接页查看；链接存在不代表当前可达。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              '缩略图可重新生成，永久副本保留原始字节。',
              style: TextStyle(fontSize: 12, color: Color(0xff626d7a)),
            ),
          ],
        ),
      ),
    );
  }
}
