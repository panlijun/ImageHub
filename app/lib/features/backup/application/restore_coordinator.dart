import 'dart:io';

import '../../../core/platform_resource.dart';
import '../../gallery/data/library_repository.dart';
import '../../diagnostics/domain/diagnostic_models.dart';
import '../../upload/application/upload_coordinator.dart';
import '../data/backup_zip_reader.dart';
import '../domain/backup_manifest.dart';
import '../domain/backup_restore_plan.dart';
import 'backup_snapshot.dart';

final class RestoreOutcome {
  const RestoreOutcome(
    this.report, {
    required this.cleanupPending,
    this.replaced = false,
    this.cancelledOldItems = 0,
  });
  final MergeRestoreReport report;
  final bool cleanupPending;
  final bool replaced;
  final int cancelledOldItems;
}

/// Shared orchestration: preflight never touches the live library; both
/// maintenance holds remain owned until the real commit/cleanup has ended.
final class RestoreCoordinator {
  RestoreCoordinator({
    required this.repository,
    required this.pauseUploads,
    required this.availableBytes,
    required this.publishExclusive,
    this.afterReplacement,
    BackupZipReader? reader,
  }) : _reader = reader ?? const BackupZipReader();
  final LibraryRepository repository;
  final Future<UploadRestoreHold> Function() pauseUploads;
  final Future<int> Function(Directory) availableBytes;
  final Future<bool> Function(File, File) publishExclusive;
  final Future<void> Function()? afterReplacement;
  final BackupZipReader _reader;

  Future<RestoreOutcome?> merge(
    File source,
    Directory temporaryParent, {
    required Future<bool> Function(BackupManifest, BackupRestorePlan) confirm,
    CancellationToken? cancellation,
    void Function(String phase, int done, int total)? onProgress,
  }) async {
    final token = cancellation ?? CancellationToken();
    ValidatedBackup? backup;
    UploadRestoreHold? uploads;
    LibraryRestoreHold? library;
    MergeRestoreReport? report;
    Object? failure;
    var cleanupPending = false;
    try {
      onProgress?.call('正在预检备份', 0, 1);
      backup = await _reader.preflight(
        source,
        temporaryParent,
        availableBytes: availableBytes,
        cancellation: token,
        onProgress: (done, total) => onProgress?.call('正在校验备份图片', done, total),
      );
      _cancelled(token);
      onProgress?.call('正在暂停上传并等待文件操作结束', 0, 1);
      uploads = await pauseUploads();
      _cancelled(token);
      library = await repository.acquireRestoreHold(cancellation: token);
      final prepared = await repository.prepareMergeRestore(
        hold: library,
        backup: backup,
      );
      onProgress?.call('等待确认合并恢复', 0, 1);
      final accepted = await confirm(backup.manifest, prepared.plan);
      _cancelled(token);
      if (accepted) {
        if (!prepared.plan.canCommit) {
          throw BackupSnapshotFailure('备份存在阻断冲突，当前资料库保持有效。');
        }
        report = await repository.commitMergeRestore(
          preparation: prepared,
          availableBytes: availableBytes,
          publishExclusive: publishExclusive,
          cancellation: token,
          onProgress: onProgress,
        );
      }
    } catch (error) {
      failure = error;
    } finally {
      // commitMergeRestore has returned only after its actual IO ended. No
      // cancellation callback releases a hold or deletes a worker's input.
      try {
        await backup?.dispose();
      } catch (_) {
        cleanupPending = true;
      }
      try {
        await library?.release();
      } catch (_) {
        cleanupPending = true;
      }
      try {
        uploads?.release();
      } catch (_) {
        cleanupPending = true;
      }
    }
    await _recordRestore(
      report != null,
      failure != null || cleanupPending,
      replacement: false,
    );
    if (report != null) {
      return RestoreOutcome(
        report,
        cleanupPending: cleanupPending || report.cleanupPending,
      );
    }
    if (cleanupPending) {
      throw BackupSnapshotFailure('恢复未提交，当前资料库保留；部分暂存或保护未清理，请重开核查。');
    }
    if (failure is BackupFailure || failure is BackupSnapshotFailure) {
      throw failure!;
    }
    if (failure != null) {
      throw BackupSnapshotFailure('恢复未提交，当前资料库保留；请检查备份、空间或文件保护后重试。');
    }
    return null;
  }

  Future<RestoreOutcome?> replace(
    File source,
    Directory temporaryParent, {
    required Future<bool> Function(ReplacementRestorePreparation) confirm,
    CancellationToken? cancellation,
    void Function(String phase, int done, int total)? onProgress,
    RestoreFaultHook? faultHook,
  }) async {
    final token = cancellation ?? CancellationToken();
    ValidatedBackup? backup;
    UploadRestoreHold? uploads;
    LibraryRestoreHold? library;
    ReplacementRestorePreparation? prepared;
    MergeRestoreReport? report;
    Object? failure;
    var cleanupPending = false;
    try {
      onProgress?.call('正在预检备份', 0, 1);
      backup = await _reader.preflight(
        source,
        temporaryParent,
        availableBytes: availableBytes,
        cancellation: token,
        onProgress: (done, total) => onProgress?.call('正在校验备份图片', done, total),
      );
      _cancelled(token);
      onProgress?.call('正在暂停上传并等待文件操作结束', 0, 1);
      uploads = await pauseUploads();
      _cancelled(token);
      library = await repository.acquireRestoreHold(cancellation: token);
      prepared = await repository.prepareReplacementRestore(
        hold: library,
        backup: backup,
        availableBytes: availableBytes,
        cancellation: token,
        onProgress: onProgress,
      );
      _cancelled(token);
      onProgress?.call('等待确认替换恢复', 0, 1);
      final accepted = await confirm(prepared);
      _cancelled(token);
      if (accepted) {
        report = await repository.commitReplacementRestore(
          preparation: prepared,
          availableBytes: availableBytes,
          publishExclusive: publishExclusive,
          cancellation: token,
          onProgress: onProgress,
          faultHook: faultHook,
        );
        // A committed replacement remains successful even if session cleanup
        // fails. No callback or late cancellation can undo its durable commit.
        try {
          await afterReplacement?.call();
        } catch (_) {
          cleanupPending = true;
        }
      }
    } catch (error) {
      failure = error;
    } finally {
      // Both repository calls wait for actual file work before returning. Keep
      // their maintenance ownership until snapshot and preflight cleanup ends.
      if (prepared != null) {
        try {
          await repository.discardReplacementPreparation(prepared);
        } catch (_) {
          cleanupPending = true;
        }
      }
      try {
        await backup?.dispose();
      } catch (_) {
        cleanupPending = true;
      }
      try {
        await library?.release();
      } catch (_) {
        cleanupPending = true;
      }
      try {
        uploads?.release();
      } catch (_) {
        cleanupPending = true;
      }
    }
    await _recordRestore(
      report != null,
      failure != null || cleanupPending,
      replacement: true,
    );
    if (report != null) {
      return RestoreOutcome(
        report,
        cleanupPending: cleanupPending || report.cleanupPending,
        replaced: true,
        cancelledOldItems: prepared!.cancelledOldItems,
      );
    }
    if (cleanupPending) {
      throw BackupSnapshotFailure('替换恢复未确认提交；部分暂存或保护待清理，请保留资料库并重开核查。');
    }
    if (failure is BackupFailure || failure is BackupSnapshotFailure) {
      throw failure!;
    }
    if (failure != null) {
      throw BackupSnapshotFailure('替换恢复未提交，当前资料库保留；请检查备份、空间或文件保护后重试。');
    }
    return null;
  }

  Future<void> _recordRestore(
    bool committed,
    bool needsCheck, {
    required bool replacement,
  }) async {
    // After maintenance has released: never mutate a prepared rollback baseline.
    try {
      await repository.recordOperation(
        kind: DiagnosticKind.restore,
        code: committed
            ? (replacement ? 'restore.replace' : 'restore.merge')
            : 'restore.uncommitted',
        summary: committed ? '恢复已确认提交，已保存资料保持有效。' : '恢复未提交，当前资料库保留。',
        recoveryAction: '请核查图库和恢复反馈；未完成清理时保留现场并重开检查，任务需手动恢复。',
        // A committed restore is never reclassified as a failed restore by logging.
        failed: !committed && needsCheck,
      );
    } catch (_) {
      /* A failed logger cannot change the durable restore outcome. */
    }
  }

  void _cancelled(CancellationToken token) {
    if (token.isCancelled) {
      throw BackupSnapshotFailure('恢复已取消，当前资料库保持有效；已暂停的任务需要手动恢复。');
    }
  }
}
