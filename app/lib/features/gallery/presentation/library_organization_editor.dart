import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/text_policy.dart';
import '../data/library_repository.dart';
import '../domain/library_models.dart';
import '../domain/organization_models.dart';
import 'gallery_providers.dart';

/// Drafts remain untouched while typing. One repository transaction applies all
/// submitted fields, so a category error cannot leave tags partly saved.
Future<bool> showLibraryOrganizationEditor(
  BuildContext context,
  Iterable<String> assetIds,
) async {
  final ids = List<String>.unmodifiable(assetIds.toSet());
  if (ids.isEmpty) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) => _OrganizationEditor(ids: ids),
      ) ??
      false;
}

Future<void> showLibraryCategoryManager(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const _CategoryManager(),
    );

String organizationError(Object error) => switch (error) {
  FormatException() => error.message.toString(),
  LibraryMutationException() => error.message,
  _ => '整理未保存：$error',
};

enum _TagAction { add, remove, replace }

class _OrganizationEditor extends ConsumerStatefulWidget {
  const _OrganizationEditor({required this.ids});
  final List<String> ids;
  @override
  ConsumerState<_OrganizationEditor> createState() =>
      _OrganizationEditorState();
}

class _OrganizationEditorState extends ConsumerState<_OrganizationEditor> {
  final _tags = TextEditingController();
  List<LibraryCategory> _categories = [];
  List<ImageAsset> _assets = [];
  String? _categoryId;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _setCategory = false;
  late _TagAction _action;

  @override
  void initState() {
    super.initState();
    _action = widget.ids.length == 1 ? _TagAction.replace : _TagAction.add;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = (await ref.read(librarySessionProvider.future))
          .repository;
      final categories = await repository.listCategories();
      final assets = <ImageAsset>[];
      for (final id in widget.ids) {
        final asset = await repository.getAsset(id);
        if (asset == null) {
          throw const LibraryMutationException('部分所选图片已不可整理，请重新核对选择。');
        }
        assets.add(asset);
      }
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _assets = assets;
        if (assets.length == 1) {
          _tags.text = assets.single.tags.map((tag) => tag.name).join('，');
          _categoryId = assets.single.categoryId;
          _setCategory = true;
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = organizationError(error);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _loading || _assets.length != widget.ids.length) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final tags = TextPolicy.parseTags(_tags.text);
      final repository = (await ref.read(librarySessionProvider.future))
          .repository;
      await repository.updateOrganization(
        widget.ids,
        replaceTags: _action == _TagAction.replace ? tags : null,
        addTags: _action == _TagAction.add ? tags : null,
        removeTags: _action == _TagAction.remove ? tags : null,
        categoryId: _categoryId,
        setCategory: _setCategory,
      );
      if (!mounted) return;
      ref.invalidate(categoriesProvider);
      ref.invalidate(tagsProvider);
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = organizationError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _manage() async {
    await showLibraryCategoryManager(context);
    if (!mounted) return;
    try {
      final categories = await (await ref.read(librarySessionProvider.future))
          .repository
          .listCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
          if (!categories.any((category) => category.id == _categoryId)) {
            _categoryId = null;
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = organizationError(error));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('整理 ${widget.ids.length} 张图片'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading || _saving) const LinearProgressIndicator(),
              Text('实际作用 ${widget.ids.length} 张；其他整理信息与原始字节保留。'),
              if (_assets.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _assets.map((asset) => asset.displayName).join('、'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 18),
              DropdownButtonFormField<_TagAction>(
                isExpanded: true,
                initialValue: _action,
                decoration: const InputDecoration(labelText: '标签操作'),
                items: const [
                  DropdownMenuItem(
                    value: _TagAction.add,
                    child: Text('增加标签（保留已有标签）'),
                  ),
                  DropdownMenuItem(
                    value: _TagAction.remove,
                    child: Text('移除指定标签'),
                  ),
                  DropdownMenuItem(
                    value: _TagAction.replace,
                    child: Text('替换全部标签'),
                  ),
                ],
                onChanged: _loading || _saving
                    ? null
                    : (value) => setState(() => _action = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('organization-tags'),
                controller: _tags,
                enabled: !_loading && !_saving,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '标签草稿',
                  helperText: '逗号、分号或换行分隔；保存时验证，最多 50 个。',
                ),
              ),
              if (_action == _TagAction.replace)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('替换会移除未在草稿中列出的已有标签；空草稿会清空标签。'),
                ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同时赋值分类'),
                subtitle: const Text('未勾选时保留每张图片原分类。'),
                value: _setCategory,
                onChanged: _loading || _saving
                    ? null
                    : (value) => setState(() => _setCategory = value!),
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey(
                  'organization-category-$_categoryId-${_categories.length}',
                ),
                initialValue: _categoryId ?? '',
                decoration: const InputDecoration(labelText: '分类'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('未分类')),
                  for (final category in _categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: _setCategory && !_loading && !_saving
                    ? (value) => setState(
                        () => _categoryId = value == '' ? null : value,
                      )
                    : null,
              ),
              TextButton(
                onPressed: _loading || _saving ? null : _manage,
                child: const Text('管理分类'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('organization-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!_loading && _assets.isEmpty)
                TextButton(
                  onPressed: _saving ? null : _load,
                  child: const Text('重新读取所选图片'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('organization-save'),
          onPressed: _loading || _saving || _assets.isEmpty ? null : _save,
          child: Text(_saving ? '正在保存…' : '保存整理'),
        ),
      ],
    ),
  );
}

class _CategoryManager extends ConsumerStatefulWidget {
  const _CategoryManager();
  @override
  ConsumerState<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends ConsumerState<_CategoryManager> {
  bool _busy = false;
  String? _error;

  Future<void> _edit([LibraryCategory? category]) async {
    if (_busy) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryNameEditor(category: category),
    );
    if (!mounted || saved != true) return;
    await _run(() async {});
  }

  Future<void> _remove(LibraryCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除分类“${category.name}”？'),
        content: Text(
          '关联的 ${category.assetCount} 张图片（含回收记录）将变为未分类。不会删除图片、副本、标签或历史。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除分类'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run(
      () async =>
          (await ref.read(librarySessionProvider.future)).repository
              .removeCategory(category.id),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(categoriesProvider);
      await ref.read(galleryProvider.notifier).reload();
    } catch (error) {
      if (mounted) setState(() => _error = organizationError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('管理分类'),
      content: SizedBox(
        width: 480,
        height: 350,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('名称冲突会拒绝保存，不会合并分类。移除分类只取消分类关联。'),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: ref
                  .watch(categoriesProvider)
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: TextButton(
                        onPressed: () => ref.invalidate(categoriesProvider),
                        child: Text('分类读取失败，重试：$error'),
                      ),
                    ),
                    data: (categories) => categories.isEmpty
                        ? const Center(child: Text('尚无分类'))
                        : ListView(
                            children: [
                              for (final category in categories)
                                ListTile(
                                  title: Text(category.name),
                                  subtitle: Text(
                                    '${category.assetCount} 张（含回收）',
                                  ),
                                  trailing: Wrap(
                                    children: [
                                      IconButton(
                                        tooltip: '重命名分类',
                                        onPressed: _busy
                                            ? null
                                            : () => _edit(category),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: '移除分类',
                                        onPressed: _busy
                                            ? null
                                            : () => _remove(category),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _edit(),
          child: const Text('新建分类'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _CategoryNameEditor extends ConsumerStatefulWidget {
  const _CategoryNameEditor({this.category});
  final LibraryCategory? category;
  @override
  ConsumerState<_CategoryNameEditor> createState() =>
      _CategoryNameEditorState();
}

class _CategoryNameEditorState extends ConsumerState<_CategoryNameEditor> {
  late final _draft = TextEditingController(text: widget.category?.name ?? '');
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = TextPolicy.normalizeName(_draft.text);
      final repository = (await ref.read(librarySessionProvider.future))
          .repository;
      if (widget.category == null) {
        await repository.createCategory(name);
      } else {
        await repository.renameCategory(widget.category!.id, name);
      }
      if (mounted) {
        ref.invalidate(categoriesProvider);
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = organizationError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.category == null ? '新建分类' : '重命名分类'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('category-name'),
              controller: _draft,
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '分类名称'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? '正在保存…' : '确定'),
        ),
      ],
    ),
  );
}
