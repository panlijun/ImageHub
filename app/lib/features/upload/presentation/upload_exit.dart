import 'package:material_ui/material_ui.dart';

import '../../gallery/presentation/gallery_providers.dart';

/// Every visible work page uses the same application service shutdown.
/// Page navigation itself does not dispose uploads or cancel their intent.
Future<bool> requestLibraryExit(
  BuildContext context,
  LibrarySession session, {
  Future<void> Function()? beforeClose,
}) async {
  final queue = session.existingUploads;
  if (queue != null && queue.activeCount > 0) {
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('上传仍在执行'),
        content: const Text(
          '停止本机网络执行并退出？未派发任务会保留。已发送的请求可能已在远端完成，重开后先核查未知结果，不会自动重新发送。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续使用'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('停止并退出'),
          ),
        ],
      ),
    );
    if (stop != true) return false;
  }
  try {
    await beforeClose?.call();
    await session.close();
    return true;
  } catch (_) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('尚未安全退出'),
          content: const Text('文件使用或数据关闭尚未确认完成，保护记录已保留。请检查系统并重试退出。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回应用'),
            ),
          ],
        ),
      );
    }
    return false;
  }
}
