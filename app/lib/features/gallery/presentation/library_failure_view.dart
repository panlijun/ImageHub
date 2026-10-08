import 'package:material_ui/material_ui.dart';

import '../../../core/platform_resource.dart';

/// A failed open never becomes an empty library or a destructive reset action.
class LibraryFailureView extends StatelessWidget {
  const LibraryFailureView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final openFailure = error is LibraryOpenException;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 32),
              const SizedBox(height: 12),
              const Text('图库打开失败', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 12),
              Text(
                openFailure
                    ? (error as LibraryOpenException).message
                    : '读取失败，现有数据已保留。请检查空间或权限后重试。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('重试打开')),
              if (openFailure) ...[
                const SizedBox(height: 16),
                const Text('当前资料库未安全打开，已停止使用它。现有数据没有被清空。'),
                const ExpansionTile(
                  title: Text('数据保全与恢复说明'),
                  childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Text(
                      '请保留完整资料库目录，包括数据库、永久图片和暂存证据，避免只移动或覆盖其中一个文件。\n\n'
                      '如果提示格式不兼容，请用支持该格式的版本重新打开；如果有已确认的备份，可在独立的新资料库先校验，再确认恢复。\n\n'
                      '当前状态无法确认数据完整性，因此不生成业务备份或自动修复。检查空间、权限或版本后，可重试打开。',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
