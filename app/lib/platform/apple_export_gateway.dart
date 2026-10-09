import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/platform_resource.dart';
import '../features/processing/domain/export_models.dart';
import 'apple_resource_gateway.dart' show appleHandlePattern;
import 'export_mime.dart';
import 'generated/apple_files.g.dart';

/// A completion means the native writer/Photos operation has actually drained.
class AppleExportGateway {
  AppleExportGateway({AppleFileHost? host}) : _host = host ?? AppleFileHost();
  final AppleFileHost _host;

  Future<List<ExportItemResult>> export(
    List<ExportInput> inputs, {
    CancellationToken? cancellation,
    bool photos = false,
  }) async {
    final frozen = List<ExportInput>.unmodifiable(inputs);
    if (frozen.isEmpty) return const [];
    if (frozen.map((input) => input.id).toSet().length != frozen.length ||
        frozen.any((input) => input.id.isEmpty)) {
      return List.unmodifiable(
        frozen.map((input) => _failed(input, '保存输入身份无效，未开始写入。')),
      );
    }
    final operationIds = List.generate(frozen.length, (_) => const Uuid().v4());
    final selectionId = const Uuid().v4();
    var selecting = false;
    Future<void>? cancellingSelection;
    String? handle;
    final results = <ExportItemResult>[];
    cancellation?.whenCancelled.then((_) {
      if (selecting) {
        cancellingSelection = _host.cancelSelection(selectionId);
        cancellingSelection!.catchError((Object _) {});
      }
    });
    try {
      cancellation?.throwIfCancelled();
      if (!photos) {
        selecting = true;
        final destination = await _host.pickDirectory(
          selectionId,
          operationIds,
        );
        selecting = false;
        handle = destination.handle;
        if (destination.cancelled) {
          if (handle != null) {
            throw const ExportFailure(ExportFailureKind.storage, '系统位置返回无效。');
          }
          throw const ResourceFailure(FailureKind.cancelled);
        }
        if (handle == null || !appleHandlePattern.hasMatch(handle)) {
          throw const ExportFailure(ExportFailureKind.storage, '无法确认系统保存位置。');
        }
        // Retirement must finish before a cancelled selector grants any IO.
        await cancellingSelection;
        cancellation?.throwIfCancelled();
      }
      for (var index = 0; index < frozen.length; index++) {
        final input = frozen[index];
        if (cancellation?.isCancelled ?? false) {
          results.add(_cancelled(input));
          continue;
        }
        if (input.expectedByteCount < 0 ||
            !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(input.expectedSha256)) {
          results.add(_failed(input, '保存内容校验信息无效，未开始写入。'));
          continue;
        }
        final operationId = operationIds[index];
        var active = true;
        Future<void>? cancelling;
        cancellation?.whenCancelled.then((_) {
          if (active) {
            cancelling = _host.cancelExport(operationId);
            cancelling!.catchError((Object _) {});
          }
        });
        try {
          final reply = await _host.exportFile(
            AppleExportRequest(
              operationId: operationId,
              sourcePath: input.source.absolute.path,
              displayName: input.displayName,
              mimeType: exportMimeType(input.displayName),
              sha256: input.expectedSha256,
              byteCount: input.expectedByteCount,
              kind: photos
                  ? AppleDestinationKind.photos
                  : AppleDestinationKind.directory,
              destinationHandle: handle,
            ),
          );
          if (reply.code == AppleIoCode.ok) {
            if (!_confirmedReply(reply, photos)) {
              results.add(_failed(input, '系统尚未确认实际保存结果。'));
              continue;
            }
            // A confirmed late save is preserved even after cancellation intent.
            results.add(
              ExportItemResult(
                id: input.id,
                status: ExportStatus.saved,
                fileName: reply.displayName,
                destinationUri: reply.uri,
                reason: reply.cleanupPending ? '已确认保存；私有暂存清理未确认，现场保留。' : null,
              ),
            );
          } else if (reply.code == AppleIoCode.cancelled) {
            results.add(_cancelled(input));
          } else {
            results.add(
              _failed(
                input,
                _reason(reply.code),
                permission: reply.code == AppleIoCode.permissionDenied,
              ),
            );
          }
        } on PlatformException catch (error) {
          results.add(
            _failed(
              input,
              '系统保存未确认，请检查授权与空间后重试。',
              permission: error.code == 'permissionDenied',
            ),
          );
        } catch (_) {
          results.add(_failed(input, '系统保存未确认，请检查授权与空间后重试。'));
        } finally {
          active = false;
          try {
            await cancelling;
          } catch (_) {
            // Actual export has returned; cancellation delivery is independent.
          }
        }
      }
    } on ResourceFailure catch (error) {
      if (error.kind != FailureKind.cancelled) rethrow;
      results.addAll(frozen.skip(results.length).map(_cancelled));
    } catch (_) {
      results.addAll(
        frozen
            .skip(results.length)
            .map((input) => _failed(input, '无法确认系统保存位置，请重新选择。')),
      );
    } finally {
      selecting = false;
      var cleanupFailed = false;
      try {
        await cancellingSelection;
      } catch (_) {
        cleanupFailed = true;
      }
      if (handle != null && appleHandlePattern.hasMatch(handle)) {
        try {
          await _host.closeDestination(handle);
        } catch (_) {
          cleanupFailed = true;
        }
      }
      if (cleanupFailed) {
        for (var i = 0; i < results.length; i++) {
          final result = results[i];
          results[i] = ExportItemResult(
            id: result.id,
            status: result.status,
            fileName: result.fileName,
            destinationUri: result.destinationUri,
            failureKind: result.failureKind,
            reason: '系统位置授权收尾未确认；已确认保存的文件保留。',
          );
        }
      }
    }
    return List.unmodifiable(results);
  }

  bool _confirmedReply(AppleExportReply reply, bool photos) {
    final name = reply.displayName;
    if (name == null ||
        name.isEmpty ||
        name.runes.length > 255 ||
        name.contains(RegExp(r'[\x00-\x1f\x7f/\\]'))) {
      return false;
    }
    final rawUri = reply.uri ?? '';
    final uri = Uri.tryParse(rawUri);
    if (uri == null ||
        uri.toString() != rawUri ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    if (photos) {
      return uri.scheme == 'ph' &&
          uri.host == 'asset' &&
          !uri.hasPort &&
          uri.pathSegments.length == 1 &&
          RegExp(r'^[A-Za-z0-9/_-]{1,256}$').hasMatch(uri.pathSegments.single);
    }
    return uri.scheme == 'file' &&
        (uri.host.isEmpty || uri.host == 'localhost') &&
        !uri.hasPort &&
        uri.path.startsWith('/') &&
        !uri.pathSegments.any((segment) => segment == '.' || segment == '..') &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.last == name;
  }

  ExportItemResult _cancelled(ExportInput input) => ExportItemResult(
    id: input.id,
    status: ExportStatus.cancelled,
    reason: '已取消系统保存。',
  );

  ExportItemResult _failed(
    ExportInput input,
    String reason, {
    bool permission = false,
  }) => ExportItemResult(
    id: input.id,
    status: ExportStatus.failed,
    failureKind: permission
        ? ExportFailureKind.permissionDenied
        : ExportFailureKind.storage,
    reason: reason,
  );

  String _reason(AppleIoCode code) => switch (code) {
    AppleIoCode.permissionDenied => '系统保存授权被拒绝，请重新选择或授权。',
    AppleIoCode.sourceMissing => '应用内副本不可用，请重新取得完整副本。',
    AppleIoCode.inputChanged => '输入或目标内容校验不一致，未确认保存。',
    AppleIoCode.unsupported => '所选系统位置或图片格式暂不支持保存。',
    AppleIoCode.cleanupPending ||
    AppleIoCode.unconfirmed => '写入或清理结果未确认，请核查目标文件；现场保留。',
    _ => '系统保存未完成，请检查空间与授权后重试。',
  };
}
