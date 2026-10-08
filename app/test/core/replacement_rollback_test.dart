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
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';
import 'package:imagehost/features/gallery/data/library_database.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late ImageAsset asset;
  late QueueTestSecrets secrets;
  LibraryRestoreHold? hold;
  final proofDirectories = <Directory>[];

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-rollback-test-');
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    asset = (await repository.importResource(
      PlatformResource(
        displayName: '原始整理.png',
        openRead: () =>
            Stream.value(img.encodePng(img.Image(width: 8, height: 6))),
      ),
    )).asset!;
    hold = null;
    proofDirectories.clear();
  });
  tearDown(() async {
    await hold?.release();
    await repository.close();
    await sandbox.delete(recursive: true);
    // These are exact private test-created roots retained by deliberate
    // unknown-content failures, never a scan of application temp directories.
    for (final directory in proofDirectories) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  List<Map<String, Object?>> rows(String table, {String? database}) {
    final db = sqlite3.open(
      database ?? '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      final columns = db
          .select('PRAGMA table_info("$table")')
          .map((r) => '"${r['name']}"')
          .join(',');
      return db
          .select('SELECT * FROM "$table" ORDER BY $columns')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } finally {
      db.close();
    }
  }

  Map<String, List<Map<String, Object?>>> state({String? database}) {
    final db = sqlite3.open(
      database ?? '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    late List<String> tables;
    try {
      tables = db
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .map((r) => r['name'] as String)
          .toList();
    } finally {
      db.close();
    }
    return {for (final table in tables) table: rows(table, database: database)};
  }

  void mutate(void Function(Database) action) {
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      db.execute('PRAGMA foreign_keys=ON');
      action(db);
    } finally {
      db.close();
    }
  }

  Future<ReplacementSnapshot> capture() async {
    hold ??= await repository.acquireRestoreHold();
    return repository.captureReplacementSnapshot(
      hold: hold!,
      availableBytes: (_) async => 1 << 40,
    );
  }

  Map<String, Object?> payload(ReplacementSnapshot snapshot) =>
      Map<String, Object?>.from(
        jsonDecode(
          rows('restore_operations')
                  .singleWhere((r) => r['id'] == snapshot.id)['payload_json']
              as String,
        ) as Map,
      );

  Future<void> prove(
    ReplacementSnapshot snapshot, {
    Future<int> Function(Directory)? available,
    CancellationToken? cancellation,
  }) => repository.proveReplacementSnapshotRecovery(
    snapshot,
    availableBytes:
        available ??
        (directory) async {
          proofDirectories.add(directory);
          return 1 << 40;
        },
    cancellation: cancellation,
  );

  Map<String, Object?> replacementJournal(String snapshotId) => {
    'format': 1,
    'snapshotId': snapshotId,
    'manifest': BackupManifest(
      packageId: const Uuid().v4(),
      createdUtc: 1,
      mode: BackupMode.metadata,
      versions: [],
      assets: [],
      categories: [],
      tags: [],
      origins: [],
      accounts: [],
      results: [],
      history: [],
      images: [],
    ).toJson(redactor: SecretRedactor()),
    'copies': <Object?>[],
    'secrets': [
      for (final reference in {
        for (final table in ['provider_targets', 'remote_upload_results'])
          for (final row in rows(table))
            if (row['secret_reference'] != null)
              row['secret_reference'] as String,
      })
        {
          'reference': reference,
          'hash': secrets.values[reference] == null
              ? null
              : sha256
                    .convert(utf8.encode(secrets.values[reference]!))
                    .toString(),
        },
    ],
  };

  Future<void> interruptedReplacement(
    ReplacementSnapshot snapshot, {
    String phase = 'replace-rollback',
    bool changeMetadata = true,
  }) async {
    final id = const Uuid().v4();
    mutate((db) {
      db.execute(
        'INSERT INTO restore_operations(id, phase, payload_json, created_utc) VALUES (?, ?, ?, 0)',
        [id, phase, jsonEncode(replacementJournal(snapshot.id))],
      );
      if (changeMetadata) {
        db.execute("UPDATE assets SET display_name='故障半成品', favorite=0");
        db.execute("UPDATE provider_targets SET alias='故障账号', enabled=0");
        db.execute('UPDATE upload_batches SET paused=0');
        db.execute(
          "UPDATE upload_publications SET state='queued', user_paused=0",
        );
        db.execute("UPDATE diagnostic_records SET code='interrupted'");
      }
    });
    await repository.close();
    await hold!.release();
    hold = null;
    repository = await LibraryRepository.open(root, secretStore: secrets);
  }

  test('UT-080/IT-005 partial recovery proof rebuilds all 27 tables, raw output and part bytes, missing paths and protected UUID without backend access', () async {
    final category = await repository.createCategory('原分类');
    await repository.updateOrganization(
      [asset.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['原标签'],
      favorite: true,
    );
    await ProcessingCoordinator(repository).process(
      [asset.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        mode: ProcessingMode.sizeFirst,
        longestSide: 4,
      ),
      displayName: '保留输出.png',
    );
    final outputPath =
        rows('processed_outputs').single['relative_path'] as String;
    await File('${root.path}/$outputPath.part')
        .writeAsBytes([1, 3, 5, 7], flush: true);
    final target = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '原账号',
      anonymous: false,
      credential: 'synthetic-proof-secret-01234567',
      persistence: CredentialPersistence.protected,
    );
    final queued = await repository.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [asset.id],
      targetIds: [target],
      allowOriginalMetadata: true,
    );
    await repository.setUploadItemPaused(queued.items.single.id, true);
    await repository.removeAssets([asset.id]);
    await repository.recordDiagnostic(
      DiagnosticEvent(
        id: const Uuid().v4(),
        occurredAt: DateTime.now().toUtc(),
        kind: DiagnosticKind.importImage,
        level: DiagnosticLevel.info,
        code: 'import.saved',
        summary: '本机保存确认',
        recoveryAction: '',
        entityId: asset.id,
      ),
    );
    // The missing original is preserved as missing while the output/part bytes
    // remain raw byte evidence. No executable queue runs in the rebuilt root.
    await File('${root.path}/${asset.deviceCopy.relativePath}').delete();
    final snapshot = await capture();
    final before = state();
    expect(before.length, 28);
    final secretValues = Map<String, String>.from(secrets.values);
    secrets.failReads = true;
    var independentlyReadRebuilt = false;
    await prove(
      snapshot,
      available: (directory) async {
        proofDirectories.add(directory);
        expect(directory.absolute.path, isNot(startsWith(root.absolute.path)));
        final rebuilt = File('${directory.path}/library.sqlite');
        if (await rebuilt.exists()) {
          final actual = state(database: rebuilt.path);
          for (final table in before.keys.where(
            (t) => t != 'restore_operations',
          )) {
            expect(actual[table], before[table], reason: table);
          }
          expect(actual['restore_operations'], isEmpty);
          final db = sqlite3.open(rebuilt.path, mode: OpenMode.readOnly);
          try {
            expect(db.select('PRAGMA foreign_key_check'), isEmpty);
            expect(
              db.select('PRAGMA user_version').single.values.single,
              librarySchemaVersion,
            );
          } finally {
            db.close();
          }
          independentlyReadRebuilt = true;
        }
        return 1 << 40;
      },
    );
    expect(independentlyReadRebuilt, true);
    expect(state(), before);
    expect(secrets.values, secretValues);
    expect(before['upload_batches']!.single['paused'], 1);
    expect(before['upload_publications']!.single['state'], 'paused');
    expect(before['upload_publications']!.single['user_paused'], 1);
    expect(
      before['provider_targets']!.single['secret_reference'],
      isA<String>(),
    );
    expect(await File('${root.path}/$outputPath.part').readAsBytes(), [
      1,
      3,
      5,
      7,
    ]);
    for (final directory in proofDirectories) {
      expect(await directory.exists(), false);
    }
    secrets.failReads = false;
    await repository.discardReplacementSnapshot(snapshot);
  });

  test('UT-080 partial proof checks system temporary volume capacity and cancellation without changing source', () async {
    final snapshot = await capture();
    final before = state();
    await expectLater(
      prove(
        snapshot,
        available: (directory) async {
          proofDirectories.add(directory);
          expect(directory.absolute.path, isNot(root.absolute.path));
          return 0;
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    final cancellation = CancellationToken();
    await expectLater(
      prove(
        snapshot,
        available: (directory) async {
          proofDirectories.add(directory);
          cancellation.cancel();
          return 1 << 40;
        },
        cancellation: cancellation,
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(state(), before);
    for (final directory in proofDirectories) {
      expect(await directory.exists(), false);
    }
    await repository.discardReplacementSnapshot(snapshot);
  });

  test('UT-080 partial tampered snapshot bytes and unknown snapshot files block proof', () async {
    final snapshot = await capture();
    final record = payload(snapshot);
    final path = '${root.path}/${record['directory']}';
    final unknown = File('$path/unknown.bin');
    await unknown.writeAsBytes([9], flush: true);
    await expectLater(prove(snapshot), throwsA(isA<BackupSnapshotFailure>()));
    expect(await unknown.exists(), true);
    await unknown.delete();
    final entry = (record['files'] as List).cast<Map>().single;
    final bytes = File('$path/${entry['filename']}');
    final original = await bytes.readAsBytes();
    await bytes.writeAsBytes([8], flush: true);
    await expectLater(prove(snapshot), throwsA(isA<BackupSnapshotFailure>()));
    await bytes.writeAsBytes(original, flush: true);
    await repository.discardReplacementSnapshot(snapshot);
  });

  test('UT-080 partial proof refuses changed journal, foreign owner and released hold', () async {
    final snapshot = await capture();
    final text = rows('restore_operations').single['payload_json'] as String;
    mutate(
      (db) => db.execute('UPDATE restore_operations SET payload_json=?', [
        '$text ',
      ]),
    );
    await expectLater(prove(snapshot), throwsA(isA<BackupSnapshotFailure>()));
    mutate(
      (db) =>
          db.execute('UPDATE restore_operations SET payload_json=?', [text]),
    );
    final foreign = await LibraryRepository.open(
      Directory('${sandbox.path}/foreign'),
    );
    try {
      await expectLater(
        foreign.proveReplacementSnapshotRecovery(
          snapshot,
          availableBytes: (_) async => 1 << 40,
        ),
        throwsA(isA<BackupSnapshotFailure>()),
      );
    } finally {
      await foreign.close();
    }
    await hold!.release();
    hold = null;
    await expectLater(prove(snapshot), throwsA(isA<BackupSnapshotFailure>()));
    // Normal startup only reclaims this owned snapshot after close.
  });

  test('UT-080 partial proof cleanup inspects unknown contents before deleting any known byte', () async {
    final snapshot = await capture();
    Directory? saved;
    await expectLater(
      prove(
        snapshot,
        available: (directory) async {
          saved = directory;
          proofDirectories.add(directory);
          final rebuilt = File('${directory.path}/library.sqlite');
          if (await rebuilt.exists()) {
            await File('${directory.path}/unknown.bin')
                .writeAsBytes([9], flush: true);
            return 0;
          }
          return 1 << 40;
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(await File('${saved!.path}/library.sqlite').exists(), true);
    expect(await File('${saved!.path}/unknown.bin').readAsBytes(), [9]);
    await repository.discardReplacementSnapshot(snapshot);
  });

  test('UT-080 partial linked snapshot byte is refused without reading external bytes', () async {
    final snapshot = await capture();
    final record = payload(snapshot);
    final entry = (record['files'] as List).cast<Map>().single;
    final byteFile = File(
      '${root.path}/${record['directory']}/${entry['filename']}',
    );
    final original = await byteFile.readAsBytes();
    final external = File('${sandbox.path}/external.bin');
    await external.writeAsBytes([8, 6, 4], flush: true);
    await byteFile.delete();
    final link = Link(byteFile.path);
    try {
      await link.create(external.path);
    } on FileSystemException {
      await byteFile.writeAsBytes(original, flush: true);
      await repository.discardReplacementSnapshot(snapshot);
      markTestSkipped('当前 Windows 进程没有符号链接创建权限，链接分支未实测。');
      return;
    }
    try {
      await expectLater(prove(snapshot), throwsA(isA<BackupSnapshotFailure>()));
      expect(await external.readAsBytes(), [8, 6, 4]);
    } finally {
      await link.delete();
      await byteFile.writeAsBytes(original, flush: true);
      await repository.discardReplacementSnapshot(snapshot);
    }
  });

  test('UT-080/IT-005 partial close waits actual proof IO and holds root lock until scratch cleanup', () async {
    final snapshot = await capture();
    final entered = Completer<void>(), resume = Completer<void>();
    final proving = prove(
      snapshot,
      available: (directory) async {
        proofDirectories.add(directory);
        if (!entered.isCompleted) {
          entered.complete();
          await resume.future;
        }
        return 1 << 40;
      },
    );
    await entered.future;
    var closed = false;
    final closing = repository.close().then((_) => closed = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, false);
    await expectLater(hold!.release(), throwsA(isA<BackupSnapshotFailure>()));
    await expectLater(
      LibraryRepository.open(root),
      throwsA(isA<LibraryOpenException>()),
    );
    resume.complete();
    await proving;
    await closing;
    expect(closed, true);
    await hold!.release();
    hold = null;
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(rows('assets').single['id'], asset.id);
    for (final directory in proofDirectories) {
      expect(await directory.exists(), false);
    }
  });

  test('UT-080/IT-005 partial startup rollback restores real metadata, paused intent and secret reference; snapshot-writing row is not revived', () async {
    await repository.recordDiagnostic(
      DiagnosticEvent(
        id: const Uuid().v4(),
        occurredAt: DateTime.now().toUtc(),
        kind: DiagnosticKind.importImage,
        level: DiagnosticLevel.info,
        code: 'import.saved',
        summary: '本机保存确认',
        recoveryAction: '',
        entityId: asset.id,
      ),
    );
    await repository.updateOrganization(
      [asset.id],
      replaceTags: ['保留标签'],
      favorite: true,
    );
    final target = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '保留账号',
      anonymous: false,
      credential: 'synthetic-rollback-secret-012345',
      persistence: CredentialPersistence.protected,
    );
    final pausedBatch = await repository.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [asset.id],
      targetIds: [target],
      allowOriginalMetadata: true,
    );
    await repository.setUploadItemPaused(pausedBatch.items.single.id, true);
    final snapshot = await capture();
    await prove(snapshot);
    final expected = state()..remove('restore_operations');
    final values = Map<String, String>.from(secrets.values);
    final originalBytes = await File(
      '${root.path}/${asset.deviceCopy.relativePath}',
    ).readAsBytes();
    await interruptedReplacement(snapshot);
    final actual = state()..remove('restore_operations');
    expect(actual, expected);
    expect(rows('restore_operations'), isEmpty);
    expect(secrets.values, values);
    expect(
      await File('${root.path}/${asset.deviceCopy.relativePath}').readAsBytes(),
      originalBytes,
    );
    expect(rows('upload_batches').single['paused'], 1);
    expect(rows('upload_publications').single['state'], 'paused');
    expect(rows('upload_publications').single['user_paused'], 1);
  });

  test(
    'UT-080 partial committed replacement is never rolled back to old metadata',
    () async {
      final snapshot = await capture();
      await interruptedReplacement(snapshot, phase: 'replace-committed');
      expect(rows('assets').single['display_name'], '故障半成品');
    },
  );

  test('UT-080 partial old bytes changed after snapshot block rollback and preserve all evidence', () async {
    final snapshot = await capture();
    final original = File('${root.path}/${asset.deviceCopy.relativePath}');
    await original.writeAsBytes([1, 2, 3], flush: true);
    await interruptedReplacement(snapshot);
    expect(rows('assets').single['display_name'], '故障半成品');
    expect(
      rows('restore_operations').any((r) => r['phase'] == 'replace-rollback'),
      true,
    );
    expect(await original.readAsBytes(), [1, 2, 3]);
    expect(
      await File(
        '${root.path}/staging/replacement-${snapshot.id}/current.sqlite',
      ).exists(),
      true,
    );
  });

  test('UT-080 partial missing old location appearing after snapshot blocks rollback', () async {
    final original = File('${root.path}/${asset.deviceCopy.relativePath}');
    await original.delete();
    final snapshot = await capture();
    await original.writeAsBytes([7, 8], flush: true);
    await interruptedReplacement(snapshot);
    expect(rows('assets').single['display_name'], '故障半成品');
    expect(
      rows('restore_operations').any((r) => r['phase'] == 'replace-rollback'),
      true,
    );
    expect(await original.readAsBytes(), [7, 8]);
  });
}
