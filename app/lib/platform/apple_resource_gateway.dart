import 'dart:async';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/platform_resource.dart';
import 'generated/apple_files.g.dart';

final appleHandlePattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Holds a selected scope until bounded native reads have actually finished.
class AppleResourceGateway {
  AppleResourceGateway({AppleFileHost? host}) : _host = host ?? AppleFileHost();
  final AppleFileHost _host;

  Future<List<PlatformResource>> pickBackup({
    CancellationToken? cancellation,
  }) async {
    final selectionId = const Uuid().v4();
    var selecting = true;
    Future<void>? cancelling;
    cancellation?.whenCancelled.then((_) {
      if (selecting) {
        cancelling = _host.cancelSelection(selectionId);
        cancelling!.catchError((Object _) {});
      }
    });
    List<PlatformResource> selected = const [];
    try {
      cancellation?.throwIfCancelled();
      selected = await resources(await _host.pickBackup(selectionId));
      if (cancellation?.isCancelled ?? false) {
        for (final resource in selected) {
          await resource.release?.call();
        }
        selected = const [];
        cancellation!.throwIfCancelled();
      }
      return selected;
    } on ResourceFailure {
      rethrow;
    } on PlatformException catch (error) {
      throw appleResourceFailure(error.code);
    } catch (_) {
      throw const ResourceFailure(FailureKind.unavailable);
    } finally {
      selecting = false;
      try {
        await cancelling;
      } catch (_) {
        // No resource may be handed off while selector retirement is unknown.
        for (final resource in selected) {
          await resource.release?.call();
        }
        throw const ResourceFailure(FailureKind.storage);
      }
    }
  }

  Future<List<PlatformResource>> resources(AppleSelection selection) async {
    final handles = selection.resources
        .map((item) => item.handle)
        .where(appleHandlePattern.hasMatch)
        .toSet();
    Future<Never> reject() async {
      var cleanupFailed = false;
      for (final handle in handles) {
        try {
          await _host.closeResource(handle);
        } catch (_) {
          cleanupFailed = true;
        }
      }
      throw ResourceFailure(
        cleanupFailed ? FailureKind.storage : FailureKind.unavailable,
      );
    }

    if (selection.cancelled) {
      return selection.resources.isEmpty ? const [] : reject();
    }
    if (selection.resources.length != 1) return reject();
    final picked = selection.resources.single;
    if (!appleHandlePattern.hasMatch(picked.handle) ||
        picked.displayName.isEmpty ||
        picked.displayName.runes.length > 512 ||
        picked.displayName.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return reject();
    }
    final reader = _AppleResourceReader(_host, picked.handle);
    return List.unmodifiable([
      PlatformResource(
        displayName: picked.displayName,
        sourceType: 'backup',
        openRead: () => reader.read(null),
        openReadWithCancellation: reader.read,
        release: reader.close,
      ),
    ]);
  }
}

class _AppleResourceReader {
  _AppleResourceReader(this.host, this.handle);
  final AppleFileHost host;
  final String handle;
  bool _opened = false;
  Future<void>? _closing;

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

  Stream<List<int>> read(CancellationToken? cancellation) async* {
    if (_opened || _closing != null) {
      throw const ResourceFailure(FailureKind.sourceMissing);
    }
    _opened = true;
    try {
      while (true) {
        cancellation?.throwIfCancelled();
        final reading = host.readResource(handle);
        final reply = cancellation == null
            ? await reading
            : await Future.any<AppleReadReply?>([
                reading,
                cancellation.whenCancelled.then((_) => null),
              ]);
        if (reply == null) {
          var closeFailed = false;
          try {
            await close();
          } catch (_) {
            closeFailed = true;
          }
          // Even failed retirement cannot detach a still-running native read.
          try {
            await reading;
          } catch (_) {
            // Delivery is cancelled only after the real read has returned.
          }
          if (closeFailed) throw const ResourceFailure(FailureKind.storage);
          cancellation!.throwIfCancelled();
          throw const ResourceFailure(FailureKind.unavailable);
        }
        cancellation?.throwIfCancelled();
        if (reply.code != AppleIoCode.ok) {
          throw appleResourceFailure(reply.code.name);
        }
        if (reply.bytes.length > 64 * 1024 ||
            (reply.bytes.isEmpty && !reply.eof)) {
          throw const ResourceFailure(FailureKind.unavailable);
        }
        if (reply.bytes.isNotEmpty) yield reply.bytes;
        if (reply.eof) break;
      }
    } on ResourceFailure {
      rethrow;
    } on PlatformException catch (error) {
      throw appleResourceFailure(error.code);
    } catch (_) {
      throw const ResourceFailure(FailureKind.unavailable);
    } finally {
      await close();
    }
  }
}

ResourceFailure appleResourceFailure(String code) =>
    ResourceFailure(switch (code) {
      'cancelled' => FailureKind.cancelled,
      'permissionDenied' => FailureKind.permissionDenied,
      'sourceMissing' => FailureKind.sourceMissing,
      'cloudPending' => FailureKind.cloudPending,
      'unsupported' => FailureKind.unsupported,
      'storage' || 'cleanupPending' || 'unconfirmed' => FailureKind.storage,
      _ => FailureKind.unavailable,
    });
