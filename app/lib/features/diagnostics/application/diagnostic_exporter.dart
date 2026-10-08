import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/platform_resource.dart';
import '../../gallery/data/library_repository.dart';
import '../../processing/application/file_exporter.dart';
import '../../processing/domain/export_models.dart';

/// Owns only a private temporary JSON source; the common exporter owns the
/// destination and does not complete until its real IO and verification end.
class DiagnosticExporter {
  const DiagnosticExporter({this.fileExporter = const FileExporter()});
  final FileExporter fileExporter;

  Future<ExportItemResult> export(
    DiagnosticExportDocument document,
    Directory destination, {
    CancellationToken? cancellation,
    ExportFaultHook? faultHook,
  }) => exportUsing(
    document,
    (inputs) => fileExporter.exportToDirectory(
      inputs,
      destination,
      cancellation: cancellation,
      faultHook: faultHook,
    ),
    cancellation: cancellation,
  );

  Future<ExportItemResult> exportUsing(
    DiagnosticExportDocument document,
    Future<List<ExportItemResult>> Function(List<ExportInput>) transfer, {
    CancellationToken? cancellation,
    Directory? temporaryParent,
  }) async {
    Directory? temporary;
    File? source;
    String? digest;
    RandomAccessFile? writer;
    ExportItemResult? result;
    Object? failure;
    var cleanupPending = false;
    var writerClosed = true;
    var writerCloseUncertain = false;
    final id = const Uuid().v4();
    try {
      cancellation?.throwIfCancelled();
      final parent = temporaryParent ?? Directory.systemTemp;
      await _checkPath(parent.path);
      temporary = await parent.createTemp('imagehost-diagnostics-');
      await _checkPath(temporary.path);
      final name = 'ImageHub-diagnostics-$id.json';
      source = File(p.join(temporary.path, name));
      await source.create(exclusive: true);
      digest = sha256.convert(document.bytes).toString();
      writer = await source.open(mode: FileMode.writeOnly);
      writerClosed = false;
      await writer.writeFrom(document.bytes);
      await writer.flush();
      try {
        await writer.close();
      } catch (_) {
        writerCloseUncertain = true;
        rethrow;
      }
      writerClosed = true;
      writer = null;
      await _checkPath(source.path);
      if (await FileSystemEntity.type(source.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await source.length() != document.bytes.length ||
          (await sha256.bind(source.openRead()).first).toString() != digest) {
        throw const ExportFailure(
          ExportFailureKind.inputChanged,
          '诊断临时内容校验未通过。',
        );
      }
      cancellation?.throwIfCancelled();
      final results = await transfer(
        List<ExportInput>.unmodifiable([
          ExportInput(
            id: id,
            source: source,
            displayName: name,
            expectedSha256: digest,
            expectedByteCount: document.bytes.length,
          ),
        ]),
      );
      result = results.single;
      if (result.id != id) {
        result = null;
        throw const ExportFailure(
          ExportFailureKind.invalidInput,
          '诊断导出回执与本次内容不一致。',
        );
      }
    } catch (error) {
      failure = error;
    } finally {
      // Never release ownership by deleting an unknown child recursively.
      try {
        await writer?.close();
        writerClosed = !writerCloseUncertain;
      } catch (_) {
        cleanupPending = true;
      }
      try {
        if (temporary != null) {
          await _checkPath(temporary.path);
          if (!writerClosed) {
            cleanupPending = true;
          } else if (source != null && digest != null) {
            await _checkPath(source.path);
            if (await FileSystemEntity.type(source.path, followLinks: false) ==
                FileSystemEntityType.file) {
              final actual = await sha256.bind(source.openRead()).first;
              if (await source.length() == document.bytes.length &&
                  actual.toString() == digest) {
                await source.delete();
              } else {
                cleanupPending = true;
              }
            } else if (await FileSystemEntity.type(
                  source.path,
                  followLinks: false,
                ) !=
                FileSystemEntityType.notFound) {
              cleanupPending = true;
            }
          } else if (source != null) {
            // A failed write has no complete content evidence. Preserve it.
            cleanupPending = true;
          }
          if (writerClosed &&
              await temporary.list(followLinks: false).isEmpty) {
            await temporary.delete();
          } else {
            cleanupPending = true;
          }
        }
      } catch (_) {
        cleanupPending = true;
      }
    }
    if (result != null) {
      return ExportItemResult(
        id: result.id,
        status: result.status == ExportStatus.saved
            ? ExportStatus.saved
            : cleanupPending
            ? ExportStatus.failed
            : result.status,
        fileName: result.fileName,
        destinationPath: result.destinationPath,
        destinationUri: result.destinationUri,
        failureKind: result.failureKind,
        reason: cleanupPending
            ? '${result.reason == null ? '' : '${result.reason} '}诊断临时内容清理未确认，现场已保留，请检查后重试。'
            : result.reason,
      );
    }
    final cancelled =
        failure is ResourceFailure && failure.kind == FailureKind.cancelled;
    return ExportItemResult(
      id: id,
      status: cancelled && !cleanupPending
          ? ExportStatus.cancelled
          : ExportStatus.failed,
      reason: cleanupPending
          ? '诊断临时内容清理未确认，现场已保留，请检查后重试。'
          : cancelled
          ? '已取消诊断导出。'
          : '诊断导出未完成，请检查目录权限和空间后重试。',
    );
  }

  Future<void> _checkPath(String path) async {
    var ancestor = p.normalize(p.absolute(path));
    while (true) {
      if (await FileSystemEntity.type(ancestor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const ExportFailure(
          ExportFailureKind.unsafePath,
          '诊断导出临时目录不可安全使用。',
        );
      }
      final parent = p.dirname(ancestor);
      if (parent == ancestor) return;
      ancestor = parent;
    }
  }
}
