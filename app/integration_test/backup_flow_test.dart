import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/app.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_coordinator.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/domain/backup_settings.dart';
import 'package:imagehost/features/backup/presentation/backup_screen.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/platform/export_gateway.dart';
import 'package:imagehost/platform/backup_import_gateway.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:imagehost/platform/system_secret_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT-005/BAK-005 partial Windows real capacity exclusive ZIP settings export merge replacement rollback protected secret exclusion and reopen',
    (tester) async {
      final sandbox = await Directory.systemTemp.createTemp(
        'imagehost-backup-engine-',
      );
      final root = Directory('${sandbox.path}/library');
      final export = await Directory('${sandbox.path}/exports').create();
      final stage = await Directory('${sandbox.path}/preflight').create();
      final secrets = SystemSecretStore();
      const capacity = StorageCapacity();
      var repository = await LibraryRepository.open(root, secretStore: secrets);
      String? target;
      LibrarySession? session;
      ProviderContainer? container;
      try {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('备份原生验证'))),
        );
        final free = await capacity.availableBytes(export);
        expect(free, greaterThan(1024 * 1024));
        // Actual Windows MoveFileExW must refuse an existing destination and
        // retain both files, then move to a fresh name without a copy fallback.
        final existing = await File('${export.path}/existing.zip')
            .writeAsString('existing', flush: true);
        final unpublished = await File('${export.path}/publication.partial')
            .writeAsString('new', flush: true);
        expect(await capacity.publishExclusive(unpublished, existing), false);
        expect(await existing.readAsString(), 'existing');
        expect(await unpublished.readAsString(), 'new');
        final moved = File('${export.path}/fresh.zip');
        expect(await capacity.publishExclusive(unpublished, moved), true);
        expect(await moved.readAsString(), 'new');
        expect(await unpublished.exists(), false);
        await existing.delete();
        await moved.delete();

        const key = 'synthetic-native-backup-key-0123456789';
        final bytes = img.encodePng(img.Image(width: 9, height: 7));
        final asset = (await repository.importResource(
          PlatformResource(
            displayName: '$key.png',
            openRead: () => Stream.value(bytes),
          ),
        )).asset!;
        target = await repository.saveTarget(
          service: ImageHostService.imgbb,
          alias: '原生备份验证',
          anonymous: false,
          credential: key,
        );
        await repository.close();
        repository = await LibraryRepository.open(root, secretStore: secrets);
        final portableSettings = DeviceSettings(
          uploadConcurrency: 5,
          processingConcurrency: 2,
          quality: 73,
          longestSide: 2300,
          processingMode: ProcessingMode.sizeFirst,
          cacheLimitMiB: 384,
          defaultOutputRetention: OutputRetention.week,
          networkUploadPolicy: NetworkUploadPolicy.wifiAndEthernet,
        );
        final changedAfterCapture = DeviceSettings.fromJson({
          ...portableSettings.toJson(),
          'quality': 79,
        });
        final localSettings = DeviceSettings(
          uploadConcurrency: 2,
          processingConcurrency: 1,
          quality: 91,
          longestSide: 900,
          cacheLimitMiB: 128,
          defaultOutputRetention: OutputRetention.hour,
          networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
        );
        final coordinator = BackupCoordinator(
          capture: (mode, token, progress) async {
            final captured = await repository.captureBackupSnapshot(
              mode: mode,
              cancellation: token,
              onVerification: progress,
            );
            try {
              expect(captured.manifest.settings!.values, portableSettings);
              // The SQL snapshot is immutable: a later genuine settings save
              // must not alter the settings serialized into this ZIP.
              await _saveSettings(repository, changedAfterCapture);
              expect(captured.manifest.settings!.values, portableSettings);
              return captured;
            } catch (_) {
              await captured.release();
              rethrow;
            }
          },
          availableBytes: capacity.availableBytes,
          publishExclusive: capacity.publishExclusive,
        );
        for (final mode in [BackupMode.full, BackupMode.metadata]) {
          await _saveSettings(repository, portableSettings);
          final report = await coordinator.export(export, mode);
          expect(repository.currentDeviceSettings, changedAfterCapture);
          expect(await report.file.length(), report.byteCount);
          expect(report.cleanupPending, false);
          final valid = await const BackupZipReader().preflight(
            report.file,
            stage,
            availableBytes: capacity.availableBytes,
          );
          try {
            expect(valid.manifest.settings!.values, portableSettings);
            expect(
              valid.manifest.settings!.availability.keys,
              unorderedEquals(BackupSetting.values),
            );
            expect(valid.manifest.assets.single.id, asset.id);
            expect(valid.manifest.assets.single.displayName, '[已隐藏].png');
            expect(valid.manifest.accounts.single.id, target);
            expect(valid.imageFiles.length, mode == BackupMode.full ? 1 : 0);
            expect(await report.file.readAsBytes(), isNotEmpty);
            final manifestFile = valid.manifest;
            expect(manifestFile.assets.single.versionId, asset.version.id);
            // Stored ZIP is uncompressed; even scanning its text sees no key.
            expect(
              utf8.decode(
                await report.file.readAsBytes(),
                allowMalformed: true,
              ),
              isNot(contains(key)),
            );
            // Actual Windows no-replace publication now also targets the live
            // managed originals volume. A preflight result alone is not restore.
            final restoredRoot = Directory(
              '${sandbox.path}/restored-${mode.name}',
            );
            var restored = await LibraryRepository.open(
              restoredRoot,
              secretStore: secrets,
            );
            try {
              await _saveSettings(restored, localSettings);
              final hold = await restored.acquireRestoreHold();
              try {
                final prepared = await restored.prepareMergeRestore(
                  hold: hold,
                  backup: valid,
                );
                expect(prepared.plan.canCommit, true);
                expect(prepared.settings.current, localSettings);
                expect(prepared.settings.values, portableSettings);
                expect(prepared.settings.restored, hasLength(8));
                expect(prepared.settings.skipped, isEmpty);
                final restoredReport = await restored.commitMergeRestore(
                  preparation: prepared,
                  availableBytes: capacity.availableBytes,
                  publishExclusive: capacity.publishExclusive,
                );
                expect(restoredReport.settings!.values, portableSettings);
                expect(restored.currentDeviceSettings, portableSettings);
                expect(restored.processingScheduler.configuredConcurrency, 2);
                expect(restoredReport.addedAssets, 1);
                expect(
                  restoredReport.savedCopies,
                  mode == BackupMode.full ? 1 : 0,
                );
                expect(restoredReport.cleanupPending, false);
              } finally {
                await hold.release();
              }
              await restored.close();
              restored = await LibraryRepository.open(
                restoredRoot,
                secretStore: secrets,
              );
              expect((await restored.loadSettings()).values, portableSettings);
              expect(restored.currentDeviceSettings, portableSettings);
              expect(restored.processingScheduler.configuredConcurrency, 2);
              final durable = (await restored.getAsset(asset.id))!;
              expect(durable.version.id, asset.version.id);
              expect(durable.displayName, '[已隐藏].png');
              if (mode == BackupMode.full) {
                expect(
                  await (await restored.originalFor(durable)).readAsBytes(),
                  bytes,
                );
              } else {
                expect(
                  await File(
                    '${restoredRoot.path}/${durable.deviceCopy.relativePath}',
                  ).exists(),
                  false,
                );
                expect(await restored.thumbnailFor(durable), isNull);
              }
              final restoredAccount = (await restored.listTargets()).single;
              expect(restoredAccount.id, target);
              expect(restoredAccount.enabled, false);
              expect(restoredAccount.health, AccountHealth.unconfigured);
              expect(await restored.listUploadBatches(), isEmpty);
              // Replace a populated live library with real Windows publication,
              // actual rollback proof and system-protected credential cleanup.
              final oldBytes = img.encodePng(img.Image(width: 13, height: 8));
              final sentinel = (await restored.importResource(
                PlatformResource(
                  displayName: '替换前本机独立图.png',
                  openRead: () => Stream.value(oldBytes),
                ),
              )).asset!;
              final oldTarget = await restored.saveTarget(
                service: ImageHostService.imgbb,
                alias: '替换前原生合成账号',
                anonymous: false,
                credential: 'synthetic-native-replace-key-0123456789',
              );
              final oldDb = sqlite.sqlite3.open(
                '${restoredRoot.path}/library.sqlite',
                mode: sqlite.OpenMode.readOnly,
              );
              late String oldReference;
              try {
                oldReference =
                    oldDb.select(
                          'SELECT secret_reference FROM provider_targets WHERE id=?',
                          [oldTarget],
                        ).single['secret_reference']
                        as String;
              } finally {
                oldDb.close();
              }
              final epoch = restored.executionEpoch;
              await _saveSettings(restored, localSettings);
              final replaceHold = await restored.acquireRestoreHold();
              try {
                final failed = await restored.prepareReplacementRestore(
                  hold: replaceHold,
                  backup: valid,
                  availableBytes: capacity.availableBytes,
                );
                expect(failed.settings.current, localSettings);
                expect(failed.settings.values, portableSettings);
                await expectLater(
                  restored.commitReplacementRestore(
                    preparation: failed,
                    availableBytes: capacity.availableBytes,
                    publishExclusive: capacity.publishExclusive,
                    faultHook: (boundary) async {
                      if (boundary == RestoreBoundary.metadataWritten) {
                        throw StateError('native rollback injection');
                      }
                    },
                  ),
                  throwsA(isA<BackupSnapshotFailure>()),
                );
                await restored.discardReplacementPreparation(failed);
              } finally {
                await replaceHold.release();
              }
              expect(restored.executionEpoch, epoch);
              // Fault injection after metadata write must roll back the real
              // settings row and leave runtime policy at the original values.
              expect(restored.currentDeviceSettings, localSettings);
              expect((await restored.loadSettings()).values, localSettings);
              expect(restored.processingScheduler.configuredConcurrency, 1);
              expect(
                await (await restored.originalFor(
                  (await restored.getAsset(sentinel.id))!,
                )).readAsBytes(),
                oldBytes,
              );
              expect(
                await secrets.read(oldReference),
                'synthetic-native-replace-key-0123456789',
              );
              final committedHold = await restored.acquireRestoreHold();
              try {
                final prepared = await restored.prepareReplacementRestore(
                  hold: committedHold,
                  backup: valid,
                  availableBytes: capacity.availableBytes,
                );
                expect(prepared.settings.current, localSettings);
                expect(prepared.settings.values, portableSettings);
                final replaced = await restored.commitReplacementRestore(
                  preparation: prepared,
                  availableBytes: capacity.availableBytes,
                  publishExclusive: capacity.publishExclusive,
                );
                expect(replaced.cleanupPending, false);
                expect(replaced.addedAssets, 1);
                expect(replaced.settings!.restored, hasLength(8));
                expect(replaced.settings!.skipped, isEmpty);
                expect(restored.currentDeviceSettings, portableSettings);
                expect(restored.processingScheduler.configuredConcurrency, 2);
              } finally {
                await committedHold.release();
              }
              expect(restored.executionEpoch, isNot(epoch));
              expect(await secrets.read(oldReference), isNull);
              expect(await restored.getAsset(sentinel.id), isNull);
              await restored.close();
              restored = await LibraryRepository.open(
                restoredRoot,
                secretStore: secrets,
              );
              expect((await restored.loadSettings()).values, portableSettings);
              expect(restored.currentDeviceSettings, portableSettings);
              expect(restored.processingScheduler.configuredConcurrency, 2);
              expect((await restored.listAssets()).total, 1);
              final replaced = (await restored.getAsset(asset.id))!;
              expect(replaced.version.id, asset.version.id);
              if (mode == BackupMode.full) {
                expect(
                  await (await restored.originalFor(replaced)).readAsBytes(),
                  bytes,
                );
              } else {
                expect(
                  await File(
                    '${restoredRoot.path}/${replaced.deviceCopy.relativePath}',
                  ).exists(),
                  false,
                );
              }
            } finally {
              for (final account in await restored.listTargets()) {
                await restored.removeTarget(account.id);
              }
              await restored.close();
            }
          } finally {
            await valid.dispose();
          }
        }
        expect(await export.list().toList(), hasLength(2));
        expect(await stage.list().toList(), isEmpty);
        await _saveSettings(repository, portableSettings);
        final boundary = GlobalKey();
        session = LibrarySession(repository, const []);
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((ref) async => session!),
            backupExportGatewayProvider.overrideWithValue(
              _BackupPicker(export),
            ),
            backupImportGatewayProvider.overrideWithValue(
              _RestorePicker(export, stage),
            ),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: boundary, child: const ImageHostApp()),
          ),
        );
        await _until(tester, () => container!.read(galleryProvider).hasValue);
        await tester.tap(find.text('备份与恢复'));
        await _until(
          tester,
          () => find.textContaining('资料库已载入').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('导出完整备份'));
        await _until(tester, () => find.text('备份已提交').evaluate().isNotEmpty);
        expect(await export.list().toList(), hasLength(3));
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '导出完整备份'))
              .onPressed,
          isNotNull,
        );
        await tester.ensureVisible(find.text('选择备份并合并恢复'));
        await tester.tap(find.text('选择备份并合并恢复'));
        await _until(
          tester,
          () => find.byType(AlertDialog).evaluate().isNotEmpty,
        );
        expect(repository.restoring, true);
        expect(find.text('将覆盖 8 项可用设置；跳过 0 项。'), findsOneWidget);
        expect(find.text('有损输出质量：73'), findsOneWidget);
        expect(session.uploads.networkAllowed, false);
        // Capture the production confirmation with actual frozen values visible.
        await tester.ensureVisible(find.text('有损输出质量：73'));
        await tester.pump(const Duration(milliseconds: 350));
        final settingsCapture =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final settingsPicture = await settingsCapture.toImage(pixelRatio: 1);
        final settingsEncoded = await settingsPicture.toByteData(
          format: ui.ImageByteFormat.png,
        );
        settingsPicture.dispose();
        final settingsArtifacts = await Directory('../docs/validation')
            .create(recursive: true);
        await File('${settingsArtifacts.path}/windows-backup-settings.png')
            .writeAsBytes(settingsEncoded!.buffer.asUint8List(), flush: true);
        await tester.tap(find.widgetWithText(FilledButton, '确认合并恢复'));
        await _until(tester, () => find.text('合并恢复已提交').evaluate().isNotEmpty);
        expect(repository.restoring, false);
        expect(find.text('已恢复 8 项可用设置；跳过 0 项。'), findsOneWidget);
        expect(repository.currentDeviceSettings, portableSettings);
        expect(session.uploads.networkAllowed, false);
        expect(session.uploads.concurrency, 5);
        expect(
          session.uploads.networkPolicy,
          NetworkUploadPolicy.wifiAndEthernet,
        );
        expect((await repository.listAssets()).total, 1);
        // The live source name is preserved; a masked portable view cannot
        // rename current local data during an idempotent merge.
        expect((await repository.getAsset(asset.id))!.displayName, '$key.png');
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('合并恢复已提交'));
        // Let the disabled-to-enabled button animation finish before recording
        // its resting colors; a zero-duration frame captures an intermediate.
        await tester.pump(const Duration(milliseconds: 350));
        final capture =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final picture = await capture.toImage(pixelRatio: 1);
        final encoded = await picture.toByteData(
          format: ui.ImageByteFormat.png,
        );
        picture.dispose();
        final artifacts = await Directory('build/validation')
            .create(recursive: true);
        await File('${artifacts.path}/windows-backup-merge-restore.png')
            .writeAsBytes(encoded!.buffer.asUint8List(), flush: true);
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        container = null;
        await session.close();
        session = null;
        repository = await LibraryRepository.open(root, secretStore: secrets);
        expect((await repository.loadSettings()).values, portableSettings);
        expect((await repository.listAssets()).total, 1);
        expect((await repository.getAsset(asset.id))!.version, asset.version);
        // The private current snapshot uses actual Windows space and keeps
        // the current protected credential association. It is not exported.
        final rollbackHold = await repository.acquireRestoreHold();
        final currentSnapshot = await repository.captureReplacementSnapshot(
          hold: rollbackHold,
          availableBytes: capacity.availableBytes,
        );
        expect(currentSnapshot.assetCount, 1);
        expect(currentSnapshot.fileCount, 1);
        await repository.verifyReplacementSnapshot(currentSnapshot);
        final privateDirectory = Directory(
          '${root.path}/staging/replacement-${currentSnapshot.id}',
        );
        expect(await privateDirectory.exists(), true);
        await repository.close();
        await rollbackHold.release();
        repository = await LibraryRepository.open(root, secretStore: secrets);
        expect(await privateDirectory.exists(), false);
        final retained = (await repository.getAsset(asset.id))!;
        expect(
          await (await repository.originalFor(retained)).readAsBytes(),
          bytes,
        );
        expect((await repository.resolveTarget(target)).credential, key);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        await session?.existingUploads?.close();
        if (target != null) await repository.removeTarget(target);
        await repository.close();
        await sandbox.delete(recursive: true);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}

Future<void> _saveSettings(
  LibraryRepository repository,
  DeviceSettings values,
) async {
  final current = await repository.loadSettings();
  await repository.saveSettings(
    current,
    values,
    defaultTargetIds: current.defaultTargetIds,
  );
}

class _BackupPicker extends ExportGateway {
  const _BackupPicker(this.directory);
  final Directory directory;
  @override
  Future<Directory?> pickDirectory() async => directory;
}

class _RestorePicker extends BackupImportGateway {
  const _RestorePicker(this.exports, this.temporary);
  final Directory exports, temporary;
  @override
  Future<File?> pickBackup() async => (await exports.list().toList())
      .whereType<File>()
      .firstWhere((f) => f.path.contains('ImageHost-full-'));
  @override
  Future<Directory> temporaryParent() async => temporary;
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (predicate()) return;
  }
  fail('Windows 备份页面未达到预期真实状态');
}
