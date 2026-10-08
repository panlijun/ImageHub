import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/gallery_query.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory sandbox;
  late Directory root;
  LibraryRepository? repository;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost_query_test_');
    root = Directory(p.join(sandbox.path, 'library'));
    repository = await LibraryRepository.open(root);
  });
  tearDown(() async {
    await repository?.close();
    repository = null;
    await sandbox.delete(recursive: true);
  });

  Future<ImageAsset> import(String name, int red) async {
    final image = img.Image(width: 3, height: 2, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(red, 30, 160, 255));
    final bytes = img.encodeBmp(image);
    final result = await repository!.importResource(
      PlatformResource(displayName: name, openRead: () => Stream.value(bytes)),
    );
    expect(result.status, ImportStatus.saved);
    return result.asset!;
  }

  Future<void> reopen() async {
    await repository!.close();
    repository = null;
    repository = await LibraryRepository.open(root);
  }

  Future<T> inspect<T>(T Function(Database) read) async {
    await repository!.close();
    repository = null;
    final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      return read(database);
    } finally {
      database.close();
      repository = await LibraryRepository.open(root);
    }
  }

  test('GalleryQuery immutable values, normalization and unfiltered state', () {
    const query = GalleryQuery(keyword: '  ÄBC图  ', favoritesOnly: true);
    expect(query.keyword, '  ÄBC图  ');
    expect(query.normalizedKeyword, 'äbc图');
    expect(query.isUnfiltered, false);
    expect(query, const GalleryQuery(keyword: '  ÄBC图  ', favoritesOnly: true));
    expect(
      query.hashCode,
      const GalleryQuery(keyword: '  ÄBC图  ', favoritesOnly: true).hashCode,
    );
    expect(
      query,
      isNot(const GalleryQuery(keyword: 'äbc图', favoritesOnly: true)),
    );
    expect(const GalleryQuery().isUnfiltered, true);
    expect(const GalleryQuery(keyword: ' \t ').isUnfiltered, true);
    expect(const GalleryQuery(favoritesOnly: true).isUnfiltered, false);
  });

  test(
    'UT-016 partial favorite changes preserve metadata and bytes across reopen',
    () async {
      final saved = await import('KeepName.BMP', 80);
      final other = await import('Other.BMP', 81);
      final category = await repository!.createCategory('keep');
      await repository!.assignCategory([saved.id], category.id);
      final before = (await repository!.getAsset(saved.id))!;
      final bytes = await (await repository!.originalFor(before)).readAsBytes();
      final versionRows = await inspect(
        (database) => database
            .select('SELECT * FROM versions ORDER BY id')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
      );
      final copyRows = await inspect(
        (database) => database
            .select('SELECT * FROM device_copies ORDER BY id')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
      );
      final updatedAt = DateTime.parse('2026-10-04T12:00:00Z');
      final favorite = await withClock(
        Clock.fixed(updatedAt),
        () => repository!.setFavorite(saved.id, true),
      );
      expect(favorite.favorite, true);
      expect(favorite.updatedAt, updatedAt);
      expect(favorite.id, before.id);
      expect(favorite.displayName, before.displayName);
      expect(favorite.importedAt, before.importedAt);
      expect(favorite.sourceType, before.sourceType);
      expect(favorite.category, before.category);
      expect(favorite.recycled, before.recycled);
      expect(favorite.version, before.version);
      expect(favorite.deviceCopy, before.deviceCopy);
      expect(await repository!.getAsset(other.id), other);
      await reopen();
      expect(await repository!.getAsset(saved.id), favorite);
      expect(
        await (await repository!.originalFor(favorite)).readAsBytes(),
        bytes,
      );
      await inspect((database) {
        expect(
          database
              .select('SELECT * FROM versions ORDER BY id')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
          versionRows,
        );
        expect(
          database
              .select('SELECT * FROM device_copies ORDER BY id')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
          copyRows,
        );
        expect(database.select('SELECT * FROM import_operations'), isEmpty);
      });
      final unfavorite = await repository!.setFavorite(saved.id, false);
      expect(unfavorite.favorite, false);
      await reopen();
      expect(await repository!.getAsset(saved.id), unfavorite);
    },
  );

  test('UT-016 partial serial favorite updates reject missing and recycled identities', () async {
    final saved = await import('Selected.BMP', 1);
    final recycled = await import('Recycled.BMP', 2);
    final updates = await Future.wait([
      repository!.setFavorite(saved.id, true),
      repository!.setFavorite(saved.id, false),
    ]);
    expect(updates.map((asset) => asset.favorite), [true, false]);
    expect((await repository!.getAsset(saved.id))!.favorite, false);
    await inspect((database) {
      database.execute('UPDATE assets SET recycled=1 WHERE id=?', [
        recycled.id,
      ]);
    });
    final before = await inspect(
      (database) => database
          .select('SELECT * FROM assets ORDER BY id')
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
    );
    for (final id in [
      'invalid-id',
      '00000000-0000-4000-8000-000000000000',
      recycled.id,
    ]) {
      await expectLater(repository!.setFavorite(id, true), throwsStateError);
      expect(await repository!.getAsset(id), isNull);
    }
    final after = await inspect(
      (database) => database
          .select('SELECT * FROM assets ORDER BY id')
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
    );
    expect(after, before);
    expect((await repository!.listAssets()).items.map((asset) => asset.id), [
      saved.id,
    ]);
    expect(await repository!.matchingAssetIds(), [saved.id]);
  });

  test('UT-017 partial Unicode name substring, literal percent/underscore and favorite intersection', () async {
    final fixtures = <ImageAsset>[];
    for (final entry in [
      'ÄBC_100%.BMP',
      'äbc-100x.BMP',
      '普通图片.BMP',
      'ABC_100%.BMP',
      "O'Reilly.BMP",
    ]) {
      fixtures.add(await import(entry, fixtures.length + 10));
    }
    await repository!.setFavorite(fixtures[0].id, true);
    await repository!.setFavorite(fixtures[2].id, true);
    Future<Set<String>> matches(GalleryQuery query) async {
      final page = await repository!.listAssets(query: query);
      final ids = await repository!.matchingAssetIds(query: query);
      expect(page.total, ids.length);
      expect(page.items.map((asset) => asset.id), ids);
      return ids.toSet();
    }

    expect(await matches(const GalleryQuery(keyword: '  ÄbC  ')), {
      fixtures[0].id,
      fixtures[1].id,
    });
    expect(await matches(const GalleryQuery(keyword: '%')), {
      fixtures[0].id,
      fixtures[3].id,
    });
    expect(await matches(const GalleryQuery(keyword: '_')), {
      fixtures[0].id,
      fixtures[3].id,
    });
    expect(await matches(const GalleryQuery(keyword: "O'REILLY")), {
      fixtures[4].id,
    });
    expect(await matches(const GalleryQuery(keyword: '通图')), {fixtures[2].id});
    expect(
      await matches(const GalleryQuery(keyword: 'ÄBC', favoritesOnly: true)),
      {fixtures[0].id},
    );
    expect(await matches(const GalleryQuery(favoritesOnly: true)), {
      fixtures[0].id,
      fixtures[2].id,
    });
    expect(
      await matches(
        const GalleryQuery(keyword: 'not found', favoritesOnly: true),
      ),
      isEmpty,
    );
    expect(
      await matches(const GalleryQuery(keyword: '  \t  ')),
      fixtures.map((asset) => asset.id).toSet(),
    );
    await reopen();
    expect(
      await matches(const GalleryQuery(keyword: 'ÄBC', favoritesOnly: true)),
      {fixtures[0].id},
    );
  });

  test('UT-017 partial database filtering before paging returns all 65 matching UUIDs in stable order', () async {
    final matches = <ImageAsset>[];
    for (var index = 0; index < 65; index++) {
      matches.add(
        await withClock(
          Clock.fixed(
            DateTime.parse(
              index == 0 ? '2026-10-04T01:00:00Z' : '2026-10-04T02:00:00Z',
            ),
          ),
          () => import('MATCH-$index.BMP', index),
        ),
      );
    }
    for (var index = 65; index < 70; index++) {
      await withClock(
        Clock.fixed(DateTime.parse('2026-10-04T03:00:00Z')),
        () => import('Unrelated-$index.BMP', index),
      );
    }
    matches.sort((a, b) {
      final byTime = b.importedAt.compareTo(a.importedAt);
      return byTime == 0 ? a.id.compareTo(b.id) : byTime;
    });
    final expected = matches.map((asset) => asset.id).toList();
    const query = GalleryQuery(keyword: 'match');
    final first = await repository!.listAssets(query: query);
    final second = await repository!.listAssets(offset: 60, query: query);
    final beyond = await repository!.listAssets(offset: 65, query: query);
    expect(first.total, 65);
    expect(first.items.map((asset) => asset.id), expected.take(60));
    expect(second.total, 65);
    expect(second.items.map((asset) => asset.id), expected.skip(60));
    expect(beyond.total, 65);
    expect(beyond.items, isEmpty);
    expect(await repository!.matchingAssetIds(query: query), expected);
    expect((await repository!.listAssets()).total, 70);
    expect(await repository!.matchingAssetIds(), hasLength(70));
    await reopen();
    expect(await repository!.matchingAssetIds(query: query), expected);
    expect(await repository!.getAsset(expected.last), matches.last);
  });

  test('Gallery page bounds remain enforced with filtered queries', () async {
    for (final invalid in [
      (offset: -1, limit: 60),
      (offset: 0, limit: 0),
      (offset: 0, limit: 61),
    ]) {
      await expectLater(
        repository!.listAssets(
          offset: invalid.offset,
          limit: invalid.limit,
          query: const GalleryQuery(keyword: 'x'),
        ),
        throwsArgumentError,
      );
    }
  });
}
