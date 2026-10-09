import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../features/backup/application/backup_snapshot.dart';
import '../core/platform_resource.dart';
import 'mobile_file_workspace.dart';

class BackupImportGateway {
  const BackupImportGateway({this.operatingSystem});
  final String? operatingSystem;
  String get _platform => operatingSystem ?? Platform.operatingSystem;
  // Native granted sources are handed off only as owned, closed private copies.
  bool get supportsPlatform =>
      {'windows', 'android', 'ios', 'macos'}.contains(_platform);

  Future<BackupSource?> acquireBackup({CancellationToken? cancellation}) async {
    if (_platform == 'android') return acquireAndroidBackup(cancellation);
    if (_platform == 'ios' || _platform == 'macos') {
      return acquireAppleBackup(cancellation);
    }
    if (!supportsPlatform) throw BackupSnapshotFailure('此平台尚未接入备份文件取得。');
    final file = await pickBackup();
    return file == null ? null : BackupSource(file);
  }

  Future<File?> pickBackup() async {
    try {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'ImageHub 备份', extensions: ['zip']),
        ],
      );
      return selected == null ? null : File(selected.path);
    } catch (_) {
      throw BackupSnapshotFailure('无法选择备份文件，请检查文件访问权限后重试。');
    }
  }

  Future<Directory> temporaryParent() async =>
      _platform == 'windows' ? Directory.systemTemp : mobileTemporaryParent();
}
