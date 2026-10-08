import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/gallery_query.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/domain/organization_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory sandbox;
  late Directory root;
  LibraryRepository? repository;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost_organization_');
    root = Directory(p.join(sandbox.path, 'library'));
    repository = await LibraryRepository.open(root);
  });
  tearDown(() async {
    await repository?.close();
    repository = null;
    await sandbox.delete(recursive: true);
  });

  Future<void> reopen() async {
    await repository!.close();
    repository = null;
    repository = await LibraryRepository.open(root);
  }

  Future<ImageAsset> import(
    String name,
    int red, {
    String format = 'BMP',
    String source = 'file',
    int width = 3,
  }) async {
    final picture = img.Image(width: width, height: 2, numChannels: 4);
    img.fill(picture, color: img.ColorRgba8(red, 30, 160, 255));
    final bytes = format == 'PNG'
        ? img.encodePng(picture)
        : img.encodeBmp(picture);
    final result = await repository!.importResource(
      PlatformResource(
        displayName: name,
        sourceType: source,
        openRead: () => Stream.value(bytes),
      ),
    );
    expect(result.status, ImportStatus.saved);
    return result.asset!;
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    await repository!.close();
    repository = null;
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      return {
        for (final table in [
          'assets',
          'versions',
          'device_copies',
          'categories',
          'tags',
          'asset_tags',
        ])
          table: db
              .select('SELECT * FROM $table ORDER BY rowid')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
      };
    } finally {
      db.close();
      repository = await LibraryRepository.open(root);
    }
  }

  Future<List<String>> assertQuery(
    GalleryQuery query,
    Set<String> expected,
  ) async {
    final all = await repository!.matchingAssetIds(query: query);
    expect(all.toSet(), expected);
    final pages = <String>[];
    for (var offset = 0; offset <= all.length; offset += 2) {
      final page = await repository!.listAssets(
        query: query,
        offset: offset,
        limit: 2,
      );
      expect(page.total, expected.length);
      pages.addAll(page.items.map((asset) => asset.id));
    }
    expect(pages, all);
    return all;
  }

  test(
    'UT-016 category NFC/full folding reuse preserves first display and UUID',
    () async {
      final first = await repository!.createCategory('  Straße  ');
      final folded = await repository!.createCategory('STRASSE');
      expect(folded.id, first.id);
      expect(folded.name, 'Straße');
      final nfc = await repository!.createCategory(' Cafe\u0301 ');
      expect(nfc.name, 'Café');
      expect((await repository!.createCategory('CAFÉ')).id, nfc.id);
      expect(
        first.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      await reopen();
      expect((await repository!.listCategories()).map((c) => c.name).toSet(), {
        'Straße',
        'Café',
      });
      expect((await repository!.createCategory('strasse')).id, first.id);
    },
  );

  test('UT-016 rename collision rolls back and remove keeps bytes, identities, tags, favorite', () async {
    final a = await import('a.bmp', 1);
    final b = await import('b.bmp', 2);
    final x = await repository!.createCategory('X');
    final y = await repository!.createCategory('Straße');
    await repository!.updateOrganization(
      [a.id, b.id],
      setCategory: true,
      categoryId: x.id,
      replaceTags: ['Keep'],
      favorite: true,
    );
    final before = await snapshot();
    await expectLater(
      repository!.renameCategory(x.id, 'STRASSE'),
      throwsA(isA<LibraryMutationException>()),
    );
    expect(await snapshot(), before);
    await repository!.renameCategory(x.id, 'Renamed');
    final renamed = (await repository!.getAsset(a.id))!;
    expect(renamed.category, 'Renamed');
    expect(renamed.categoryId, x.id);
    final bytes = await (await repository!.originalFor(a)).readAsBytes();
    await repository!.removeCategory(x.id);
    await reopen();
    for (final original in [a, b]) {
      final current = (await repository!.getAsset(original.id))!;
      expect(current.category, isNull);
      expect(current.categoryId, isNull);
      expect(current.version, original.version);
      expect(current.deviceCopy, original.deviceCopy);
      expect(current.favorite, true);
      expect(current.tags.map((t) => t.name), ['Keep']);
      expect(await repository!.verifyCopy(current), CopyAvailability.available);
    }
    expect(await (await repository!.originalFor(a)).readAsBytes(), bytes);
    expect((await repository!.listCategories()).single.id, y.id);
  });

  test(
    'UT-014 first global tag display reuse and normalized remove are persisted',
    () async {
      final a = await import('a.bmp', 1);
      final b = await import('b.bmp', 2);
      await repository!.replaceTags(
        [a.id],
        [' Straße ', 'Cafe\u0301', 'STRASSE'],
      );
      await repository!.replaceTags([b.id], ['strasse', 'CAFÉ']);
      final first = (await repository!.getAsset(a.id))!;
      final second = (await repository!.getAsset(b.id))!;
      expect(first.tags.map((t) => t.name), ['Straße', 'Café']);
      expect(second.tags, first.tags);
      await repository!.removeTags([b.id], ['STRASSE']);
      await reopen();
      expect((await repository!.getAsset(b.id))!.tags, [first.tags.last]);
      expect((await repository!.getAsset(a.id))!.tags, first.tags);
      expect(await repository!.listTags(), hasLength(2));
    },
  );

  test('UT-015 50 succeeds, 51 in one batch member rolls back catalog and all assets', () async {
    final a = await import('a.bmp', 1);
    final b = await import('b.bmp', 2);
    await repository!.replaceTags([a.id], ['Original']);
    await repository!.replaceTags([b.id], List.generate(50, (i) => 'Tag$i'));
    expect((await repository!.getAsset(b.id))!.tags, hasLength(50));
    final before = await snapshot();
    await expectLater(
      repository!.updateOrganization(
        [a.id, b.id],
        addTags: ['New'],
        favorite: true,
      ),
      throwsFormatException,
    );
    expect(await snapshot(), before);
    await expectLater(
      repository!.replaceTags([a.id], List.generate(51, (i) => 'Fresh$i')),
      throwsFormatException,
    );
    expect(await snapshot(), before);
  });

  test('UT-015 Unicode scalar boundaries and blank names reject without partial writes', () async {
    final a = await import('a.bmp', 1);
    final max = List.filled(64, '😀').join();
    await repository!.replaceTags([a.id], ['x', max]);
    expect((await repository!.getAsset(a.id))!.tags.map((t) => t.name), [
      'x',
      max,
    ]);
    await repository!.createCategory(max);
    final before = await snapshot();
    for (final invalid in ['   ', '$max😀']) {
      await expectLater(
        repository!.replaceTags([a.id], ['Valid', invalid]),
        throwsFormatException,
      );
      await expectLater(
        repository!.createCategory(invalid),
        throwsFormatException,
      );
      expect(await snapshot(), before);
    }
  });

  test(
    'UT-016 absent/recycled asset and missing category reject whole mutation',
    () async {
      final a = await import('a.bmp', 1);
      final b = await import('b.bmp', 2);
      final category = await repository!.createCategory('Keep');
      await repository!.assignCategory([a.id], category.id);
      await repository!.removeAssets([b.id]);
      final before = await snapshot();
      for (final invalidId in ['missing', b.id]) {
        await expectLater(
          repository!.updateOrganization(
            [a.id, invalidId],
            replaceTags: ['New'],
            favorite: true,
            setCategory: true,
            categoryId: category.id,
          ),
          throwsA(isA<LibraryMutationException>()),
        );
        expect(await snapshot(), before);
      }
      await expectLater(
        repository!.updateOrganization(
          [a.id],
          replaceTags: ['New'],
          favorite: true,
          setCategory: true,
          categoryId: 'missing',
        ),
        throwsA(isA<LibraryMutationException>()),
      );
      expect(await snapshot(), before);
    },
  );

  test('UT-017 partial AND category/tags/source/format/availability/favorite query shares count, pages, UUIDs', () async {
    final category = await repository!.createCategory('Target');
    final other = await repository!.createCategory('Other');
    final assets = <ImageAsset>[];
    for (var i = 0; i < 9; i++) {
      final a = await import(
        'Item$i',
        i + 1,
        format: i == 3 ? 'BMP' : 'PNG',
        source: i == 4 ? 'photo' : 'file',
      );
      assets.add(a);
      await repository!.updateOrganization(
        [a.id],
        setCategory: true,
        categoryId: i == 5 ? other.id : category.id,
        replaceTags: i == 6 ? ['First'] : ['First', 'Second'],
        favorite: i != 7,
      );
    }
    final missingFile = await repository!.originalFor(assets[2]);
    await missingFile.delete();
    await repository!.refreshCopyStatuses();
    final tags = await repository!.listTags();
    final query = GalleryQuery.filtered(
      categoryId: category.id,
      tagIds: tags.map((t) => t.id),
      sourceType: 'file',
      format: 'PNG',
      availability: CopyAvailability.available,
      favoritesOnly: true,
    );
    expect(
      await assertQuery(query, {assets[0].id, assets[1].id, assets[8].id}),
      hasLength(3),
    );
    await assertQuery(query.copyWith(availability: CopyAvailability.missing), {
      assets[2].id,
    });
    await reopen();
    await assertQuery(query, {assets[0].id, assets[1].id, assets[8].id});
  });

  test('UT-017 partial NFC/fullfold searches name, category, tag, source, and actual format', () async {
    final a = await import('Straße-Cafe\u0301', 1, format: 'PNG');
    final b = await import('Different', 2, source: 'photo');
    final category = await repository!.createCategory('文章');
    await repository!.updateOrganization(
      [a.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['工作'],
    );
    for (final keyword in ['STRASSE', 'CAFÉ', '文章', '工作', 'png']) {
      await assertQuery(GalleryQuery(keyword: keyword), {a.id});
    }
    await assertQuery(const GalleryQuery(keyword: '系统照片'), {b.id});
    await assertQuery(const GalleryQuery(keyword: 'FILE'), {a.id});
  });

  test('UT-018 name/size sort direction uses UUID tie-break across pages and restart', () async {
    final assets = [
      await import('Zulu', 1, width: 8),
      await import('alpha', 2),
      await import('ALPHA', 3),
      await import('Beta', 4, width: 5),
    ];
    for (final ascending in [true, false]) {
      for (final sort in [GallerySort.name, GallerySort.size]) {
        final expected = [...assets]
          ..sort((a, b) {
            final c = sort == GallerySort.name
                ? a.displayName.toLowerCase().compareTo(
                    b.displayName.toLowerCase(),
                  )
                : a.version.byteCount.compareTo(b.version.byteCount);
            return c == 0
                ? a.id.compareTo(b.id)
                : ascending
                ? c
                : -c;
          });
        final query = GalleryQuery(sort: sort, ascending: ascending);
        expect(
          await assertQuery(query, assets.map((a) => a.id).toSet()),
          expected.map((a) => a.id),
        );
        await reopen();
        expect(
          await repository!.matchingAssetIds(query: query),
          expected.map((a) => a.id),
        );
      }
    }
  });

  test('UT-012 partial / IT-001 real missing/damaged bytes refresh and persist after restart', () async {
    final healthy = await import('healthy', 1);
    final missing = await import('missing', 2);
    final damaged = await import('damaged', 3);
    await (await repository!.originalFor(missing)).delete();
    final damagedFile = await repository!.originalFor(damaged);
    final changed = await damagedFile.readAsBytes();
    changed[changed.length - 1] ^= 1;
    await damagedFile.writeAsBytes(changed, flush: true);
    final progress = <(int, int)>[];
    await repository!.refreshCopyStatuses(
      onProgress: (done, total) => progress.add((done, total)),
    );
    expect(progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);
    await reopen();
    for (final entry in [
      (CopyAvailability.available, healthy),
      (CopyAvailability.missing, missing),
      (CopyAvailability.damaged, damaged),
    ]) {
      await assertQuery(GalleryQuery(availability: entry.$1), {entry.$2.id});
      expect(
        await repository!.verifyCopy(
          (await repository!.getAsset(entry.$2.id))!,
        ),
        entry.$1,
      );
    }
    expect((await repository!.listAssets()).total, 3);
  });
}
