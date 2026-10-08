import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform_resource.dart';
import '../application/backup_snapshot.dart';
import '../domain/backup_manifest.dart';

/// Writes only an unpublished, private staged package. The caller must retain
/// the snapshot lease until this future finishes, including after cancellation.
final class BackupZipWriter {
  Future<void> write(
    BackupSnapshotLease snapshot,
    File destination, {
    CancellationToken? cancellation,
    void Function(int written, int total)? onProgress,
  }) async {
    if (snapshot.released) {
      throw BackupSnapshotFailure('备份快照保护已结束，不能写入备份。');
    }
    if (cancellation?.isCancelled ?? false) {
      throw BackupSnapshotFailure('备份已取消，原资料库保持有效。');
    }
    final BackupManifest manifest;
    try {
      manifest = BackupManifest.decode(snapshot.manifestBytes);
    } catch (_) {
      throw BackupSnapshotFailure('备份清单无效，未写入备份。');
    }
    final sources = <_SourceEntry>[];
    if (manifest.mode != snapshot.manifest.mode ||
        manifest.images.length != snapshot.manifest.images.length) {
      throw BackupSnapshotFailure('备份清单与受保护快照不一致。');
    }
    for (var i = 0; i < manifest.images.length; i++) {
      final entry = manifest.images[i];
      final original = snapshot.manifest.images[i];
      final source = snapshot.permanentFiles[entry.versionId];
      if (entry.versionId != original.versionId ||
          entry.name != original.name ||
          entry.sha256 != original.sha256 ||
          entry.byteCount != original.byteCount ||
          source == null) {
        throw BackupSnapshotFailure('备份清单与受保护快照不一致。');
      }
      sources.add(_SourceEntry(entry, p.normalize(p.absolute(source.path))));
    }
    final request = _WriteRequest(
      snapshot.manifestBytes,
      sources,
      p.normalize(p.absolute(destination.path)),
    );
    final events = ReceivePort();
    SendPort? control;
    var callbackFailed = false;
    var lastProgress = -1;
    final subscription = events.listen((Object? event) {
      if (event is SendPort) {
        control = event;
        if (cancellation?.isCancelled ?? false) control!.send(null);
      } else if (event is int && !callbackFailed) {
        lastProgress = event;
        try {
          onProgress?.call(event, request.total);
        } catch (_) {
          callbackFailed = true;
          control?.send(null);
        }
        if (cancellation?.isCancelled ?? false) control?.send(null);
      }
    });
    final timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if ((cancellation?.isCancelled ?? false) || callbackFailed) {
        control?.send(null);
      }
    });
    _WriteResult result;
    try {
      // Do not capture the snapshot and its database release callback in the
      // isolate closure. All worker input is an explicit portable DTO.
      result = await _runWorker(request, events.sendPort);
    } catch (_) {
      throw BackupSnapshotFailure('备份写入失败；请保留资料库并检查暂存目录。');
    } finally {
      timer.cancel();
      await subscription.cancel();
      events.close();
    }
    // The worker result and progress use different ports. Deliver the final
    // count explicitly if result delivery wins their last-message race.
    if (result.code == 0 && !callbackFailed && lastProgress < request.total) {
      try {
        onProgress?.call(request.total, request.total);
      } catch (_) {
        callbackFailed = true;
      }
    }
    if (result.code == 0 &&
        ((cancellation?.isCancelled ?? false) || callbackFailed)) {
      try {
        _checkPath(request.destination, fileRequired: true);
        await destination.delete();
      } catch (_) {
        throw BackupSnapshotFailure('备份已停止，但暂存文件清理失败；请核查暂存目录。');
      }
      result = const _WriteResult(1);
    }
    if (result.code != 0) {
      throw BackupSnapshotFailure(switch (result.code) {
        1 => '备份已取消，原资料库保持有效。',
        3 => '备份写入失败且暂存文件清理失败；请核查暂存目录。',
        4 => '备份原图缺失、损坏或发生变化，未生成可发布备份。',
        _ => '备份写入失败，原资料库保持有效。',
      }, affectedVersions: result.version == null ? [] : [result.version!]);
    }
  }
}

Future<_WriteResult> _runWorker(_WriteRequest request, SendPort progress) =>
    Isolate.run(() => _writeWorker(request, progress));

final class _WriteRequest {
  const _WriteRequest(this.manifestBytes, this.sources, this.destination);
  final Uint8List manifestBytes;
  final List<_SourceEntry> sources;
  final String destination;
  int get total =>
      manifestBytes.length +
      sources.fold<int>(0, (count, source) => count + source.entry.byteCount);
}

final class _SourceEntry {
  const _SourceEntry(this.entry, this.path);
  final BackupImageEntry entry;
  final String path;
}

final class _WriteResult {
  const _WriteResult(this.code, [this.version]);
  final int code;
  final String? version;
}

final class _Cancelled implements Exception {}

final class _Changed implements Exception {
  const _Changed(this.version);
  final String version;
}

Future<_WriteResult> _writeWorker(
  _WriteRequest request,
  SendPort progress,
) async {
  final control = ReceivePort();
  var cancelled = false;
  final listener = control.listen((_) => cancelled = true);
  progress.send(control.sendPort);
  void checkCancellation() {
    if (cancelled) throw _Cancelled();
  }

  final target = File(request.destination);
  _CheckedOutput? output;
  var owned = false;
  var result = const _WriteResult(0);
  try {
    await Future<void>.delayed(Duration.zero);
    checkCancellation();
    _checkPath(request.destination);
    // Never remove an existing target, even when exclusive creation fails.
    target.createSync(exclusive: true);
    owned = true;
    _checkPath(request.destination, fileRequired: true);
    output = _CheckedOutput(request.destination, progress);
    final encoder = _CheckedZipEncoder();
    encoder.startEncode(output);
    final manifest = ArchiveFile(
      'manifest.json',
      request.manifestBytes.length,
      request.manifestBytes,
    )..compression = CompressionType.none;
    encoder.add(manifest);
    await Future<void>.delayed(Duration.zero);
    checkCancellation();
    for (final source in request.sources) {
      final entry = source.entry;
      InputFileStream? input;
      try {
        _checkPath(source.path, fileRequired: true);
        final digest = _DigestSink();
        final hash = sha256.startChunkedConversion(digest);
        var size = 0;
        var crc = 0;
        try {
          await for (final chunk in File(source.path).openRead()) {
            checkCancellation();
            size += chunk.length;
            if (size > entry.byteCount) throw _Changed(entry.versionId);
            hash.add(chunk);
            crc = getCrc32(chunk, crc);
          }
        } finally {
          hash.close();
        }
        if (size != entry.byteCount || digest.value != entry.sha256) {
          throw _Changed(entry.versionId);
        }
        checkCancellation();
        _checkPath(source.path, fileRequired: true);
        input = InputFileStream(source.path, bufferSize: 256 * 1024);
        output.expected = entry;
        final file = ArchiveFile.stream(entry.name, input)
          ..compression = CompressionType.none
          ..crc32 = crc;
        // Store streams in bounded chunks; deflate in archive 4.3 buffers the
        // whole image. The output hashes the actual bytes written a second time.
        encoder.add(file);
        output.expected = null;
      } on _Cancelled {
        rethrow;
      } on _Changed {
        rethrow;
      } catch (_) {
        throw _Changed(entry.versionId);
      } finally {
        input?.closeSync();
      }
      // Sync encoding cannot service isolate messages inside the current entry.
      // Cancellation waits for this real IO, then prevents the next entry.
      await Future<void>.delayed(Duration.zero);
      checkCancellation();
    }
    encoder.endEncode();
    output.flush();
    await Future<void>.delayed(Duration.zero);
    checkCancellation();
  } on _Cancelled {
    result = const _WriteResult(1);
  } on _Changed catch (error) {
    result = _WriteResult(4, error.version);
  } catch (_) {
    result = const _WriteResult(2);
  } finally {
    try {
      output?.closeSync();
      if (owned && result.code == 0) {
        // OutputFileStream.flush drains its buffer, but does not fsync.
        final handle = target.openSync(mode: FileMode.append);
        try {
          handle.flushSync();
        } finally {
          handle.closeSync();
        }
      }
    } catch (_) {
      result = const _WriteResult(2);
    }
    if (owned && result.code != 0) {
      try {
        _checkPath(request.destination, fileRequired: true);
        target.deleteSync();
      } catch (_) {
        result = const _WriteResult(3);
      }
    }
    await listener.cancel();
    control.close();
  }
  return result;
}

void _checkPath(String path, {bool fileRequired = false}) {
  var ancestor = path;
  var first = true;
  while (true) {
    final type = FileSystemEntity.typeSync(ancestor, followLinks: false);
    if (type == FileSystemEntityType.link ||
        (first && fileRequired && type != FileSystemEntityType.file) ||
        (!first && type != FileSystemEntityType.directory)) {
      throw const FileSystemException('Unsafe backup path');
    }
    final parent = p.dirname(ancestor);
    if (ancestor == parent) break;
    ancestor = parent;
    first = false;
  }
}

final class _CheckedOutput extends OutputFileStream {
  factory _CheckedOutput(String path, SendPort progress) =>
      _CheckedOutput._(FileHandle(path, mode: FileAccess.write), progress);
  _CheckedOutput._(this.handle, this.progress)
    : super.withFileHandle(handle, bufferSize: 256 * 1024);
  final FileHandle handle;
  final SendPort progress;
  BackupImageEntry? expected;
  int written = 0;

  @override
  void closeSync() {
    try {
      super.closeSync();
    } finally {
      // A failed buffer flush must still close the real OS handle.
      handle.closeSync();
    }
  }

  @override
  void writeStream(InputStream stream) {
    final descriptor = expected;
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    var count = 0;
    try {
      while (!stream.isEOS) {
        final countToRead = stream.length > 256 * 1024
            ? 256 * 1024
            : stream.length;
        if (countToRead <= 0) break;
        final bytes = stream.readBytes(countToRead).toUint8List();
        count += bytes.length;
        if (descriptor != null && count > descriptor.byteCount) {
          throw _Changed(descriptor.versionId);
        }
        hash.add(bytes);
        writeBytes(bytes);
        written += bytes.length;
        progress.send(written);
      }
    } finally {
      hash.close();
    }
    if (descriptor != null &&
        (count != descriptor.byteCount || digest.value != descriptor.sha256)) {
      throw _Changed(descriptor.versionId);
    }
  }
}

/// archive's uncompressed branch otherwise ignores ArchiveFile.crc32 and
/// rereads the source synchronously. Use the CRC from the cancellable verified
/// read; the output independently verifies that those exact bytes are stored.
final class _CheckedZipEncoder extends ZipEncoder {
  @override
  int getFileCrc32(ArchiveFile file) => file.crc32 ?? super.getFileCrc32(file);
}

final class _DigestSink implements Sink<Digest> {
  String? value;
  @override
  void add(Digest data) => value = data.toString();
  @override
  void close() {}
}
