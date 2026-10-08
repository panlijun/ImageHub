import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/domain/organization_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory sandbox;
  late Directory root;
  late LibraryRepository repository;
  late List<int> bytes;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost_import_recycle_',
    );
    root = Directory(p.join(sandbox.path, 'library'));
    repository = await LibraryRepository.open(root);
    final image = img.Image(width: 3, height: 2);
    img.fill(image, color: img.ColorRgb8(19, 78, 171));
    bytes = img.encodePng(image);
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });
  Future<ImportResult> import([String name = 'fresh.png']) =>
      repository.importResource(
        PlatformResource(
          displayName: name,
          openRead: () => Stream.value(bytes),
        ),
      );
  Future<void> reopen() async {
    await repository.close();
    repository = await LibraryRepository.open(root);
  }

  test('Immutable asset tag snapshot cannot drift after creation', () async {
    final saved = (await import()).asset!;
    final draft = [const LibraryTag(id: 'tag', name: 'Keep')];
    final snapshot = ImageAsset(
      id: saved.id,
      displayName: saved.displayName,
      version: saved.version,
      deviceCopy: saved.deviceCopy,
      importedAt: saved.importedAt,
      updatedAt: saved.updatedAt,
      sourceType: saved.sourceType,
      tags: draft,
    );
    final hash = snapshot.hashCode;
    draft.clear();
    expect(snapshot.tags.single.name, 'Keep');
    expect(snapshot.hashCode, hash);
    expect(() => snapshot.tags.clear(), throwsUnsupportedError);
  });

  test(
    'UT-005 / LIB-008 retained orphan bytes reuse a new asset identity',
    () async {
      final original = (await import('old.png')).asset!;
      final file = await repository.originalFor(original);
      final category = await repository.createCategory('旧分类');
      await repository.updateOrganization(
        [original.id],
        setCategory: true,
        categoryId: category.id,
        replaceTags: ['旧标签'],
        favorite: true,
      );
      await repository.removeAssets([original.id]);
      await repository.purgeAssets([original.id], confirmRecords: true);
      expect(await file.readAsBytes(), bytes);
      final fresh = await import();
      expect(fresh.status, ImportStatus.saved);
      expect(fresh.asset!.id, isNot(original.id));
      expect(fresh.asset!.version, original.version);
      expect(fresh.asset!.deviceCopy, original.deviceCopy);
      expect(fresh.asset!.displayName, 'fresh.png');
      expect(fresh.asset!.favorite, false);
      expect(fresh.asset!.categoryId, isNull);
      expect(fresh.asset!.tags, isEmpty);
      await reopen();
      expect((await repository.listAssets()).items.single, fresh.asset);
      expect(
        await repository.getAsset(original.id, includeRecycled: true),
        isNull,
      );
      expect(await file.readAsBytes(), bytes);
      expect(
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => p.dirname(f.path) == p.join(root.path, 'staging')),
        isEmpty,
      );
    },
  );

  for (final damaged in [false, true]) {
    test(
      'UT-006 / LIB-008 orphan ${damaged ? 'damaged' : 'missing'} copy repaired without duplicate version',
      () async {
        final original = (await import()).asset!;
        final file = await repository.originalFor(original);
        await repository.removeAssets([original.id]);
        await repository.purgeAssets([original.id], confirmRecords: true);
        if (damaged) {
          await file.writeAsBytes([1, 2, 3], flush: true);
        } else {
          await file.delete();
        }
        final fresh = await import();
        expect(fresh.status, ImportStatus.saved);
        expect(fresh.asset!.id, isNot(original.id));
        expect(fresh.asset!.version, original.version);
        expect(fresh.asset!.deviceCopy.id, original.deviceCopy.id);
        expect(
          await (await repository.originalFor(fresh.asset!)).readAsBytes(),
          bytes,
        );
        await reopen();
        expect((await repository.listAssets()).total, 1);
      },
    );
  }

  test(
    'UT-005 shared content chooses active asset before recycled duplicate',
    () async {
      final original = (await import()).asset!;
      await repository.removeAssets([original.id]);
      await repository.close();
      final activeId = const Uuid().v4();
      final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
      db.execute('PRAGMA foreign_keys=ON');
      db.execute(
        'INSERT INTO assets(id,display_name,version_id,imported_utc,updated_utc,source_type) VALUES (?,?,?,?,?,?)',
        [activeId, 'active.png', original.version.id, 1, 1, 'file'],
      );
      db.close();
      repository = await LibraryRepository.open(root);
      final result = await import();
      expect(result.status, ImportStatus.duplicate);
      expect(result.asset!.id, activeId);
      expect(
        (await repository.getAsset(
          original.id,
          includeRecycled: true,
        ))!.recycled,
        true,
      );
    },
  );

  test('UT-028 / LIB-008 repair cannot replace a leased source path', () async {
    final original = (await import()).asset!;
    final lease = await repository.acquireAssetLease([
      original.id,
    ], purpose: 'processing');
    final file = File(lease.pathsByVersion[original.version.id]!);
    await file.writeAsBytes([7, 8, 9], flush: true);
    try {
      final rejected = await import();
      expect(rejected.status, ImportStatus.failed);
      expect(rejected.failure!.kind, FailureKind.activeUse);
      expect(await file.readAsBytes(), [7, 8, 9]);
      expect(
        (await repository.getAsset(original.id))!.deviceCopy,
        original.deviceCopy,
      );
    } finally {
      await lease.release();
    }
    final repaired = await import();
    expect(repaired.status, ImportStatus.repaired);
    expect(repaired.asset!.id, original.id);
    expect(
      await (await repository.originalFor(repaired.asset!)).readAsBytes(),
      bytes,
    );
  });

  test(
    'UT-010 reused-commit cleanup journal is validated and recovered',
    () async {
      final saved = (await import()).asset!;
      await repository.close();
      final operationId = const Uuid().v4();
      final stage = File(p.join(root.path, 'staging', '$operationId.part'));
      await stage.writeAsBytes(bytes, flush: true);
      final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
      db.execute(
        'INSERT INTO import_operations(id,asset_id,version_id,copy_id,stage_path,final_path,display_name,source_type,created_utc,phase,digest,byte_count,format,width,height,frame_count,orientation) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          operationId,
          saved.id,
          saved.version.id,
          saved.deviceCopy.id,
          'staging/$operationId.part',
          'originals/$operationId.original',
          saved.displayName,
          saved.sourceType,
          saved.importedAt.millisecondsSinceEpoch,
          'committedReuse',
          saved.version.sha256,
          saved.version.byteCount,
          saved.version.format,
          saved.version.width,
          saved.version.height,
          saved.version.frameCount,
          saved.version.orientation,
        ],
      );
      db.close();
      repository = await LibraryRepository.open(root);
      expect(repository.recoveryIssues, isEmpty);
      expect(repository.recoveredImportCount, 1);
      expect(await stage.exists(), false);
      expect((await repository.listAssets()).items.single, saved);
      expect(await (await repository.originalFor(saved)).readAsBytes(), bytes);
      await reopen();
      expect(repository.recoveredImportCount, 0);
    },
  );
}
