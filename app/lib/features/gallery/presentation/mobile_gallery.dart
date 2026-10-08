import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/library_repository.dart';
import '../domain/library_models.dart';
import '../domain/gallery_query.dart';
import 'asset_widgets.dart';
import 'gallery_providers.dart';
import 'library_organization_editor.dart';
import 'library_failure_view.dart';
import 'gallery_filter_controls.dart';
import 'original_preview_screen.dart';
import '../../links/presentation/link_results_screen.dart';

const _accent = Color(0xff3a5be0);
const _muted = Color(0xff657184);
const _background = Color(0xfff7f8fa);
const _line = Color(0xffe5e9f0);

ThemeData _m1Theme(ThemeData theme) {
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(11));
  return theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      primary: _accent,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: _background,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 46),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 46),
        shape: shape,
        side: const BorderSide(color: _line),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
  );
}

/// Mobile M1 presents confirmed repository data; no prototype fixtures or tasks.
class MobileGallery extends ConsumerStatefulWidget {
  const MobileGallery({
    super.key,
    required this.gallery,
    required this.session,
    required this.busy,
    required this.loadingMore,
    required this.supportsPhotos,
    required this.onImport,
    required this.onRetry,
    required this.onRefresh,
    required this.onLoadMore,
    required this.notices,
    this.onProcessing,
    this.onAccounts,
    this.onTasks,
    this.onBackup,
    this.onSettings,
    this.onAssetLinks,
    this.onLinksVisibility,
    this.onRequestExit,
  });
  final AsyncValue<GalleryPage> gallery;
  final AsyncValue<LibrarySession> session;
  final bool busy;
  final bool loadingMore;
  final bool supportsPhotos;
  final Future<void> Function(bool photos) onImport;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final VoidCallback? onProcessing;
  final VoidCallback? onAccounts;
  final VoidCallback? onTasks;
  final VoidCallback? onBackup;
  final VoidCallback? onSettings;
  final ValueChanged<List<String>>? onAssetLinks;
  final ValueChanged<bool>? onLinksVisibility;
  final Future<void> Function()? onRequestExit;
  final List<Widget> notices;

  @override
  ConsumerState<MobileGallery> createState() => _MobileGalleryState();
}

class _MobileGalleryState extends ConsumerState<MobileGallery> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final Set<String> _selectedIds = {};
  Timer? _searchDelay;
  int _section = 0;
  bool _selecting = false;
  bool _dense = false;
  bool _selectingAll = false;
  bool _searchPending = false;
  bool _linksBusy = false;
  bool _working = false;
  bool _exitPending = false;
  int? _dueCount;
  GalleryPage? _lastPage;
  String? _operationFeedback;
  int _mutationGeneration = 0;

  bool get _blocked => widget.busy || _working || _exitPending;

  bool get _ready =>
      widget.session.hasValue &&
      !widget.session.isLoading &&
      !widget.session.hasError &&
      widget.gallery.hasValue &&
      !widget.gallery.isLoading &&
      !widget.gallery.hasError &&
      !_searchPending;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(galleryQueryProvider).keyword;
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      _mutationGeneration++;
      _searchDelay?.cancel();
      _search.clear();
      setState(() {
        _selectedIds.clear();
        _selecting = false;
        _selectingAll = false;
        _searchPending = false;
        _section = 0;
        _lastPage = null;
        _dueCount = null;
        _operationFeedback = null;
      });
      widget.onLinksVisibility?.call(false);
    });
  }

  @override
  void dispose() {
    _searchDelay?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _message(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _handleBack() async {
    if (_exitPending || _linksBusy || _working || _selectingAll) return;
    if (_selecting) {
      _cancelSelection();
      return;
    }
    if (_section != 0) {
      setState(() => _section = 0);
      widget.onLinksVisibility?.call(false);
      return;
    }
    if (ref.read(galleryQueryProvider).recycledOnly && !widget.busy) {
      await _switchRecycle(false);
      return;
    }
    final request = widget.onRequestExit;
    if (request == null) {
      if (widget.busy) _message('导入正在进行，可先停止后续导入。已保存图片保留。');
      return;
    }
    setState(() => _exitPending = true);
    try {
      await request();
    } catch (_) {
      if (mounted) _message('尚未确认安全退出，请等待当前操作完成后重试。');
    } finally {
      if (mounted) setState(() => _exitPending = false);
    }
  }

  Future<void> _switchRecycle(bool recycle) async {
    if (_blocked || _selectingAll || _linksBusy) return;
    _searchDelay?.cancel();
    _search.clear();
    ref
        .read(galleryQueryProvider.notifier)
        .replace(GalleryQuery(recycledOnly: recycle));
    setState(() {
      _searchPending = false;
      _dueCount = null;
      _operationFeedback = null;
      _section = 0;
    });
    widget.onLinksVisibility?.call(false);
    if (!recycle) return;
    try {
      final count = await widget.session.requireValue.repository
          .recycledDueCount();
      if (mounted && ref.read(galleryQueryProvider).recycledOnly) {
        setState(() => _dueCount = count);
      }
    } catch (_) {
      if (mounted) setState(() => _operationFeedback = '到期提示读取失败，回收记录仍保留，请重试。');
    }
  }

  Future<void> _reloadAfterMutation() async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(tagsProvider);
    ref.invalidate(assetPreviewProvider);
    await widget.onRefresh();
    if (mounted && ref.read(galleryQueryProvider).recycledOnly) {
      final count = await widget.session.requireValue.repository
          .recycledDueCount();
      if (mounted) setState(() => _dueCount = count);
    }
  }

  Future<void> _refreshDirectly() async {
    try {
      await widget.onRefresh();
    } catch (_) {
      if (mounted) {
        setState(() => _operationFeedback = '图库刷新失败，最后有效列表保留，请重试读取。');
      }
    }
  }

  Future<bool> _mutate(Future<String> Function() action) async {
    if (_blocked || _selectingAll || !_ready) return false;
    setState(() {
      _working = true;
      _operationFeedback = null;
    });
    var committed = false;
    try {
      final message = await action();
      committed = true;
      try {
        await _reloadAfterMutation();
        if (mounted) setState(() => _operationFeedback = message);
      } catch (_) {
        if (mounted) {
          setState(
            () => _operationFeedback = '$message 图库刷新失败，最后有效列表保留，请重试读取。',
          );
        }
      }
    } catch (_) {
      try {
        await _reloadAfterMutation();
        if (mounted) {
          setState(
            () => _operationFeedback =
                '操作未全部完成。保护引用或文件读写可能阻止清除，已重新读取实际图库，请核对后重试。',
          );
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => _operationFeedback = '操作未全部完成，重新读取也失败。最后有效列表保留，请重试读取并核对结果。',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (mounted && !committed && ModalRoute.of(context)?.isCurrent != true) {
      _message('操作未完成，保护记录保留。请核对当前图片与活动任务。');
    }
    return committed;
  }

  Future<bool> _remove(Iterable<String> selected) async {
    final ids = List<String>.unmodifiable(selected);
    if (_blocked || _selectingAll || !_ready || ids.isEmpty) return false;
    final generation = _mutationGeneration;
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
    if (!mounted || confirmed != true || generation != _mutationGeneration) {
      return false;
    }
    return _mutate(() async {
      final changed = await widget.session.requireValue.repository.removeAssets(
        ids,
      );
      if (mounted) {
        setState(
          () => _selectedIds.removeAll(changed.map((asset) => asset.id)),
        );
      }
      return '已将 ${changed.length} 张图片移入回收区，副本保留。';
    });
  }

  Future<bool> _restore(Iterable<String> selected) async {
    final ids = List<String>.unmodifiable(selected);
    if (ids.isEmpty) return false;
    return _mutate(() async {
      final repository = widget.session.requireValue.repository;
      for (final id in ids) {
        final asset = await repository.getAsset(id, includeRecycled: true);
        if (asset == null || !asset.recycled) {
          throw StateError('所选记录已不存在或已离开回收区，请重新核对。');
        }
      }
      final changed = await repository.restoreAssets(ids);
      if (mounted) {
        setState(
          () => _selectedIds.removeAll(changed.map((asset) => asset.id)),
        );
      }
      return '已恢复 ${changed.length} 张图片，身份、整理与历史保留。';
    });
  }

  Future<bool> _purge(Iterable<String> selected) async {
    final ids = List<String>.unmodifiable(selected);
    if (_blocked || _selectingAll || !_ready || ids.isEmpty) return false;
    final generation = _mutationGeneration;
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
                    key: const Key('mobile-purge-mode'),
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
                      key: const Key('mobile-purge-confirm-records'),
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
                      key: const Key('mobile-purge-confirm-copies'),
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
              key: const Key('mobile-purge-execute'),
              onPressed: (mode == 1 || records) && (mode == 0 || copies)
                  ? () => Navigator.pop(context, (mode != 1, mode != 0))
                  : null,
              child: const Text('执行永久清除'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed == null || generation != _mutationGeneration) {
      return false;
    }
    return _mutate(() async {
      final repository = widget.session.requireValue.repository;
      for (final id in ids) {
        final asset = await repository.getAsset(id, includeRecycled: true);
        if (asset == null || !asset.recycled) {
          throw StateError('所选记录已不存在或已离开回收区，请重新核对。');
        }
      }
      final result = await repository.purgeAssets(
        ids,
        confirmRecords: confirmed.$1,
        confirmCopies: confirmed.$2,
      );
      if (mounted) setState(() => _selectedIds.removeAll(ids));
      return '永久清除已完成：${result.recordsRemoved} 项记录、${result.copiesRemoved} 份副本。${confirmed.$1 ? '' : '记录保留。'}${confirmed.$2 ? '' : '副本保留。'}';
    });
  }

  void _searchChanged(String value) {
    _searchDelay?.cancel();
    setState(() => _searchPending = true);
    _searchDelay = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        ref.read(galleryQueryProvider.notifier).setKeyword(value);
        setState(() => _searchPending = false);
      }
    });
  }

  void _clearQuery() {
    _searchDelay?.cancel();
    _search.clear();
    _searchPending = false;
    ref.read(galleryQueryProvider.notifier).clear();
    setState(() {});
  }

  Future<void> _importSource() async {
    if (!_ready || _blocked || _selectingAll) return;
    final photos = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          key: const Key('mobile-import-source-scroll'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '添加到应用图库',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                '导入后保存独立本机副本，用户原文件保留。',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 20),
              if (widget.supportsPhotos) ...[
                FilledButton.icon(
                  key: const Key('import-source-photos'),
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('从系统照片选择'),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                key: const Key('import-source-files'),
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.folder_outlined),
                label: const Text('从文件选择'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && photos != null) await widget.onImport(photos);
  }

  Future<void> _selectMatching() async {
    if (_selectingAll || !_ready || _blocked) return;
    // One repository query captures the entire matching identity set, not a page.
    final query = ref.read(galleryQueryProvider);
    setState(() => _selectingAll = true);
    try {
      final repository = widget.session.requireValue.repository;
      final ids = await repository.matchingAssetIds(query: query);
      if (mounted && _selecting) setState(() => _selectedIds.addAll(ids));
    } catch (_) {
      if (mounted) _message('选择结果读取失败，已有选择保留，请重试。');
    } finally {
      if (mounted) setState(() => _selectingAll = false);
    }
  }

  void _cancelSelection() => setState(() {
    _selecting = false;
    _selectedIds.clear();
  });

  Future<void> _organizeSelection() async {
    if (!_ready || _blocked || _selectingAll || _selectedIds.isEmpty) return;
    final ids = List<String>.unmodifiable(_selectedIds);
    setState(() => _selectingAll = true);
    try {
      final saved = await showLibraryOrganizationEditor(context, ids);
      if (!mounted || !saved) return;
      try {
        await widget.onRefresh();
        if (mounted) _message('所选图片的整理信息已保存。');
      } catch (_) {
        if (mounted) _message('整理已保存，但图库刷新失败，请重试。');
      }
    } catch (_) {
      if (mounted) _message('整理状态读取失败，请重新打开图库核对。');
    } finally {
      if (mounted) setState(() => _selectingAll = false);
    }
  }

  void _reviewSelection() {
    final ids = List<String>.unmodifiable(_selectedIds);
    final repository = widget.session.asData?.value.repository;
    if (repository == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '核对已选 ${ids.length} 张',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(_selectedIds.clear);
                      },
                      child: const Text('清空选择'),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '筛选切换不会增加选择；此处包含其他分页和筛选中的已选图片。',
                  style: TextStyle(color: _muted),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: ids.length,
                  itemBuilder: (context, index) =>
                      _SelectedFile(repository: repository, id: ids[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _tools() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '工具与设置',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
              ),
              subtitle: Text('个人本地工具，无需应用云账户'),
            ),
            ListTile(
              key: const Key('mobile-recycle-entry'),
              enabled: !_blocked && !_selectingAll && widget.session.hasValue,
              leading: Icon(
                ref.watch(galleryQueryProvider).recycledOnly
                    ? Icons.photo_library_outlined
                    : Icons.delete_outline,
              ),
              title: Text(
                ref.watch(galleryQueryProvider).recycledOnly ? '返回图库' : '回收区',
              ),
              subtitle: const Text('恢复图片，或分别确认清记录与本机副本'),
              onTap: () {
                final recycle = !ref.read(galleryQueryProvider).recycledOnly;
                Navigator.pop(context);
                unawaited(_switchRecycle(recycle));
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重新读取图库'),
              enabled: !_blocked && widget.session.hasValue,
              onTap: () {
                Navigator.pop(context);
                unawaited(_refreshDirectly());
              },
            ),
            ListTile(
              enabled: _ready && !_blocked && widget.onAccounts != null,
              leading: const Icon(Icons.key_outlined),
              title: const Text('图床账号'),
              subtitle: const Text('Catbox / ImgBB 本机凭据与目标配置'),
              onTap: () {
                Navigator.pop(context);
                widget.onAccounts?.call();
              },
            ),
            ListTile(
              enabled: _ready && !_blocked && widget.onProcessing != null,
              leading: const Icon(Icons.crop),
              title: const Text('图片处理'),
              subtitle: const Text('压缩、裁剪、拼接与永久保存'),
              onTap: () {
                Navigator.pop(context);
                widget.onProcessing?.call();
              },
            ),
            ListTile(
              enabled: _ready && !_blocked && widget.onTasks != null,
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('上传任务'),
              subtitle: const Text('创建批次、等待条件与确认结果'),
              onTap: () {
                Navigator.pop(context);
                widget.onTasks?.call();
              },
            ),
            ListTile(
              enabled: _ready && !_blocked && widget.onBackup != null,
              leading: const Icon(Icons.backup_outlined),
              title: const Text('备份与恢复'),
              subtitle: const Text('查看备份方式与平台导出能力'),
              onTap: () {
                Navigator.pop(context);
                widget.onBackup?.call();
              },
            ),
            ListTile(
              enabled: _ready && !_blocked && widget.onSettings != null,
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              subtitle: const Text('本机默认值、实际并发与数据留存说明'),
              onTap: () {
                Navigator.pop(context);
                widget.onSettings?.call();
              },
            ),
          ],
        ),
      ),
    ),
  );

  void _openDetail(ImageAsset asset) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => Theme(
        data: _m1Theme(Theme.of(context)),
        child: _MobileAssetDetails(
          asset: asset,
          onRemove: () => _remove([asset.id]),
          onRestore: () => _restore([asset.id]),
          onPurge: () => _purge([asset.id]),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(galleryQueryProvider);
    if (!widget.gallery.isLoading &&
        !widget.gallery.hasError &&
        widget.gallery.hasValue) {
      _lastPage = widget.gallery.requireValue;
    }
    if (!_searchPending && _search.text != query.keyword) {
      _search.text = query.keyword;
    }
    final theme = Theme.of(context);
    return Theme(
      data: _m1Theme(theme),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_handleBack());
        },
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _section,
              children: [
                _galleryBody(query.favoritesOnly),
                LinkResultsScreen(
                  embedded: true,
                  active: _section == 1,
                  onBusyChanged: (busy) {
                    if (mounted) setState(() => _linksBusy = busy);
                  },
                ),
                const _PendingDestination(
                  icon: Icons.cloud_upload_outlined,
                  title: '上传任务尚未接入',
                  message: '上传功能完成后，可以在这里查看每张图片的进度和结果。本机图库中的副本已独立保管。',
                ),
              ],
            ),
          ),
          bottomNavigationBar: _selecting && _section == 0
              ? _selectionBar()
              : NavigationBar(
                  height: 74,
                  selectedIndex: _section,
                  backgroundColor: Colors.white,
                  indicatorColor: const Color(0xffedf1ff),
                  onDestinationSelected: (index) {
                    if (_linksBusy || _blocked || _selectingAll) return;
                    FocusManager.instance.primaryFocus?.unfocus();
                    if (index == 2 && widget.onTasks != null) {
                      if (_ready && !_blocked) widget.onTasks!();
                      return;
                    }
                    setState(() => _section = index);
                    widget.onLinksVisibility?.call(index == 1);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.photo_library_outlined),
                      selectedIcon: Icon(Icons.photo_library, color: _accent),
                      label: '图库',
                    ),
                    NavigationDestination(icon: Icon(Icons.link), label: '链接'),
                    NavigationDestination(
                      icon: Icon(Icons.cloud_upload_outlined),
                      label: '任务',
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _galleryBody(bool favoritesOnly) => CustomScrollView(
    key: const PageStorageKey('mobile-gallery-scroll'),
    controller: _scroll,
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
          child: Row(
            children: [
              const Icon(
                Icons.photo_library_outlined,
                color: _accent,
                size: 21,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'ImageHub',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const Text('本机图库', style: TextStyle(color: _muted, fontSize: 11)),
              IconButton(
                tooltip: '工具与设置',
                onPressed: _tools,
                icon: const Icon(Icons.settings_outlined, size: 21),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selecting
                          ? '已选 ${_selectedIds.length} 张'
                          : ref.watch(galleryQueryProvider).recycledOnly
                          ? '回收区'
                          : '我的图库',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.7,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _selecting
                          ? '筛选变化保留已有选择'
                          : widget.gallery.isLoading || _searchPending
                          ? '正在读取本机图库…'
                          : widget.gallery.hasError ||
                                widget.gallery.asData == null
                          ? '独立保存在此设备'
                          : '${widget.gallery.requireValue.total} 张${ref.read(galleryQueryProvider).isUnfiltered ? '图片' : '匹配图片'}，独立保存在此设备',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_selecting)
                OutlinedButton(
                  onPressed: _working ? null : _cancelSelection,
                  child: const Text('取消'),
                )
              else ...[
                TextButton(
                  key: const Key('mobile-select'),
                  onPressed:
                      _ready &&
                          !_blocked &&
                          widget.gallery.requireValue.total > 0
                      ? () => setState(() => _selecting = true)
                      : null,
                  child: const Text('选择'),
                ),
                if (!ref.watch(galleryQueryProvider).recycledOnly)
                  FilledButton.icon(
                    key: const Key('import-files'),
                    onPressed: _ready && !_blocked ? _importSource : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('导入'),
                  ),
              ],
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            key: const Key('mobile-search'),
            controller: _search,
            onChanged: _searchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '名称、分类、标签、图床、历史账号、普通 URL',
              prefixIcon: const Icon(Icons.search, size: 21, color: _muted),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_search.text.isNotEmpty)
                    IconButton(
                      tooltip: '清除搜索',
                      onPressed: () {
                        _searchDelay?.cancel();
                        _search.clear();
                        _searchPending = false;
                        ref.read(galleryQueryProvider.notifier).setKeyword('');
                        setState(() {});
                      },
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  IconButton(
                    key: const Key('mobile-filters'),
                    tooltip: '组合筛选',
                    onPressed: _ready && !_blocked && !_selectingAll
                        ? () => showDialog<void>(
                            context: context,
                            builder: (_) => const GalleryFilterDialog(),
                          )
                        : null,
                    icon: const Icon(Icons.tune, size: 20),
                  ),
                ],
              ),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: _line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: _accent),
              ),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FilterButton(
                    label: '全部',
                    selected: !favoritesOnly,
                    onPressed: () => ref
                        .read(galleryQueryProvider.notifier)
                        .setFavoritesOnly(false),
                  ),
                  _FilterButton(
                    label: '收藏',
                    selected: favoritesOnly,
                    onPressed: () => ref
                        .read(galleryQueryProvider.notifier)
                        .setFavoritesOnly(true),
                  ),
                  _FilterButton(
                    label: '有链接',
                    selected:
                        ref.watch(galleryQueryProvider).uploadFilter ==
                        GalleryUploadFilter.confirmed,
                    onPressed: _ready && !_blocked
                        ? () {
                            final query = ref.read(galleryQueryProvider);
                            ref
                                .read(galleryQueryProvider.notifier)
                                .replace(
                                  query.copyWith(
                                    uploadFilter:
                                        query.uploadFilter ==
                                            GalleryUploadFilter.confirmed
                                        ? null
                                        : GalleryUploadFilter.confirmed,
                                  ),
                                );
                          }
                        : null,
                  ),
                ],
              ),
              if (_selecting)
                TextButton(
                  key: const Key('select-matching'),
                  onPressed: _ready && !_blocked && !_selectingAll
                      ? _selectMatching
                      : null,
                  child: Text(_selectingAll ? '正在选择…' : '全选结果'),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '舒适视图',
                        isSelected: !_dense,
                        onPressed: () => setState(() => _dense = false),
                        icon: const Icon(Icons.grid_view_outlined, size: 20),
                        selectedIcon: const Icon(
                          Icons.grid_view,
                          size: 20,
                          color: _accent,
                        ),
                      ),
                      IconButton(
                        tooltip: '紧凑视图',
                        isSelected: _dense,
                        onPressed: () => setState(() => _dense = true),
                        icon: const Icon(Icons.apps, size: 20),
                        selectedIcon: const Icon(
                          Icons.apps,
                          size: 20,
                          color: _accent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      if (widget.notices.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: widget.notices),
          ),
        ),
      if (ref.watch(galleryQueryProvider).recycledOnly)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '30 天到期仅提示，未经确认持续保留。${_dueCount == null ? '' : '当前 $_dueCount 张可清理。'}',
                ),
                TextButton(
                  key: const Key('mobile-return-gallery'),
                  onPressed: _blocked || _selectingAll
                      ? null
                      : () => _switchRecycle(false),
                  child: const Text('返回图库'),
                ),
              ],
            ),
          ),
        ),
      if (_working) const SliverToBoxAdapter(child: LinearProgressIndicator()),
      if (_operationFeedback != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(_operationFeedback!),
          ),
        ),
      ..._gallerySlivers(),
    ],
  );

  List<Widget> _gallerySlivers() {
    final gallery = widget.gallery;
    final hasPrevious =
        _lastPage != null &&
        widget.session.hasValue &&
        !widget.session.hasError;
    if (gallery.isLoading && !hasPrevious) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _MobileStatus(icon: null, title: '正在打开本机图库…', message: ''),
        ),
      ];
    }
    if (gallery.hasError && !hasPrevious) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: LibraryFailureView(
            error: gallery.error,
            onRetry: widget.onRetry,
          ),
        ),
      ];
    }
    final page = gallery.hasError || gallery.isLoading
        ? _lastPage!
        : gallery.requireValue;
    final recycled = ref.read(galleryQueryProvider).recycledOnly;
    final retainedNotice = <Widget>[
      if (gallery.isLoading)
        const SliverToBoxAdapter(child: LinearProgressIndicator()),
      if (gallery.hasError)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('读取失败，最后有效列表仍保留。当前操作已暂停，请重试读取。'),
                TextButton(
                  onPressed: _refreshDirectly,
                  child: const Text('重试读取'),
                ),
              ],
            ),
          ),
        ),
    ];
    if (page.items.isEmpty) {
      final filtered = !ref.read(galleryQueryProvider).isUnfiltered;
      return [
        ...retainedNotice,
        SliverFillRemaining(
          hasScrollBody: false,
          child: _MobileStatus(
            icon: filtered ? Icons.search : Icons.photo_library_outlined,
            title: filtered
                ? '没有匹配图片'
                : recycled
                ? '回收区为空'
                : '把第一张图片放进来',
            message: filtered
                ? '试试其他名称，或清除当前筛选。'
                : recycled
                ? '移除的资产可在这里恢复。'
                : '导入后，会为图片保存独立的本机副本。',
            action: filtered
                ? OutlinedButton(
                    onPressed: _clearQuery,
                    child: const Text('清除筛选'),
                  )
                : recycled
                ? null
                : FilledButton.icon(
                    onPressed: !_ready || _blocked ? null : _importSource,
                    icon: const Icon(Icons.add),
                    label: const Text('导入图片'),
                  ),
          ),
        ),
      ];
    }
    final groups = <(DateTime, List<ImageAsset>)>[];
    for (final asset in page.items) {
      final local = asset.importedAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (groups.isEmpty || groups.last.$1 != day) groups.add((day, []));
      groups.last.$2.add(asset);
    }
    return [
      ...retainedNotice,
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              DateFormat('yyyy 年 M 月 d 日').format(group.$1),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final columns = _dense ? 3 : 2;
              final gap = _dense ? 5.0 : 12.0;
              final width =
                  (constraints.crossAxisExtent - (columns - 1) * gap) / columns;
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: _dense ? 5 : 16,
                  mainAxisExtent: _dense
                      ? width
                      : width / 1.08 +
                            52 * MediaQuery.textScalerOf(context).scale(1),
                ),
                itemCount: group.$2.length,
                itemBuilder: (context, index) {
                  final asset = group.$2[index];
                  return _MobileAssetTile(
                    asset: asset,
                    dense: _dense,
                    selecting: _selecting,
                    selected: _selectedIds.contains(asset.id),
                    onTap: () {
                      if (!_ready || _blocked || _selectingAll) return;
                      if (_selecting) {
                        setState(() {
                          if (!_selectedIds.add(asset.id)) {
                            _selectedIds.remove(asset.id);
                          }
                        });
                      } else {
                        _openDetail(asset);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
      if (page.items.length < page.total)
        SliverToBoxAdapter(
          child: Center(
            child: TextButton(
              key: const Key('mobile-load-more'),
              onPressed: !_ready || widget.loadingMore || _blocked
                  ? null
                  : widget.onLoadMore,
              child: Text(
                widget.loadingMore
                    ? '正在读取…'
                    : '加载更多（${page.items.length}/${page.total}）',
              ),
            ),
          ),
        ),
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Text(
            '永久副本与来源独立；卸载或清除应用数据可能移除副本。',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ),
      ),
    ];
  }

  Widget _selectionBar() => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: _line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已选 ${_selectedIds.length} 张 · ${ref.watch(galleryQueryProvider).recycledOnly ? '恢复或确认永久清除' : '可批量整理'}',
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (!ref.watch(galleryQueryProvider).recycledOnly)
                  OutlinedButton.icon(
                    key: const Key('mobile-remove-selection'),
                    onPressed:
                        _ready &&
                            !_blocked &&
                            !_selectingAll &&
                            _selectedIds.isNotEmpty
                        ? () => _remove(List<String>.unmodifiable(_selectedIds))
                        : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('移入回收区'),
                  ),
                if (ref.watch(galleryQueryProvider).recycledOnly) ...[
                  OutlinedButton.icon(
                    key: const Key('mobile-restore-selection'),
                    onPressed:
                        _ready &&
                            !_blocked &&
                            !_selectingAll &&
                            _selectedIds.isNotEmpty
                        ? () =>
                              _restore(List<String>.unmodifiable(_selectedIds))
                        : null,
                    icon: const Icon(Icons.restore),
                    label: const Text('恢复所选'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('mobile-purge-selection'),
                    onPressed:
                        _ready &&
                            !_blocked &&
                            !_selectingAll &&
                            _selectedIds.isNotEmpty
                        ? () => _purge(List<String>.unmodifiable(_selectedIds))
                        : null,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('永久清除'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (!ref.watch(galleryQueryProvider).recycledOnly)
              OutlinedButton.icon(
                key: const Key('mobile-organize-selection'),
                onPressed:
                    _ready &&
                        !_blocked &&
                        !_selectingAll &&
                        _selectedIds.isNotEmpty
                    ? _organizeSelection
                    : null,
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('分类与标签'),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const Key('mobile-copy-links'),
              onPressed:
                  _ready &&
                      !_blocked &&
                      !_selectingAll &&
                      _selectedIds.isNotEmpty &&
                      widget.onAssetLinks != null
                  ? () => widget.onAssetLinks!(
                      List<String>.unmodifiable(_selectedIds),
                    )
                  : null,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('复制链接'),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: OutlinedButton(onPressed: null, child: Text('压缩')),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: OutlinedButton(onPressed: null, child: Text('拼接')),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: FilledButton(onPressed: null, child: Text('上传')),
                ),
                IconButton(
                  key: const Key('review-selection'),
                  tooltip: '核对选择集',
                  onPressed: _reviewSelection,
                  icon: const Icon(Icons.checklist_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xffedf1ff)
            : Colors.transparent,
        foregroundColor: selected ? _accent : _muted,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Text(label),
    ),
  );
}

class _MobileAssetTile extends StatelessWidget {
  const _MobileAssetTile({
    required this.asset,
    required this.dense,
    required this.selecting,
    required this.selected,
    required this.onTap,
  });
  final ImageAsset asset;
  final bool dense;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selecting ? selected : null,
    label: '${selecting ? '选择' : '查看'} ${asset.displayName}',
    child: InkWell(
      key: ValueKey('mobile-asset-${asset.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(dense ? 6 : 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xffe9edf3),
                borderRadius: BorderRadius.circular(dense ? 6 : 11),
                border: selected && selecting
                    ? Border.all(color: _accent, width: 2)
                    : null,
              ),
              padding: EdgeInsets.all(selected && selecting ? 4 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(dense ? 6 : 11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AssetPreviewImage(
                      asset: asset,
                      fit: BoxFit.cover,
                      compact: true,
                    ),
                    if (selecting)
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 24,
                          color: selected ? _accent : Colors.white,
                        ),
                      ),
                    if (asset.favorite && !selecting)
                      const Positioned(
                        top: 7,
                        left: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x66172033),
                            borderRadius: BorderRadius.all(Radius.circular(5)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(
                              Icons.star,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (!dense) ...[
            const SizedBox(height: 7),
            Text(
              asset.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${asset.version.format.toUpperCase()} · ${formatBytes(asset.version.byteCount)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
          ],
        ],
      ),
    ),
  );
}

class _SelectedFile extends StatefulWidget {
  const _SelectedFile({required this.repository, required this.id});
  final LibraryRepository repository;
  final String id;
  @override
  State<_SelectedFile> createState() => _SelectedFileState();
}

class _SelectedFileState extends State<_SelectedFile> {
  late final _asset = widget.repository.getAsset(
    widget.id,
    includeRecycled: true,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<ImageAsset?>(
    future: _asset,
    builder: (context, snapshot) => ListTile(
      leading: const Icon(Icons.check_circle_outline),
      title: Text(
        snapshot.hasError
            ? '读取所选图片失败'
            : snapshot.connectionState != ConnectionState.done
            ? '正在读取图片名称…'
            : snapshot.data?.displayName ?? '所选图片已经不可见',
      ),
      subtitle: snapshot.data == null
          ? null
          : Text(
              '${snapshot.data!.version.format} · ${formatBytes(snapshot.data!.version.byteCount)}',
            ),
    ),
  );
}

class _MobileStatus extends StatelessWidget {
  const _MobileStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData? icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            const CircularProgressIndicator()
          else
            Icon(icon, size: 46, color: _muted),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

class _PendingDestination extends StatelessWidget {
  const _PendingDestination({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverFillRemaining(
        hasScrollBody: false,
        child: _MobileStatus(icon: icon, title: title, message: message),
      ),
    ],
  );
}

class _MobileAssetDetails extends ConsumerStatefulWidget {
  const _MobileAssetDetails({
    required this.asset,
    required this.onRemove,
    required this.onRestore,
    required this.onPurge,
  });
  final ImageAsset asset;
  final Future<bool> Function() onRemove, onRestore, onPurge;
  @override
  ConsumerState<_MobileAssetDetails> createState() =>
      _MobileAssetDetailsState();
}

class _MobileAssetDetailsState extends ConsumerState<_MobileAssetDetails> {
  late ImageAsset _asset = widget.asset;
  bool _savingFavorite = false;
  bool _organizing = false;
  bool _changingLifecycle = false;
  bool get _busy => _savingFavorite || _organizing || _changingLifecycle;

  Future<void> _changeLifecycle(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _changingLifecycle = true);
    var completed = false;
    try {
      completed = await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作未完成，已有图片与保护记录保留，请重新读取后核对。')),
        );
      }
    } finally {
      if (mounted) setState(() => _changingLifecycle = false);
    }
    if (mounted && completed) Navigator.of(context).pop();
  }

  Future<void> _organize() async {
    if (_busy || _asset.recycled) return;
    setState(() => _organizing = true);
    try {
      final saved = await showLibraryOrganizationEditor(context, [_asset.id]);
      if (!saved || !mounted) return;
      final repository = (await ref.read(librarySessionProvider.future))
          .repository;
      final updated = await repository.getAsset(_asset.id);
      if (!mounted) return;
      if (updated != null) setState(() => _asset = updated);
      try {
        await ref.read(galleryProvider.notifier).reload();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('整理已保存，但图库刷新失败，请重试。')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('整理状态读取失败，请重新打开详情核对。')));
      }
    } finally {
      if (mounted) setState(() => _organizing = false);
    }
  }

  Future<void> _favorite() async {
    if (_busy || _asset.recycled) return;
    setState(() => _savingFavorite = true);
    try {
      final repository = (await ref.read(librarySessionProvider.future))
          .repository;
      final saved = await repository.setFavorite(_asset.id, !_asset.favorite);
      if (!mounted) return;
      setState(() => _asset = saved);
      try {
        await ref.read(galleryProvider.notifier).reload();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('收藏已保存，但图库刷新失败，请重试。')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('收藏未能保存，原状态保留，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(assetPreviewProvider(_asset));
    final available =
        preview.asData?.value.availability == CopyAvailability.available;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          leading: IconButton(
            key: const Key('mobile-detail-back'),
            tooltip: '返回',
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text(
            '图片详情',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              key: const Key('mobile-favorite'),
              tooltip: _asset.favorite ? '取消收藏' : '收藏',
              onPressed: _busy || _asset.recycled ? null : _favorite,
              icon: _savingFavorite
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _asset.favorite ? Icons.star : Icons.star_border,
                      color: _asset.favorite ? const Color(0xffb38b35) : _muted,
                    ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xffe9edf3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AssetPreviewImage(asset: _asset),
                    ),
                  ),
                ),
              ),
              TextButton.icon(
                key: const Key('mobile-original-preview'),
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OriginalPreviewScreen(asset: _asset),
                        ),
                      ),
                icon: Icon(
                  _asset.version.isAnimated
                      ? Icons.play_circle_outline
                      : Icons.zoom_in,
                ),
                label: Text(_asset.version.isAnimated ? '查看原图与播放动画' : '查看原图'),
              ),
              const SizedBox(height: 24),
              SelectableText(
                _asset.displayName,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${formatBytes(_asset.version.byteCount)} · ${_asset.version.format.toUpperCase()} · ${_asset.version.width} × ${_asset.version.height}${_asset.version.isAnimated ? ' · 动画 ${_asset.version.frameCount} 帧' : ''}',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 18),
              Text(
                '分类：${_asset.category ?? '未分类'}',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
              if (_asset.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in _asset.tags) Chip(label: Text(tag.name)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('mobile-organize'),
                onPressed: _busy || _asset.recycled ? null : _organize,
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('编辑分类与标签'),
              ),
              const SizedBox(height: 18),
              if (_asset.recycled) ...[
                const Text('此图片位于回收区。30 天到期仅提示，恢复保留原身份、整理与历史。'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('mobile-restore-asset'),
                  onPressed: _busy
                      ? null
                      : () => _changeLifecycle(widget.onRestore),
                  icon: const Icon(Icons.restore),
                  label: const Text('恢复图片'),
                ),
                OutlinedButton.icon(
                  key: const Key('mobile-purge-asset'),
                  onPressed: _busy
                      ? null
                      : () => _changeLifecycle(widget.onPurge),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('永久清除'),
                ),
              ] else
                OutlinedButton.icon(
                  key: const Key('mobile-remove-asset'),
                  onPressed: _busy
                      ? null
                      : () => _changeLifecycle(widget.onRemove),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('移入回收区'),
                ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: available
                      ? const Color(0xffedf4f0)
                      : const Color(0xfffff4e8),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Icon(
                      available ? Icons.check : Icons.info_outline,
                      size: 21,
                      color: available
                          ? const Color(0xff467462)
                          : const Color(0xff966128),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preview.isLoading
                                ? '正在校验本机副本…'
                                : preview.hasError
                                ? '副本校验或预览失败'
                                : copyLabel(preview.requireValue.availability),
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            available
                                ? '来源被移除，也可以继续使用'
                                : '已有图片信息保留；可重试校验或重新导入。',
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    if (preview.hasError)
                      IconButton(
                        tooltip: '重试校验',
                        onPressed: () =>
                            ref.invalidate(assetPreviewProvider(_asset)),
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: null, child: Text('编辑副本')),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(onPressed: null, child: Text('上传原图')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '请从“工具与设置”处理图片，或从“任务”创建上传。',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 24),
              const Text(
                '远程结果',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前永久版本：${_asset.confirmedRemoteResultCount} 项已确认普通链接。',
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                    Text(
                      _asset.lastConfirmedUploadAt == null
                          ? '尚无确认上传时间。'
                          : '最近确认上传：${DateFormat('yyyy-MM-dd HH:mm:ss').format(_asset.lastConfirmedUploadAt!.toLocal())}',
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                    const Text(
                      '已确认的普通远程结果请在链接页查看；链接存在不代表当前可达。',
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '导入于 ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_asset.importedAt.toLocal())}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                '来源：${sourceLabel(_asset.sourceType)} · 独立副本',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              const Text(
                '此处为可再生预览，永久副本保留原始字节。',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
