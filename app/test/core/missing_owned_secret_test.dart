import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

void main() {
  for (final missingManagement in [false, true]) {
    test(
      'UT-074/089 missing owned ${missingManagement ? 'management' : 'credential'} value refuses backup and diagnostic export after reopen',
      () async {
        final sandbox = await Directory.systemTemp.createTemp(
          'imagehost_missing_secret_',
        );
        final root = Directory('${sandbox.path}/library');
        final secrets = QueueTestSecrets();
        var repository = await LibraryRepository.open(
          root,
          secretStore: secrets,
        );
        const key = 'synthetic-owned-credential-0123456789';
        const management =
            'https://ibb.co/remoteID/missingManagementToken0123456789';
        final picture = img.encodePng(img.Image(width: 4, height: 3));
        try {
          final imported = await repository.importResource(
            PlatformResource(
              displayName: '$key.png',
              openRead: () => Stream.value(picture),
            ),
          );
          final asset = imported.asset!;
          final target = await repository.saveTarget(
            service: ImageHostService.imgbb,
            alias: '合成账号',
            anonymous: false,
            credential: key,
          );
          if (missingManagement) {
            final batch = await repository.enqueueUploads(
              intentId: 'synthetic-owned-management',
              assetIds: [asset.id],
              targetIds: [target],
              allowOriginalMetadata: true,
            );
            final execution = (await repository.beginUploadAttempt(
              batch.items.single.id,
            ))!;
            try {
              expect(
                await repository.authorizeUploadRequest(execution.attemptId),
                true,
              );
              await repository.finishUploadAttempt(
                execution,
                ProviderUploadSuccess(
                  service: ImageHostService.imgbb,
                  remoteId: 'remoteID',
                  directUrl: Uri.parse('https://i.ibb.co/imageID/source.png'),
                  managementSecret: SensitiveManagementSecret(management),
                ),
                accumulatedRunning: const Duration(seconds: 1),
              );
            } finally {
              await execution.release();
            }
          }
          final lostValue = missingManagement ? management : key;
          final reference = secrets.values.entries
              .singleWhere((entry) => entry.value == lostValue)
              .key;
          await repository.close();
          secrets.values.remove(
            reference,
          ); // Simulates a missing backend item, not an exception.
          repository = await LibraryRepository.open(root, secretStore: secrets);
          for (final mode in BackupMode.values) {
            await expectLater(
              repository.captureBackupSnapshot(mode: mode),
              throwsA(isA<BackupSnapshotFailure>()),
            );
          }
          await expectLater(
            repository.loadDiagnostics(),
            throwsA(isA<DiagnosticFailure>()),
          );
          await expectLater(
            repository.prepareDiagnosticSelection(),
            throwsA(isA<DiagnosticFailure>()),
          );
          final database = sqlite3.open(
            '${root.path}/library.sqlite',
            mode: OpenMode.readOnly,
          );
          try {
            expect(
              database
                  .select('SELECT COUNT(*) AS n FROM file_leases')
                  .single['n'],
              0,
            );
            final column = missingManagement
                ? 'remote_upload_results'
                : 'provider_targets';
            expect(
              database
                  .select('SELECT secret_reference FROM $column')
                  .single['secret_reference'],
              reference,
            );
          } finally {
            database.close();
          }
          final page = await repository.listAssets();
          expect(page.items.single.id, asset.id);
          expect(
            await (await repository.originalFor(page.items.single))
                .readAsBytes(),
            picture,
          );

          // Restoring the referenced synthetic value permits a fresh safe view,
          // without discarding the original asset, reference or diagnostic rows.
          secrets.values[reference] = lostValue;
          final backup = await repository.captureBackupSnapshot(
            mode: BackupMode.metadata,
          );
          try {
            expect(utf8.decode(backup.manifestBytes), isNot(contains(key)));
            expect(
              utf8.decode(backup.manifestBytes),
              isNot(contains(management)),
            );
            expect(backup.manifest.assets.single.id, asset.id);
          } finally {
            await backup.release();
          }
          final plan = await repository.prepareDiagnosticSelection();
          final document = await repository.diagnosticExport(plan);
          expect(utf8.decode(document.bytes), isNot(contains(key)));
          expect(utf8.decode(document.bytes), isNot(contains(management)));
        } finally {
          await repository.close();
          await sandbox.delete(recursive: true);
        }
      },
    );
  }

  test('UT-089 confirmed diagnostic selection rechecks missing owned secret at execution', () async {
    final root = await Directory.systemTemp.createTemp(
      'imagehost_missing_secret_plan_',
    );
    final secrets = QueueTestSecrets();
    final repository = await LibraryRepository.open(root, secretStore: secrets);
    try {
      await repository.saveTarget(
        service: ImageHostService.catbox,
        alias: '合成确认',
        anonymous: false,
        credential: 'synthetic-confirmed-plan-key',
      );
      final plan = await repository.prepareDiagnosticSelection();
      final entry = secrets.values.entries.single;
      secrets.values.remove(entry.key);
      await expectLater(
        repository.diagnosticExport(plan),
        throwsA(isA<DiagnosticFailure>()),
      );
      secrets.values[entry.key] = entry.value;
      expect((await repository.diagnosticExport(plan)).count, plan.count);
    } finally {
      await repository.close();
      await root.delete(recursive: true);
    }
  });
}
