import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_database.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

// Independent schema-1 fixture for this new project. It has no old ImageHost
// application data and does not derive its DDL from generated schema-2 code.
const _schema1 = [
  '''CREATE TABLE versions (
    id TEXT NOT NULL PRIMARY KEY, digest TEXT NOT NULL, byte_count INTEGER NOT NULL,
    format TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL,
    frame_count INTEGER NOT NULL, orientation INTEGER NOT NULL,
    UNIQUE(digest, byte_count))''',
  '''CREATE TABLE assets (
    id TEXT NOT NULL PRIMARY KEY, display_name TEXT NOT NULL,
    version_id TEXT NOT NULL REFERENCES versions(id), imported_utc INTEGER NOT NULL,
    updated_utc INTEGER NOT NULL, source_type TEXT NOT NULL,
    favorite INTEGER NOT NULL DEFAULT 0 CHECK(favorite IN (0,1)), category TEXT,
    recycled INTEGER NOT NULL DEFAULT 0 CHECK(recycled IN (0,1)))''',
  '''CREATE TABLE device_copies (
    id TEXT NOT NULL PRIMARY KEY, version_id TEXT NOT NULL UNIQUE REFERENCES versions(id),
    relative_path TEXT NOT NULL UNIQUE)''',
  '''CREATE TABLE import_operations (
    id TEXT NOT NULL PRIMARY KEY, asset_id TEXT NOT NULL, version_id TEXT NOT NULL,
    copy_id TEXT NOT NULL, stage_path TEXT NOT NULL, final_path TEXT NOT NULL,
    display_name TEXT NOT NULL, source_type TEXT NOT NULL, created_utc INTEGER NOT NULL,
    phase TEXT NOT NULL, digest TEXT, byte_count INTEGER, format TEXT,
    width INTEGER, height INTEGER, frame_count INTEGER, orientation INTEGER)''',
  'CREATE INDEX assets_import_order ON assets(imported_utc DESC, id ASC)',
];

void main() {
  late Directory sandbox;
  late Directory root;
  late File databaseFile;
  LibraryRepository? repository;
  late Map<String, List<int>> originals;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost_schema1_');
    root = Directory(p.join(sandbox.path, 'library'));
    await Directory(p.join(root.path, 'originals')).create(recursive: true);
    databaseFile = File(p.join(root.path, 'library.sqlite'));
    originals = {};
  });
  tearDown(() async {
    await repository?.close();
    repository = null;
    await sandbox.delete(recursive: true);
  });

  Future<void> fixture(List<String?> categories) async {
    final db = sqlite3.open(databaseFile.path);
    try {
      db.execute('PRAGMA foreign_keys=ON');
      for (final ddl in _schema1) {
        db.execute(ddl);
      }
      for (var i = 0; i < categories.length; i++) {
        final picture = img.Image(width: 3, height: 2, numChannels: 4);
        img.fill(picture, color: img.ColorRgba8(i + 1, 30, 160, 255));
        final bytes = img.encodePng(picture);
        final relativePath = 'originals/v$i.png';
        originals[relativePath] = bytes;
        await File(p.join(root.path, relativePath))
            .writeAsBytes(bytes, flush: true);
        db.execute('INSERT INTO versions VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [
          'v$i',
          sha256.convert(bytes).toString(),
          bytes.length,
          'PNG',
          3,
          2,
          1,
          1,
        ]);
        db.execute('INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [
          'a$i',
          'Picture$i',
          'v$i',
          1700000000000 + i,
          1700000001000 + i,
          i.isEven ? 'file' : 'photo',
          i.isEven ? 1 : 0,
          categories[i],
          i == categories.length - 1 ? 1 : 0,
        ]);
        db.execute('INSERT INTO device_copies VALUES (?, ?, ?)', [
          'd$i',
          'v$i',
          relativePath,
        ]);
      }
      db.execute('PRAGMA user_version=1');
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      db.close();
    }
  }

  Map<String, List<Map<String, Object?>>> snapshot() {
    final db = sqlite3.open(databaseFile.path);
    try {
      final names = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      return {
        for (final name in names.map((row) => row['name'] as String))
          name: db
              .select('SELECT * FROM $name ORDER BY rowid')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
      };
    } finally {
      db.close();
    }
  }

  test('UT-093 / IT-006 partial own schema 1 to 2 keeps assets/content/copies and merges normalized category UUIDs', () async {
    await fixture([' Straße ', 'STRASSE', 'Cafe\u0301', 'CAFÉ', null]);
    final before = snapshot();
    repository = await LibraryRepository.open(root);
    final categories = await repository!.listCategories();
    expect(categories, hasLength(2));
    final street = categories.singleWhere((c) => c.name == 'Straße');
    final cafe = categories.singleWhere((c) => c.name == 'Café');
    expect(street.assetCount, 2);
    expect(cafe.assetCount, 2);
    expect(
      street.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      final asset = (await repository!.getAsset('a$i', includeRecycled: true))!;
      expect(asset.id, 'a$i');
      expect(asset.version.id, 'v$i');
      expect(asset.deviceCopy.id, 'd$i');
      expect(
        asset.categoryId,
        i < 2
            ? street.id
            : i < 4
            ? cafe.id
            : null,
      );
      expect(asset.favorite, i.isEven);
      expect(asset.recycled, i == 4);
      expect(asset.importedAt.millisecondsSinceEpoch, 1700000000000 + i);
      expect(asset.updatedAt.millisecondsSinceEpoch, 1700000001000 + i);
      expect(await repository!.verifyCopy(asset), CopyAvailability.available);
      expect(
        await (await repository!.originalFor(asset)).readAsBytes(),
        originals[asset.deviceCopy.relativePath],
      );
    }
    await repository!.close();
    repository = null;
    final after = snapshot();
    expect(after['versions'], before['versions']);
    expect(after['import_operations'], before['import_operations']);
    for (var i = 0; i < 5; i++) {
      expect(
        {...after['assets']![i]}
          ..remove('category')
          ..remove('recycled_utc'),
        {...before['assets']![i]}..remove('category'),
      );
      expect(
        {...after['device_copies']![i]}
          ..remove('availability')
          ..remove('verified_utc'),
        before['device_copies']![i],
      );
    }
    final db = sqlite3.open(databaseFile.path);
    try {
      expect(
        db.select('PRAGMA user_version').single.values.single,
        librarySchemaVersion,
      );
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        db
            .select('PRAGMA foreign_key_list(assets)')
            .any(
              (r) =>
                  r['table'] == 'categories' &&
                  r['from'] == 'category' &&
                  r['to'] == 'id',
            ),
        true,
      );
      db.execute('PRAGMA foreign_keys=ON');
      expect(
        () => db.execute(
          "UPDATE assets SET category='missing-category' WHERE id='a0'",
        ),
        throwsA(isA<SqliteException>()),
      );
    } finally {
      db.close();
    }
    repository = await LibraryRepository.open(root);
    expect((await repository!.getAsset('a0'))!.categoryId, street.id);
    expect((await repository!.listCategories()).map((c) => c.id).toSet(), {
      street.id,
      cafe.id,
    });
  });

  for (final invalid in [' ', List.filled(65, '😀').join()]) {
    test(
      'UT-093 failed schema upgrade invalid category ${invalid.trim().isEmpty ? 'blank' : '65 scalars'} leaves original schema/data intact',
      () async {
        await fixture(['Valid first', invalid]);
        final before = snapshot();
        await expectLater(
          LibraryRepository.open(root),
          throwsA(isA<LibraryOpenException>()),
        );
        expect(snapshot(), before);
        final db = sqlite3.open(databaseFile.path);
        try {
          expect(db.select('PRAGMA user_version').single.values.single, 1);
          expect(
            db.select('PRAGMA integrity_check').single.values.single,
            'ok',
          );
          expect(db.select('PRAGMA foreign_key_check'), isEmpty);
          expect(
            db.select('PRAGMA table_info(assets)').map((r) => r['name']),
            isNot(contains('recycled_utc')),
          );
          expect(
            db.select('PRAGMA table_info(device_copies)').map((r) => r['name']),
            isNot(contains('availability')),
          );
        } finally {
          db.close();
        }
        for (final entry in originals.entries) {
          expect(
            await File(p.join(root.path, entry.key)).readAsBytes(),
            entry.value,
          );
        }
        // Opening it again must fail consistently, without building a half-schema.
        await expectLater(
          LibraryRepository.open(root),
          throwsA(isA<LibraryOpenException>()),
        );
        expect(snapshot(), before);
      },
    );
  }

  test('UT-093 future schema rejects without resetting or mutating database/file bytes', () async {
    await fixture(['Keep']);
    final db = sqlite3.open(databaseFile.path);
    db.execute('PRAGMA user_version=99');
    db.close();
    final before = snapshot();
    final databaseBytes = await databaseFile.readAsBytes();
    await expectLater(
      LibraryRepository.open(root),
      throwsA(isA<LibraryOpenException>()),
    );
    expect(snapshot(), before);
    expect(await databaseFile.readAsBytes(), databaseBytes);
    final unchanged = sqlite3.open(databaseFile.path);
    expect(unchanged.select('PRAGMA user_version').single.values.single, 99);
    unchanged.close();
    for (final entry in originals.entries) {
      expect(
        await File(p.join(root.path, entry.key)).readAsBytes(),
        entry.value,
      );
    }
  });
}
