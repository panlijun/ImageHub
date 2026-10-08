import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

void main() {
  late Directory sandbox, sourceRoot, destinationRoot;
  late LibraryRepository source, destination;
  late QueueTestSecrets sourceSecrets, destinationSecrets;
  late List<ImageAsset> incoming;
  late ImageAsset sentinel;
  final validated = <ValidatedBackup>[];
  var packageNumber = 0;

  Future<ImageAsset> importPng(
    LibraryRepository repository,
    int marker, {
    String? name,
  }) async {
    final image = img.Image(width: 9 + marker, height: 7);
    img.fill(image, color: img.ColorRgb8(marker, 50, 110));
    final pixels = img.encodePng(image);
    final result = await repository.importResource(
      PlatformResource(
        displayName: name ?? '真实导入-$marker.png',
        openRead: () => Stream.value(pixels),
      ),
    );
    expect(result.status, ImportStatus.saved);
    return result.asset!;
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-merge-restore-');
    sourceRoot = Directory('${sandbox.path}/source-library');
    destinationRoot = Directory('${sandbox.path}/destination-library');
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
    incoming = [await importPng(source, 1), await importPng(source, 2)];
    sentinel = await importPng(destination, 3, name: '原资料库.png');
    validated.clear();
  });

  tearDown(() async {
    for (final backup in validated) {
      await backup.dispose();
    }
    await source.close();
    await destination.close();
    await sandbox.delete(recursive: true);
  });

  Future<ValidatedBackup> package({
    BackupMode mode = BackupMode.full,
    LibraryRepository? repository,
  }) async {
    final snapshot = await (repository ?? source).captureBackupSnapshot(
      mode: mode,
    );
    final archive = File('${sandbox.path}/package-${packageNumber++}.zip');
    try {
      await BackupZipWriter().write(snapshot, archive);
    } finally {
      // Writer waits for the actual isolate before this protection is released.
      await snapshot.release();
    }
    final staging = await Directory('${sandbox.path}/preflight').create();
    final backup = await const BackupZipReader().preflight(
      archive,
      staging,
      availableBytes: (_) async => 1 << 40,
    );
    validated.add(backup);
    return backup;
  }

  // A deterministic test substitute checks nonexistence before rename. This is
  // not evidence of Windows native atomic no-replace publication capability.
  Future<bool> publishExclusive(File staged, File target) async {
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    await staged.rename(target.path);
    return true;
  }

  Future<MergeRestoreReport> restore(
    ValidatedBackup backup, {
    RestoreFaultHook? faultHook,
    CancellationToken? cancellation,
    Future<int> Function(Directory)? availableBytes,
  }) async {
    final hold = await destination.acquireRestoreHold();
    try {
      final preparation = await destination.prepareMergeRestore(
        hold: hold,
        backup: backup,
      );
      expect(preparation.plan.canCommit, true);
      return await destination.commitMergeRestore(
        preparation: preparation,
        availableBytes: availableBytes ?? (_) async => 1 << 40,
        publishExclusive: publishExclusive,
        cancellation: cancellation,
        faultHook: faultHook,
      );
    } finally {
      await hold.release();
    }
  }

  Future<void> reopen() async {
    await destination.close();
    destination = await LibraryRepository.open(
      destinationRoot,
      secretStore: destinationSecrets,
    );
  }

  List<Map<String, Object?>> rows(String table) {
    final database = sqlite3.open('${destinationRoot.path}/library.sqlite');
    try {
      return database
          .select('SELECT * FROM $table ORDER BY 1')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
    } finally {
      database.close();
    }
  }

  Map<String, List<Map<String, Object?>>> sqlState() => {
    for (final table in [
      'versions',
      'assets',
      'device_copies',
      'categories',
      'tags',
      'asset_tags',
      'provider_targets',
      'remote_upload_results',
      'restored_output_origins',
      'imported_upload_histories',
      'upload_batches',
      'upload_publications',
      'upload_attempts',
    ])
      table: rows(table),
  };

  Future<Map<String, String>> originalBytes() async {
    final originals = Directory('${destinationRoot.path}/originals');
    final result = <String, String>{};
    await for (final entry in originals.list()) {
      if (entry is File) {
        result[entry.uri.pathSegments.last] = sha256
            .convert(await entry.readAsBytes())
            .toString();
      }
    }
    return result;
  }

  test('UT-073/074/075 IT-005 partial real full merge preserves organization provenance audit results and survives reopen and rebackup', () async {
    final category = await source.createCategory('旅行');
    await source.updateOrganization(
      [incoming.first.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['海边'],
      favorite: true,
    );
    final output = await ProcessingCoordinator(source).process(
      [incoming.first.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        mode: ProcessingMode.sizeFirst,
        longestSide: 4,
      ),
      displayName: '永久处理结果.png',
    );
    await source.saveOutput(output.id);
    const credential = 'synthetic-merge-restore-key-0123456789';
    final account = await source.saveTarget(
      service: ImageHostService.catbox,
      alias: '来源账号',
      anonymous: false,
      credential: credential,
    );
    final batch = await source.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [incoming.first.id],
      targetIds: [account],
      allowOriginalMetadata: true,
    );
    final execution = (await source.beginUploadAttempt(batch.items.single.id))!;
    try {
      expect(await source.authorizeUploadRequest(execution.attemptId), true);
      // Repository persistence test only: no real network request is issued.
      await source.finishUploadAttempt(
        execution,
        ProviderUploadSuccess(
          service: ImageHostService.catbox,
          remoteId: 'restored.png',
          directUrl: Uri.parse('https://files.catbox.moe/restored.png'),
        ),
        accumulatedRunning: const Duration(seconds: 1),
      );
    } finally {
      await execution.release();
    }
    await source.removeAssets([incoming.last.id]);
    final independent = await importPng(source, 4, name: '仅清记录保留字节.png');
    await source.removeAssets([independent.id]);
    await source.purgeAssets([independent.id], confirmRecords: true);
    final backup = await package();
    expect(backup.manifest.origins, hasLength(1));
    expect(backup.manifest.results, hasLength(1));
    expect(backup.manifest.history, hasLength(1));
    final report = await restore(backup);
    expect(report.addedAssets, 3);
    expect(report.addedResults, 1);
    expect(report.importedHistories, 1);
    expect(report.savedCopies, 4);
    expect(report.cleanupPending, false);
    await reopen();
    final asset = (await destination.getAsset(incoming.first.id))!;
    expect(asset.favorite, true);
    expect(asset.category, '旅行');
    expect(asset.tags.single.name, '海边');
    final recycled = (await destination.getAsset(
      incoming.last.id,
      includeRecycled: true,
    ))!;
    expect(recycled.recycled, true);
    expect(await destination.getAsset(incoming.last.id), isNull);
    expect(
      await destination.getAsset(independent.id, includeRecycled: true),
      isNull,
    );
    expect(
      rows('versions').map((row) => row['id']),
      contains(independent.version.id),
    );
    expect(await destination.listUploadBatches(), isEmpty);
    expect(rows('upload_attempts'), isEmpty);
    expect(rows('upload_publications'), isEmpty);
    expect(await destination.listImportedUploadHistories(), hasLength(1));
    expect(
      (await destination.listUploadResults()).single.directUrl,
      Uri.parse('https://files.catbox.moe/restored.png'),
    );
    final restoredAccount = (await destination.listTargets()).single;
    expect(restoredAccount.enabled, false);
    expect(restoredAccount.selectedByDefault, false);
    expect(restoredAccount.health, AccountHealth.unconfigured);
    expect(destinationSecrets.values, isEmpty);
    expect(rows('provider_targets').single['secret_reference'], isNull);
    final origin = backup.manifest.origins.single;
    expect(
      await destination.restoredOutputOrigins(origin.versionId),
      hasLength(1),
    );
    final rebackup = await package(repository: destination);
    expect(rebackup.manifest.origins, hasLength(1));
    expect(rebackup.manifest.results, hasLength(1));
    expect(rebackup.manifest.history, hasLength(1));
    expect(rebackup.manifest.images, hasLength(5));
    final portable = jsonEncode(
      rebackup.manifest.toJson(redactor: SecretRedactor()),
    );
    expect(portable, isNot(contains(sourceRoot.path)));
    expect(portable, isNot(contains(destinationRoot.path)));
    expect(portable, isNot(contains('relativePath')));
    expect(portable, isNot(contains('secretReference')));
    expect(portable, isNot(contains(credential)));
    expect(rows('restore_operations'), isEmpty);
    for (final file in rebackup.imageFiles.values) {
      expect(await file.exists(), true);
    }
    final beforeRepeat = sqlState();
    final beforeBytes = await originalBytes();
    final repeated = await restore(backup);
    expect(repeated.addedAssets, 0);
    expect(repeated.addedResults, 0);
    expect(repeated.importedHistories, 0);
    expect(repeated.savedCopies, 0);
    expect(sqlState(), beforeRepeat);
    expect(await originalBytes(), beforeBytes);
  });

  test('UT-073/074 partial matching content with different UUIDs keeps current organization and copy identity', () async {
    final same = await importPng(destination, 1, name: '当前名称.png');
    expect(same.id, isNot(incoming.first.id));
    final currentCategory = await destination.createCategory('当前分类');
    await destination.updateOrganization(
      [same.id],
      setCategory: true,
      categoryId: currentCategory.id,
      replaceTags: ['当前标签'],
      favorite: true,
    );
    await source.updateOrganization([incoming.first.id], replaceTags: ['恢复标签']);
    final backup = await package();
    final report = await restore(backup);
    expect(report.addedAssets, 1);
    final merged = (await destination.getAsset(same.id))!;
    expect(merged.displayName, '当前名称.png');
    expect(merged.categoryId, currentCategory.id);
    expect(merged.favorite, true);
    expect(merged.tags.map((tag) => tag.name), containsAll(['当前标签', '恢复标签']));
    expect(merged.deviceCopy, same.deviceCopy);
    expect(await destination.getAsset(incoming.first.id), isNull);
    expect(rows('versions'), hasLength(3));
  });

  test('UT-073/074 partial redacted portable view never rewrites existing local names organization or account alias', () async {
    const credential = 'synthetic-restore-redaction-0123456789';
    const assetName = '本机-$credential.png';
    const categoryName = '分类-$credential';
    const tagName = '标签-$credential';
    const accountAlias = '本机原始账号别名';
    // All local organization is written before credential registration, so
    // the test distinguishes original local names from the portable safe view.
    final local = await importPng(destination, 1, name: assetName);
    final category = await destination.createCategory(categoryName);
    await destination.updateOrganization(
      [local.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: [tagName],
      favorite: true,
    );
    final targetId = await destination.saveTarget(
      service: ImageHostService.catbox,
      alias: accountAlias,
      anonymous: false,
      credential: credential,
    );
    final original = (await destination.getAsset(local.id))!;
    final originalAccount = rows('provider_targets').single;
    await source.updateOrganization(
      [incoming.first.id],
      replaceTags: ['普通恢复标签'],
    );
    final before = await destination.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    try {
      expect(utf8.decode(before.manifestBytes), isNot(contains(credential)));
      expect(
        before.manifest.assets
            .singleWhere((asset) => asset.id == local.id)
            .displayName,
        '本机-${SecretRedactor.hidden}.png',
      );
      expect(
        before.manifest.categories.single.name,
        '分类-${SecretRedactor.hidden}',
      );
      expect(before.manifest.tags.single.name, '标签-${SecretRedactor.hidden}');
    } finally {
      await before.release();
    }
    final backup = await package();
    expect((await restore(backup)).addedAssets, 1);
    await reopen();
    final retained = (await destination.getAsset(local.id))!;
    expect(retained.displayName, assetName);
    expect(retained.categoryId, category.id);
    expect(retained.category, categoryName);
    expect(
      retained.tags.map((tag) => tag.name),
      containsAll([tagName, '普通恢复标签']),
    );
    expect(
      retained.tags.any((tag) => tag.name.contains(SecretRedactor.hidden)),
      false,
    );
    expect(retained.importedAt, original.importedAt);
    expect(retained.updatedAt, original.updatedAt);
    expect(retained.sourceType, original.sourceType);
    expect(retained.deviceCopy, original.deviceCopy);
    final retainedAccount = (await destination.listTargets()).single;
    expect(retainedAccount.id, targetId);
    expect(retainedAccount.alias, accountAlias);
    expect(rows('provider_targets').single, originalAccount);
    expect(destinationSecrets.values.values, contains(credential));
    final rebackup = await package(repository: destination);
    expect(
      rebackup.manifest.assets
          .singleWhere((asset) => asset.id == local.id)
          .displayName,
      '本机-${SecretRedactor.hidden}.png',
    );
    expect(
      rebackup.manifest.categories.single.name,
      '分类-${SecretRedactor.hidden}',
    );
    expect(
      rebackup.manifest.tags.map((tag) => tag.name),
      containsAll(['标签-${SecretRedactor.hidden}', '普通恢复标签']),
    );
    final portable = jsonEncode(
      rebackup.manifest.toJson(redactor: SecretRedactor()),
    );
    expect(portable, isNot(contains(credential)));
  });

  test('UT-074/075 IT-005 partial metadata creates missing copies then full repairs stable copy UUID across reopen', () async {
    final metadata = await package(mode: BackupMode.metadata);
    expect((await restore(metadata)).metadataOnly, true);
    final missing = (await destination.getAsset(incoming.first.id))!;
    expect(
      await File('${destinationRoot.path}/${missing.deviceCopy.relativePath}')
          .exists(),
      false,
    );
    expect(
      rows('device_copies').singleWhere(
        (row) => row['id'] == missing.deviceCopy.id,
      )['availability'],
      'missing',
    );
    await reopen();
    final full = await package();
    expect((await restore(full)).savedCopies, 2);
    await reopen();
    final repaired = (await destination.getAsset(incoming.first.id))!;
    expect(repaired.deviceCopy.id, missing.deviceCopy.id);
    expect(
      repaired.deviceCopy.relativePath,
      isNot(missing.deviceCopy.relativePath),
    );
    expect(
      rows('device_copies').singleWhere(
        (row) => row['id'] == missing.deviceCopy.id,
      )['availability'],
      'available',
    );
    expect(
      sha256
          .convert(
            await File(
              '${destinationRoot.path}/${repaired.deviceCopy.relativePath}',
            ).readAsBytes(),
          )
          .toString(),
      repaired.version.sha256,
    );
    expect(
      (await package(repository: destination)).manifest.images,
      hasLength(3),
    );
  });

  for (final boundary in [
    RestoreBoundary.intent,
    RestoreBoundary.copied,
    RestoreBoundary.prepared,
    RestoreBoundary.published,
    RestoreBoundary.beforeCommit,
    RestoreBoundary.metadataWritten,
  ]) {
    test(
      'UT-074/075 IT-005 partial injected ${boundary.name} failure rolls back SQL and owned bytes without hardware power-loss claim',
      () async {
        final backup = await package();
        final beforeSql = sqlState();
        final beforeBytes = await originalBytes();
        var hit = false;
        await expectLater(
          restore(
            backup,
            faultHook: (value) async {
              if (value == boundary) {
                hit = true;
                throw StateError('synthetic boundary failure');
              }
            },
          ),
          throwsA(isA<BackupSnapshotFailure>()),
        );
        expect(hit, true);
        expect(sqlState(), beforeSql);
        expect(await originalBytes(), beforeBytes);
        expect(rows('restore_operations'), isEmpty);
        final staged = await Directory('${destinationRoot.path}/staging')
            .list()
            .where((entry) => entry.path.endsWith('.part'))
            .toList();
        expect(staged, isEmpty);
        await reopen();
        expect(sqlState(), beforeSql);
        expect(await originalBytes(), beforeBytes);
        expect(
          (await destination.getAsset(sentinel.id))!.displayName,
          '原资料库.png',
        );
      },
    );
  }

  test('UT-074 IT-005 partial post-commit hook failure retains reported success after reopen', () async {
    final backup = await package();
    final cancellation = CancellationToken();
    var committed = false;
    final report = await restore(
      backup,
      cancellation: cancellation,
      faultHook: (value) async {
        if (value == RestoreBoundary.committed) {
          committed = true;
          cancellation.cancel();
          throw StateError('synthetic display failure after commit');
        }
      },
    );
    expect(committed, true);
    expect(cancellation.isCancelled, true);
    expect(report.addedAssets, 2);
    expect(report.savedCopies, 2);
    await reopen();
    expect((await destination.listAssets()).total, 3);
    expect((await originalBytes()).length, 3);
    expect(rows('restore_operations'), isEmpty);
  });

  test('UT-075 partial preflight file mutation low space and cancellation preserve old SQL and bytes', () async {
    final beforeSql = sqlState();
    final beforeBytes = await originalBytes();
    final changed = await package();
    final changedFile = changed.imageFiles.values.first;
    final verifiedBytes = await changedFile.readAsBytes();
    await changedFile.writeAsBytes([1, 2, 3]);
    await expectLater(restore(changed), throwsA(isA<BackupSnapshotFailure>()));
    expect(sqlState(), beforeSql);
    expect(await originalBytes(), beforeBytes);
    await expectLater(changed.dispose(), throwsA(isA<BackupSnapshotFailure>()));
    expect(await changedFile.readAsBytes(), [1, 2, 3]);
    // This fixture wrote the mutation itself. Restoring its exact verified
    // bytes makes the owned workspace safe for the normal teardown retry.
    await changedFile.writeAsBytes(verifiedBytes, flush: true);
    final valid = await package();
    await expectLater(
      restore(valid, availableBytes: (_) async => 0),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    var capacityChecks = 0;
    await expectLater(
      restore(
        valid,
        availableBytes: (_) async {
          capacityChecks++;
          return capacityChecks == 1 ? 1 << 40 : 0;
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(capacityChecks, 2);
    final cancelled = CancellationToken()..cancel();
    await expectLater(
      restore(valid, cancellation: cancelled),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    final duringCopy = CancellationToken();
    await expectLater(
      restore(
        valid,
        cancellation: duringCopy,
        faultHook: (boundary) async {
          if (boundary == RestoreBoundary.copied) duringCopy.cancel();
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    final insideTransaction = CancellationToken();
    var metadataWritten = false;
    await expectLater(
      restore(
        valid,
        cancellation: insideTransaction,
        faultHook: (boundary) async {
          if (boundary == RestoreBoundary.metadataWritten) {
            metadataWritten = true;
            insideTransaction.cancel();
          }
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(metadataWritten, true);
    expect(sqlState(), beforeSql);
    expect(await originalBytes(), beforeBytes);
    expect(rows('restore_operations'), isEmpty);
  });

  test('UT-074 IT-005 partial close waits for real restore publication IO keeps root lock and rolls back before commit', () async {
    final backup = await package();
    final beforeSql = sqlState();
    final beforeBytes = await originalBytes();
    final hold = await destination.acquireRestoreHold();
    final preparation = await destination.prepareMergeRestore(
      hold: hold,
      backup: backup,
    );
    final enteredIO = Completer<void>();
    final finishIO = Completer<void>();
    var readerClosed = false, libraryClosed = false;
    final restoring = destination.commitMergeRestore(
      preparation: preparation,
      availableBytes: (_) async => 1 << 40,
      publishExclusive: (staged, target) async {
        // Keep a real staged-file reader open across close intent. The
        // controlled delay represents an unfinished publication operation.
        if (!enteredIO.isCompleted) {
          final reader = await staged.open();
          enteredIO.complete();
          try {
            await finishIO.future;
            expect(await reader.read(16), isNotEmpty);
          } finally {
            await reader.close();
            readerClosed = true;
          }
        }
        return publishExclusive(staged, target);
      },
    );
    final rejected = expectLater(
      restoring,
      throwsA(isA<BackupSnapshotFailure>()),
    );
    await enteredIO.future.timeout(const Duration(seconds: 5));
    final closing = destination.close().then((_) => libraryClosed = true);
    try {
      await expectLater(hold.release(), throwsA(isA<BackupSnapshotFailure>()));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(readerClosed, false);
      expect(libraryClosed, false);
      await expectLater(
        LibraryRepository.open(
          destinationRoot,
          secretStore: destinationSecrets,
        ),
        throwsA(isA<LibraryOpenException>()),
      );
    } finally {
      finishIO.complete();
    }
    await rejected.timeout(const Duration(seconds: 5));
    await closing.timeout(const Duration(seconds: 5));
    expect(readerClosed, true);
    expect(libraryClosed, true);
    await hold.release();
    await hold.release();
    await reopen();
    expect(sqlState(), beforeSql);
    expect(await originalBytes(), beforeBytes);
    expect(rows('restore_operations'), isEmpty);
    expect((await destination.listAssets()).total, 1);
  });

  test('UT-074 IT-005 partial hold blocks new writes drains real file lease without deadlock and preserves paused current queue', () async {
    final target = await destination.saveTarget(
      service: ImageHostService.catbox,
      alias: '当前账号',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    final batch = await destination.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [sentinel.id],
      targetIds: [target],
      allowOriginalMetadata: true,
    );
    final snapshot = await destination.captureBackupSnapshot(
      mode: BackupMode.full,
    );
    final file = snapshot.permanentFiles.values.single;
    final actualReader = await file.open();
    var ready = false;
    final acquiring = destination.acquireRestoreHold().then((hold) {
      ready = true;
      return hold;
    });
    try {
      await expectLater(
        destination.setFavorite(sentinel.id, true),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(ready, false);
      expect(rows('file_leases'), hasLength(1));
      expect(await actualReader.read(16), isNotEmpty);
    } finally {
      await actualReader.close();
      // Release happens only after the actual file IO is closed.
      await snapshot.release();
    }
    final hold = await acquiring.timeout(const Duration(seconds: 5));
    try {
      expect(ready, true);
      expect(rows('file_leases'), isEmpty);
      await expectLater(
        destination.setFavorite(sentinel.id, true),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      expect(rows('upload_batches').single['paused'], 1);
      expect(
        rows('upload_publications').single['state'],
        PublishState.paused.name,
      );
    } finally {
      await hold.release();
    }
    await destination.setFavorite(sentinel.id, true);
    expect((await destination.getAsset(sentinel.id))!.favorite, true);
    final retained = (await destination.listUploadBatches()).single;
    expect(retained.id, batch.id);
    expect(retained.paused, true);
    expect(retained.items.single.state, PublishState.paused);
    await reopen();
    expect((await destination.listUploadBatches()).single.paused, true);
  });
}
