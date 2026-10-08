import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/gallery_query.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late QueueTestSecrets secrets;
  late ImageAsset a, b, c;
  late String cat, imgbb;
  final extraRepositories = <LibraryRepository>[];
  var serial = 0;

  Future<ImageAsset> importImage(String name, int marker) async {
    final image = img.Image(width: 9 + marker, height: 6);
    img.fill(image, color: img.ColorRgb8(marker % 255, 40, 90));
    final imported = await repository.importResource(
      PlatformResource(
        displayName: name,
        openRead: () => Stream.value(img.encodePng(image)),
      ),
    );
    expect(imported.status, ImportStatus.saved);
    return imported.asset!;
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost-gallery-remote-',
    );
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    a = await importImage('Cafe\u0301 Straße A.png', 1);
    b = await importImage('本地 B.png', 2);
    c = await importImage('无远端 C.png', 3);
    cat = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: 'FrozenAlpha',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    imgbb = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: 'FrozenBeta',
      anonymous: false,
      credential: 'SyntheticGalleryCredential0123456789',
    );
    extraRepositories.clear();
  });
  tearDown(() async {
    for (final extra in extraRepositories) {
      await extra.close();
    }
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  List<Map<String, Object?>> rows(String table, {String? database}) {
    final db = sqlite3.open(
      database ?? '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return db
          .select('SELECT * FROM "$table" ORDER BY 1')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } finally {
      db.close();
    }
  }

  void mutate(void Function(Database) action, {String? database}) {
    final db = sqlite3.open(database ?? '${root.path}/library.sqlite');
    try {
      db.execute('PRAGMA foreign_keys=ON');
      action(db);
    } finally {
      db.close();
    }
  }

  Future<UploadBatch> enqueue(
    ImageAsset asset,
    String target, {
    String? outputId,
  }) => repository.enqueueUploads(
    intentId: const Uuid().v4(),
    assetIds: outputId == null ? [asset.id] : [],
    outputIds: outputId == null ? [] : [outputId],
    targetIds: [target],
    allowOriginalMetadata: true,
    forceAgain: true,
  );

  Future<UploadExecution> begin(UploadBatch batch) async =>
      (await repository.beginUploadAttempt(batch.items.single.id))!;

  Future<void> finish(
    UploadExecution execution,
    ProviderUploadResult outcome, {
    bool interrupted = false,
  }) async {
    try {
      await repository.finishUploadAttempt(
        execution,
        outcome,
        accumulatedRunning: Duration.zero,
        interrupted: interrupted,
      );
    } finally {
      await execution.release();
    }
  }

  Future<RemoteUploadResult> succeed(
    ImageAsset asset,
    String target, {
    String? outputId,
    String? slug,
    bool late = false,
  }) async {
    final batch = await enqueue(asset, target, outputId: outputId);
    final execution = await begin(batch);
    expect(await repository.authorizeUploadRequest(execution.attemptId), true);
    if (late) await repository.cancelUploadItems([execution.item.id]);
    final service = execution.item.target.service;
    final name = slug ?? 'gallery${++serial}';
    await finish(
      execution,
      ProviderUploadSuccess(
        service: service,
        remoteId: service == ImageHostService.catbox ? '$name.png' : name,
        directUrl: Uri.parse(
          service == ImageHostService.catbox
              ? 'https://files.catbox.moe/$name.png'
              : 'https://i.ibb.co/$name/image.png',
        ),
      ),
    );
    // Only synthetic provider evidence enters the actual SQL commit boundary;
    // no transport, adapter or HTTP request exists in these fixtures.
    return (await repository.listUploadResults()).singleWhere(
      (r) => r.attemptId == execution.attemptId,
    );
  }

  Future<UploadBatch> fail(
    ImageAsset asset,
    String target, {
    bool unknown = false,
  }) async {
    final batch = await enqueue(asset, target);
    await finish(
      await begin(batch),
      unknown
          ? const ProviderUploadUnknown(UploadFailureKind.protocol)
          : const ProviderUploadFailure(
              UploadFailureKind.quota,
              UploadDeliveryEvidence.confirmedRejected,
            ),
    );
    return batch;
  }

  Future<void> matches(
    GalleryQuery query,
    Set<String> expected, {
    LibraryRepository? owner,
  }) async {
    final library = owner ?? repository;
    final page = await library.listAssets(query: query);
    expect(
      page.total,
      expected.length,
      reason:
          'scope ${query.uploadFilter?.name}, service ${query.remoteService?.name}, kind ${query.remoteInputKind?.name}',
    );
    expect(page.items.map((asset) => asset.id).toSet(), expected);
    expect((await library.matchingAssetIds(query: query)).toSet(), expected);
  }

  Future<(LibraryRepository, Directory)> restore(BackupMode mode) async {
    final snapshot = await repository.captureBackupSnapshot(mode: mode);
    final archive = File('${sandbox.path}/package-${++serial}.zip');
    try {
      await BackupZipWriter().write(snapshot, archive);
    } finally {
      await snapshot.release();
    }
    final backup = await const BackupZipReader().preflight(
      archive,
      await Directory('${sandbox.path}/preflight-$serial').create(),
      availableBytes: (_) async => 1 << 40,
    );
    final destinationRoot = Directory('${sandbox.path}/restored-$serial');
    final destination = await LibraryRepository.open(
      destinationRoot,
      secretStore: QueueTestSecrets(),
    );
    extraRepositories.add(destination);
    final hold = await destination.acquireRestoreHold();
    try {
      final preparation = await destination.prepareMergeRestore(
        hold: hold,
        backup: backup,
      );
      expect(preparation.plan.canCommit, true);
      await destination.commitMergeRestore(
        preparation: preparation,
        availableBytes: (_) async => 1 << 40,
        publishExclusive: (source, target) async {
          if (await FileSystemEntity.type(target.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            return false;
          }
          await source.rename(target.path);
          return true;
        },
      );
    } finally {
      await hold.release();
      await backup.dispose();
    }
    return (destination, destinationRoot);
  }

  test('UT-017 immutable query copy equality and hash include all remote filters and preserve caller tag drafts', () {
    final drafts = ['b', 'a', 'a'];
    final query = GalleryQuery.filtered(
      keyword: 'Straße',
      categoryId: 'category',
      tagIds: drafts,
      remoteTargetId: 'target',
      remoteService: ImageHostService.imgbb,
      remoteInputKind: UploadInputKind.processed,
      uploadFilter: GalleryUploadFilter.failed,
      sort: GallerySort.uploaded,
      ascending: true,
    );
    drafts.add('later');
    expect(query.tagIds, ['a', 'b']);
    expect(() => query.tagIds.add('mutate'), throwsUnsupportedError);
    final copy = query.copyWith();
    expect(copy, query);
    expect(copy.hashCode, query.hashCode);
    for (final different in [
      query.copyWith(remoteTargetId: null),
      query.copyWith(remoteService: null),
      query.copyWith(remoteInputKind: null),
      query.copyWith(uploadFilter: null),
    ]) {
      expect(different, isNot(query));
    }
    final reset = query.copyWith(
      keyword: '',
      categoryId: null,
      tagIds: [],
      remoteTargetId: null,
      remoteService: null,
      remoteInputKind: null,
      uploadFilter: null,
    );
    expect(reset.isUnfiltered, true);
    expect(query.normalizedKeyword, 'strasse');
  });

  test('UT-017/018 local Unicode name category tags format and favorite intersect the same remote failed scope', () async {
    final category = await repository.createCategory('Cafe\u0301 类别');
    await repository.updateOrganization(
      [a.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['Straße标签'],
      favorite: true,
    );
    await fail(a, cat);
    await succeed(b, cat);
    await fail(c, imgbb);
    final query = GalleryQuery.filtered(
      keyword: 'CAFÉ',
      categoryId: category.id,
      favoritesOnly: true,
      format: 'PNG',
      sourceType: 'file',
      remoteTargetId: cat,
      remoteService: ImageHostService.catbox,
      remoteInputKind: UploadInputKind.original,
      uploadFilter: GalleryUploadFilter.failed,
    );
    await matches(query, {a.id});
    await matches(query.copyWith(keyword: 'STRASSE'), {a.id});
    await matches(query.copyWith(remoteTargetId: imgbb), {});
    await matches(
      query.copyWith(uploadFilter: GalleryUploadFilter.confirmed),
      {},
    );
    await matches(const GalleryQuery(keyword: '系统文件'), {a.id, b.id, c.id});
    final tagId = (await repository.getAsset(a.id))!.tags.single.id;
    await matches(query.copyWith(keyword: '', tagIds: [tagId]), {a.id});
  });

  test('UT-017 remote target status service kind and URL keyword never combine evidence from different rows', () async {
    await fail(a, cat);
    await succeed(a, imgbb, slug: 'onlyImgUrl');
    final failed = GalleryQuery(
      remoteTargetId: cat,
      uploadFilter: GalleryUploadFilter.failed,
    );
    await matches(failed.copyWith(keyword: 'FROZENALPHA'), {a.id});
    await matches(failed.copyWith(keyword: 'CAFÉ STRASSE'), {a.id});
    await matches(failed.copyWith(keyword: 'onlyImgUrl'), {});
    await matches(failed.copyWith(keyword: 'FrozenBeta'), {});
    await matches(failed.copyWith(remoteService: ImageHostService.imgbb), {});
    await matches(
      failed.copyWith(remoteInputKind: UploadInputKind.processed),
      {},
    );
    await matches(
      const GalleryQuery(
        keyword: 'onlyimgurl',
        remoteService: ImageHostService.imgbb,
        uploadFilter: GalleryUploadFilter.confirmed,
      ),
      {a.id},
    );
    await matches(
      const GalleryQuery(
        keyword: 'catbox',
        uploadFilter: GalleryUploadFilter.failed,
      ),
      {a.id},
    );
  });

  test('UT-017 history target identities survive deletion and same-name replacement while current config names cannot rewrite frozen search', () async {
    await withClock(
      Clock.fixed(DateTime.utc(2026, 1, 1)),
      () => succeed(a, cat),
    );
    await repository.saveTarget(
      id: cat,
      service: ImageHostService.catbox,
      alias: '更新配置名称',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    await matches(GalleryQuery(keyword: 'FrozenAlpha', remoteTargetId: cat), {
      a.id,
    });
    await matches(GalleryQuery(keyword: '更新配置名称', remoteTargetId: cat), {});
    // New frozen evidence uses the updated alias at a distinct real timestamp.
    await withClock(Clock.fixed(DateTime.utc(2026, 1, 2)), () => fail(b, cat));
    await repository.removeTarget(cat);
    final replacement = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '更新配置名称',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    expect(replacement, isNot(cat));
    await matches(GalleryQuery(remoteTargetId: replacement), {});
    await matches(GalleryQuery(remoteTargetId: cat), {a.id, b.id});
    final targets = await repository.listGalleryRemoteTargets();
    expect(targets.map((t) => t.id), [cat]);
    expect(targets.single.alias, '更新配置名称');
    expect(targets.map((t) => t.id), isNot(contains(replacement)));
  });

  test('UT-017 content identity reuses confirmed evidence after clear-record and real reimport without binding the removed asset UUID', () async {
    await succeed(a, cat);
    final original = await File('${root.path}/${a.deviceCopy.relativePath}')
        .readAsBytes();
    await repository.removeAssets([a.id]);
    await repository.purgeAssets([a.id], confirmRecords: true);
    final imported = await repository.importResource(
      PlatformResource(
        displayName: '再次导入.png',
        openRead: () => Stream.value(original),
      ),
    );
    expect(imported.status, ImportStatus.saved);
    expect(imported.asset!.id, isNot(a.id));
    expect(imported.asset!.version.id, a.version.id);
    await matches(
      GalleryQuery(
        remoteTargetId: cat,
        uploadFilter: GalleryUploadFilter.confirmed,
      ),
      {imported.asset!.id},
    );
    expect(
      (await repository.getAsset(imported.asset!.id))!
          .confirmedRemoteResultCount,
      1,
    );
  });

  test('UT-017 processed result matches only a permanently saved same-digest version rather than its source asset', () async {
    final output = await ProcessingCoordinator(repository).process(
      [a.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        mode: ProcessingMode.sizeFirst,
        longestSide: 3,
      ),
      displayName: '永久处理.png',
    );
    final saved = await repository.saveOutput(output.id);
    expect(saved.status, ImportStatus.saved);
    expect(saved.asset!.version.sha256, isNot(a.version.sha256));
    await succeed(a, imgbb, outputId: output.id);
    final processed = GalleryQuery(
      remoteTargetId: imgbb,
      remoteInputKind: UploadInputKind.processed,
      uploadFilter: GalleryUploadFilter.confirmed,
    );
    await matches(processed, {saved.asset!.id});
    await matches(
      processed.copyWith(remoteInputKind: UploadInputKind.original),
      {},
    );
    expect((await repository.getAsset(a.id))!.lastConfirmedUploadAt, isNull);
    expect(
      (await repository.getAsset(saved.asset!.id))!.confirmedRemoteResultCount,
      1,
    );
  });

  test('UT-017 remote evidence requires both current content SHA and byte count without changing local asset identities', () async {
    final result = await succeed(a, cat);
    final failed = await fail(b, imgbb);
    mutate((db) {
      db.execute(
        'UPDATE remote_upload_results SET byte_count=byte_count+1 WHERE id=?',
        [result.id],
      );
      db.execute(
        'UPDATE upload_publications SET byte_count=byte_count+1 WHERE id=?',
        [failed.items.single.id],
      );
    });
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.confirmed),
      {},
    );
    await matches(
      GalleryQuery(
        remoteTargetId: imgbb,
        uploadFilter: GalleryUploadFilter.failed,
      ),
      {},
    );
    expect((await repository.getAsset(a.id))!.confirmedRemoteResultCount, 0);
    expect((await repository.getAsset(a.id))!.lastConfirmedUploadAt, isNull);
    mutate(
      (db) => db.execute(
        'UPDATE remote_upload_results SET byte_count=?,version_digest=? WHERE id=?',
        [a.version.byteCount, 'f' * 64, result.id],
      ),
    );
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.confirmed),
      {},
    );
    expect(
      (await repository.listAssets()).items.map((asset) => asset.id).toSet(),
      {a.id, b.id, c.id},
    );
  });

  test('UT-017 without links means no confirmation in the exact scope and scoped history must exist', () async {
    await succeed(a, cat);
    await fail(b, cat);
    await fail(b, imgbb, unknown: true);
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.withoutLinks),
      {b.id, c.id},
    );
    await matches(
      GalleryQuery(
        remoteTargetId: cat,
        uploadFilter: GalleryUploadFilter.withoutLinks,
      ),
      {b.id},
    );
    await matches(
      GalleryQuery(
        remoteTargetId: imgbb,
        uploadFilter: GalleryUploadFilter.withoutLinks,
      ),
      {b.id},
    );
    await matches(
      const GalleryQuery(
        remoteService: ImageHostService.catbox,
        uploadFilter: GalleryUploadFilter.withoutLinks,
      ),
      {b.id},
    );
    await matches(
      const GalleryQuery(
        remoteInputKind: UploadInputKind.processed,
        uploadFilter: GalleryUploadFilter.withoutLinks,
      ),
      {},
    );
    await matches(
      GalleryQuery(
        remoteTargetId: const Uuid().v4(),
        uploadFilter: GalleryUploadFilter.withoutLinks,
      ),
      {},
    );
    await matches(
      const GalleryQuery(
        keyword: '无远端 C',
        uploadFilter: GalleryUploadFilter.withoutLinks,
      ),
      {c.id},
    );
    await matches(
      const GalleryQuery(
        keyword: 'FrozenAlpha',
        uploadFilter: GalleryUploadFilter.withoutLinks,
      ),
      {b.id},
    );
  });

  test('UT-017 active statuses use real queued waiting paused interrupted and running publications', () async {
    final queued = await enqueue(a, cat);
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.active),
      {a.id},
    );
    await repository.setUploadBatchPaused(queued.id, true);
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.active),
      {a.id},
    );
    await repository.cancelUploadItems([queued.items.single.id]);
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.active),
      {},
    );
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.cancelled),
      {a.id},
    );
    final waiting = await enqueue(b, cat);
    await finish(
      await begin(waiting),
      const ProviderUploadFailure(
        UploadFailureKind.authorization,
        UploadDeliveryEvidence.confirmedRejected,
      ),
    );
    final interrupted = await enqueue(c, imgbb);
    await finish(
      await begin(interrupted),
      const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
      interrupted: true,
    );
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.active),
      {b.id, c.id},
    );
    final running = await enqueue(a, imgbb);
    final execution = await begin(running);
    try {
      await matches(
        GalleryQuery(
          remoteTargetId: imgbb,
          uploadFilter: GalleryUploadFilter.active,
        ),
        {a.id, c.id},
      );
    } finally {
      await finish(
        execution,
        const ProviderUploadUnknown(UploadFailureKind.protocol),
      );
    }
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.unknown),
      {a.id},
    );
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.active),
      {b.id, c.id},
    );
  });

  test('UT-017 late ordinary confirmation is independent of cancelled terminal intent and failed evidence can coexist', () async {
    final result = await succeed(a, cat, late: true);
    expect(result.late, true);
    await fail(a, imgbb);
    await matches(
      GalleryQuery(
        remoteTargetId: cat,
        uploadFilter: GalleryUploadFilter.confirmed,
      ),
      {a.id},
    );
    await matches(
      GalleryQuery(
        remoteTargetId: cat,
        uploadFilter: GalleryUploadFilter.cancelled,
      ),
      {a.id},
    );
    await matches(
      GalleryQuery(
        remoteTargetId: imgbb,
        uploadFilter: GalleryUploadFilter.failed,
      ),
      {a.id},
    );
    await matches(
      GalleryQuery(
        remoteTargetId: imgbb,
        uploadFilter: GalleryUploadFilter.confirmed,
      ),
      {},
    );
    final fresh = (await repository.getAsset(a.id))!;
    expect(fresh.lastConfirmedUploadAt, result.confirmedAt);
    expect(fresh.confirmedRemoteResultCount, 1);
  });

  test('UT-018 upload sort uses MAX actual UTC confirmation and keeps NULL last in both directions with UUID ties', () async {
    final early = DateTime.utc(2026, 1, 1), late = DateTime.utc(2026, 2, 2);
    await withClock(Clock.fixed(early), () => succeed(a, cat));
    await withClock(Clock.fixed(late), () => succeed(a, imgbb));
    await withClock(Clock.fixed(early), () => succeed(b, cat));
    await withClock(Clock.fixed(DateTime.utc(2026, 3, 3)), () => fail(a, cat));
    expect((await repository.getAsset(a.id))!.lastConfirmedUploadAt, late);
    expect((await repository.getAsset(a.id))!.confirmedRemoteResultCount, 2);
    expect((await repository.getAsset(c.id))!.lastConfirmedUploadAt, isNull);
    expect(
      (await repository.matchingAssetIds(
        query: const GalleryQuery(sort: GallerySort.uploaded, ascending: true),
      )),
      [b.id, a.id, c.id],
    );
    expect(
      (await repository.matchingAssetIds(
        query: const GalleryQuery(sort: GallerySort.uploaded),
      )),
      [a.id, b.id, c.id],
    );
    await withClock(Clock.fixed(late), () => succeed(b, imgbb));
    final tied = [a.id, b.id]..sort();
    for (final ascending in [true, false]) {
      expect(
        await repository.matchingAssetIds(
          query: GalleryQuery(sort: GallerySort.uploaded, ascending: ascending),
        ),
        [...tied, c.id],
      );
    }
  });

  test('UT-018 local ordinary removal updates MAX and count without fabricating a date from succeeded publication', () async {
    final earlyDate = DateTime.utc(2026, 1, 1),
        lateDate = DateTime.utc(2026, 2, 1);
    final early = await withClock(
      Clock.fixed(earlyDate),
      () => succeed(a, cat),
    );
    final late = await withClock(
      Clock.fixed(lateDate),
      () => succeed(a, imgbb),
    );
    await repository.removeLocalLinkResults([
      late.id,
    ], confirmLocalRemoval: true);
    var asset = (await repository.getAsset(a.id))!;
    expect(asset.lastConfirmedUploadAt, earlyDate);
    expect(asset.confirmedRemoteResultCount, 1);
    await repository.removeLocalLinkResults([
      early.id,
    ], confirmLocalRemoval: true);
    asset = (await repository.getAsset(a.id))!;
    expect(asset.lastConfirmedUploadAt, isNull);
    expect(asset.confirmedRemoteResultCount, 0);
    await matches(
      const GalleryQuery(uploadFilter: GalleryUploadFilter.confirmed),
      {},
    );
    await matches(
      GalleryQuery(
        remoteTargetId: cat,
        uploadFilter: GalleryUploadFilter.withoutLinks,
      ),
      {a.id},
    );
    expect(
      rows('upload_publications').every((r) => r['state'] == 'succeeded'),
      true,
    );
  });

  test('UT-017/018 sixty-row pagination count and complete UUID scope use exactly the same remote query', () async {
    final assets = [a, b, c];
    for (var i = 4; i <= 65; i++) {
      assets.add(await importImage('分页-$i.png', i));
    }
    for (final asset in assets) {
      await succeed(asset, cat);
    }
    await fail(a, imgbb);
    final query = GalleryQuery(
      remoteTargetId: cat,
      remoteService: ImageHostService.catbox,
      remoteInputKind: UploadInputKind.original,
      uploadFilter: GalleryUploadFilter.confirmed,
      sort: GallerySort.name,
      ascending: true,
    );
    final before = rows('assets');
    final first = await repository.listAssets(query: query, limit: 60);
    final second = await repository.listAssets(
      query: query,
      offset: 60,
      limit: 60,
    );
    final ids = await repository.matchingAssetIds(query: query);
    expect(first.total, 65);
    expect(second.total, 65);
    expect(first.items, hasLength(60));
    expect(second.items, hasLength(5));
    expect([...first.items, ...second.items].map((asset) => asset.id), ids);
    expect(ids.toSet(), assets.map((asset) => asset.id).toSet());
    expect(() => ids.add('unselected'), throwsUnsupportedError);
    expect(rows('assets'), before);
    await matches(query.copyWith(remoteService: ImageHostService.imgbb), {});
  });

  for (final mode in BackupMode.values) {
    test(
      'UT-017 ${mode.name} actual backup restore indexes imported terminal evidence without making queue tasks',
      () async {
        await fail(a, cat);
        await fail(b, imgbb, unknown: true);
        final cancelled = await enqueue(c, cat);
        await repository.cancelUploadItems([cancelled.items.single.id]);
        await succeed(a, imgbb);
        final (restored, destinationRoot) = await restore(mode);
        await matches(
          GalleryQuery(
            remoteTargetId: cat,
            uploadFilter: GalleryUploadFilter.failed,
          ),
          {a.id},
          owner: restored,
        );
        await matches(
          GalleryQuery(
            remoteTargetId: imgbb,
            uploadFilter: GalleryUploadFilter.unknown,
          ),
          {},
          owner: restored,
        );
        await matches(
          GalleryQuery(
            remoteTargetId: cat,
            uploadFilter: GalleryUploadFilter.cancelled,
          ),
          {c.id},
          owner: restored,
        );
        await matches(
          GalleryQuery(
            keyword: 'FrozenAlpha',
            remoteTargetId: cat,
            uploadFilter: GalleryUploadFilter.failed,
          ),
          {a.id},
          owner: restored,
        );
        await matches(
          GalleryQuery(
            remoteTargetId: imgbb,
            uploadFilter: GalleryUploadFilter.confirmed,
          ),
          {a.id},
          owner: restored,
        );
        expect(await restored.listUploadBatches(), isEmpty);
        final importedHistory = await restored.listImportedUploadHistories();
        expect(importedHistory, hasLength(3));
        expect(importedHistory.map((h) => h.state.name).toSet(), {
          'failed',
          'cancelled',
          'succeeded',
        });
        expect(importedHistory.any((h) => h.input.referenceId == b.id), false);
        expect(
          (await restored.listGalleryRemoteTargets()).map((t) => t.id).toSet(),
          {cat, imgbb},
        );
        expect(
          rows(
            'upload_publications',
            database: '${destinationRoot.path}/library.sqlite',
          ),
          isEmpty,
        );
        final asset = (await restored.getAsset(a.id))!;
        expect(asset.confirmedRemoteResultCount, 1);
        expect(
          await File('${destinationRoot.path}/${asset.deviceCopy.relativePath}')
              .exists(),
          mode == BackupMode.full,
        );
      },
    );
  }

  test('UT-017 SEC later credentials mask native and restored frozen alias before SQL keyword and count', () async {
    const future = 'FutureGalleryAliasSecret0123456789';
    await repository.saveTarget(
      id: cat,
      service: ImageHostService.catbox,
      alias: future,
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    await fail(a, cat);
    final (restored, destinationRoot) = await restore(BackupMode.metadata);
    await matches(GalleryQuery(keyword: future, remoteTargetId: cat), {a.id});
    await matches(GalleryQuery(keyword: future, remoteTargetId: cat), {
      a.id,
    }, owner: restored);
    for (final owner in [repository, restored]) {
      await owner.saveTarget(
        service: ImageHostService.imgbb,
        alias: '新凭据',
        anonymous: false,
        credential: future,
      );
      await matches(
        GalleryQuery(keyword: future, remoteTargetId: cat),
        {},
        owner: owner,
      );
      expect((await owner.listGalleryRemoteTargets()).single.alias, '[已隐藏]');
      await matches(
        GalleryQuery(
          keyword: '[已隐藏]',
          remoteTargetId: cat,
          uploadFilter: GalleryUploadFilter.failed,
        ),
        {a.id},
        owner: owner,
      );
    }
    expect(
      rows(
            'imported_upload_histories',
            database: '${destinationRoot.path}/library.sqlite',
          ).single['snapshot_json']
          as String,
      isNot(contains(future)),
    );
    await matches(
      const GalleryQuery(keyword: 'SyntheticGalleryCredential0123456789'),
      {},
    );
  });

  test('UT-017 SEC credential keyword cannot search older local names categories or tags and never rewrites those originals', () async {
    const future = 'FutureLocalGallerySecret0123456789';
    final named = await importImage('$future.png', 7);
    final category = await repository.createCategory('分类$future');
    await repository.updateOrganization(
      [named.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['标签$future'],
    );
    final before = (await repository.getAsset(named.id))!;
    await matches(const GalleryQuery(keyword: future), {named.id});
    await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '新秘密',
      anonymous: false,
      credential: future,
    );
    await matches(const GalleryQuery(keyword: future), {});
    final after = (await repository.getAsset(named.id))!;
    expect(after.displayName, before.displayName);
    expect(after.category, before.category);
    expect(after.tags, before.tags);
    expect(
      rows('assets').singleWhere((r) => r['id'] == named.id)['display_name'],
      '$future.png',
    );
  });

  test('UT-017 SEC malformed imported fragment fails explicitly and future snapshot blocks reopen without an empty-library overwrite', () async {
    await fail(a, cat);
    final (restored, destinationRoot) = await restore(BackupMode.metadata);
    final database = '${destinationRoot.path}/library.sqlite';
    final before = rows('assets', database: database);
    final original =
        rows(
              'imported_upload_histories',
              database: database,
            ).single['snapshot_json']
            as String;
    await matches(
      GalleryQuery(
        remoteTargetId: cat,
        uploadFilter: GalleryUploadFilter.failed,
      ),
      {a.id},
      owner: restored,
    );
    const malformed = '{broken';
    mutate(
      (db) => db.execute(
        'UPDATE imported_upload_histories SET snapshot_json=?',
        [malformed],
      ),
      database: database,
    );
    await expectLater(
      restored.listAssets(
        query: GalleryQuery(
          remoteTargetId: cat,
          uploadFilter: GalleryUploadFilter.failed,
        ),
      ),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      restored.matchingAssetIds(query: GalleryQuery(remoteTargetId: cat)),
      throwsA(isA<Exception>()),
    );
    expect(rows('assets', database: database), before);
    expect(
      rows(
        'imported_upload_histories',
        database: database,
      ).single['snapshot_json'],
      malformed,
    );
    mutate(
      (db) => db.execute(
        'UPDATE imported_upload_histories SET snapshot_json=?',
        [original],
      ),
      database: database,
    );
    await matches(
      GalleryQuery(
        remoteTargetId: cat,
        uploadFilter: GalleryUploadFilter.failed,
      ),
      {a.id},
      owner: restored,
    );
    final future = jsonEncode({'formatVersion': 999});
    mutate(
      (db) => db.execute(
        'UPDATE imported_upload_histories SET snapshot_json=?',
        [future],
      ),
      database: database,
    );
    await restored.close();
    await expectLater(
      LibraryRepository.open(destinationRoot, secretStore: QueueTestSecrets()),
      throwsA(isA<LibraryOpenException>()),
    );
    expect(rows('assets', database: database), before);
    expect(
      rows(
        'imported_upload_histories',
        database: database,
      ).single['snapshot_json'],
      future,
    );
    mutate(
      (db) => db.execute(
        'UPDATE imported_upload_histories SET snapshot_json=?',
        [original],
      ),
      database: database,
    );
    final reopened = await LibraryRepository.open(
      destinationRoot,
      secretStore: QueueTestSecrets(),
    );
    extraRepositories.add(reopened);
    await matches(
      GalleryQuery(
        remoteTargetId: cat,
        uploadFilter: GalleryUploadFilter.failed,
      ),
      {a.id},
      owner: reopened,
    );
  });
}
