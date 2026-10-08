import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/library_models.dart';
import 'gallery_providers.dart';

String formatBytes(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

String sourceLabel(String source) => switch (source) {
  'photo' => '系统照片',
  'processed' => '处理结果',
  'file' => '系统文件',
  _ => '系统授权资源',
};

String copyLabel(CopyAvailability availability) => switch (availability) {
  CopyAvailability.available => '本机副本可用',
  CopyAvailability.missing => '副本缺失，请重导入相同图片修复',
  CopyAvailability.damaged => '副本损坏，请重导入相同图片修复',
  CopyAvailability.inaccessible => '暂时无法读取副本，请检查目录权限',
};

class AssetPreviewImage extends ConsumerWidget {
  const AssetPreviewImage({
    super.key,
    required this.asset,
    this.fit = BoxFit.contain,
    this.compact = false,
    this.selectedFrame,
  });
  final ImageAsset asset;
  final BoxFit fit;
  final bool compact;
  final int? selectedFrame;

  void _retry(WidgetRef ref) {
    if (selectedFrame == null) {
      ref.invalidate(assetPreviewProvider(asset));
    } else {
      ref.invalidate(assetFramePreviewProvider((asset, selectedFrame!)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(
        selectedFrame == null
            ? assetPreviewProvider(asset)
            : assetFramePreviewProvider((asset, selectedFrame!)),
      )
      .when(
        loading: () => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (error, stack) => compact
            ? Center(
                child: IconButton(
                  tooltip: '预览失败，重试',
                  onPressed: () => _retry(ref),
                  icon: const Icon(Icons.refresh),
                ),
              )
            : Center(
                child: TextButton.icon(
                  onPressed: () => _retry(ref),
                  icon: const Icon(Icons.refresh),
                  label: const Text('预览失败，重试'),
                ),
              ),
        data: (preview) {
          final bytes = preview.bytes;
          if (bytes == null) {
            if (compact) {
              final label = switch (preview.availability) {
                CopyAvailability.available => '预览不可用',
                CopyAvailability.missing => '副本缺失',
                CopyAvailability.damaged => '副本损坏',
                CopyAvailability.inaccessible => '不可读取',
              };
              return Tooltip(
                message: preview.availability == CopyAvailability.available
                    ? preview.cacheMessage ?? '永久副本可用，缩略图暂不可用。'
                    : copyLabel(preview.availability),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_outlined, size: 24),
                      const SizedBox(height: 5),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  preview.availability == CopyAvailability.available
                      ? preview.cacheMessage ?? '副本已保存，缩略图暂不可用。'
                      : copyLabel(preview.availability),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Image.memory(
            bytes,
            fit: fit,
            semanticLabel: asset.displayName,
            errorBuilder: (context, error, stack) => compact
                ? Center(
                    child: IconButton(
                      tooltip: '重建预览',
                      onPressed: () => _retry(ref),
                      icon: const Icon(Icons.refresh),
                    ),
                  )
                : Center(
                    child: TextButton(
                      onPressed: () => _retry(ref),
                      child: const Text('重建预览'),
                    ),
                  ),
          );
        },
      );
}
