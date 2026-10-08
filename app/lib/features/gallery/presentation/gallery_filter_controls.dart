import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../accounts/domain/account_models.dart';
import '../../upload/domain/upload_queue_models.dart';
import '../domain/gallery_query.dart';
import '../domain/library_models.dart';
import 'gallery_providers.dart';
import 'library_organization_editor.dart';

class GalleryFilterDialog extends ConsumerWidget {
  const GalleryFilterDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(galleryQueryProvider);
    void change(GalleryQuery query) =>
        ref.read(galleryQueryProvider.notifier).replace(query);
    return AlertDialog(
      title: const Text('组合筛选与排序'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('多个条件按交集检索。可用性按最近一次显式校验结果筛选；尚未校验不算缺失。'),
              const SizedBox(height: 12),
              ref
                  .watch(categoriesProvider)
                  .when(
                    loading: () => const Text('正在读取分类…'),
                    error: (error, _) => TextButton(
                      onPressed: () => ref.invalidate(categoriesProvider),
                      child: const Text('分类读取失败，现有条件保留；重试'),
                    ),
                    data: (categories) => DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey(
                        'filter-category-${query.categoryId}-${query.uncategorized}',
                      ),
                      initialValue: query.uncategorized
                          ? '@none'
                          : query.categoryId ?? '',
                      decoration: const InputDecoration(labelText: '分类'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('全部分类')),
                        const DropdownMenuItem(
                          value: '@none',
                          child: Text('未分类'),
                        ),
                        for (final category in categories)
                          DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        if (query.categoryId != null &&
                            !categories.any(
                              (category) => category.id == query.categoryId,
                            ))
                          DropdownMenuItem(
                            value: query.categoryId,
                            child: const Text('分类已移除，请清空条件'),
                          ),
                      ],
                      onChanged: (value) => change(
                        query.copyWith(
                          categoryId: value == '' || value == '@none'
                              ? null
                              : value,
                          uncategorized: value == '@none',
                        ),
                      ),
                    ),
                  ),
              TextButton(
                onPressed: () => showLibraryCategoryManager(context),
                child: const Text('管理分类'),
              ),
              const Text('标签（多选交集）'),
              ref
                  .watch(tagsProvider)
                  .when(
                    loading: () => const Text('正在读取标签…'),
                    error: (error, _) => TextButton(
                      onPressed: () => ref.invalidate(tagsProvider),
                      child: const Text('标签读取失败，现有条件保留；重试'),
                    ),
                    data: (tags) => tags.isEmpty
                        ? const Text('尚无标签')
                        : Wrap(
                            spacing: 6,
                            children: [
                              for (final tag in tags)
                                FilterChip(
                                  label: Text(tag.name),
                                  selected: query.tagIds.contains(tag.id),
                                  onSelected: (selected) {
                                    final ids = query.tagIds.toSet();
                                    if (selected) {
                                      ids.add(tag.id);
                                    } else {
                                      ids.remove(tag.id);
                                    }
                                    change(query.copyWith(tagIds: ids));
                                  },
                                ),
                            ],
                          ),
                  ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('filter-format-${query.format}'),
                initialValue: query.format ?? '',
                decoration: const InputDecoration(labelText: '格式'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部格式')),
                  for (final format in ['JPEG', 'PNG', 'WebP', 'GIF', 'BMP'])
                    DropdownMenuItem(
                      value: format,
                      child: Text(format.toUpperCase()),
                    ),
                ],
                onChanged: (value) =>
                    change(query.copyWith(format: value == '' ? null : value)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('filter-source-${query.sourceType}'),
                initialValue: query.sourceType ?? '',
                decoration: const InputDecoration(labelText: '来源'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('全部来源')),
                  DropdownMenuItem(value: 'file', child: Text('系统文件')),
                  DropdownMenuItem(value: 'photo', child: Text('系统照片')),
                  DropdownMenuItem(value: 'processed', child: Text('处理结果')),
                ],
                onChanged: (value) => change(
                  query.copyWith(sourceType: value == '' ? null : value),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('filter-availability-${query.availability}'),
                initialValue: query.availability?.name ?? '',
                decoration: const InputDecoration(labelText: '最近校验可用性'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部状态（含未校验）')),
                  for (final status in CopyAvailability.values)
                    DropdownMenuItem(
                      value: status.name,
                      child: Text(switch (status) {
                        CopyAvailability.available => '本机副本可用',
                        CopyAvailability.missing => '副本缺失',
                        CopyAvailability.damaged => '副本损坏',
                        CopyAvailability.inaccessible => '暂时无法读取',
                      }),
                    ),
                ],
                onChanged: (value) => change(
                  query.copyWith(
                    availability: value == ''
                        ? null
                        : CopyAvailability.values.byName(value!),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GallerySort>(
                key: ValueKey('gallery-sort-${query.sort}'),
                isExpanded: true,
                initialValue: query.sort,
                decoration: const InputDecoration(labelText: '排序'),
                items: const [
                  DropdownMenuItem(
                    value: GallerySort.imported,
                    child: Text('导入时间'),
                  ),
                  DropdownMenuItem(
                    value: GallerySort.uploaded,
                    child: Text('最近确认上传'),
                  ),
                  DropdownMenuItem(value: GallerySort.name, child: Text('名称')),
                  DropdownMenuItem(value: GallerySort.size, child: Text('大小')),
                ],
                onChanged: (value) => change(query.copyWith(sort: value)),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('升序'),
                value: query.ascending,
                onChanged: (value) => change(query.copyWith(ascending: value)),
              ),
              const Text('按最近确认上传排序时，尚无确认日期的图片始终排在末尾。'),
              const _RemoteFilterControls(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => ref.read(galleryQueryProvider.notifier).clear(),
          child: const Text('清空筛选与排序'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _RemoteFilterControls extends ConsumerWidget {
  const _RemoteFilterControls();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(galleryQueryProvider);
    void change(GalleryQuery next) =>
        ref.read(galleryQueryProvider.notifier).replace(next);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Text('目标、服务、图片类型和状态须来自同一次记录。只匹配图片当前保存的内容，其他处理版本请选对应图片。'),
        const SizedBox(height: 8),
        const Text('同一张图片可能有多次上传，各次状态不同。这里只筛选本机记录，不会联网。'),
        const SizedBox(height: 12),
        ref
            .watch(galleryRemoteTargetsProvider)
            .when(
              skipLoadingOnRefresh: false,
              skipError: false,
              loading: () => const Text('正在读取历史目标，现有条件保持…'),
              error: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('历史目标读取失败，目标选择已暂停，现有筛选条件保持。'),
                  TextButton(
                    key: const Key('gallery-remote-targets-retry'),
                    onPressed: () =>
                        ref.invalidate(galleryRemoteTargetsProvider),
                    child: const Text('重试读取历史目标'),
                  ),
                ],
              ),
              data: (targets) => DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('gallery-remote-target-${query.remoteTargetId}'),
                initialValue: query.remoteTargetId ?? '',
                decoration: const InputDecoration(labelText: '历史上传目标'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部历史目标')),
                  for (final target in targets)
                    DropdownMenuItem(
                      value: target.id,
                      child: Text(
                        '${target.alias} · ${target.service == ImageHostService.catbox ? 'Catbox' : 'ImgBB'} · ${target.id.length > 8 ? target.id.substring(0, 8) : target.id}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (query.remoteTargetId != null &&
                      !targets.any((t) => t.id == query.remoteTargetId))
                    DropdownMenuItem(
                      value: query.remoteTargetId,
                      child: const Text('此目标暂无匹配记录，可清空条件'),
                    ),
                ],
                onChanged: (value) => change(
                  query.copyWith(remoteTargetId: value == '' ? null : value),
                ),
              ),
            ),
        if (!ref.watch(galleryRemoteTargetsProvider).hasValue &&
            query.remoteTargetId != null)
          Text('仍按历史目标 UUID 筛选：${query.remoteTargetId}'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey('gallery-remote-service-${query.remoteService}'),
          initialValue: query.remoteService?.name ?? '',
          decoration: const InputDecoration(labelText: '图床服务'),
          items: const [
            DropdownMenuItem(value: '', child: Text('全部服务')),
            DropdownMenuItem(value: 'catbox', child: Text('Catbox')),
            DropdownMenuItem(value: 'imgbb', child: Text('ImgBB')),
          ],
          onChanged: (value) => change(
            query.copyWith(
              remoteService: value == ''
                  ? null
                  : ImageHostService.values.byName(value!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey('gallery-remote-kind-${query.remoteInputKind}'),
          initialValue: query.remoteInputKind?.name ?? '',
          decoration: const InputDecoration(labelText: '上传图片类型'),
          items: const [
            DropdownMenuItem(value: '', child: Text('全部输入类型')),
            DropdownMenuItem(value: 'original', child: Text('原图')),
            DropdownMenuItem(value: 'processed', child: Text('处理结果')),
          ],
          onChanged: (value) => change(
            query.copyWith(
              remoteInputKind: value == ''
                  ? null
                  : UploadInputKind.values.byName(value!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey('gallery-remote-status-${query.uploadFilter}'),
          initialValue: query.uploadFilter?.name ?? '',
          decoration: const InputDecoration(labelText: '上传记录状态'),
          items: const [
            DropdownMenuItem(value: '', child: Text('全部上传记录')),
            DropdownMenuItem(value: 'confirmed', child: Text('已确认普通链接')),
            DropdownMenuItem(value: 'failed', child: Text('有失败项')),
            DropdownMenuItem(value: 'unknown', child: Text('结果未知')),
            DropdownMenuItem(value: 'active', child: Text('有未结束项')),
            DropdownMenuItem(value: 'cancelled', child: Text('已取消项')),
            DropdownMenuItem(value: 'withoutLinks', child: Text('无普通链接')),
          ],
          onChanged: (value) => change(
            query.copyWith(
              uploadFilter: value == ''
                  ? null
                  : GalleryUploadFilter.values.byName(value!),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('未结束项包含排队、等待、执行、暂停或中断的上传。“无普通链接”按选定目标、服务和图片类型判断。'),
        TextButton(
          key: const Key('gallery-clear-remote-filters'),
          onPressed: () => change(
            query.copyWith(
              remoteTargetId: null,
              remoteService: null,
              remoteInputKind: null,
              uploadFilter: null,
            ),
          ),
          child: const Text('清空远程条件'),
        ),
      ],
    );
  }
}
