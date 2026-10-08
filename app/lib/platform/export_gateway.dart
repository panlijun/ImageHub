import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../features/processing/domain/export_models.dart';
import '../features/processing/application/file_exporter.dart';
import '../core/platform_resource.dart';
import 'android_export_gateway.dart';

/// Only adapts the system directory picker; it does not report a saved file.
class ExportGateway {
  const ExportGateway();

  bool get supportsDirectoryExport => Platform.isWindows || Platform.isMacOS;
  bool get supportsFileExport => supportsDirectoryExport || Platform.isAndroid;
  bool get supportsPhotos => Platform.isAndroid;

  Future<List<ExportItemResult>> exportFiles(
    List<ExportInput> inputs, {
    CancellationToken? cancellation,
    bool photos = false,
  }) async {
    if (Platform.isAndroid) {
      return AndroidExportGateway().export(
        inputs,
        cancellation: cancellation,
        photos: photos,
      );
    }
    if (photos || !supportsDirectoryExport) {
      throw const ExportFailure(
        ExportFailureKind.unsupported,
        '此平台尚未接入所选保存方式。',
      );
    }
    final directory = await pickDirectory();
    cancellation?.throwIfCancelled();
    if (directory == null) {
      return inputs
          .map(
            (input) => ExportItemResult(
              id: input.id,
              status: ExportStatus.cancelled,
              reason: '已取消目录选择。',
            ),
          )
          .toList();
    }
    return const FileExporter().exportToDirectory(
      inputs,
      directory,
      cancellation: cancellation,
    );
  }

  /// Null means the user cancelled. Mobile requires its native export bridge.
  Future<Directory?> pickDirectory() async {
    if (!supportsDirectoryExport) {
      throw const ExportFailure(
        ExportFailureKind.unsupported,
        '此平台的原生文件导出尚未接入。',
      );
    }
    try {
      final path = await getDirectoryPath(confirmButtonText: '导出到此目录');
      return path == null ? null : Directory(path);
    } on PlatformException catch (error) {
      final code = error.code.toLowerCase();
      if ({
        'cancelled',
        'canceled',
        'user_cancelled',
        'user_canceled',
      }.contains(code)) {
        return null;
      }
      if ({
        'permission_denied',
        'access_denied',
        'authorization_denied',
      }.contains(code)) {
        throw const ExportFailure(
          ExportFailureKind.permissionDenied,
          '导出目录授权失败，请重新选择并授权。',
        );
      }
      throw const ExportFailure(ExportFailureKind.storage, '无法选择导出目录，请重新选择。');
    } catch (_) {
      throw const ExportFailure(ExportFailureKind.storage, '无法选择导出目录，请重新选择。');
    }
  }
}
