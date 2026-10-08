import 'dart:io';

import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:path/path.dart' as p;
import 'package:imagehost/core/platform_resource.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/gallery/data/library_database.dart';
import 'package:sqlite3/sqlite3.dart';

// These fixtures represent this project's own formats, never an older app.
void main() {
  late Directory sandbox;
  late File databaseFile;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost-processing-schema-',
    );
    databaseFile = File('${sandbox.path}/library.sqlite');
  });
  tearDown(() async {
    final owned = p.normalize(await sandbox.resolveSymbolicLinks());
    final temp = p.normalize(await Directory.systemTemp.resolveSymbolicLinks());
    if (!p.isWithin(temp, owned) ||
        !p.basename(owned).startsWith('imagehost-processing-schema-')) {
      throw StateError('测试目录不在预期临时根目录。');
    }
    await sandbox.delete(recursive: true);
  });

  void mutate(void Function(Database) action) {
    final database = sqlite3.open(databaseFile.path);
    try {
      database.execute('PRAGMA foreign_keys=ON');
      action(database);
    } finally {
      database.close();
    }
  }

  Future<void> openDatabase() async {
    final database = LibraryDatabase(databaseFile);
    try {
      await database.customSelect('SELECT * FROM library_metadata').get();
    } finally {
      await database.close();
    }
  }

  Map<String, Object?> snapshot() {
    final database = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
    try {
      return {
        'version': database.select('PRAGMA user_version').single.values.single,
        'schema': database
            .select(
              "SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
            )
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
        for (final table in database.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        ))
          table['name'] as String: database
              .select('SELECT * FROM "${table['name']}" ORDER BY rowid')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
      };
    } finally {
      database.close();
    }
  }

  void seedPublication(Database database) {
    database.execute(
      "INSERT INTO upload_batches(id,intent_id,created_utc,paused) VALUES('batch','intent',1,1)",
    );
    database.execute('''INSERT INTO upload_publications(
        id,batch_id,position,input_json,target_json,target_id,version_digest,
        byte_count,policy_key,state,user_paused,wait_reason,retry_delay_micros,
        created_utc,updated_utc)
        VALUES('item','batch',0,'frozen-input','frozen-target','target','digest',
        123,'frozen-policy','paused',1,'retry',8000000,1,2)''');
  }

  Future<void> fixture(int version) async {
    await openDatabase();
    mutate((database) {
      if (version >= 5) seedPublication(database);
      database.execute(
        'ALTER TABLE upload_publications DROP COLUMN processing_job_id',
      );
      database.execute('DROP TABLE upload_processing_jobs');
      if (version < 9) {
        database.execute(
          'ALTER TABLE upload_publications DROP COLUMN user_paused',
        );
      }
      if (version < 8) database.execute('DROP TABLE diagnostic_records');
      if (version < 7) {
        for (final column in [
          'link_state',
          'link_reason',
          'link_checked_utc',
          'last_accessible_utc',
          'probe_generation',
          'probe_http_status',
        ]) {
          database.execute(
            'ALTER TABLE remote_upload_results DROP COLUMN $column',
          );
        }
      }
      if (version < 6) {
        for (final table in [
          'restore_operations',
          'imported_upload_histories',
          'restored_output_origins',
        ]) {
          database.execute('DROP TABLE $table');
        }
      }
      if (version < 5) {
        for (final table in [
          'upload_events',
          'upload_result_operations',
          'remote_upload_results',
          'upload_attempts',
          'upload_publications',
          'upload_batches',
        ]) {
          database.execute('DROP TABLE $table');
        }
      }
      if (version < 4) {
        database.execute('DROP TABLE credential_operations');
        database.execute('DROP TABLE provider_targets');
      }
      if (version < 3) {
        database.execute('ALTER TABLE import_operations DROP COLUMN output_id');
        for (final table in [
          'output_leases',
          'output_references',
          'saved_output_origins',
          'processed_outputs',
        ]) {
          database.execute('DROP TABLE $table');
        }
      }
      database.execute('PRAGMA user_version=$version');
      expect(database.select('PRAGMA foreign_key_check'), isEmpty);
    });
  }

  test('UT-093 QUE-005 schema10 fresh creates 28 tables and enforces shared processing dependency identities', () async {
    await openDatabase();
    mutate((database) {
      expect(
        database.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        ),
        hasLength(28),
      );
      final publicationForeignKeys = database.select(
        'PRAGMA foreign_key_list(upload_publications)',
      );
      expect(
        publicationForeignKeys
            .where((row) => row['from'] == 'processing_job_id')
            .single['table'],
        'upload_processing_jobs',
      );
      final jobForeignKeys = database.select(
        'PRAGMA foreign_key_list(upload_processing_jobs)',
      );
      expect(jobForeignKeys, hasLength(1));
      expect(jobForeignKeys.single['from'], 'batch_id');
      expect(jobForeignKeys.single['table'], 'upload_batches');
      seedPublication(database);
      database.execute(
        "INSERT INTO upload_processing_jobs(id,batch_id,policy_key,request_json,state,output_id,created_utc,updated_utc) VALUES('job','batch','policy','frozen-request','ready','expired-output',1,2)",
      );
      database.execute(
        "UPDATE upload_publications SET processing_job_id='job' WHERE id='item'",
      );
      expect(
        () => database.execute(
          "INSERT INTO upload_processing_jobs(id,batch_id,policy_key,request_json,state,created_utc,updated_utc) VALUES('duplicate','batch','policy','{}','queued',1,2)",
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => database.execute(
          "UPDATE upload_publications SET processing_job_id='missing' WHERE id='item'",
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => database.execute(
          "DELETE FROM upload_processing_jobs WHERE id='job'",
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(database.select('PRAGMA foreign_key_check'), isEmpty);
    });
    final before = snapshot();
    await openDatabase();
    expect(snapshot(), before);
  });

  test('UT-093 QUE-005 own schema1 upgrade preserves source identities and creates upload processing dependencies', () async {
    mutate((database) {
      for (final statement in [
        '''CREATE TABLE versions (
          id TEXT NOT NULL PRIMARY KEY, digest TEXT NOT NULL, byte_count INTEGER NOT NULL,
          format TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL,
          frame_count INTEGER NOT NULL, orientation INTEGER NOT NULL,
          UNIQUE(digest,byte_count))''',
        '''CREATE TABLE assets (
          id TEXT NOT NULL PRIMARY KEY, display_name TEXT NOT NULL,
          version_id TEXT NOT NULL REFERENCES versions(id), imported_utc INTEGER NOT NULL,
          updated_utc INTEGER NOT NULL, source_type TEXT NOT NULL,
          favorite INTEGER NOT NULL DEFAULT 0, category TEXT,
          recycled INTEGER NOT NULL DEFAULT 0)''',
        '''CREATE TABLE device_copies (
          id TEXT NOT NULL PRIMARY KEY, version_id TEXT NOT NULL UNIQUE REFERENCES versions(id),
          relative_path TEXT NOT NULL UNIQUE)''',
        '''CREATE TABLE import_operations (
          id TEXT NOT NULL PRIMARY KEY, asset_id TEXT NOT NULL, version_id TEXT NOT NULL,
          copy_id TEXT NOT NULL, stage_path TEXT NOT NULL, final_path TEXT NOT NULL,
          display_name TEXT NOT NULL, source_type TEXT NOT NULL, created_utc INTEGER NOT NULL,
          phase TEXT NOT NULL, digest TEXT, byte_count INTEGER, format TEXT,
          width INTEGER, height INTEGER, frame_count INTEGER, orientation INTEGER)''',
        'CREATE INDEX assets_import_order ON assets(imported_utc DESC,id ASC)',
        "INSERT INTO versions VALUES('version','digest',123,'PNG',3,2,1,1)",
        "INSERT INTO assets VALUES('asset','保留名称','version',1,2,'file',1,NULL,0)",
        "INSERT INTO device_copies VALUES('copy','version','originals/retained.png')",
        'PRAGMA user_version=1',
      ]) {
        database.execute(statement);
      }
    });
    final before = snapshot();
    await openDatabase();
    final after = snapshot();
    expect(after['version'], librarySchemaVersion);
    expect(after['versions'], before['versions']);
    expect(after['import_operations'], before['import_operations']);
    expect(after['upload_processing_jobs'], isEmpty);
    expect(after['upload_publications'], isEmpty);
    mutate((database) {
      expect(
        database
            .select('SELECT id,display_name,version_id,favorite FROM assets')
            .single
            .values,
        ['asset', '保留名称', 'version', 1],
      );
      expect(
        database
            .select('SELECT id,version_id,relative_path FROM device_copies')
            .single
            .values,
        ['copy', 'version', 'originals/retained.png'],
      );
      expect(database.select('PRAGMA foreign_key_check'), isEmpty);
    });
  });

  for (var version = 2; version <= 9; version++) {
    test(
      'UT-093 QUE-005 own schema$version upgrade preserves frozen inputs and independent pause, adds empty dependencies',
      () async {
        await fixture(version);
        final before = snapshot();
        await openDatabase();
        final after = snapshot();
        expect(after['version'], librarySchemaVersion);
        expect(after['upload_processing_jobs'], isEmpty);
        for (final table in before.keys.where(
          (key) =>
              key != 'schema' &&
              key != 'version' &&
              key != 'upload_publications',
        )) {
          expect(after[table], before[table], reason: table);
        }
        if (version >= 5) {
          final oldRow = (before['upload_publications'] as List).single as Map;
          final newRow = Map<String, Object?>.from(
            (after['upload_publications'] as List).single as Map,
          );
          expect(newRow.remove('processing_job_id'), isNull);
          if (version < 9) expect(newRow.remove('user_paused'), 0);
          expect(newRow, oldRow);
        }
        mutate((database) {
          expect(database.select('PRAGMA foreign_key_check'), isEmpty);
        });
      },
    );
  }

  for (final version in [6, 7, 8, 9]) {
    test(
      'UT-093 BAK-006 own schema$version unfinished restore refuses upgrade before schema or evidence changes',
      () async {
        await fixture(version);
        mutate((database) {
          database.execute(
            "INSERT INTO restore_operations(id,phase,payload_json,created_utc) VALUES('restore','replace-writing','retained-evidence',1)",
          );
        });
        final before = snapshot();
        await expectLater(
          openDatabase(),
          throwsA(
            isA<DriftRemoteException>().having(
              (error) => error.remoteCause,
              'cause',
              isA<LibraryOpenException>().having(
                (cause) => cause.message,
                'message',
                '升级前须先用兼容版本完成恢复操作；原数据与恢复证据已保留。',
              ),
            ),
          ),
        );
        expect(snapshot(), before);
      },
    );
  }
}
