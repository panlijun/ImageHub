import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../features/links/domain/link_transfer.dart';

/// Only ordinary text enters the native clipboard/share APIs. Native errors and
/// share result identifiers never leave this boundary as displayable values.
final class SystemLinkTransferGateway implements LinkTransferGateway {
  SystemLinkTransferGateway({
    Future<void> Function(ClipboardData)? writeClipboard,
    Future<ShareResult> Function(ShareParams)? share,
  }) : _writeClipboard = writeClipboard ?? _writeNativeClipboard,
       _share = share ?? SharePlus.instance.share;

  final Future<void> Function(ClipboardData) _writeClipboard;
  final Future<ShareResult> Function(ShareParams) _share;

  // Flutter's Clipboard.setData uses an OptionalMethodChannel, which silently
  // completes when the native backend is absent. Use the same SDK protocol on
  // a strict channel so an unavailable clipboard cannot be reported as copied.
  static const _clipboardChannel = MethodChannel(
    'flutter/platform',
    JSONMethodCodec(),
  );
  static Future<void> _writeNativeClipboard(ClipboardData data) =>
      _clipboardChannel.invokeMethod<void>('Clipboard.setData', {
        'text': data.text,
      });

  @override
  Future<LinkTransferStatus> copyText(String text) async {
    try {
      await _writeClipboard(ClipboardData(text: text));
      return LinkTransferStatus.copied;
    } on MissingPluginException {
      return LinkTransferStatus.unsupported;
    } catch (_) {
      return LinkTransferStatus.failed;
    }
  }

  @override
  Future<LinkTransferStatus> shareText(
    String text, {
    LinkShareAnchor? anchor,
  }) async {
    if (anchor != null &&
        (!anchor.left.isFinite ||
            !anchor.top.isFinite ||
            !anchor.width.isFinite ||
            !anchor.height.isFinite ||
            anchor.width <= 0 ||
            anchor.height <= 0)) {
      return LinkTransferStatus.failed;
    }
    try {
      final result = await _share(
        ShareParams(
          text: text,
          title: 'ImageHost 普通链接',
          sharePositionOrigin: anchor == null
              ? null
              : Rect.fromLTWH(
                  anchor.left,
                  anchor.top,
                  anchor.width,
                  anchor.height,
                ),
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => LinkTransferStatus.shared,
        ShareResultStatus.dismissed => LinkTransferStatus.cancelled,
        ShareResultStatus.unavailable => LinkTransferStatus.unconfirmed,
      };
    } on MissingPluginException {
      return LinkTransferStatus.unsupported;
    } catch (_) {
      return LinkTransferStatus.failed;
    }
  }
}
