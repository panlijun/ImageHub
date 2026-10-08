import 'dart:async';
import 'dart:io';

/// A granted source is consumed during import; it is never a permanent reference.
class PlatformResource {
  const PlatformResource({
    required this.displayName,
    required this.openRead,
    this.openReadWithCancellation,
    this.release,
    this.sourceType = 'file',
  });

  final String displayName;
  final String sourceType;

  /// Releases a granted source only after its actual reads have drained.
  /// Callers also release selected resources that were never opened.
  final Future<void> Function()? release;

  /// Subscription cancellation must finish only after actual source IO drains.
  /// Import retains its writer protection until this cleanup future completes;
  /// a timeout or cancellation request alone must never signal IO completion.
  final Stream<List<int>> Function() openRead;

  /// Acquisition adapters recheck this token after awaited readiness checks,
  /// before opening a new source. Cancellation still waits for stream cleanup.
  final Stream<List<int>> Function(CancellationToken? cancellation)?
  openReadWithCancellation;

  Stream<List<int>> read({CancellationToken? cancellation}) {
    cancellation?.throwIfCancelled();
    return openReadWithCancellation?.call(cancellation) ?? openRead();
  }

  factory PlatformResource.file(File file, {String? displayName}) =>
      PlatformResource(
        displayName: displayName ?? file.uri.pathSegments.last,
        openRead: file.openRead,
      );
}

class CancellationToken {
  bool _cancelled = false;
  final Completer<void> _cancellation = Completer<void>();
  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _cancellation.future;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancellation.complete();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const ResourceFailure(FailureKind.cancelled);
  }
}

enum FailureKind {
  cancelled,
  permissionDenied,
  sourceMissing,
  cloudPending,
  unavailable,
  invalidImage,
  unsupported,
  resourceBudget,
  storage,
  lowSpace,
  storageUnavailable,
  needsRestore,
  activeUse,
}

class ResourceFailure implements Exception {
  const ResourceFailure(this.kind);
  final FailureKind kind;
  String get message => switch (kind) {
    FailureKind.cancelled => '已停止导入，已保存的图片仍保留。',
    FailureKind.permissionDenied => '无法读取所选图片，请重新授权或选择。',
    FailureKind.sourceMissing => '所选来源已失效，请重新选择图片。',
    FailureKind.cloudPending => '图片仍需从云端或离线存储取得；请先下载到本机，再重新选择导入。其他已就绪图片可继续导入。',
    FailureKind.unavailable => '图片暂时无法取得，请下载到本机后重新选择。',
    FailureKind.invalidImage => '图片内容损坏或无效，请选择完整图片。',
    FailureKind.unsupported => '暂不支持此图片格式，请选择 PNG、JPEG、WebP、GIF 或 BMP。',
    FailureKind.resourceBudget => '图片超出当前候选内存预算，请先减小尺寸。',
    FailureKind.storage => '本机保存失败，请检查可用空间和目录权限后重试。',
    FailureKind.lowSpace => '本机可用空间不足，新写入已停止；请到空间管理清理缩略图、日志或到期结果后重试，永久图片保持不变。',
    FailureKind.storageUnavailable =>
      '无法确认本机可用空间，新写入已停止；请检查目录权限和系统能力后重试，已有图片保留。',
    FailureKind.needsRestore => '相同图片位于回收区，请先恢复该资产。',
    FailureKind.activeUse => '相同内容仍有文件使用、保护引用或未完成清除，请完成相关操作后重试。',
  };
  @override
  String toString() => message;
}

class LibraryOpenException implements Exception {
  const LibraryOpenException(this.message);
  final String message;
  @override
  String toString() => message;
}
