import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../application/backup_snapshot.dart';

/// Tracks only entries created by this operation. A private directory name
/// does not grant permission to delete unknown children or changed content.
final class BackupTemporaryWorkspace {
  BackupTemporaryWorkspace(Directory root)
    : root = Directory(p.normalize(root.absolute.path));

  final Directory root;
  final Map<String, _OwnedEntry> _entries = {};
  bool _ioUncertain = false;

  BackupTemporaryWorkspace copy() {
    final result = BackupTemporaryWorkspace(root);
    result._entries.addAll(_entries);
    result._ioUncertain = _ioUncertain;
    return result;
  }

  void registerDirectory(Directory directory) {
    _register(
      directory.path,
      const _OwnedEntry(FileSystemEntityType.directory),
    );
  }

  /// Call only after exclusive creation succeeded, or a worker that owns
  /// exclusive creation returned a complete, closed file normally.
  void registerFile(File file) {
    _register(file.path, const _OwnedEntry(FileSystemEntityType.file));
  }

  void markIoUncertain() => _ioUncertain = true;

  /// The moved file is now a user export. Its former name cannot establish
  /// ownership of any file that appears there after publication.
  void forgetPublishedFile(File file) => _entries.remove(_relative(file.path));

  void recordVerifiedFile(File file, String digest, int bytes) {
    final relative = _relative(file.path);
    if (_entries[relative]?.type != FileSystemEntityType.file ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        bytes < 0) {
      throw _failure();
    }
    _entries[relative] = _OwnedEntry(FileSystemEntityType.file, digest, bytes);
  }

  Future<int> verifyAndRecordFile(File file) async {
    final relative = _relative(file.path);
    if (_entries[relative]?.type != FileSystemEntityType.file) throw _failure();
    try {
      await _checkPath(file.path, FileSystemEntityType.file);
      final bytes = await file.length();
      final evidence = await _digest(file, bytes);
      if (evidence.$2 != bytes) throw _failure();
      recordVerifiedFile(file, evidence.$1, evidence.$2);
      return evidence.$2;
    } catch (_) {
      // A complete writer without readable complete content evidence must not
      // be downgraded to permission to erase an arbitrary unverified partial.
      markIoUncertain();
      rethrow;
    }
  }

  void _register(String path, _OwnedEntry entry) {
    final relative = _relative(path);
    final parent = p.dirname(relative);
    if (_entries.containsKey(relative) ||
        (parent != '.' &&
            _entries[parent]?.type != FileSystemEntityType.directory)) {
      throw _failure();
    }
    _entries[relative] = entry;
  }

  String _relative(String path) {
    final absolute = p.normalize(p.absolute(path));
    if (!p.isWithin(root.path, absolute)) throw _failure();
    return p.relative(absolute, from: root.path);
  }

  Future<void> remove() async {
    try {
      await _remove();
    } catch (_) {
      // Native exceptions can include complete paths; expose fixed feedback.
      throw _failure();
    }
  }

  Future<void> _remove() async {
    if (_ioUncertain) throw _failure();
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    await _checkPath(root.path, FileSystemEntityType.directory);

    // Inspect the entire tree before deleting the first known file. Never
    // recurse through an unknown directory or a linked descendant.
    Future<void> inspect(Directory directory) async {
      await _checkPath(directory.path, FileSystemEntityType.directory);
      await for (final child in directory.list(followLinks: false)) {
        final relative = _relative(child.path);
        final type = await FileSystemEntity.type(
          child.path,
          followLinks: false,
        );
        final expected = _entries[relative];
        if (expected == null || type != expected.type) throw _failure();
        if (type == FileSystemEntityType.directory) {
          await inspect(Directory(child.path));
        }
      }
    }

    await inspect(root);
    for (final entry in _entries.entries) {
      await _checkEntry(entry.key, entry.value);
    }
    for (final entry in _entries.entries.where(
      (entry) => entry.value.type == FileSystemEntityType.file,
    )) {
      if (await _checkEntry(entry.key, entry.value)) {
        await File(p.join(root.path, entry.key)).delete();
      }
    }
    final directories =
        _entries.entries
            .where(
              (entry) => entry.value.type == FileSystemEntityType.directory,
            )
            .toList()
          ..sort(
            (a, b) => p.split(b.key).length.compareTo(p.split(a.key).length),
          );
    for (final entry in directories) {
      if (await _checkEntry(entry.key, entry.value)) {
        // A later foreign child makes this nonrecursive deletion fail safely.
        await Directory(p.join(root.path, entry.key)).delete();
      }
    }
    await _checkPath(root.path, FileSystemEntityType.directory);
    await root.delete();
  }

  Future<bool> _checkEntry(String relative, _OwnedEntry entry) async {
    final path = p.join(root.path, relative);
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return false;
    }
    await _checkPath(path, entry.type);
    if (entry.digest != null) {
      final file = File(path);
      if (await file.length() != entry.bytes) throw _failure();
      final evidence = await _digest(file, entry.bytes!);
      if (evidence.$1 != entry.digest || evidence.$2 != entry.bytes) {
        throw _failure();
      }
    }
    return true;
  }

  Future<void> _checkPath(String path, FileSystemEntityType type) async {
    var current = p.normalize(p.absolute(path));
    var expected = type;
    while (true) {
      if (await FileSystemEntity.type(current, followLinks: false) !=
          expected) {
        throw _failure();
      }
      final parent = p.dirname(current);
      if (parent == current) return;
      current = parent;
      expected = FileSystemEntityType.directory;
    }
  }

  Future<(String, int)> _digest(File file, int maximumBytes) async {
    var bytes = 0;
    final digest = await sha256
        .bind(
          file.openRead().map((chunk) {
            bytes += chunk.length;
            if (bytes > maximumBytes) throw _failure();
            return chunk;
          }),
        )
        .first;
    return (digest.toString(), bytes);
  }

  static BackupSnapshotFailure _failure() =>
      BackupSnapshotFailure('备份暂存无法安全清理，未知或变化内容及未确认结束的 IO 现场已保留，请核查后重试。');
}

final class _OwnedEntry {
  const _OwnedEntry(this.type, [this.digest, this.bytes]);
  final FileSystemEntityType type;
  final String? digest;
  final int? bytes;
}
