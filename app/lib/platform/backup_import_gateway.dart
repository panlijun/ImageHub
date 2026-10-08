import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../features/backup/application/backup_snapshot.dart';

class BackupImportGateway {
  const BackupImportGateway();
  // Publication/capacity are currently verified only on Windows. Other
  // platforms keep the shared restore service but cannot start native IO.
  bool get supportsPlatform => Platform.isWindows;
  Future<File?> pickBackup() async {
    try {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'ImageHost 备份', extensions: ['zip']),
        ],
      );
      return selected == null ? null : File(selected.path);
    } catch (_) {
      throw BackupSnapshotFailure('无法选择备份文件，请检查文件访问权限后重试。');
    }
  }

  Future<Directory> temporaryParent() async => Directory.systemTemp;
}
