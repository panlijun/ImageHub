import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_database.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late QueueTestSecrets secrets;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost-restore-schema-',
    );
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final png = img.encodePng(img.Image(width: 8, height: 6));
    final asset = (await repository.importResource(
      PlatformResource(
        displayName: '本机原图.png',
        openRead: () => Stream.value(png),
      ),
    )).asset!;
    final category = await repository.createCategory('保留分类');
    await repository.updateOrganization(
      [asset.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['保留标签'],
      favorite: true,
    );
    final account = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '保留账号',
      anonymous: false,
      credential: 'synthetic-migration-credential-123456',
    );
    final batch = await repository.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [asset.id],
      targetIds: [account],
      allowOriginalMetadata: true,
    );
    await repository.setUploadBatchPaused(batch.id, true);
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  Map<String, List<Map<String, Object?>>> rows(Database db) => {
    for (final row in db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      row['name'] as String: db
          .select('SELECT * FROM ${row['name']} ORDER BY rowid')
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
  };

  test('UT-093 IT-006 partial own schema 5 to current adds audit/log and link evidence without changing stable data credentials or paused intents', () async {
    final asset = (await repository.listAssets()).items.single;
    final bytes = await (await repository.originalFor(asset)).readAsBytes();
    await repository.close();
    final db = sqlite3.open('${root.path}/library.sqlite');
    late Map<String, List<Map<String, Object?>>> before;
    try {
      // Remove all later tables/columns to form this project's actual schema 5.
      db.execute(
        'ALTER TABLE upload_publications DROP COLUMN processing_job_id',
      );
      db.execute('DROP TABLE upload_processing_jobs');
      db.execute('DROP TABLE diagnostic_records');
      db.execute('ALTER TABLE upload_publications DROP COLUMN user_paused');
      db.execute('DROP TABLE restored_output_origins');
      db.execute('DROP TABLE imported_upload_histories');
      db.execute('DROP TABLE restore_operations');
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
      db.execute('PRAGMA user_version=5');
      before = rows(db);
    } finally {
      db.close();
    }
    final savedSecrets = Map.of(secrets.values);
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final check = sqlite3.open('${root.path}/library.sqlite');
    try {
      final after = rows(check);
      for (final table in before.keys) {
        expect(
          after[table],
          table == 'upload_publications'
              ? [
                  for (final row in before[table]!)
                    {...row, 'user_paused': 0, 'processing_job_id': null},
                ]
              : before[table],
          reason: 'schema-5 $table identities and fields preserved',
        );
      }
      for (final table in [
        'restored_output_origins',
        'imported_upload_histories',
        'restore_operations',
        'diagnostic_records',
      ]) {
        expect(after[table], isEmpty);
      }
      expect(
        check.select('PRAGMA user_version').single.values.single,
        librarySchemaVersion,
      );
      expect(check.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(check.select('PRAGMA foreign_key_check'), isEmpty);
      expect(check.select('PRAGMA journal_mode').single.values.single, 'wal');
      check.execute('PRAGMA foreign_keys=ON');
      expect(
        () => check.execute(
          "INSERT INTO restored_output_origins VALUES ('orphan','missing','{}')",
        ),
        throwsA(isA<SqliteException>()),
      );
    } finally {
      check.close();
    }
    expect(secrets.values, savedSecrets);
    final retained = (await repository.getAsset(asset.id))!;
    expect(retained.deviceCopy.id, asset.deviceCopy.id);
    expect(await (await repository.originalFor(retained)).readAsBytes(), bytes);
  });

  test('UT-075/079 partial malformed restore log validates all entries before cleaning any owned stage and preserves external bytes', () async {
    final captured = await repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    final manifest = captured.manifest;
    await captured.release();
    await repository.close();
    final owned = const Uuid().v4(),
        malformed = const Uuid().v4(),
        operation = const Uuid().v4();
    final stage = File('${root.path}/staging/$owned.part');
    await stage.writeAsString('recoverable-stage', flush: true);
    final external = File('${sandbox.path}/external-source.png');
    await external.writeAsString('external-must-stay', flush: true);
    final spec = <String, Object?>{
      'versionId': manifest.versions.single.id,
      'incomingId': manifest.versions.single.id,
      'copyId': const Uuid().v4(),
      'stagePath': 'staging/$owned.part',
      'finalPath': 'originals/$owned.original',
      'oldPath': null,
      'bytes': true,
      'publication': 'pending',
    };
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      db.execute('INSERT INTO restore_operations VALUES (?,?,?,?)', [
        operation,
        'writing',
        jsonEncode({
          'manifest': jsonDecode(
            utf8.decode(manifest.encode(redactor: SecretRedactor())),
          ),
          'copies': [
            spec,
            {
              ...spec,
              'copyId': const Uuid().v4(),
              'stagePath': 'staging/$malformed.part',
              'finalPath': external.path,
            },
          ],
        }),
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ]);
    } finally {
      db.close();
    }
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(
      repository.recoveryIssues.any((i) => i.operationId == operation),
      true,
    );
    expect(await stage.readAsString(), 'recoverable-stage');
    expect(await external.readAsString(), 'external-must-stay');
    await expectLater(
      repository.acquireRestoreHold(),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect((await repository.listAssets()).total, 1);
  });
}
