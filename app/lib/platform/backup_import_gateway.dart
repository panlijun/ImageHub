import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../features/backup/application/backup_snapshot.dart';
import '../core/platform_resource.dart';
import 'mobile_file_workspace.dart';

class BackupImportGateway {
  const BackupImportGateway();
  // Android uses an owned, closed stream copy rather than a URI as a file path.
  bool get supportsPlatform => Platform.isWindows || Platform.isAndroid;

  Future<BackupSource?> acquireBackup({CancellationToken? cancellation}) async {
    if (Platform.isAndroid) return acquireAndroidBackup(cancellation);
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
      Platform.isAndroid ? mobileTemporaryParent() : Directory.systemTemp;
}
