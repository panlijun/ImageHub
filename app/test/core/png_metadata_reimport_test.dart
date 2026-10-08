import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/image_processor.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'png_orientation_fixture.dart';
import 'upload_repository_test.dart' show QueueTestSecrets;

void main() {
  late Directory sandbox, root;
  LibraryRepository? repository;
  late QueueTestSecrets secrets;
  late List<int> bytes;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-png-reimport-');
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  });
  tearDown(() async {
    await repository?.close();
    await sandbox.delete(recursive: true);
  });

  List<Map<String, Object?>> rows(String table) {
    final db = sqlite3.open(
      '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return [
        for (final row in db.select('SELECT * FROM "$table" ORDER BY 1'))
          Map<String, Object?>.from(row),
      ];
    } finally {
      db.close();
    }
  }

  void mutate(void Function(Database) action) {
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      db.execute('PRAGMA foreign_keys=ON');
      action(db);
    } finally {
      db.close();
    }
  }

  Future<void> reopen({ImportFaultHook? faultHook}) async {
    await repository?.close();
    repository = null;
    repository = await LibraryRepository.open(
      root,
      secretStore: secrets,
      faultHook: faultHook,
    );
  }

  Future<ImportResult> import() => repository!.importResource(
    PlatformResource(
      displayName: 'reselected.png',
      openRead: () => Stream.value(bytes),
    ),
  );
  Future<ImageAsset> legacy(
    int direction, {
    Future<void> Function(ImageAsset)? beforeLegacy,
  }) async {
    bytes = addPngExif(
      img.encodePng(orientationMatrix()),
      orientationTiff(direction),
    );
    final original = (await import()).asset!;
    final category = await repository!.createCategory('保留分类');
    await repository!.updateOrganization(
      [original.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['保留标签'],
      favorite: true,
    );
    await beforeLegacy?.call(original);
    await repository!.close();
    repository = null;
    mutate((db) {
      db.execute('UPDATE assets SET display_name=? WHERE id=?', [
        '保留名称.png',
        original.id,
      ]);
      db.execute(
        'UPDATE versions SET width=2,height=3,orientation=1 WHERE id=?',
        [original.version.id],
      );
      // Model a committed own-project old decoder state, including its frozen
      // audit/input JSON; this is fixture setup, never a production migration.
      for (final table in ['upload_publications', 'remote_upload_results']) {
        for (final row in db.select('SELECT id,input_json FROM $table')) {
          final input =
              jsonDecode(row['input_json'] as String) as Map<String, dynamic>;
          final version = input['version'] as Map<String, dynamic>;
          if (version['id'] != original.version.id) continue;
          version['width'] = 2;
          version['height'] = 3;
          version['orientation'] = 1;
          db.execute('UPDATE $table SET input_json=? WHERE id=?', [
            jsonEncode(input),
            row['id'],
          ]);
        }
      }
    });
    await reopen();
    return (await repository!.getAsset(original.id))!;
  }

  void expectMetadata(ImageAsset asset, int direction) => expect(
    [asset.version.width, asset.version.height, asset.version.orientation],
    [direction >= 5 ? 3 : 2, direction >= 5 ? 2 : 3, direction],
  );
  Future<void> expectProcessAndBackup(ImageAsset asset, int direction) async {
    final result = await const ImageProcessor().process(
      ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: [
          ProcessingInput(
            file: await repository!.originalFor(asset),
            assetId: asset.id,
            version: asset.version,
          ),
        ],
      ),
    );
    try {
      final decoded = img.decodePng(await result.file.readAsBytes())!;
      expect(
        [decoded.width, decoded.height],
        [asset.version.width, asset.version.height],
      );
      final expected = orientedPixelIndices[direction]!;
      for (final pixel in decoded) {
        expect([
          pixel.r,
          pixel.g,
          pixel.b,
          pixel.a,
        ], matrixPixel(expected[pixel.y * decoded.width + pixel.x]));
      }
    } finally {
      await result.dispose();
    }
    final backup = await repository!.captureBackupSnapshot(
      mode: BackupMode.full,
    );
    try {
      final version = backup.manifest.versions.single;
      expect(
        [version.width, version.height, version.orientation],
        [asset.version.width, asset.version.height, direction],
      );
      expect(
        await backup.permanentFiles[asset.version.id]!.readAsBytes(),
        bytes,
      );
    } finally {
      await backup.release();
    }
  }

  for (var direction = 1; direction <= 8; direction++) {
    test(
      'IMG-005/IMP-006 PNG $direction explicit reimport retains identities and organization and enables real processing/full backup',
      () async {
        final old = await legacy(direction);
        final assetRows = rows('assets'), copyRows = rows('device_copies');
        final tags = rows('asset_tags'), categories = rows('categories');
        final repaired = await import();
        expect(
          repaired.status,
          direction == 1 ? ImportStatus.duplicate : ImportStatus.repaired,
        );
        final actual = repaired.asset!;
        expectMetadata(actual, direction);
        expect(actual.id, old.id);
        expect(actual.version.id, old.version.id);
        expect(actual.deviceCopy, old.deviceCopy);
        expect(actual.displayName, old.displayName);
        expect(actual.favorite, true);
        expect(actual.tags.single.name, '保留标签');
        expect(actual.importedAt, old.importedAt);
        expect(actual.updatedAt, old.updatedAt);
        expect(rows('assets'), assetRows);
        expect(rows('device_copies'), copyRows);
        expect(rows('asset_tags'), tags);
        expect(rows('categories'), categories);
        expect(rows('versions'), hasLength(1));
        expect(rows('import_operations'), isEmpty);
        expect(
          await (await repository!.originalFor(actual)).readAsBytes(),
          bytes,
        );
        await expectProcessAndBackup(actual, direction);
        await reopen();
        expectMetadata((await repository!.getAsset(old.id))!, direction);
        expect((await import()).status, ImportStatus.duplicate);
      },
    );
  }

  test('IMG-005 retained orphan version is corrected atomically with a new asset without changing permanent identity/path', () async {
    final old = await legacy(6);
    final path = File('${root.path}/${old.deviceCopy.relativePath}');
    await repository!.removeAssets([old.id]);
    await repository!.purgeAssets([old.id], confirmRecords: true);
    final saved = await import();
    expect(saved.status, ImportStatus.saved);
    expect(saved.asset!.id, isNot(old.id));
    expect(saved.asset!.version.id, old.version.id);
    expect(saved.asset!.deviceCopy, old.deviceCopy);
    expectMetadata(saved.asset!, 6);
    expect(await path.readAsBytes(), bytes);
    expect(rows('versions'), hasLength(1));
    expect(rows('import_operations'), isEmpty);
    await expectProcessAndBackup(saved.asset!, 6);
  });

  for (final damaged in [false, true]) {
    test(
      'IMG-005 ${damaged ? 'damaged' : 'missing'} legacy PNG repairs copy and metadata in one association',
      () async {
        final old = await legacy(8);
        final file = File('${root.path}/${old.deviceCopy.relativePath}');
        if (damaged) {
          await file.writeAsBytes([1, 2, 3]);
        } else {
          await file.delete();
        }
        final result = await import();
        expect(result.status, ImportStatus.repaired);
        final actual = result.asset!;
        expectMetadata(actual, 8);
        expect(actual.id, old.id);
        expect(actual.version.id, old.version.id);
        expect(actual.deviceCopy.id, old.deviceCopy.id);
        expect(
          actual.deviceCopy.relativePath,
          isNot(old.deviceCopy.relativePath),
        );
        expect(actual.importedAt, old.importedAt);
        expect(actual.updatedAt, old.updatedAt);
        expect(actual.tags, old.tags);
        expect(
          await (await repository!.originalFor(actual)).readAsBytes(),
          bytes,
        );
        await expectProcessAndBackup(actual, 8);
      },
    );
  }

  test('IMG-005 recycled duplicate retains wrong frozen description until explicit restore and reimport', () async {
    final old = await legacy(6);
    await repository!.removeAssets([old.id]);
    final before = rows('versions');
    final result = await import();
    expect(result.status, ImportStatus.needsRestore);
    expect(result.asset!.recycled, true);
    expect(rows('versions'), before);
    await repository!.restoreAssets([old.id]);
    final corrected = await import();
    expect(corrected.status, ImportStatus.repaired);
    expectMetadata(corrected.asset!, 6);
  });

  for (final fields in [
    'width=7',
    'height=7',
    'frame_count=2',
    'orientation=3',
    "format='JPEG'",
  ]) {
    test(
      'IMG-005 unknown PNG version disagreement $fields is rejected without mutation or another identity',
      () async {
        final old = await legacy(6);
        await repository!.close();
        repository = null;
        mutate(
          (db) => db.execute('UPDATE versions SET $fields WHERE id=?', [
            old.version.id,
          ]),
        );
        await reopen();
        final before = rows('versions'),
            copies = rows('device_copies'),
            assets = rows('assets');
        final result = await import();
        expect(result.status, ImportStatus.failed);
        expect(result.failure?.kind, FailureKind.invalidImage);
        expect(rows('versions'), before);
        expect(rows('device_copies'), copies);
        expect(rows('assets'), assets);
        expect(
          await File('${root.path}/${old.deviceCopy.relativePath}')
              .readAsBytes(),
          bytes,
        );
        expect(rows('import_operations'), isEmpty);
      },
    );
  }

  test('IMG-005 actual file lease prevents metadata repair through its real read and release', () async {
    final old = await legacy(3);
    final lease = await repository!.acquireAssetLease([
      old.id,
    ], purpose: 'processing');
    try {
      final before = rows('versions');
      final blocked = await import();
      expect(blocked.status, ImportStatus.failed);
      expect(blocked.failure?.kind, FailureKind.activeUse);
      expect(rows('versions'), before);
      expect(
        await File(lease.pathsByVersion[old.version.id]!).readAsBytes(),
        bytes,
      );
      expect(rows('file_leases'), hasLength(1));
    } finally {
      await lease.release();
    }
    final corrected = await import();
    expect(corrected.status, ImportStatus.repaired);
    expectMetadata(corrected.asset!, 3);
  });

  test('IMG-005 real queued frozen upload remains unchanged until explicit cancel/history confirmation then new reimport', () async {
    final old = await legacy(
      6,
      beforeLegacy: (asset) async {
        final target = await repository!.saveTarget(
          service: ImageHostService.catbox,
          alias: '本地测试目标',
          anonymous: false,
          credential: 'synthetic-png-reimport-key',
        );
        await repository!.enqueueUploads(
          intentId: 'png-reimport-frozen',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
        );
      },
    );
    final batch = (await repository!.listUploadBatches()).single;
    final publications = rows('upload_publications'),
        refs = rows('version_references');
    expect(batch.items.single.input.version, old.version);
    final result = await import();
    expect(result.failure?.kind, FailureKind.activeUse);
    expect(rows('upload_publications'), publications);
    expect(rows('version_references'), refs);
    expect((await repository!.getAsset(old.id))!.version, old.version);
    await repository!.cancelUploadItems([batch.items.single.id]);
    final plan = await repository!.prepareUploadHistoryClear(
      publicationIds: [batch.items.single.id],
      importedHistoryIds: [],
    );
    await repository!.clearUploadHistory(plan, confirmHistoryRemoval: true);
    expect(rows('version_references'), isEmpty);
    expectMetadata((await import()).asset!, 6);
    expect(batch.items.single.input.version, old.version);
    expect(rows('upload_attempts'), isEmpty);
  });

  test('IMG-005 persistent version reference protects legacy PNG until explicit release', () async {
    final old = await legacy(7);
    await repository!.registerProtection(
      ownerType: 'processing',
      ownerId: 'frozen-pixels',
      versionIds: [old.version.id],
    );
    final before = rows('versions');
    expect((await import()).failure?.kind, FailureKind.activeUse);
    expect(rows('versions'), before);
    expect(rows('version_references'), hasLength(1));
    await repository!.releaseProtection(
      ownerType: 'processing',
      ownerId: 'frozen-pixels',
    );
    expectMetadata((await import()).asset!, 7);
  });

  test('IMG-005 unchanged metadata retains ordinary duplicate behavior even with an actual input lease', () async {
    final old = await legacy(1);
    final lease = await repository!.acquireAssetLease([
      old.id,
    ], purpose: 'processing');
    try {
      final before = rows('versions');
      expect((await import()).status, ImportStatus.duplicate);
      expect(rows('versions'), before);
      expect(
        await File(lease.pathsByVersion[old.version.id]!).readAsBytes(),
        bytes,
      );
    } finally {
      await lease.release();
    }
  });

  test('IMG-005 repair retains an actual ordinary confirmation and frozen successful history bytes', () async {
    await legacy(
      6,
      beforeLegacy: (asset) async {
        final target = await repository!.saveTarget(
          service: ImageHostService.catbox,
          alias: '本地确认目标',
          anonymous: false,
          credential: 'synthetic-png-confirmation-key',
        );
        final batch = await repository!.enqueueUploads(
          intentId: 'png-ordinary-confirmation',
          assetIds: [asset.id],
          targetIds: [target],
          allowOriginalMetadata: true,
        );
        final execution = (await repository!.beginUploadAttempt(
          batch.items.single.id,
        ))!;
        try {
          await repository!.finishUploadAttempt(
            execution,
            ProviderUploadSuccess(
              service: ImageHostService.catbox,
              remoteId: 'fixture.png',
              directUrl: Uri.parse('https://files.catbox.moe/fixture.png'),
            ),
            accumulatedRunning: Duration.zero,
          );
        } finally {
          await execution.release();
        }
      },
    );
    final confirmations = rows('remote_upload_results'),
        publications = rows('upload_publications');
    expect(confirmations, hasLength(1));
    final actual = (await import()).asset!;
    expectMetadata(actual, 6);
    expect(rows('remote_upload_results'), confirmations);
    expect(rows('upload_publications'), publications);
    expect(actual.confirmedRemoteResultCount, 1);
    // The separately implemented portable audit relation must preserve these
    // frozen fields while accepting the confirmed permanent description.
    await expectProcessAndBackup(actual, 6);
    expect(rows('remote_upload_results'), confirmations);
    expect(rows('upload_publications'), publications);
  });

  for (final orphan in [false, true]) {
    test(
      'IMG-005 ${orphan ? 'orphan' : 'available'} metadata correction recovers an existing ready journal after precommit interruption',
      () async {
        final old = await legacy(6);
        if (orphan) {
          await repository!.removeAssets([old.id]);
          await repository!.purgeAssets([old.id], confirmRecords: true);
        }
        await reopen(
          faultHook: (boundary) async {
            if (boundary == ImportBoundary.beforeDbCommit) {
              throw StateError('fixture interruption');
            }
          },
        );
        final failed = await import();
        expect(failed.status, ImportStatus.failed);
        expect(rows('versions').single['orientation'], 1);
        expect(rows('import_operations').single['phase'], 'ready');
        await reopen();
        final actual = (await repository!.listAssets()).items.single;
        expectMetadata(actual, 6);
        expect(actual.version.id, old.version.id);
        expect(actual.deviceCopy, old.deviceCopy);
        expect(actual.id, orphan ? isNot(old.id) : old.id);
        expect(rows('import_operations'), isEmpty);
        await expectProcessAndBackup(actual, 6);
      },
    );
  }

  for (final corruptRelationship in [false, true]) {
    test(
      'IMG-005 committed reuse with removed stage ${corruptRelationship ? 'preserves a corrupt relation instead of guessing' : 'recovers after failed journal deletion'}',
      () async {
        final old = await legacy(6);
        final assetRows = rows('assets'), copies = rows('device_copies');
        mutate(
          (db) => db.execute(
            "CREATE TRIGGER keep_import_journal BEFORE DELETE ON import_operations BEGIN SELECT RAISE(ABORT, 'fixture journal retention'); END",
          ),
        );
        final confirmed = await import();
        expect(confirmed.status, ImportStatus.repaired);
        expectMetadata(confirmed.asset!, 6);
        final op = rows('import_operations').single;
        expect(op['phase'], 'committedReuse');
        expect(op['asset_id'], old.id);
        expect(op['version_id'], old.version.id);
        expect(op['copy_id'], old.deviceCopy.id);
        expect(await File('${root.path}/${op['stage_path']}').exists(), false);
        expect(await File('${root.path}/${op['final_path']}').exists(), false);
        expect(repository!.recoveryIssues, isNotEmpty);
        await repository!.close();
        repository = null;
        mutate((db) {
          db.execute('DROP TRIGGER keep_import_journal');
          if (corruptRelationship) {
            db.execute('UPDATE import_operations SET copy_id=? WHERE id=?', [
              '10000000-0000-4000-8000-000000000001',
              op['id'],
            ]);
          }
        });
        await reopen();
        final actual = (await repository!.getAsset(old.id))!;
        expectMetadata(actual, 6);
        expect(rows('assets'), assetRows);
        expect(rows('device_copies'), copies);
        expect(
          await (await repository!.originalFor(actual)).readAsBytes(),
          bytes,
        );
        expect(await File('${root.path}/${op['final_path']}').exists(), false);
        if (corruptRelationship) {
          expect(rows('import_operations'), hasLength(1));
          expect(
            rows('import_operations').single['copy_id'],
            '10000000-0000-4000-8000-000000000001',
          );
          expect(repository!.recoveryIssues, isNotEmpty);
        } else {
          expect(rows('import_operations'), isEmpty);
          expect(repository!.recoveryIssues, isEmpty);
          await expectProcessAndBackup(actual, 6);
        }
      },
    );
  }
}
