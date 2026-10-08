import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../features/backup/application/backup_snapshot.dart';

final class StorageCapacity {
  const StorageCapacity({
    this.channel = const MethodChannel('io.imagehost/storage_capacity'),
    @visibleForTesting String? operatingSystem,
    // The public test argument intentionally initializes a private field.
    // ignore: prefer_initializing_formals
  }) : _operatingSystem = operatingSystem;

  final MethodChannel channel;
  final String? _operatingSystem;

  bool get supportsPlatform =>
      switch (_operatingSystem ?? Platform.operatingSystem) {
        'windows' || 'android' || 'ios' || 'macos' => true,
        _ => false,
      };

  Future<int> availableBytes(Directory directory) async {
    if (!supportsPlatform) {
      throw BackupSnapshotFailure('无法确认目标可用空间，请选择其他目标。');
    }

    try {
      final bytes = await channel.invokeMethod<int>(
        'availableBytes',
        p.normalize(directory.absolute.path),
      );
      if (bytes == null || bytes < 0) {
        throw BackupSnapshotFailure('无法确认目标可用空间，请选择其他目标。');
      }
      return bytes;
    } catch (_) {
      throw BackupSnapshotFailure('无法确认目标可用空间，请选择其他目标。');
    }
  }

  Future<bool> publishExclusive(File source, File destination) async {
    if (!supportsPlatform) {
      throw BackupSnapshotFailure('无法安全发布备份文件，请选择其他目标。');
    }

    try {
      final published = await channel.invokeMethod<bool>(
        'publishExclusive',
        <String, String>{
          'source': p.normalize(source.absolute.path),
          'destination': p.normalize(destination.absolute.path),
        },
      );
      if (published == null) {
        throw BackupSnapshotFailure('无法安全发布备份文件，请选择其他目标。');
      }
      return published;
    } catch (_) {
      throw BackupSnapshotFailure('无法安全发布备份文件，请选择其他目标。');
    }
  }
}
