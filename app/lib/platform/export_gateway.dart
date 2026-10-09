import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../features/processing/domain/export_models.dart';
import '../features/processing/application/file_exporter.dart';
import '../core/platform_resource.dart';
import 'android_export_gateway.dart';
import 'apple_export_gateway.dart';

/// Adapts system destinations; saved results follow actual transfer completion.
class ExportGateway {
  const ExportGateway({this.operatingSystem});
  final String? operatingSystem;
  String get _platform => operatingSystem ?? Platform.operatingSystem;

  bool get supportsDirectoryExport =>
      _platform == 'windows' || _platform == 'macos';
  bool get supportsFileExport => supportsDirectoryExport || supportsPhotos;
  bool get supportsPhotos => _platform == 'android' || _platform == 'ios';

  /// The URI is a receipt shape; the native gateway must already confirm IO.
  bool confirmsSystemFileSave(ExportItemResult result) {
    final name = result.fileName;
    if (result.status != ExportStatus.saved || name == null || name.isEmpty) {
      return false;
    }
    final raw = result.destinationUri ?? '';
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    if (_platform == 'android') {
      return uri.scheme == 'content' && uri.authority.isNotEmpty;
    }
    return _platform == 'ios' &&
        uri.toString() == raw &&
        uri.scheme == 'file' &&
        (uri.host.isEmpty || uri.host == 'localhost') &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.path.startsWith('/') &&
        uri.pathSegments.isNotEmpty &&
        !uri.pathSegments.any((segment) => segment == '.' || segment == '..') &&
        uri.pathSegments.last == name;
  }

  Future<List<ExportItemResult>> exportFiles(
    List<ExportInput> inputs, {
    CancellationToken? cancellation,
    bool photos = false,
  }) async {
    if (_platform == 'android') {
      return AndroidExportGateway().export(
        inputs,
        cancellation: cancellation,
        photos: photos,
      );
    }
    if (_platform == 'ios') {
      return AppleExportGateway().export(
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
