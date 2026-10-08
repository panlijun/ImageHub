import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform_resource.dart';
import '../domain/export_models.dart';

enum ExportBoundary {
  beforeTargetClose,
  afterTargetClose,
  beforeTargetVerification,
  afterTargetVerification,
}

typedef ExportFaultHook = Future<void> Function(
  ExportBoundary boundary,
  ExportInput input,
  File destination,
);

/// Copies one item at a time. Callers release leases only after this completes.
class FileExporter {
  const FileExporter();

  Future<List<ExportItemResult>> exportToDirectory(
    List<ExportInput> inputs,
    Directory directory, {
    CancellationToken? cancellation,
    ExportFaultHook? faultHook,
  }) async {
    final results = <ExportItemResult>[];
    for (final input in List<ExportInput>.of(inputs)) {
      if (cancellation?.isCancelled ?? false) {
        results.add(_cancelled(input));
        continue;
      }
      results.add(await _exportOne(input, directory, cancellation, faultHook));
    }
    return List.unmodifiable(results);
  }

  Future<ExportItemResult> _exportOne(
    ExportInput input,
    Directory directory,
    CancellationToken? cancellation,
    ExportFaultHook? faultHook,
  ) async {
    File? created;
    RandomAccessFile? writer;
    final writtenDigest = _DigestSink();
    final hasher = sha256.startChunkedConversion(writtenDigest);
    var hasherClosed = false;
    var writtenByteCount = 0;
    try {
      if (input.id.isEmpty ||
          input.expectedByteCount < 0 ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(input.expectedSha256)) {
        throw const ExportFailure(
          ExportFailureKind.invalidInput,
          '导出输入标识或内容校验信息无效。',
        );
      }
      final root = await _checkPath(directory.absolute.path);
      if (await FileSystemEntity.type(root, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const ExportFailure(
          ExportFailureKind.storage,
          '导出目录不存在或不可用，请重新选择。',
        );
      }
      final sourcePath = await _checkPath(input.source.absolute.path);
      final source = File(sourcePath);
      if (await FileSystemEntity.type(sourcePath, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const ExportFailure(
          ExportFailureKind.sourceMissing,
          '应用内导出副本不存在或不可用。',
        );
      }
      await _verifyInput(source, input, cancellation);
      cancellation?.throwIfCancelled();
      final name = _safeName(input);
      final extension = p.extension(name);
      final stem = p.basenameWithoutExtension(name);
      var suffix = 0;
      while (true) {
        cancellation?.throwIfCancelled();
        final candidate = File(
          p.join(root, suffix == 0 ? name : '$stem ($suffix)$extension'),
        );
        await _checkPath(candidate.path);
        // Exclusive creation makes another exporter winning the name harmless.
        try {
          await candidate.create(exclusive: true);
          created = candidate;
          break;
        } on FileSystemException {
          final type = await FileSystemEntity.type(
            candidate.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.link) throw _unsafePath;
          if (type == FileSystemEntityType.notFound) rethrow;
          suffix++;
        }
      }
      await _checkPath(source.path);
      await _checkPath(created.path);
      writer = await created.open(mode: FileMode.writeOnly);
      var copied = 0;
      await for (final chunk in source.openRead()) {
        cancellation?.throwIfCancelled();
        copied += chunk.length;
        if (copied > input.expectedByteCount) throw _inputChanged;
        await writer.writeFrom(chunk);
        hasher.add(chunk);
        writtenByteCount += chunk.length;
      }
      hasher.close();
      hasherClosed = true;
      cancellation?.throwIfCancelled();
      await writer.flush();
      await faultHook?.call(ExportBoundary.beforeTargetClose, input, created);
      await writer.close();
      writer = null;
      await faultHook?.call(ExportBoundary.afterTargetClose, input, created);
      cancellation?.throwIfCancelled();
      await faultHook?.call(
        ExportBoundary.beforeTargetVerification,
        input,
        created,
      );
      await _checkPath(created.path);
      await _verifyInput(created, input, cancellation);
      // Detect input replacement or mutation during the copy as well.
      await _checkPath(source.path);
      await _verifyInput(source, input, cancellation);
      await faultHook?.call(
        ExportBoundary.afterTargetVerification,
        input,
        created,
      );
      cancellation?.throwIfCancelled();
      return ExportItemResult(
        id: input.id,
        status: ExportStatus.saved,
        fileName: p.basename(created.path),
        destinationPath: created.path,
      );
    } catch (error) {
      // Cancellation is an intent; do not return until real IO is closed.
      var cleanupFailed = false;
      if (!hasherClosed) {
        hasher.close();
        hasherClosed = true;
      }
      if (writer != null) {
        try {
          await writer.close();
        } catch (_) {
          cleanupFailed = true;
        }
      }
      if (created != null) {
        try {
          await _checkPath(created.path);
          final type = await FileSystemEntity.type(
            created.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.file) {
            // A replaced or modified path no longer has our written evidence.
            // dart:io has no atomic no-follow/file-id delete API: these checks
            // conservatively reject detectable replacement, but a malicious
            // external mutation between checking and deleting still requires
            // a future platform handle primitive to eliminate that race.
            if (await _matchesWritten(
              created,
              writtenDigest.value!.toString(),
              writtenByteCount,
            )) {
              await _checkPath(created.path);
              await created.delete(); // Never recursively remove anything.
            } else {
              cleanupFailed = true;
            }
          } else if (type != FileSystemEntityType.notFound) {
            cleanupFailed = true;
          }
        } catch (_) {
          cleanupFailed = true;
        }
      }
      final cancelled =
          error is ResourceFailure && error.kind == FailureKind.cancelled;
      final failure = _mapFailure(error);
      return ExportItemResult(
        id: input.id,
        status: cancelled && !cleanupFailed
            ? ExportStatus.cancelled
            : ExportStatus.failed,
        fileName: created == null ? null : p.basename(created.path),
        destinationPath: created?.path,
        failureKind: cancelled && !cleanupFailed ? null : failure.kind,
        reason:
            '${cancelled ? '已取消导出。' : failure.message}'
            '${cleanupFailed ? ' 本次未完成文件无法安全清除，请检查导出目录。' : ''}',
      );
    }
  }

  Future<bool> _matchesWritten(
    File file,
    String expected,
    int byteCount,
  ) async {
    var count = 0;
    final digest = await sha256
        .bind(
          file.openRead().map((chunk) {
            count += chunk.length;
            if (count > byteCount) throw _inputChanged;
            return chunk;
          }),
        )
        .first;
    return count == byteCount && digest.toString() == expected;
  }

  Future<void> _verifyInput(
    File file,
    ExportInput input,
    CancellationToken? cancellation,
  ) async {
    var count = 0;
    final digest = await sha256
        .bind(
          file.openRead().map((chunk) {
            cancellation?.throwIfCancelled();
            count += chunk.length;
            if (count > input.expectedByteCount) throw _inputChanged;
            return chunk;
          }),
        )
        .first;
    cancellation?.throwIfCancelled();
    if (count != input.expectedByteCount ||
        digest.toString() != input.expectedSha256.toLowerCase()) {
      throw _inputChanged;
    }
  }

  Future<String> _checkPath(String absolutePath) async {
    var ancestor = absolutePath;
    while (true) {
      if (await FileSystemEntity.type(ancestor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw _unsafePath;
      }
      final parent = p.dirname(ancestor);
      if (parent == ancestor) break;
      ancestor = parent;
    }
    return p.normalize(absolutePath);
  }

  String _safeName(ExportInput input) {
    var name = input.displayName.split(RegExp(r'[/\\]')).last;
    name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"|?*]'), '_').trim();
    name = name.replaceFirst(RegExp(r'[. ]+$'), '');
    if (name.isEmpty || name == '.' || name == '..') name = 'export';
    if (p.extension(name).isEmpty) {
      final extension = p.extension(input.source.path);
      if (RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(extension)) {
        name += extension;
      }
    }
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = '_$name';
    }
    // Keep the format suffix while leaving space for collision suffixes.
    final extension = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    return '${String.fromCharCodes(stem.runes.take(160))}$extension';
  }

  ExportItemResult _cancelled(ExportInput input) => ExportItemResult(
    id: input.id,
    status: ExportStatus.cancelled,
    reason: '已取消导出。',
  );

  ExportFailure _mapFailure(Object error) {
    if (error is ExportFailure) return error;
    if (error is FileSystemException &&
        {5, 13}.contains(error.osError?.errorCode)) {
      return const ExportFailure(
        ExportFailureKind.permissionDenied,
        '无法读写导出文件，请重新授权或选择目录。',
      );
    }
    return const ExportFailure(
      ExportFailureKind.storage,
      '文件导出失败，请检查目录权限与可用空间后重试。',
    );
  }

  static const _unsafePath = ExportFailure(
    ExportFailureKind.unsafePath,
    '导出路径包含符号链接，已停止此项导出。',
  );

  static const _inputChanged = ExportFailure(
    ExportFailureKind.inputChanged,
    '导出副本内容已变更或目标校验失败，请重新取得完整副本。',
  );
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
