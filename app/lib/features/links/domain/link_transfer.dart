/// Platform actions never mutate the library or request an upload.
enum LinkTransferStatus {
  copied,
  shared,
  cancelled,
  unconfirmed,
  unsupported,
  failed,
  empty,
  stale,
}

final class LinkShareAnchor {
  const LinkShareAnchor({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
  final double left, top, width, height;
}

abstract interface class LinkTransferGateway {
  Future<LinkTransferStatus> copyText(String text);
  Future<LinkTransferStatus> shareText(String text, {LinkShareAnchor? anchor});
}

final class LinkTransferReport {
  const LinkTransferReport({
    required this.status,
    required this.copied,
    required this.skipped,
    required this.duplicates,
  });
  final LinkTransferStatus status;
  final int copied, skipped, duplicates;
  String get message => switch (status) {
    LinkTransferStatus.copied =>
      '已复制 $copied 项；跳过 $skipped 项，去重 $duplicates 项。',
    LinkTransferStatus.shared =>
      '系统报告已分享 $copied 项；跳过 $skipped 项，去重 $duplicates 项。不能据此确认接收方已保存或收到。',
    LinkTransferStatus.cancelled => '已取消分享，结果记录保留。',
    LinkTransferStatus.unconfirmed => '已调用系统分享，但无法确认分享结果；记录保留。',
    LinkTransferStatus.unsupported => '当前系统不支持此操作，结果记录保留。',
    LinkTransferStatus.failed => '本地复制或分享未完成，结果记录保留；可重试，不会重新上传。',
    LinkTransferStatus.empty => '没有可用普通链接；跳过 $skipped 项，未调用系统复制或分享。',
    LinkTransferStatus.stale => '资料库会话已变化，请重新选择并确认链接。',
  };
}
