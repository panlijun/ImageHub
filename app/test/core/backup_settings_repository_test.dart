import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/domain/backup_settings.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/domain/upload_processing_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

// UT-073/083 and IT-005 partial: real managed files, SQLite, ZIP, preflight,
// associated restore transactions and normal reopen. Publication below is a
// deterministic transport substitute, not native atomic publication evidence.
void main() {
  const prefix = 'imagehost-backup-settings-repository-';
  late Directory sandbox, sourceRoot, destinationRoot;
  late LibraryRepository source, destination;
  late QueueTestSecrets sourceSecrets, destinationSecrets;
  late ImageAsset incoming, sentinel;
  final backups = <ValidatedBackup>[];
  var packageNumber = 0;
  final incomingSettings = DeviceSettings(
    uploadConcurrency: 7,
    processingConcurrency: 3,
    quality: 43,
    longestSide: 937,
    processingMode: ProcessingMode.sizeFirst,
    cacheLimitMiB: 127,
    defaultOutputRetention: OutputRetention.week,
    networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
  );
  final localSettings = DeviceSettings(
    uploadConcurrency: 2,
    processingConcurrency: 2,
    quality: 64,
    longestSide: 721,
    processingMode: ProcessingMode.fidelity,
    cacheLimitMiB: 383,
    defaultOutputRetention: OutputRetention.hour,
  );

  Future<ImageAsset> image(LibraryRepository repository, int marker) async {
    final pixels = img.Image(width: 9 + marker, height: 7);
    img.fill(pixels, color: img.ColorRgb8(marker, 50, 110));
    final result = await repository.importResource(
      PlatformResource(
        displayName: '设置恢复-$marker.png',
        openRead: () => Stream.value(img.encodePng(pixels)),
      ),
    );
    expect(result.status, ImportStatus.saved);
    return result.asset!;
  }

  Future<void> saveValues(
    LibraryRepository repository,
    DeviceSettings values, {
    Iterable<String> defaults = const [],
  }) async {
    await repository.saveSettings(
      await repository.loadSettings(),
      values,
      defaultTargetIds: defaults,
    );
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(prefix);
    sourceRoot = Directory(p.join(sandbox.path, 'source'));
    destinationRoot = Directory(p.join(sandbox.path, 'destination'));
    sourceSecrets = QueueTestSecrets();
    destinationSecrets = QueueTestSecrets();
    source = await LibraryRepository.open(
      sourceRoot,
      secretStore: sourceSecrets,
    );
    destination = await LibraryRepository.open(
      destinationRoot,
      secretStore: destinationSecrets,
    );
    incoming = await image(source, 1);
    sentinel = await image(destination, 2);
    await saveValues(source, incomingSettings);
    await saveValues(destination, localSettings);
    backups.clear();
  });

  tearDown(() async {
    for (final backup in backups) {
      await backup.dispose();
    }
    await source.close();
    await destination.close();
    final temp = p.normalize(await Directory.systemTemp.resolveSymbolicLinks());
    final owned = p.normalize(await sandbox.resolveSymbolicLinks());
    if (!p.isAbsolute(owned) ||
        !p.isWithin(temp, owned) ||
        !p.basename(owned).startsWith(prefix)) {
      throw StateError('拒绝删除未确认归属的测试目录。');
    }
    await Directory(owned).delete(recursive: true);
  });

  List<Map<String, Object?>> rows(String table, {Directory? root}) {
    final db = sqlite3.open(
      p.join((root ?? destinationRoot).path, 'library.sqlite'),
      mode: OpenMode.readOnly,
    );
    try {
      return db
          .select('SELECT * FROM "$table" ORDER BY 1')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
    } finally {
      db.close();
    }
  }

  String storedSettings({Directory? root}) =>
      rows(
            'library_metadata',
            root: root,
          ).singleWhere((row) => row['key'] == 'device_settings_v1')['value']
          as String;

  void replaceStoredSettings(Directory root, String value) {
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      db.execute(
        "UPDATE library_metadata SET value=? WHERE key='device_settings_v1'",
        [value],
      );
    } finally {
      db.close();
    }
  }

  Future<void> reopen() async {
    await destination.close();
    destination = await LibraryRepository.open(
      destinationRoot,
      secretStore: destinationSecrets,
    );
  }

  Future<ValidatedBackup> writeAndPreflight(
    BackupSnapshotLease snapshot,
  ) async {
    final archive = File(
      p.join(sandbox.path, 'package-${packageNumber++}.zip'),
    );
    try {
      await BackupZipWriter().write(snapshot, archive);
    } finally {
      // Release only after the actual ZIP worker has finished.
      await snapshot.release();
    }
    final backup = await const BackupZipReader().preflight(
      archive,
      await Directory(p.join(sandbox.path, 'preflight')).create(),
      availableBytes: (_) async => 1 << 40,
    );
    backups.add(backup);
    return backup;
  }

  Future<ValidatedBackup> package({
    BackupMode mode = BackupMode.full,
    void Function(Map<String, Object?>)? editManifest,
  }) async {
    final captured = await source.captureBackupSnapshot(mode: mode);
    if (editManifest == null) return writeAndPreflight(captured);
    try {
      final json = Map<String, Object?>.from(
        jsonDecode(utf8.decode(captured.manifestBytes)) as Map,
      );
      editManifest(json);
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      final manifest = BackupManifest.decode(bytes);
      final rewritten = BackupSnapshotLease(
        manifest: manifest,
        manifestBytes: bytes,
        permanentFiles: captured.permanentFiles,
        onRelease: captured.release,
      );
      return await writeAndPreflight(rewritten);
    } finally {
      await captured.release();
    }
  }

  Future<bool> publishExclusive(File stage, File target) async {
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    await stage.rename(target.path);
    return true;
  }

  Future<MergeRestoreReport> restore(
    ValidatedBackup backup, {
    bool replacement = false,
    CancellationToken? cancellation,
    RestoreFaultHook? faultHook,
  }) async {
    final hold = await destination.acquireRestoreHold();
    ReplacementRestorePreparation? preparedReplacement;
    try {
      if (replacement) {
        preparedReplacement = await destination.prepareReplacementRestore(
          hold: hold,
          backup: backup,
          availableBytes: (_) async => 1 << 40,
        );
        return await destination.commitReplacementRestore(
          preparation: preparedReplacement,
          availableBytes: (_) async => 1 << 40,
          publishExclusive: publishExclusive,
          cancellation: cancellation,
          faultHook: faultHook,
        );
      }
      final preparation = await destination.prepareMergeRestore(
        hold: hold,
        backup: backup,
      );
      expect(preparation.plan.canCommit, isTrue);
      return await destination.commitMergeRestore(
        preparation: preparation,
        availableBytes: (_) async => 1 << 40,
        publishExclusive: publishExclusive,
        cancellation: cancellation,
        faultHook: faultHook,
      );
    } finally {
      if (preparedReplacement != null) {
        await destination.discardReplacementPreparation(preparedReplacement);
      }
      await hold.release();
    }
  }

  for (final replacement in [false, true]) {
    test(
      'UT-073/081/083 IT-005 partial BAK-005 ${replacement ? 'metadata replacement' : 'full merge'} restores all eight frozen settings with assets and survives reopen',
      () async {
        final snapshot = await source.captureBackupSnapshot(
          mode: replacement ? BackupMode.metadata : BackupMode.full,
        );
        // A settings save after capture cannot change the SQL-bound snapshot.
        await saveValues(source, DeviceSettings.defaults);
        final backup = await writeAndPreflight(snapshot);
        expect(backup.manifest.settings!.values, incomingSettings);
        var signals = 0;
        final subscription = destination.settingsChanges.listen((_) {
          signals++;
          // The signal must follow the actual committed asset/settings view.
          expect(storedSettings(), jsonEncode(incomingSettings.toJson()));
          expect(rows('assets').any((row) => row['id'] == incoming.id), isTrue);
        });
        try {
          final report = await restore(backup, replacement: replacement);
          expect(report.settings!.included, isTrue);
          expect(report.settings!.restored, BackupSetting.values);
          expect(report.settings!.skipped, isEmpty);
          expect(destination.currentDeviceSettings, incomingSettings);
          expect(destination.processingScheduler.effectiveConcurrency, 3);
          expect(signals, 1);
          final asset = (await destination.getAsset(incoming.id))!;
          expect(asset.version.id, incoming.version.id);
          expect(asset.version.sha256, incoming.version.sha256);
          expect(asset.version.byteCount, incoming.version.byteCount);
          expect(
            await destination.getAsset(sentinel.id),
            replacement ? isNull : isNotNull,
          );
        } finally {
          await subscription.cancel();
        }
        await reopen();
        expect((await destination.loadSettings()).values, incomingSettings);
        expect(destination.currentDeviceSettings, incomingSettings);
        expect(
          (await destination.getAsset(incoming.id))!.version,
          incoming.version,
        );
        final fresh = await destination.captureBackupSnapshot(
          mode: BackupMode.metadata,
        );
        try {
          expect(fresh.manifest.settings!.values, incomingSettings);
        } finally {
          await fresh.release();
        }
      },
    );

    test(
      'UT-073/081/083 IT-005 partial BAK-005 ${replacement ? 'replacement' : 'merge'} metadata-written fault rolls SQL and runtime back without settings notification',
      () async {
        final backup = await package();
        final before = storedSettings();
        final oldAssets = rows('assets');
        var signals = 0, boundaryCalls = 0;
        final subscription = destination.settingsChanges.listen(
          (_) => signals++,
        );
        try {
          await expectLater(
            restore(
              backup,
              replacement: replacement,
              faultHook: (boundary) async {
                if (boundary == RestoreBoundary.metadataWritten) {
                  boundaryCalls++;
                  expect(destination.currentDeviceSettings, localSettings);
                  throw StateError('controlled rollback');
                }
              },
            ),
            throwsA(isA<BackupSnapshotFailure>()),
          );
          expect(boundaryCalls, 1);
          expect(signals, 0);
          expect(storedSettings(), before);
          expect(rows('assets'), oldAssets);
          expect(destination.currentDeviceSettings, localSettings);
          expect(destination.processingScheduler.effectiveConcurrency, 2);
        } finally {
          await subscription.cancel();
        }
        await reopen();
        expect((await destination.loadSettings()).values, localSettings);
        expect(rows('assets'), oldAssets);
      },
    );

    test(
      'UT-073/081/083 partial BAK-005 ${replacement ? 'replacement' : 'merge'} cancellation inside settings transaction leaves old policy durable',
      () async {
        final backup = await package(mode: BackupMode.metadata);
        final cancellation = CancellationToken();
        final before = storedSettings();
        var signals = 0;
        final subscription = destination.settingsChanges.listen(
          (_) => signals++,
        );
        try {
          await expectLater(
            restore(
              backup,
              replacement: replacement,
              cancellation: cancellation,
              faultHook: (boundary) async {
                if (boundary == RestoreBoundary.metadataWritten) {
                  cancellation.cancel();
                }
              },
            ),
            throwsA(isA<BackupSnapshotFailure>()),
          );
          expect(signals, 0);
          expect(storedSettings(), before);
          expect(destination.currentDeviceSettings, localSettings);
          expect(await destination.getAsset(incoming.id), isNull);
          expect(await destination.getAsset(sentinel.id), isNotNull);
        } finally {
          await subscription.cancel();
        }
        await reopen();
        expect(destination.currentDeviceSettings, localSettings);
      },
    );

    test(
      'UT-073/081/083 partial BAK-005 real format-1 ${replacement ? 'replacement' : 'merge'} package retains local settings instead of default overwrite',
      () async {
        final backup = await package(
          mode: BackupMode.metadata,
          editManifest: (json) {
            json['formatVersion'] = 1;
            json.remove('settings');
          },
        );
        expect(backup.manifest.settings, isNull);
        final before = storedSettings();
        var signals = 0;
        final subscription = destination.settingsChanges.listen(
          (_) => signals++,
        );
        try {
          final report = await restore(backup, replacement: replacement);
          expect(report.settings!.included, isFalse);
          expect(report.settings!.restored, isEmpty);
          expect(signals, 0);
          expect(storedSettings(), before);
          expect(destination.currentDeviceSettings, localSettings);
        } finally {
          await subscription.cancel();
        }
        await reopen();
        expect((await destination.loadSettings()).values, localSettings);
        expect(await destination.getAsset(incoming.id), isNotNull);
      },
    );
  }

  test('UT-073/081/083 partial BAK-005 preparation alone and discarded replacement never write settings', () async {
    final backup = await package(mode: BackupMode.metadata);
    final before = storedSettings();
    var signals = 0;
    final subscription = destination.settingsChanges.listen((_) => signals++);
    final hold = await destination.acquireRestoreHold();
    try {
      final preparation = await destination.prepareMergeRestore(
        hold: hold,
        backup: backup,
      );
      expect(preparation.settings.values, incomingSettings);
      expect(destination.currentDeviceSettings, localSettings);
      expect(storedSettings(), before);
      final replacement = await destination.prepareReplacementRestore(
        hold: hold,
        backup: backup,
        availableBytes: (_) async => 1 << 40,
      );
      expect(replacement.settings.values, incomingSettings);
      await destination.discardReplacementPreparation(replacement);
      expect(signals, 0);
      expect(storedSettings(), before);
    } finally {
      await hold.release();
      await subscription.cancel();
    }
    await reopen();
    expect(destination.currentDeviceSettings, localSettings);
    expect(await destination.getAsset(incoming.id), isNull);
  });

  for (final replacement in [false, true]) {
    test(
      'UT-073/081/083 partial BAK-005 settings changed after ${replacement ? 'replacement' : 'merge'} review reject commit and preserve latest durable value',
      () async {
        final backup = await package(mode: BackupMode.metadata);
        final changed = DeviceSettings(quality: 71, cacheLimitMiB: 479);
        final changedJson = jsonEncode(changed.toJson());
        final oldAssets = rows('assets');
        var signals = 0;
        final subscription = destination.settingsChanges.listen(
          (_) => signals++,
        );
        final hold = await destination.acquireRestoreHold();
        ReplacementRestorePreparation? preparedReplacement;
        try {
          MergeRestorePreparation? preparedMerge;
          if (replacement) {
            preparedReplacement = await destination.prepareReplacementRestore(
              hold: hold,
              backup: backup,
              availableBytes: (_) async => 1 << 40,
            );
            expect(preparedReplacement.settings.current, localSettings);
          } else {
            preparedMerge = await destination.prepareMergeRestore(
              hold: hold,
              backup: backup,
            );
            expect(preparedMerge.settings.current, localSettings);
          }
          // Controlled external SQL corruption/change exercises the writer-gate
          // recheck; this does not use another application or old library format.
          replaceStoredSettings(destinationRoot, changedJson);
          await expectLater(
            replacement
                ? destination.commitReplacementRestore(
                    preparation: preparedReplacement!,
                    availableBytes: (_) async => 1 << 40,
                    publishExclusive: publishExclusive,
                  )
                : destination.commitMergeRestore(
                    preparation: preparedMerge!,
                    availableBytes: (_) async => 1 << 40,
                    publishExclusive: publishExclusive,
                  ),
            throwsA(isA<BackupSnapshotFailure>()),
          );
          expect(storedSettings(), changedJson);
          expect(rows('assets'), oldAssets);
          expect(destination.currentDeviceSettings, localSettings);
          expect(signals, 0);
        } finally {
          if (preparedReplacement != null) {
            await destination.discardReplacementPreparation(
              preparedReplacement,
            );
          }
          await hold.release();
          await subscription.cancel();
        }
        await reopen();
        expect((await destination.loadSettings()).values, changed);
        expect(destination.currentDeviceSettings, changed);
        expect(rows('assets'), oldAssets);
      },
    );
  }

  test('UT-073/081/083 partial BAK-005 real ZIP platform-unavailable settings are skipped and keep local values', () async {
    final backup = await package(
      mode: BackupMode.metadata,
      editManifest: (json) {
        final settings = json['settings']! as Map;
        final availability = settings['availability']! as Map;
        // An empty availability set covers every real host without pretending
        // that this Windows test is Android/iOS device acceptance.
        availability[BackupSetting.quality.name] = <String>[];
        availability[BackupSetting.cacheLimitMiB.name] = <String>[];
      },
    );
    final report = await restore(backup);
    expect(report.settings!.skipped, [
      BackupSetting.quality,
      BackupSetting.cacheLimitMiB,
    ]);
    expect(report.settings!.restored.length, 6);
    final expected = DeviceSettings.fromJson({
      ...incomingSettings.toJson(),
      'quality': localSettings.quality,
      'cacheLimitMiB': localSettings.cacheLimitMiB,
    });
    expect(destination.currentDeviceSettings, expected);
    await reopen();
    expect((await destination.loadSettings()).values, expected);
  });

  test('UT-063/073/081/083 partial BAK-005 merge preserves frozen processing parameters default target UUID and session upload denial', () async {
    final target = await destination.saveTarget(
      service: ImageHostService.catbox,
      alias: '同名默认目标',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
      selectedByDefault: true,
    );
    final incomingTarget = await source.saveTarget(
      service: ImageHostService.catbox,
      alias: '同名默认目标',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
      selectedByDefault: true,
    );
    final queued = await destination.enqueueUploads(
      intentId: 'settings-preserve-frozen-processing',
      processing: [
        UploadProcessingSelection(
          assetIds: [sentinel.id],
          recipe: ProcessingRecipe(
            operation: ProcessingOperation.compress,
            mode: ProcessingMode.fidelity,
            outputFormat: ProcessingFormat.jpeg,
            longestSide: 611,
            quality: 62,
          ),
        ),
      ],
      targetIds: [target],
    );
    final job = (await destination.listUploadProcessingJobs()).single;
    final actor = UploadCoordinator(
      LibraryUploadQueueStore(destination),
      adapters: const [],
    );
    // Production session listener updates runtime concurrency/policy, while
    // injecting an actor without a pixel worker avoids unrelated execution.
    final session = LibrarySession(destination, const [], uploads: actor);
    try {
      expect(actor.networkAllowed, isFalse);
      await restore(await package(mode: BackupMode.metadata));
      expect(actor.concurrency, incomingSettings.uploadConcurrency);
      expect(actor.networkPolicy, incomingSettings.networkUploadPolicy);
      expect(actor.networkAllowed, isFalse);
      expect(actor.activeCount, 0);
      expect(rows('upload_attempts'), isEmpty);
      final after = (await destination.listUploadProcessingJobs()).single;
      expect(after.id, job.id);
      expect(after.plan.canonical, job.plan.canonical);
      expect(after.retention, job.retention);
      expect(after.plan.recipe.quality, 62);
      expect(after.plan.recipe.longestSide, 611);
      final batches = await destination.listUploadBatches();
      expect(
        batches.singleWhere((batch) => batch.id == queued.id).paused,
        isTrue,
      );
      final settings = await destination.loadSettings();
      expect(settings.defaultTargetIds, {target});
      expect(
        settings.targets
            .singleWhere((t) => t.id == incomingTarget)
            .selectedByDefault,
        isFalse,
      );
      expect(
        settings.targets.singleWhere((t) => t.id == incomingTarget).enabled,
        isFalse,
      );
    } finally {
      await session.close();
    }
    await reopen();
    expect((await destination.loadSettings()).defaultTargetIds, {target});
    expect(
      (await destination.listUploadProcessingJobs()).single.plan.canonical,
      job.plan.canonical,
    );
  });

  test('UT-073/081/083/090 partial BAK-005 damaged and future stored settings cannot be defaulted during capture or prepare', () async {
    final backup = await package(mode: BackupMode.metadata);
    final valid = storedSettings();
    for (final bad in [
      '{broken-json',
      jsonEncode({...localSettings.toJson(), 'formatVersion': 999}),
    ]) {
      replaceStoredSettings(destinationRoot, bad);
      try {
        await expectLater(
          destination.captureBackupSnapshot(mode: BackupMode.metadata),
          throwsA(isA<BackupSnapshotFailure>()),
        );
        final hold = await destination.acquireRestoreHold();
        try {
          await expectLater(
            destination.prepareMergeRestore(hold: hold, backup: backup),
            throwsA(isA<BackupSnapshotFailure>()),
          );
          await expectLater(
            destination.prepareReplacementRestore(
              hold: hold,
              backup: backup,
              availableBytes: (_) async => 1 << 40,
            ),
            throwsA(isA<BackupSnapshotFailure>()),
          );
        } finally {
          await hold.release();
        }
        expect(storedSettings(), bad);
        expect(destination.currentDeviceSettings, localSettings);
      } finally {
        replaceStoredSettings(destinationRoot, valid);
      }
    }
    await reopen();
    expect((await destination.loadSettings()).values, localSettings);
  });

  test('UT-073/081/084 partial BAK-005 production snapshot excludes credentials references target defaults and upload authorization', () async {
    const key = 'synthetic-portable-settings-secret-0123456789';
    final target = await source.saveTarget(
      service: ImageHostService.catbox,
      alias: '受保护来源目标',
      anonymous: false,
      credential: key,
      persistence: CredentialPersistence.protected,
      selectedByDefault: true,
    );
    final snapshot = await source.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    try {
      final encoded = utf8.decode(snapshot.manifestBytes);
      expect(encoded.contains(key), isFalse);
      for (final reference in sourceSecrets.values.keys) {
        expect(encoded.contains(reference), isFalse);
      }
      final json = jsonDecode(encoded) as Map;
      final settings = json['settings']! as Map;
      expect(settings.keys.toSet(), {
        'formatVersion',
        'values',
        'availability',
      });
      expect(
        (settings['values']! as Map).keys.toSet(),
        incomingSettings.toJson().keys.toSet(),
      );
      for (final forbidden in [
        'credential',
        'secretReference',
        'selectedByDefault',
        'defaultTargetIds',
        'networkAllowed',
        'networkConsent',
      ]) {
        expect(encoded.contains('"$forbidden"'), isFalse);
      }
      expect(snapshot.manifest.accounts.single.id, target);
    } finally {
      await snapshot.release();
    }
    final backup = await package(mode: BackupMode.metadata);
    await restore(backup);
    expect(destinationSecrets.values, isEmpty);
    final restored = (await destination.loadSettings()).targets.single;
    expect(restored.id, target);
    expect(restored.enabled, isFalse);
    expect(restored.selectedByDefault, isFalse);
    sourceSecrets.failReads = true;
    try {
      await expectLater(
        source.captureBackupSnapshot(mode: BackupMode.metadata),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      expect(source.currentDeviceSettings, incomingSettings);
    } finally {
      sourceSecrets.failReads = false;
    }
  });

  test('UT-073/081/084 partial BAK-005 known credential colliding with settings enum rejects export without rewriting policy', () async {
    await source.saveTarget(
      service: ImageHostService.catbox,
      alias: '枚举碰撞目标',
      anonymous: false,
      credential: ProcessingMode.sizeFirst.name,
      persistence: CredentialPersistence.protected,
    );
    final before = storedSettings(root: sourceRoot);
    await expectLater(
      source.captureBackupSnapshot(mode: BackupMode.metadata),
      throwsA(
        isA<BackupFailure>().having(
          (failure) => failure.kind,
          'kind',
          BackupFailureKind.invalidManifest,
        ),
      ),
    );
    expect(storedSettings(root: sourceRoot), before);
    expect(source.currentDeviceSettings, incomingSettings);
  });
}
