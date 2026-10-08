import 'dart:io';
import 'dart:typed_data';

import '../domain/backup_manifest.dart';

/// A committed business view and its source protection have the same boundary.
/// Runtime source paths are never part of the portable manifest.
final class BackupSnapshotLease {
  factory BackupSnapshotLease({
    required BackupManifest manifest,
    required Uint8List manifestBytes,
    required Map<String, File> permanentFiles,
    required Future<void> Function() onRelease,
  }) => BackupSnapshotLease._(
    manifest,
    Uint8List.fromList(manifestBytes).asUnmodifiableView(),
    Map.unmodifiable(permanentFiles),
    onRelease,
  );
  BackupSnapshotLease._(
    this.manifest,
    this.manifestBytes,
    this.permanentFiles,
    this._onRelease,
  );

  final BackupManifest manifest;
  final Uint8List manifestBytes;
  final Map<String, File> permanentFiles;
  final Future<void> Function() _onRelease;
  Future<void>? _releasing;
  bool _released = false;
  bool get released => _released;

  /// Call only after the actual verifier/archive/export IO has ended. Cancelling
  /// a UI intent is insufficient; the caller must first join its real worker.
  Future<void> release() => _releasing ??= _release();
  Future<void> _release() async {
    try {
      await _onRelease();
      _released = true;
    } catch (_) {
      _releasing = null;
      rethrow;
    }
  }

  @override
  String toString() => 'BackupSnapshotLease([受保护快照])';
}

final class BackupSnapshotFailure implements Exception {
  BackupSnapshotFailure(
    this.message, {
    Iterable<String> affectedVersions = const [],
  }) : affectedVersions = List.unmodifiable(affectedVersions);

  final String message;
  // Stable identities only. An error must not stringify a source path or file.
  final List<String> affectedVersions;
  @override
  String toString() => message;
}
