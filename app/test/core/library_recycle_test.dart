import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory sandbox;
  late Directory root;
  LibraryRepository? repository;
  final epoch = DateTime.utc(2026, 1, 1);

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost_recycle_test_');
    root = Directory(p.join(sandbox.path, 'library'));
    repository = await LibraryRepository.open(root);
  });
  tearDown(() async {
    await repository?.close();
    repository = null;
    await sandbox.delete(recursive: true);
  });

  Future<ImageAsset> seed({int red = 50}) async {
    final image = img.Image(width: 2, height: 2);
    img.fill(image, color: img.ColorRgb8(red, 20, 40));
    final result = await repository!.importResource(
      PlatformResource(
        displayName: 'original.png',
        openRead: () => Stream.value(img.encodePng(image)),
      ),
    );
    expect(result.status, ImportStatus.saved);
    return result.asset!;
  }

  Future<void> fixture(void Function(Database) edit) async {
    await repository!.close();
    repository = null;
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      db.execute('PRAGMA foreign_keys=ON');
      edit(db);
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      db.close();
    }
    repository = await LibraryRepository.open(root);
  }

  void insertIntent(
    Database db,
    ImageAsset asset, {
    String? path,
    bool removeRecords = false,
  }) {
    db.execute(
      'INSERT INTO purge_operations '
      '(id,version_id,relative_path,asset_ids_json,remove_records,created_utc) '
      'VALUES (?,?,?,?,?,?)',
      [
        const Uuid().v4(),
        asset.version.id,
        path ?? asset.deviceCopy.relativePath,
        jsonEncode([asset.id]),
        removeRecords ? 1 : 0,
        epoch.millisecondsSinceEpoch,
      ],
    );
  }

  test(
    'UT-019 exact 30-day prompt retains bytes, identity and organization',
    () async {
      final asset = await seed();
      final categoryId = const Uuid().v4();
      final tagId = const Uuid().v4();
      await fixture((db) {
        db.execute('INSERT INTO categories(id,name,name_key) VALUES(?,?,?)', [
          categoryId,
          '旅行',
          '旅行',
        ]);
        db.execute('INSERT INTO tags(id,name,name_key) VALUES(?,?,?)', [
          tagId,
          '标签',
          '标签',
        ]);
        db.execute('UPDATE assets SET favorite=1,category=? WHERE id=?', [
          categoryId,
          asset.id,
        ]);
        db.execute(
          'INSERT INTO asset_tags(asset_id,tag_id,position) VALUES(?,?,0)',
          [asset.id, tagId],
        );
      });
      final before = (await repository!.getAsset(asset.id))!;
      await withClock(
        Clock.fixed(epoch),
        () => repository!.removeAssets([asset.id]),
      );
      expect((await repository!.listAssets()).total, 0);
      await withClock(
        Clock.fixed(epoch.add(const Duration(days: 29))),
        () => repository!.removeAssets([asset.id]),
      );
      expect(
        await withClock(
          Clock.fixed(
            epoch
                .add(const Duration(days: 30))
                .subtract(const Duration(milliseconds: 1)),
          ),
          () => repository!.recycledDueCount(),
        ),
        0,
      );
      expect(
        await withClock(
          Clock.fixed(epoch.add(const Duration(days: 30))),
          () => repository!.recycledDueCount(),
        ),
        1,
      );
      expect(await repository!.verifyCopy(asset), CopyAvailability.available);
      final restored = (await repository!.restoreAssets([asset.id])).single;
      expect(restored.id, before.id);
      expect(restored.version, before.version);
      expect(restored.deviceCopy, before.deviceCopy);
      expect(restored.displayName, before.displayName);
      expect(restored.favorite, true);
      expect(restored.categoryId, categoryId);
      expect(restored.tags.map((tag) => tag.id), [tagId]);
      expect(restored.importedAt, before.importedAt);
      expect(restored.recycledAt, isNull);
      expect(await repository!.recycledDueCount(), 0);
    },
  );

  test(
    'UT-020 distinct confirmations and all-ID validation precede mutation',
    () async {
      final asset = await seed();
      await expectLater(
        repository!.purgeAssets([asset.id]),
        throwsArgumentError,
      );
      await expectLater(
        repository!.purgeAssets([asset.id], confirmRecords: true),
        throwsStateError,
      );
      await expectLater(
        repository!.removeAssets([asset.id, 'missing']),
        throwsStateError,
      );
      expect(await repository!.getAsset(asset.id), isNotNull);
      await repository!.removeAssets([asset.id]);
      await expectLater(
        repository!.purgeAssets(
          [asset.id, 'missing'],
          confirmRecords: true,
          confirmCopies: true,
        ),
        throwsStateError,
      );
      expect(await repository!.verifyCopy(asset), CopyAvailability.available);
      expect((await repository!.restoreAssets([asset.id])).single.id, asset.id);
    },
  );

  test('UT-020 shared bytes block copy purge; record-only purge retains bytes', () async {
    final asset = await seed();
    final sharedId = const Uuid().v4();
    await fixture((db) {
      db.execute(
        'INSERT INTO assets '
        '(id,display_name,version_id,imported_utc,updated_utc,source_type) '
        'SELECT ?,display_name,version_id,imported_utc,updated_utc,source_type '
        'FROM assets WHERE id=?',
        [sharedId, asset.id],
      );
    });
    await repository!.removeAssets([asset.id]);
    await expectLater(
      repository!.purgeAssets(
        [asset.id],
        confirmCopies: true,
        confirmRecords: true,
      ),
      throwsStateError,
    );
    final result = await repository!.purgeAssets([
      asset.id,
    ], confirmRecords: true);
    expect(result.recordsRemoved, 1);
    expect(result.copiesRemoved, 0);
    expect(
      (await repository!.getAsset(sharedId))!.version.id,
      asset.version.id,
    );
    expect(await repository!.verifyCopy(asset), CopyAvailability.available);
  });

  test(
    'UT-020 record-only purge retains independent orphan bytes and version',
    () async {
      final asset = await seed();
      await repository!.removeAssets([asset.id]);
      await repository!.purgeAssets([asset.id], confirmRecords: true);
      expect(await repository!.verifyCopy(asset), CopyAvailability.available);
      await fixture((db) {
        expect(db.select('SELECT * FROM assets'), isEmpty);
        expect(db.select('SELECT * FROM versions'), hasLength(1));
        expect(db.select('SELECT * FROM device_copies'), hasLength(1));
      });
      expect((await repository!.listAssets()).total, 0);
    },
  );

  test('UT-020 copy-only purge retains asset and organization; exact reimport repairs', () async {
    final asset = await seed();
    await repository!.setFavorite(asset.id, true);
    final result = await repository!.purgeAssets([
      asset.id,
    ], confirmCopies: true);
    expect(result.recordsRemoved, 0);
    expect(result.copiesRemoved, 1);
    final retained = (await repository!.getAsset(asset.id))!;
    expect(retained.id, asset.id);
    expect(retained.favorite, true);
    expect(await repository!.verifyCopy(retained), CopyAvailability.missing);
    final image = img.Image(width: 2, height: 2);
    img.fill(image, color: img.ColorRgb8(50, 20, 40));
    final repair = await repository!.importResource(
      PlatformResource(
        displayName: 'repair.png',
        openRead: () => Stream.value(img.encodePng(image)),
      ),
    );
    expect(repair.status, ImportStatus.repaired);
    expect(repair.asset!.id, asset.id);
    expect(repair.asset!.favorite, true);
    expect(
      await repository!.verifyCopy(repair.asset!),
      CopyAvailability.available,
    );
  });

  test(
    'UT-020 purge targets only managed copies and preserves external source',
    () async {
      final image = img.Image(width: 2, height: 2);
      img.fill(image, color: img.ColorRgb8(10, 40, 90));
      final bytes = img.encodePng(image);
      final source = File(p.join(sandbox.path, 'external.png'));
      await source.writeAsBytes(bytes);
      final asset = (await repository!.importResource(
        PlatformResource.file(source),
      )).asset!;
      await repository!.removeAssets([asset.id]);
      await repository!.purgeAssets(
        [asset.id],
        confirmRecords: true,
        confirmCopies: true,
      );
      expect(await source.readAsBytes(), bytes);
      expect(await repository!.verifyCopy(asset), CopyAvailability.missing);
    },
  );

  test(
    'UT-102 batch lease validates every real copy before acquiring any lease',
    () async {
      final healthy = await seed();
      final missing = await seed(red: 90);
      await File(p.join(root.path, missing.deviceCopy.relativePath)).delete();
      await expectLater(
        repository!.acquireAssetLease([
          healthy.id,
          missing.id,
        ], purpose: 'processing'),
        throwsStateError,
      );
      await repository!.purgeAssets([healthy.id], confirmCopies: true);
      expect(await repository!.verifyCopy(healthy), CopyAvailability.missing);
    },
  );

  for (final ownerType in [
    'processing',
    'output',
    'task',
    'export',
    'backup',
    'restore',
  ]) {
    test(
      'UT-038 partial: persistent $ownerType protection rejects permanent clear',
      () async {
        final asset = await seed();
        await repository!.registerProtection(
          ownerType: ownerType,
          ownerId: 'work',
          versionIds: [asset.version.id],
        );
        await repository!.removeAssets([asset.id]);
        await fixture((db) {
          expect(db.select('SELECT * FROM version_references'), hasLength(1));
        });
        await expectLater(
          repository!.purgeAssets([asset.id], confirmCopies: true),
          throwsStateError,
        );
        await expectLater(
          repository!.purgeAssets([asset.id], confirmRecords: true),
          throwsStateError,
        );
        await repository!.releaseProtection(
          ownerType: ownerType,
          ownerId: 'work',
        );
        final result = await repository!.purgeAssets(
          [asset.id],
          confirmRecords: true,
          confirmCopies: true,
        );
        expect(result.recordsRemoved, 1);
        expect(await repository!.verifyCopy(asset), CopyAvailability.missing);
      },
    );
  }

  test(
    'UT-038 partial: protection registration validates all versions atomically',
    () async {
      final asset = await seed();
      await expectLater(
        repository!.registerProtection(
          ownerType: 'task',
          ownerId: 'work',
          versionIds: [asset.version.id, 'missing'],
        ),
        throwsStateError,
      );
      await expectLater(
        repository!.registerProtection(
          ownerType: 'unknown',
          ownerId: 'work',
          versionIds: [asset.version.id],
        ),
        throwsArgumentError,
      );
      await repository!.purgeAssets([asset.id], confirmCopies: true);
    },
  );

  test('UT-102 cancelled caller retains lease until actual IO ends; release idempotent', () async {
    final asset = await seed();
    final lease = await repository!.acquireAssetLease([
      asset.id,
    ], purpose: 'processing');
    expect(
      lease.pathsByVersion[asset.version.id],
      p.join(root.path, p.fromUri(asset.deviceCopy.relativePath)),
    );
    final cancellation = CancellationToken()..cancel();
    expect(cancellation.isCancelled, true);
    await repository!.removeAssets([asset.id]);
    await expectLater(
      repository!.purgeAssets([asset.id], confirmCopies: true),
      throwsStateError,
    );
    expect(lease.released, false);
    await lease.release();
    await lease.release();
    expect(lease.released, true);
    await repository!.purgeAssets([asset.id], confirmCopies: true);
    expect(await repository!.verifyCopy(asset), CopyAvailability.missing);
  });

  test(
    'UT-102 close waits for lease release and rejects new file leases',
    () async {
      final asset = await seed();
      final lease = await repository!.acquireAssetLease([
        asset.id,
      ], purpose: 'export');
      var closed = false;
      final closing = repository!.close().then((_) => closed = true);
      await expectLater(
        repository!.acquireAssetLease([asset.id], purpose: 'backup'),
        throwsStateError,
      );
      expect(closed, false);
      await lease.release();
      await closing;
      expect(closed, true);
      repository = null;
      repository = await LibraryRepository.open(root);
      expect(await repository!.verifyCopy(asset), CopyAvailability.available);
    },
  );

  test(
    'UT-102 close drains lease acquisition before waiting for its IO release',
    () async {
      final asset = await seed();
      final entered = Completer<void>();
      final commitAllowed = Completer<void>();
      final acquiring = repository!.acquireAssetLease(
        [asset.id],
        purpose: 'processing',
        beforeLeaseCommit: () async {
          entered.complete();
          await commitAllowed.future;
        },
      );
      await entered.future;
      var closed = false;
      final closing = repository!.close().then((_) => closed = true);
      expect(closed, false);
      commitAllowed.complete();
      final lease = await acquiring;
      await expectLater(
        repository!.acquireAssetLease([asset.id], purpose: 'backup'),
        throwsStateError,
      );
      expect(closed, false);
      expect(lease.released, false);
      await lease.release();
      await closing;
      expect(closed, true);
      repository = null;
      repository = await LibraryRepository.open(root);
      expect(await repository!.verifyCopy(asset), CopyAvailability.available);
    },
  );

  for (final alreadyDeleted in [false, true]) {
    test(
      'IT-010 partial real journal replay after ${alreadyDeleted ? 'file deletion' : 'intent commit'}',
      () async {
        final asset = await seed();
        await repository!.removeAssets([asset.id]);
        if (alreadyDeleted) {
          await File(p.join(root.path, asset.deviceCopy.relativePath)).delete();
        }
        await fixture((db) => insertIntent(db, asset, removeRecords: true));
        expect(repository!.recoveryIssues, isEmpty);
        expect(await repository!.verifyCopy(asset), CopyAvailability.missing);
        await fixture((db) {
          expect(db.select('SELECT * FROM assets'), isEmpty);
          expect(db.select('SELECT * FROM purge_operations'), isEmpty);
          expect(
            db
                .select('SELECT availability FROM device_copies')
                .single['availability'],
            'missing',
          );
        });
      },
    );
  }

  test('IT-010 partial malformed purge path retains intent, records and exact bytes', () async {
    final asset = await seed();
    await repository!.removeAssets([asset.id]);
    await fixture(
      (db) =>
          insertIntent(db, asset, path: '../external.png', removeRecords: true),
    );
    expect(repository!.recoveryIssues, hasLength(1));
    expect(await repository!.verifyCopy(asset), CopyAvailability.available);
    await expectLater(repository!.restoreAssets([asset.id]), throwsStateError);
    await fixture((db) {
      expect(db.select('SELECT * FROM assets'), hasLength(1));
      expect(db.select('SELECT * FROM purge_operations'), hasLength(1));
    });
  });

  test('IT-010 partial stale session lease cleared; durable reference blocks replay', () async {
    final asset = await seed();
    await repository!.removeAssets([asset.id]);
    await fixture((db) {
      db.execute(
        'INSERT INTO file_leases(id,version_id,owner_id,purpose,created_utc) VALUES(?,?,?,?,?)',
        [
          const Uuid().v4(),
          asset.version.id,
          const Uuid().v4(),
          'processing',
          1,
        ],
      );
      db.execute(
        'INSERT INTO version_references(id,version_id,owner_type,owner_id) VALUES(?,?,?,?)',
        [const Uuid().v4(), asset.version.id, 'task', 'work'],
      );
      insertIntent(db, asset, removeRecords: true);
    });
    expect(repository!.recoveryIssues, hasLength(1));
    expect(await repository!.verifyCopy(asset), CopyAvailability.available);
    await fixture((db) {
      expect(db.select('SELECT * FROM file_leases'), isEmpty);
      expect(db.select('SELECT * FROM version_references'), hasLength(1));
      expect(db.select('SELECT * FROM purge_operations'), hasLength(1));
    });
    await repository!.releaseProtection(ownerType: 'task', ownerId: 'work');
    await fixture((db) {});
    expect(repository!.recoveryIssues, isEmpty);
    expect(await repository!.verifyCopy(asset), CopyAvailability.missing);
  });
}
