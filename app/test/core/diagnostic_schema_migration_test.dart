import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_database.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:sqlite3/sqlite3.dart';

// These fixtures describe this project's schema 6/7, never an older app.
void main() {
  late Directory sandbox, root;
  late File databaseFile;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost-diagnostic-schema-',
    );
    root = await Directory('${sandbox.path}/library').create();
    databaseFile = File('${root.path}/library.sqlite');
  });
  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  void mutate(void Function(Database) action) {
    final db = sqlite3.open(databaseFile.path);
    try {
      action(db);
    } finally {
      db.close();
    }
  }

  Future<void> openDatabase() async {
    final db = LibraryDatabase(databaseFile);
    try {
      await db.customSelect('SELECT * FROM library_metadata').get();
    } finally {
      await db.close();
    }
  }

  Map<String, Object?> snapshot() {
    final db = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
    try {
      final tables = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      return {
        'version': db.select('PRAGMA user_version').single.values.single,
        'schema': db
            .select(
              "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
            )
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
        for (final table in tables.map((row) => row['name'] as String))
          table: db
              .select('SELECT * FROM "$table" ORDER BY rowid')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
      };
    } finally {
      db.close();
    }
  }

  Future<void> fixture(int version) async {
    await openDatabase();
    mutate((db) {
      db.execute('INSERT INTO versions VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [
        '00000000-0000-4000-8000-000000000001',
        List.filled(64, 'a').join(),
        123,
        'PNG',
        3,
        2,
        1,
        1,
      ]);
      db.execute(
        'INSERT INTO assets(id, display_name, version_id, imported_utc, updated_utc, source_type, favorite) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          '00000000-0000-4000-8000-000000000002',
          '保留名称',
          '00000000-0000-4000-8000-000000000001',
          1,
          2,
          'file',
          1,
        ],
      );
      db.execute(
        'INSERT INTO device_copies(id, version_id, relative_path, availability) VALUES (?, ?, ?, ?)',
        [
          '00000000-0000-4000-8000-000000000003',
          '00000000-0000-4000-8000-000000000001',
          'originals/retained.png',
          'missing',
        ],
      );
      db.execute(
        'ALTER TABLE upload_publications DROP COLUMN processing_job_id',
      );
      db.execute('DROP TABLE upload_processing_jobs');
      db.execute('DROP TABLE diagnostic_records');
      db.execute('ALTER TABLE upload_publications DROP COLUMN user_paused');
      if (version == 6) {
        for (final column in [
          'link_state',
          'link_reason',
          'link_checked_utc',
          'last_accessible_utc',
          'probe_generation',
          'probe_http_status',
        ]) {
          db.execute('ALTER TABLE remote_upload_results DROP COLUMN $column');
        }
      }
      db.execute('PRAGMA user_version=$version');
    });
  }

  test('UT-093 current schema fresh database creates 28 tables and diagnostic indexes', () async {
    await openDatabase();
    mutate((db) {
      expect(
        db.select('PRAGMA user_version').single.values.single,
        librarySchemaVersion,
      );
      expect(
        db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        ),
        hasLength(28),
      );
      expect(
        db
            .select(
              "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'diagnostic_records_%' ORDER BY name",
            )
            .map((r) => r['name']),
        [
          'diagnostic_records_attempt',
          'diagnostic_records_batch',
          'diagnostic_records_order',
        ],
      );
      db.execute(
        'INSERT INTO diagnostic_records VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          '00000000-0000-4000-8000-000000000004',
          3,
          'library',
          'info',
          'opened',
          null,
          null,
          null,
          '{}',
          2,
        ],
      );
    });
    final before = snapshot();
    await openDatabase();
    expect(snapshot(), before);
  });

  test('UT-093 own schema7 to current preserves asset version copy identities and creates actual diagnostics with all indexes', () async {
    await fixture(7);
    final before = snapshot();
    expect(before.containsKey('diagnostic_records'), false);
    await openDatabase();
    final after = snapshot();
    expect(after['version'], librarySchemaVersion);
    for (final key in before.keys.where(
      (key) => key != 'schema' && key != 'version',
    )) {
      expect(after[key], before[key], reason: key);
    }
    expect(after['diagnostic_records'], isEmpty);
    mutate((db) {
      expect(
        db
            .select('PRAGMA table_info(diagnostic_records)')
            .map((r) => r['name']),
        [
          'id',
          'occurred_utc',
          'kind',
          'level',
          'code',
          'entity_id',
          'batch_id',
          'attempt_id',
          'payload_json',
          'content_bytes',
        ],
      );
      expect(db.select('PRAGMA foreign_key_list(diagnostic_records)'), isEmpty);
      for (final index in {
        'diagnostic_records_order': ['occurred_utc', 'id'],
        'diagnostic_records_batch': ['batch_id', 'occurred_utc', 'id'],
        'diagnostic_records_attempt': ['attempt_id', 'occurred_utc', 'id'],
      }.entries) {
        expect(
          db.select('PRAGMA index_info(${index.key})').map((r) => r['name']),
          index.value,
        );
      }
      db.execute(
        'INSERT INTO diagnostic_records VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          '00000000-0000-4000-8000-000000000004',
          3,
          'import',
          'info',
          'saved',
          'removed-entity',
          'removed-batch',
          'removed-attempt',
          '{}',
          2,
        ],
      );
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    });
    final recorded = snapshot()['diagnostic_records'];
    await openDatabase();
    expect(snapshot()['diagnostic_records'], recorded);
  });

  for (final version in [6, 7]) {
    test(
      'UT-093 own schema$version pending restore rejects before any schema or evidence mutation',
      () async {
        await fixture(version);
        mutate(
          (db) =>
              db.execute('INSERT INTO restore_operations VALUES (?, ?, ?, ?)', [
                '00000000-0000-4000-8000-000000000005',
                'replace-rollback',
                '{"retainedEvidence":true}',
                4,
              ]),
        );
        final before = snapshot();
        final originalBytes = await databaseFile.readAsBytes();
        for (var attempt = 0; attempt < 2; attempt++) {
          await expectLater(
            LibraryRepository.open(root),
            throwsA(isA<LibraryOpenException>()),
          );
          expect(snapshot(), before);
          expect(await databaseFile.readAsBytes(), originalBytes);
        }
      },
    );
  }

  test('UT-093 schema7 failed diagnostic index creation rolls back all new DDL and preserves original evidence', () async {
    await fixture(7);
    mutate(
      (db) => db.execute(
        'CREATE INDEX diagnostic_records_batch ON assets(imported_utc, id)',
      ),
    );
    final before = snapshot();
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        LibraryRepository.open(root),
        throwsA(isA<LibraryOpenException>()),
      );
      expect(snapshot(), before);
      expect(snapshot().containsKey('diagnostic_records'), false);
    }
  });
}
