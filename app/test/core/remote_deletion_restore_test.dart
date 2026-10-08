import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/links/domain/remote_deletion.dart';
import 'package:path/path.dart' as p;

import 'remote_deletion_repository_test.dart' show RemoteDeletionFixture;

void main() {
  late RemoteDeletionFixture f;
  late String resultId;
  late ValidatedBackup backup;
  setUp(() async {
    f = RemoteDeletionFixture();
    await f.open();
    resultId = await f.result();
    final execution = await f.begin(
      await f.repository.prepareRemoteDeletion(resultId),
    );
    await f.repository.authorizeRemoteDeletion(execution);
    await f.repository.finishRemoteDeletion(
      execution,
      const RemoteDeletionOutcome(
        RemoteDeletionState.unknown,
        RemoteDeletionReason.unconfirmed,
        httpStatus: 200,
      ),
    );
    final snapshot = await f.repository.captureBackupSnapshot(
      mode: BackupMode.full,
    );
    final archive = File(p.join(f.sandbox.path, 'portable.zip'));
    try {
      final portable = utf8.decode(snapshot.manifestBytes);
      expect(portable, isNot(contains('remote_delete_v1')));
      expect(portable, isNot(contains(RemoteDeletionFixture.credential)));
      await BackupZipWriter().write(snapshot, archive);
    } finally {
      await snapshot.release();
    }
    backup = await const BackupZipReader().preflight(
      archive,
      await Directory(p.join(f.sandbox.path, 'preflight')).create(),
      availableBytes: (_) async => 1 << 40,
    );
  });
  tearDown(() async {
    await backup.dispose();
    await f.dispose();
  });

  // Deterministic fixture publication is not proof of native atomic no-replace.
  Future<bool> publish(File staged, File target) async {
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    await staged.rename(target.path);
    return true;
  }

  Future<void> replace({RestoreFaultHook? faultHook}) async {
    final hold = await f.repository.acquireRestoreHold();
    ReplacementRestorePreparation? preparation;
    try {
      preparation = await f.repository.prepareReplacementRestore(
        hold: hold,
        backup: backup,
        availableBytes: (_) async => 1 << 40,
      );
      await f.repository.commitReplacementRestore(
        preparation: preparation,
        availableBytes: (_) async => 1 << 40,
        publishExclusive: publish,
        faultHook: faultHook,
      );
    } finally {
      if (preparation != null) {
        try {
          await f.repository.discardReplacementPreparation(preparation);
        } catch (_) {
          /* Preserve any pending durable recovery evidence. */
        }
      }
      await hold.release();
    }
  }

  test('UT-050/073 merge preserves local deletion audit while portable package carries none', () async {
    final before = f.auditRows();
    expect(backup.manifest.results.single.id, resultId);
    final hold = await f.repository.acquireRestoreHold();
    try {
      final preparation = await f.repository.prepareMergeRestore(
        hold: hold,
        backup: backup,
      );
      expect(preparation.plan.canCommit, true);
      await f.repository.commitMergeRestore(
        preparation: preparation,
        availableBytes: (_) async => 1 << 40,
        publishExclusive: publish,
      );
    } finally {
      await hold.release();
    }
    expect(f.auditRows(), before);
    expect(
      (await f.repository.listRemoteDeletions(resultId: resultId)).single.state,
      RemoteDeletionState.unknown,
    );
    await f.reopen();
    expect(f.auditRows(), before);
  });

  test('UT-050/075 replacement clears old local audit even when portable result UUID is identical', () async {
    final beforeEpoch = f.repository.executionEpoch;
    expect(f.auditRows(), hasLength(1));
    expect(backup.manifest.results.single.id, resultId);
    await replace();
    expect(f.repository.executionEpoch, isNot(beforeEpoch));
    expect((await f.repository.listUploadResults()).single.id, resultId);
    expect(await f.repository.listRemoteDeletions(resultId: resultId), isEmpty);
    expect(f.auditRows(), isEmpty);
    await f.reopen();
    expect((await f.repository.listUploadResults()).single.id, resultId);
    expect(await f.repository.listRemoteDeletions(), isEmpty);
  });

  test('UT-050/075 replacement metadataWritten fault rolls back private deletion audit and authorization', () async {
    final before = f.auditRows(), ordinary = f.rows('remote_upload_results');
    final protected = Map.of(f.secrets.values);
    final original = await f.repository.originalFor(f.asset);
    final bytes = await original.readAsBytes();
    final epoch = f.repository.executionEpoch;
    var reached = false;
    await expectLater(
      replace(
        faultHook: (boundary) async {
          if (boundary == RestoreBoundary.metadataWritten) {
            reached = true;
            throw StateError(
              'synthetic replacement failure after relation writes',
            );
          }
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(reached, true);
    expect(f.auditRows(), before);
    expect(f.rows('remote_upload_results'), ordinary);
    expect(f.secrets.values, protected);
    expect(f.repository.executionEpoch, epoch);
    expect(await original.readAsBytes(), bytes);
    await f.reopen();
    expect(f.auditRows(), before);
    expect(
      (await f.repository.listRemoteDeletions()).single.state,
      RemoteDeletionState.unknown,
    );
  });
}
