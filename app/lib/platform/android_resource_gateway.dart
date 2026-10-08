import 'dart:async';

import '../core/platform_resource.dart';
import 'generated/android_files.g.dart';

/// Android transports bounded URI chunks, never a whole batch of image bytes.
class AndroidResourceGateway {
  AndroidResourceGateway({AndroidResourceHost? host})
    : _host = host ?? AndroidResourceHost();
  final AndroidResourceHost _host;
  static final _handlePattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  Future<List<PlatformResource>> pick({
    bool photos = false,
    bool backup = false,
  }) async {
    try {
      return await resources(await _host.pickResources(photos, backup));
    } on ResourceFailure {
      rethrow;
    } catch (_) {
      throw const ResourceFailure(FailureKind.unavailable);
    }
  }

  Future<List<PlatformResource>> recover() async {
    try {
      return await resources(await _host.recoverSelection());
    } on ResourceFailure {
      rethrow;
    } catch (_) {
      throw const ResourceFailure(FailureKind.unavailable);
    }
  }

  Future<List<PlatformResource>> resources(AndroidSelection selection) async {
    final handles = selection.resources
        .map((item) => item.handle)
        .where(_handlePattern.hasMatch)
        .toSet();
    Future<Never> reject() async {
      var closeFailed = false;
      for (final handle in handles) {
        try {
          await _host.closeResource(handle);
        } catch (_) {
          closeFailed = true;
        }
      }
      throw ResourceFailure(
        closeFailed ? FailureKind.storage : FailureKind.unavailable,
      );
    }

    if (selection.cancelled) {
      if (selection.resources.isNotEmpty) {
        return reject();
      }
      return const [];
    }
    final seen = <String>{};
    final resources = <PlatformResource>[];
    for (final selected in selection.resources) {
      if (!_handlePattern.hasMatch(selected.handle) ||
          !seen.add(selected.handle) ||
          selected.displayName.isEmpty ||
          selected.displayName.runes.length > 512 ||
          !{'photo', 'file', 'backup'}.contains(selected.sourceType)) {
        return reject();
      }
      final reader = _AndroidResourceReader(_host, selected.handle);
      resources.add(
        PlatformResource(
          displayName: selected.displayName,
          sourceType: selected.sourceType,
          openRead: () => reader.read(null),
          openReadWithCancellation: reader.read,
          release: reader.close,
        ),
      );
    }
    return List.unmodifiable(resources);
  }
}

class _AndroidResourceReader {
  _AndroidResourceReader(this.host, this.handle);
  final AndroidResourceHost host;
  final String handle;
  Future<void>? _closing;
  bool _opened = false;

  Future<void> close() async {
    final pending = _closing;
    if (pending != null) return pending;
    final closing = _close();
    _closing = closing;
    try {
      await closing;
    } catch (_) {
      if (identical(_closing, closing)) _closing = null;
      rethrow;
    }
  }

  Future<void> _close() async {
    try {
      await host.closeResource(handle);
    } catch (_) {
      throw const ResourceFailure(FailureKind.storage);
    }
  }

  Stream<List<int>> read(CancellationToken? token) async* {
    if (_opened || _closing != null) {
      throw const ResourceFailure(FailureKind.sourceMissing);
    }
    _opened = true;
    try {
      while (true) {
        token?.throwIfCancelled();
        final reading = host.readResource(handle);
        AndroidReadReply? reply;
        if (token == null) {
          reply = await reading;
        } else {
          reply = await Future.any<AndroidReadReply?>([
            reading,
            token.whenCancelled.then((_) => null),
          ]);
          if (reply == null) {
            // Closing queues behind the real read. Neither future is abandoned.
            var closeFailed = false;
            try {
              await close();
            } catch (_) {
              closeFailed = true;
            }
            // Even a failed close cannot release the caller while the real
            // pending native read is still active.
            try {
              await reading;
            } catch (_) {
              // Cancellation discards delivery only; actual work has ended.
            }
            if (closeFailed) throw const ResourceFailure(FailureKind.storage);
            token.throwIfCancelled();
          }
        }
        token?.throwIfCancelled();
        if (reply == null) throw const ResourceFailure(FailureKind.unavailable);
        if (reply.code != AndroidIoCode.ok) throw _failure(reply.code);
        if (reply.bytes.length > 64 * 1024 ||
            (reply.bytes.isEmpty && !reply.eof)) {
          throw const ResourceFailure(FailureKind.unavailable);
        }
        if (reply.bytes.isNotEmpty) yield reply.bytes;
        if (reply.eof) break;
      }
    } on ResourceFailure {
      rethrow;
    } catch (_) {
      throw const ResourceFailure(FailureKind.unavailable);
    } finally {
      await close();
    }
  }

  ResourceFailure _failure(AndroidIoCode code) =>
      ResourceFailure(switch (code) {
        AndroidIoCode.cancelled => FailureKind.cancelled,
        AndroidIoCode.permissionDenied => FailureKind.permissionDenied,
        AndroidIoCode.sourceMissing => FailureKind.sourceMissing,
        AndroidIoCode.cloudPending => FailureKind.cloudPending,
        AndroidIoCode.unsupported => FailureKind.unsupported,
        AndroidIoCode.storage ||
        AndroidIoCode.cleanupPending => FailureKind.storage,
        _ => FailureKind.unavailable,
      });
}
