import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform_resource.dart';
import '../../gallery/presentation/gallery_providers.dart';
import '../application/output_preview_reader.dart';

final outputPreviewDecoderProvider = Provider<OutputPreviewDecoder>(
  (_) => const OutputPreviewDecoder(),
);

final outputPreviewProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, id) async {
      ref.watch(libraryReplacementRevisionProvider);
      final decoder = ref.watch(outputPreviewDecoderProvider);
      final cancellation = CancellationToken();
      ref.onDispose(cancellation.cancel);
      final session = await ref.watch(librarySessionProvider.future);
      return OutputPreviewReader(
        session.repository,
        decoder: decoder,
      ).read(id, cancellation: cancellation);
    }, retry: (count, error) => null);

class OutputPreview extends ConsumerWidget {
  const OutputPreview({required this.outputId, super.key});
  final String outputId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(outputPreviewProvider(outputId))
      .when(
        loading: () => const Center(child: Text('正在读取结果预览…')),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('结果预览读取失败，请重载检查；永久图片保留。'),
              TextButton(
                onPressed: () =>
                    ref.invalidate(outputPreviewProvider(outputId)),
                child: const Text('重试预览'),
              ),
            ],
          ),
        ),
        data: (bytes) => Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Center(child: Text('结果预览显示失败，请重载检查。')),
        ),
      );
}
