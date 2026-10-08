import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late QueueTestSecrets secrets;
  late List<ImageAsset> assets;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost-backup-snapshot-',
    );
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    assets = [];
    for (var i = 0; i < 2; i++) {
      final image = img.Image(width: 9 + i, height: 7);
      img.fill(image, color: img.ColorRgb8(i + 1, 50, 110));
      final bytes = img.encodePng(image);
      assets.add(
        (await repository.importResource(
          PlatformResource(
            displayName: '备份-$i.png',
            openRead: () => Stream.value(bytes),
          ),
        )).asset!,
      );
    }
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  int leases() {
    final database = sqlite3.open('${root.path}/library.sqlite');
    try {
      return database
              .select('SELECT COUNT(*) AS n FROM file_leases')
              .single['n']
          as int;
    } finally {
      database.close();
    }
  }

  test('UT-073/074 partial real committed metadata snapshot preserves organization and permanent provenance without paths', () async {
    final category = await repository.createCategory('旅行');
    await repository.updateOrganization(
      [assets.first.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['海边'],
      favorite: true,
    );
    final output = await ProcessingCoordinator(repository).process(
      [assets.first.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        mode: ProcessingMode.sizeFirst,
        longestSide: 4,
      ),
      displayName: '独立保存.png',
    );
    await repository.saveOutput(output.id);
    await repository.removeAssets([assets.last.id]);
    final capture = await repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    try {
      expect(capture.permanentFiles, isEmpty);
      expect(capture.manifest.images, isEmpty);
      expect(capture.manifest.assets, hasLength(3));
      expect(capture.manifest.origins, hasLength(1));
      expect(
        capture.manifest.assets
            .singleWhere((a) => a.id == assets.last.id)
            .recycled,
        true,
      );
      final original = capture.manifest.assets.singleWhere(
        (a) => a.id == assets.first.id,
      );
      expect(original.favorite, true);
      expect(original.categoryId, category.id);
      expect(original.tagIds, [capture.manifest.tags.single.id]);
      final text = utf8.decode(capture.manifestBytes);
      expect(text, isNot(contains('"path"')));
      expect(text, isNot(contains('relativePath')));
      expect(text, isNot(contains(root.path)));
      expect(text, isNot(contains('cache/outputs')));
      expect(text, isNot(contains('secretReference')));
      expect(leases(), 0);
      // Mutating after capture cannot create a half-old/half-new graph.
      await repository.replaceTags([assets.first.id], ['城市']);
      expect(capture.manifest.tags.single.name, '海边');
      expect(
        capture.manifest.assets.singleWhere((a) => a.id == original.id).tagIds,
        original.tagIds,
      );
    } finally {
      await capture.release();
    }
  });

  test('UT-074 partial full snapshot protects recycled and independent permanent versions until actual IO ends', () async {
    await repository.removeAssets(assets.map((a) => a.id));
    await repository.purgeAssets([assets.first.id], confirmRecords: true);
    final capture = await repository.captureBackupSnapshot(
      mode: BackupMode.full,
    );
    try {
      expect(capture.manifest.assets, hasLength(1));
      expect(capture.manifest.versions, hasLength(2));
      expect(capture.manifest.images, hasLength(2));
      expect(capture.permanentFiles.keys, contains(assets.first.version.id));
      expect(leases(), 2);
      await expectLater(
        repository.purgeAssets([assets.last.id], confirmCopies: true),
        throwsStateError,
      );
      var closed = false;
      final closing = repository.close().then((_) => closed = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(closed, false);
      for (final file in capture.permanentFiles.values) {
        expect(await file.exists(), true);
      }
      await capture.release();
      await closing;
      expect(closed, true);
      expect(leases(), 0);
    } finally {
      await capture.release();
    }
  });

  test('UT-073/074 partial missing permanent bytes reject full with affected identities and allow only explicit metadata', () async {
    await File('${root.path}/${assets.first.deviceCopy.relativePath}').delete();
    await expectLater(
      repository.captureBackupSnapshot(mode: BackupMode.full),
      throwsA(
        isA<BackupSnapshotFailure>().having(
          (e) => e.affectedVersions,
          'affected immutable version',
          [assets.first.version.id],
        ),
      ),
    );
    expect(leases(), 0);
    expect(await repository.getAsset(assets.first.id), isNotNull);
    final metadata = await repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    expect(metadata.manifest.assets, hasLength(2));
    expect(metadata.manifest.images, isEmpty);
    await metadata.release();
  });

  test('UT-074/081 partial owned protected secrets mask portable names after reopen and active intent is excluded', () async {
    const key = 'synthetic-backup-api-key-0123456789';
    const management =
        'https://ibb.co/remoteID/backupManagementToken0123456789';
    final bytes = img.encodePng(img.Image(width: 3, height: 2));
    final privateName = (await repository.importResource(
      PlatformResource(
        displayName: '$key.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    final target = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '备份-$key',
      anonymous: false,
      credential: key,
    );
    final batch = await repository.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [privateName.id],
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
          directUrl: Uri.parse('https://i.ibb.co/remoteID/fixture.png'),
          managementSecret: SensitiveManagementSecret(management),
        ),
        accumulatedRunning: const Duration(seconds: 1),
      );
    } finally {
      await execution.release();
    }
    await repository.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [privateName.id],
      targetIds: [target],
      allowOriginalMetadata: true,
      forceAgain: true,
    );
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final capture = await repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    try {
      final text = utf8.decode(capture.manifestBytes);
      for (final excluded in [
        key,
        management,
        'backupManagementToken0123456789',
        'secretReference',
        'managementAvailable',
        'queued',
        'running',
        'requestMayHaveStarted',
      ]) {
        expect(text, isNot(contains(excluded)));
      }
      expect(capture.manifest.history, hasLength(1));
      expect(capture.manifest.results, hasLength(1));
      expect(capture.manifest.accounts.single.id, target);
      expect(capture.manifest.accounts.single.alias, contains('[已隐藏]'));
      expect(
        capture.manifest.assets
            .singleWhere((a) => a.id == privateName.id)
            .displayName,
        '[已隐藏].png',
      );
      expect((await repository.listUploadBatches()).length, 2);
    } finally {
      await capture.release();
    }
  });

  test('UT-074 partial unavailable secret backend fails closed before export and does not change library', () async {
    await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '待配置',
      anonymous: false,
      credential: 'synthetic-backup-protected-key',
    );
    secrets.failReads = true;
    await expectLater(
      repository.captureBackupSnapshot(mode: BackupMode.full),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(leases(), 0);
    expect((await repository.listAssets()).total, 2);
    secrets.failReads = false;
    final capture = await repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    await capture.release();
  });

  test('UT-082 partial cancellation waits for current pixel/hash IO and releases all real protection', () async {
    final cancellation = CancellationToken();
    final verified = <int>[];
    await expectLater(
      repository.captureBackupSnapshot(
        mode: BackupMode.full,
        cancellation: cancellation,
        onVerification: (done, total) {
          verified.add(done);
          cancellation.cancel();
        },
      ),
      throwsA(
        isA<BackupSnapshotFailure>().having(
          (e) => e.message,
          'cancel feedback',
          contains('取消'),
        ),
      ),
    );
    expect(verified, [1]);
    expect(leases(), 0);
    await repository.removeAssets([assets.last.id]);
    expect(
      (await repository.purgeAssets([
        assets.last.id,
      ], confirmCopies: true)).copiesRemoved,
      1,
    );
  });
}
