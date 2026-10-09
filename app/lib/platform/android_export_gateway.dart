import 'package:uuid/uuid.dart';

import '../core/platform_resource.dart';
import '../features/processing/domain/export_models.dart';
import 'generated/android_files.g.dart';
import 'export_mime.dart';

class AndroidExportGateway {
  AndroidExportGateway({AndroidExportHost? host})
    : _host = host ?? AndroidExportHost();
  final AndroidExportHost _host;
  static final _handlePattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  Future<List<ExportItemResult>> export(
    List<ExportInput> inputs, {
    CancellationToken? cancellation,
    bool photos = false,
  }) async {
    final frozen = List<ExportInput>.unmodifiable(inputs);
    if (frozen.isEmpty) return const [];
    final operationIds = List.generate(frozen.length, (_) => const Uuid().v4());
    String? handle;
    final results = <ExportItemResult>[];
    try {
      cancellation?.throwIfCancelled();
      if (!photos) {
        final destination = frozen.length == 1
            ? await _host.createDocument(
                frozen.single.displayName,
                mime(frozen.single.displayName),
              )
            : await _host.pickDirectory(operationIds);
        handle = destination.handle;
        if (destination.cancelled) {
          if (handle != null) {
            throw const ExportFailure(ExportFailureKind.storage, '系统保存返回无效。');
          }
          return List.unmodifiable(frozen.map(_cancelled));
        }
        if (handle == null || !_handlePattern.hasMatch(handle)) {
          throw const ExportFailure(ExportFailureKind.storage, '无法确认系统保存位置。');
        }
      }
      for (var index = 0; index < frozen.length; index++) {
        final input = frozen[index];
        final operationId = operationIds[index];
        if (cancellation?.isCancelled ?? false) {
          results.add(_cancelled(input));
          continue;
        }
        var active = true;
        Future<void>? cancelRequest;
        cancellation?.whenCancelled.then((_) {
          if (active) {
            cancelRequest = _host.cancelExport(operationId);
            cancelRequest!.catchError((Object _) {});
          }
        });
        try {
          final reply = await _host.exportFile(
            AndroidExportRequest(
              operationId: operationId,
              sourcePath: input.source.absolute.path,
              displayName: input.displayName,
              mimeType: mime(input.displayName),
              sha256: input.expectedSha256,
              byteCount: input.expectedByteCount,
              kind: photos
                  ? AndroidDestinationKind.photos
                  : frozen.length == 1
                  ? AndroidDestinationKind.document
                  : AndroidDestinationKind.tree,
              destinationHandle: handle,
            ),
          );
          if (reply.code == AndroidIoCode.ok) {
            final uri = Uri.tryParse(reply.uri ?? '');
            if (uri?.scheme != 'content' ||
                uri!.authority.isEmpty ||
                reply.displayName == null ||
                reply.displayName!.isEmpty) {
              throw const ExportFailure(
                ExportFailureKind.storage,
                '系统尚未确认实际保存文件。',
              );
            }
            results.add(
              ExportItemResult(
                id: input.id,
                status: ExportStatus.saved,
                fileName: reply.displayName,
                destinationUri: reply.uri,
              ),
            );
          } else if (reply.code == AndroidIoCode.cancelled) {
            results.add(_cancelled(input));
          } else {
            results.add(
              ExportItemResult(
                id: input.id,
                status: ExportStatus.failed,
                destinationUri: reply.uri,
                reason: _reason(reply.code),
                failureKind: reply.code == AndroidIoCode.permissionDenied
                    ? ExportFailureKind.permissionDenied
                    : ExportFailureKind.storage,
              ),
            );
          }
        } catch (_) {
          results.add(
            ExportItemResult(
              id: input.id,
              status: ExportStatus.failed,
              reason: '系统保存未确认，请检查权限与空间后重试。',
            ),
          );
        } finally {
          active = false;
          try {
            await cancelRequest;
          } catch (_) {
            /* Actual export already drained. */
          }
        }
      }
    } on ResourceFailure catch (error) {
      if (error.kind != FailureKind.cancelled) rethrow;
      results.addAll(frozen.skip(results.length).map(_cancelled));
    } catch (_) {
      for (final input in frozen.skip(results.length)) {
        results.add(
          ExportItemResult(
            id: input.id,
            status: ExportStatus.failed,
            reason: '无法取得或确认系统保存位置，请重选后重试。',
          ),
        );
      }
    } finally {
      if (handle != null) {
        try {
          await _host.closeDestination(handle);
        } catch (_) {
          for (var i = 0; i < results.length; i++) {
            final result = results[i];
            results[i] = ExportItemResult(
              id: result.id,
              status: result.status,
              fileName: result.fileName,
              destinationUri: result.destinationUri,
              failureKind: result.failureKind,
              reason: '系统位置授权或未完成文件清理未确认；已确认保存的文件保留。',
            );
          }
        }
      }
    }
    return List.unmodifiable(results);
  }

  static String mime(String name) => exportMimeType(name);

  ExportItemResult _cancelled(ExportInput input) => ExportItemResult(
    id: input.id,
    status: ExportStatus.cancelled,
    reason: '已取消系统保存。',
  );

  String _reason(AndroidIoCode code) => switch (code) {
    AndroidIoCode.permissionDenied => '系统保存授权被拒绝，请重新选择或授权。',
    AndroidIoCode.sourceMissing => '应用内副本已不可用，请重新取得完整副本。',
    AndroidIoCode.inputChanged => '输入或目标内容校验不一致，未确认保存。',
    AndroidIoCode.unsupported => '该系统位置或图片格式暂不支持保存。',
    AndroidIoCode.cleanupPending ||
    AndroidIoCode.unconfirmed => '写入或清理结果无法确认，请核查目标文件；现场保留。',
    _ => '系统保存未完成，请检查空间与授权后重试。',
  };
}
