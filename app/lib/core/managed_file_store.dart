import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'platform_resource.dart';

class FileDigest {
  const FileDigest(this.sha256, this.byteCount);
  final String sha256;
  final int byteCount;
}

/// This directory is a new application namespace, never an external-source folder.
class ManagedFileStore {
  ManagedFileStore._(this.root, this._lock);
  final Directory root;
  final RandomAccessFile _lock;
  static final Set<String> _heldRoots = {};

  static Future<ManagedFileStore> open(Directory directory) async {
    final root = Directory(p.normalize(p.absolute(directory.path)));
    // Refuse any linked ancestor, including a linked library root.
    var ancestor = root.path;
    while (true) {
      if (await FileSystemEntity.type(ancestor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const LibraryOpenException('图库目录包含符号链接，请选择独立的本机目录。');
      }
      final parent = p.dirname(ancestor);
      if (parent == ancestor) break;
      ancestor = parent;
    }
    await root.create(recursive: true);
    final key = Platform.isWindows ? root.path.toLowerCase() : root.path;
    if (!_heldRoots.add(key)) {
      throw const LibraryOpenException('图库正在由另一个实例使用，请先关闭该实例。');
    }
    RandomAccessFile? handle;
    try {
      final lockPath = p.join(root.path, '.library.lock');
      if (await FileSystemEntity.type(lockPath, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const LibraryOpenException('图库锁文件无效，请保留数据并检查目录。');
      }
      handle = await File(lockPath).open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.exclusive);
      } on FileSystemException {
        throw const LibraryOpenException('图库正在由另一个实例使用，请先关闭该实例。');
      }
      final store = ManagedFileStore._(root, handle);
      for (final path in [
        'staging',
        'originals',
        'cache',
        'cache/thumbnails',
        'cache/outputs',
      ]) {
        await store.file('$path/.guard');
        await store.directory(path).create(recursive: true);
      }
      return store;
    } catch (_) {
      _heldRoots.remove(key);
      await handle?.close();
      rethrow;
    }
  }

  Directory directory(String relative) => Directory(_resolve(relative));
  String _resolve(String relative) {
    if (p.isAbsolute(relative) ||
        relative.contains('\\') ||
        relative.split('/').any((part) => part == '..' || part.isEmpty)) {
      throw const ResourceFailure(FailureKind.storage);
    }
    final resolved = p.normalize(p.join(root.path, relative));
    if (!p.isWithin(root.path, resolved)) {
      throw const ResourceFailure(FailureKind.storage);
    }
    return resolved;
  }

  Future<File> file(String relative) async {
    final path = _resolve(relative);
    var candidate = path;
    while (candidate != root.path) {
      if (await FileSystemEntity.type(candidate, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const ResourceFailure(FailureKind.storage);
      }
      candidate = p.dirname(candidate);
    }
    return File(path);
  }

  Future<FileDigest> digest(File file) async {
    var count = 0;
    final value = await sha256
        .bind(
          file.openRead().map((chunk) {
            count += chunk.length;
            return chunk;
          }),
        )
        .first;
    return FileDigest(value.toString(), count);
  }

  Future<FileDigest> copySource(
    PlatformResource source,
    String stagePath,
    CancellationToken? cancellation,
    int byteBudget,
    void Function(int count)? onProgress, {
    Future<void> Function(int bytes)? beforeWrite,
  }) async {
    final target = await file(stagePath);
    await target.create(exclusive: true);
    final writer = await target.open(mode: FileMode.writeOnly);
    final accumulator = _DigestSink();
    final hasher = sha256.startChunkedConversion(accumulator);
    var count = 0;
    StreamIterator<List<int>>? reader;
    try {
      cancellation?.throwIfCancelled();
      Stream<List<int>> stream;
      try {
        stream = source.read(cancellation: cancellation);
      } catch (error) {
        throw _sourceFailure(error);
      }
      reader = StreamIterator(
        stream.handleError((Object error) {
          throw _sourceFailure(error);
        }),
      );
      // Race only delivery of the next chunk. Cancellation cleanup below still
      // waits for the source's actual IO before closing/reclaiming the stage.
      final stopped = cancellation?.whenCancelled.then((_) => false);
      while (await (stopped == null
          ? reader.moveNext()
          : Future.any([reader.moveNext(), stopped]))) {
        cancellation?.throwIfCancelled();
        final chunk = reader.current;
        count += chunk.length;
        if (count > byteBudget) {
          throw const ResourceFailure(FailureKind.resourceBudget);
        }
        await beforeWrite?.call(chunk.length);
        cancellation?.throwIfCancelled();
        await writer.writeFrom(chunk);
        hasher.add(chunk);
        onProgress?.call(count);
      }
      cancellation?.throwIfCancelled();
      await writer.flush();
    } on ResourceFailure {
      rethrow;
    } catch (_) {
      throw const ResourceFailure(FailureKind.storage);
    } finally {
      try {
        try {
          await reader?.cancel();
        } catch (_) {
          // Unconfirmed source cleanup is not a completed cancellation. Keep
          // the import journal and partial bytes for recovery.
          throw const ResourceFailure(FailureKind.storage);
        }
      } finally {
        hasher.close();
        await writer.close();
      }
    }
    // A fresh read independently verifies the closed, flushed local bytes.
    final result = await digest(target);
    if (result.byteCount != count ||
        result.sha256 != accumulator.value?.toString()) {
      throw const ResourceFailure(FailureKind.storage);
    }
    return result;
  }

  static ResourceFailure _sourceFailure(Object error) {
    if (error is ResourceFailure) return error;
    if (error is FileSystemException) {
      if ([2, 3].contains(error.osError?.errorCode)) {
        return const ResourceFailure(FailureKind.sourceMissing);
      }
      if ([5, 13].contains(error.osError?.errorCode)) {
        return const ResourceFailure(FailureKind.permissionDenied);
      }
    }
    return const ResourceFailure(FailureKind.unavailable);
  }

  Future<void> publish(String stagePath, String finalPath) async {
    final source = await file(stagePath);
    final destination = await file(finalPath);
    if (await destination.exists()) {
      throw const ResourceFailure(FailureKind.storage);
    }
    await source.rename(destination.path);
  }

  Future<void> deleteStage(String relative) async {
    if (!RegExp(r'^staging/[0-9a-f-]{36}\.part$').hasMatch(relative)) {
      throw const ResourceFailure(FailureKind.storage);
    }
    final stage = await file(relative);
    if (await stage.exists()) await stage.delete();
  }

  Future<void> close() async {
    try {
      await _lock.unlock();
    } finally {
      await _lock.close();
      _heldRoots.remove(
        Platform.isWindows ? root.path.toLowerCase() : root.path,
      );
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
