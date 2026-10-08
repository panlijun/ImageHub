import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/platform_resource.dart';
import '../data/backup_zip_writer.dart';
import '../data/backup_temporary_workspace.dart';
import '../domain/backup_manifest.dart';
import 'backup_snapshot.dart';

typedef CaptureBackup = Future<BackupSnapshotLease> Function(
  BackupMode mode,
  CancellationToken cancellation,
  void Function(int, int) progress,
);
typedef PublishBackup = Future<bool> Function(File source, File destination);

final class BackupExportReport {
  const BackupExportReport({
    required this.file,
    required this.mode,
    required this.assets,
    required this.versions,
    required this.byteCount,
    required this.cleanupPending,
    this.cleanupMessage,
  });
  final File file;
  final BackupMode mode;
  final int assets, versions, byteCount;
  final bool cleanupPending;
  final String? cleanupMessage;
}

/// System directory selection happens outside this shared application service.
/// Publication must be atomic and exclusive on the same volume. File.rename
/// alone cannot satisfy that contract because it can overwrite an existing file.
final class BackupCoordinator {
  BackupCoordinator({
    required this.capture,
    required this.availableBytes,
    required this.publishExclusive,
    BackupZipWriter? writer,
    this.recordCompletion,
  }) : _writer = writer ?? BackupZipWriter();
  final CaptureBackup capture;
  final Future<int> Function(Directory) availableBytes;
  final PublishBackup publishExclusive;
  final BackupZipWriter _writer;
  final Future<void> Function(bool completed)? recordCompletion;

  Future<BackupExportReport> export(
    Directory destination,
    BackupMode mode, {
    CancellationToken? cancellation,
    void Function(String phase, int done, int total)? onProgress,
  }) async {
    final token = cancellation ?? CancellationToken();
    BackupSnapshotLease? snapshot;
    Directory? ownedStage;
    BackupTemporaryWorkspace? workspace;
    File? published;
    try {
      _cancelled(token);
      await _checkDirectory(destination);
      snapshot = await capture(mode, token, (done, total) {
        onProgress?.call('校验永久副本', done, total);
      });
      final view = snapshot.manifest;
      final estimate =
          snapshot.manifestBytes.length +
          view.images.fold<int>(0, (sum, image) => sum + image.byteCount) +
          (view.images.length + 1) * 512 +
          1024 * 1024;
      onProgress?.call('预计所需空间', estimate, estimate);
      final free = await availableBytes(destination);
      if (free < estimate) {
        throw BackupSnapshotFailure('目标可用空间不足，未写入备份；请选择其他目录。');
      }
      _cancelled(token);
      await _checkDirectory(destination);
      ownedStage = await destination.createTemp('.imagehost-backup-');
      workspace = BackupTemporaryWorkspace(ownedStage);
      final staged = File(p.join(ownedStage.path, 'package.partial'));
      await _writer.write(
        snapshot,
        staged,
        cancellation: token,
        onProgress: (done, total) => onProgress?.call('写入备份', done, total),
      );
      // Only a normally returned writer supplies complete, closed-file evidence.
      // A failed writer's remaining path is not adopted as our cleanup input.
      workspace.registerFile(staged);
      final byteCount = await workspace.verifyAndRecordFile(staged);
      _cancelled(token);
      onProgress?.call('提交备份', 0, 1);
      // Random package identities avoid exposing names or paths in filenames;
      // the platform still guarantees no overwrite, including a racing writer.
      for (var attempt = 0; attempt < 8; attempt++) {
        _cancelled(token);
        await _checkDirectory(destination);
        await _checkDirectory(ownedStage);
        if (await FileSystemEntity.type(staged.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw BackupSnapshotFailure('备份暂存文件不可用，未提交备份。');
        }
        final suffix = attempt == 0 ? view.packageId : const Uuid().v4();
        final name = 'ImageHub-${mode.name}-$suffix.zip';
        final target = File(p.join(destination.path, name));
        if (await publishExclusive(staged, target)) {
          published = target;
          workspace.forgetPublishedFile(staged);
          break;
        }
      }
      if (published == null) {
        throw BackupSnapshotFailure('备份文件名持续冲突，未覆盖已有文件；请选择其他目录。');
      }
      await _recordCompletion(true);
      // Publication is the commit point. A cancellation arriving afterwards
      // must not remove a completed user export or call it an incomplete backup.
      final cleanup = await _releaseAndCleanup(snapshot, workspace);
      return BackupExportReport(
        file: published,
        mode: mode,
        assets: view.assets.length,
        versions: view.versions.length,
        byteCount: byteCount,
        cleanupPending: cleanup.pending,
        cleanupMessage: cleanup.message,
      );
    } catch (error) {
      await _recordCompletion(false);
      final cleanup = await _releaseAndCleanup(snapshot, workspace);
      if (cleanup.pending) {
        throw BackupSnapshotFailure('备份未提交；${cleanup.message}');
      }
      if (error is BackupFailure || error is BackupSnapshotFailure) rethrow;
      throw BackupSnapshotFailure('备份未提交，原资料库和已有导出文件已保留。');
    }
  }

  Future<void> _recordCompletion(bool completed) async {
    try {
      await recordCompletion?.call(completed);
    } catch (_) {
      // Logging failure does not alter a committed user export.
    }
  }

  Future<_BackupCleanup> _releaseAndCleanup(
    BackupSnapshotLease? snapshot,
    BackupTemporaryWorkspace? workspace,
  ) async {
    var protectionPending = false, temporaryPending = false;
    try {
      await snapshot?.release();
    } catch (_) {
      protectionPending = true;
    }
    if (workspace != null) {
      try {
        await workspace.remove();
      } catch (_) {
        temporaryPending = true;
      }
    }
    return _BackupCleanup(protectionPending, temporaryPending);
  }

  void _cancelled(CancellationToken token) {
    if (token.isCancelled) {
      throw BackupSnapshotFailure('备份已取消，原资料库保持有效。');
    }
  }

  Future<void> _checkDirectory(Directory directory) async {
    var path = p.normalize(p.absolute(directory.path));
    while (true) {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw BackupSnapshotFailure('备份目录不可用或包含链接，请重新选择独立目录。');
      }
      final parent = p.dirname(path);
      if (parent == path) break;
      path = parent;
    }
  }
}

final class _BackupCleanup {
  const _BackupCleanup(this.protectionPending, this.temporaryPending);
  final bool protectionPending, temporaryPending;
  bool get pending => protectionPending || temporaryPending;
  String? get message => pending
      ? [
          if (protectionPending) '文件使用保护记录清理未确认，请保留资料库并重开核查。',
          if (temporaryPending) '备份暂存存在未知、变化内容或无法安全清理，现场已保留，请核查后重试。',
        ].join(' ')
      : null;
}
