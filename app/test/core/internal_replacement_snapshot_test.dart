import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
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
  late QueueTestSecrets secrets;
  late ImageAsset asset;
  LibraryRestoreHold? hold;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost-internal-snapshot-',
    );
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    asset = (await repository.importResource(
      PlatformResource(
        displayName: '本机原始名称.png',
        openRead: () =>
            Stream.value(img.encodePng(img.Image(width: 8, height: 6))),
      ),
    )).asset!;
    hold = null;
  });
  tearDown(() async {
    await hold?.release();
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  List<Map<String, Object?>> rows(String table, {String? path}) {
    final db = sqlite3.open(
      path ?? '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return db
          .select('SELECT * FROM $table ORDER BY 1')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } finally {
      db.close();
    }
  }

  void mutate(void Function(Database db) action, {String? path}) {
    final db = sqlite3.open(path ?? '${root.path}/library.sqlite');
    try {
      action(db);
    } finally {
      db.close();
    }
  }

  Future<ReplacementSnapshot> capture({
    Future<int> Function(Directory)? available,
    CancellationToken? cancellation,
    void Function(String, int, int)? progress,
  }) async {
    hold ??= await repository.acquireRestoreHold();
    return repository.captureReplacementSnapshot(
      hold: hold!,
      availableBytes: available ?? (_) async => 1 << 40,
      cancellation: cancellation,
      onProgress: progress,
    );
  }

  Map<String, Object?> payload() => Map<String, Object?>.from(
    jsonDecode(rows('restore_operations').single['payload_json'] as String)
        as Map,
  );

  String snapshotPath(ReplacementSnapshot snapshot) =>
      '${root.path}/staging/replacement-${snapshot.id}/current.sqlite';

  test('UT-080/IT-005 partial internal SQLite preserves identities, recycle, output references, protected UUID and paused queue with real bytes', () async {
    final category = await repository.createCategory('保留分类');
    await repository.updateOrganization(
      [asset.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['原标签'],
      favorite: true,
    );
    final output = await ProcessingCoordinator(repository).process(
      [asset.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        mode: ProcessingMode.sizeFirst,
        longestSide: 4,
      ),
      displayName: '内部临时输出.png',
    );
    const syntheticSecret = 'synthetic-internal-snapshot-credential-012345';
    final target = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '内部账号',
      anonymous: false,
      credential: syntheticSecret,
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
    hold = await repository.acquireRestoreHold();
    const tables = [
      'assets',
      'versions',
      'device_copies',
      'categories',
      'tags',
      'asset_tags',
      'processed_outputs',
      'version_references',
      'provider_targets',
      'upload_batches',
      'upload_publications',
      'diagnostic_records',
    ];
    final expected = {for (final table in tables) table: rows(table)};
    final snapshot = await capture();
    expect(snapshot.assetCount, 1);
    expect(snapshot.fileCount, 2);
    expect(snapshot.byteCount, greaterThan(0));
    final dbPath = snapshotPath(snapshot);
    for (final table in tables) {
      expect(rows(table, path: dbPath), expected[table], reason: table);
    }
    expect(rows('assets', path: dbPath).single['recycled'], 1);
    expect(rows('processed_outputs', path: dbPath).single['id'], output.id);
    expect(rows('upload_batches', path: dbPath).single['id'], queued.id);
    expect(rows('upload_batches', path: dbPath).single['paused'], 1);
    expect(rows('upload_publications', path: dbPath).single['user_paused'], 1);
    final reference = rows(
      'provider_targets',
      path: dbPath,
    ).single['secret_reference'];
    expect(reference, isA<String>());
    expect(secrets.values[reference], syntheticSecret);
    final journalText =
        rows('restore_operations').single['payload_json'] as String;
    expect(journalText, isNot(contains('本机原始名称')));
    expect(journalText, isNot(contains(syntheticSecret)));
    expect(journalText, isNot(contains('内部账号')));
    final record = payload();
    for (final raw in record['files'] as List) {
      final entry = raw as Map;
      if (entry['state'] == 'missing') continue;
      expect(
        await File('${root.path}/${record['directory']}/${entry['filename']}')
            .readAsBytes(),
        await File('${root.path}/${entry['source']}').readAsBytes(),
      );
    }
    await repository.verifyReplacementSnapshot(snapshot);
    await repository.discardReplacementSnapshot(snapshot);
    await repository.discardReplacementSnapshot(snapshot);
    expect(rows('restore_operations'), isEmpty);
    expect(
      await File('${root.path}/${asset.deviceCopy.relativePath}').exists(),
      true,
    );
    expect(secrets.values[reference], syntheticSecret);
  });

  test('UT-080 partial missing original is explicit evidence and not copied success', () async {
    await File('${root.path}/${asset.deviceCopy.relativePath}').delete();
    final snapshot = await capture();
    expect(snapshot.fileCount, 0);
    final entry = (payload()['files'] as List).single as Map;
    expect(entry['state'], 'missing');
    expect(entry['hash'], isNull);
    expect(entry['bytes'], isNull);
    await repository.verifyReplacementSnapshot(snapshot);
    await repository.discardReplacementSnapshot(snapshot);
    expect(rows('assets').single['id'], asset.id);
  });

  test('UT-080 partial all output states and recorded partial bytes are retained without pixel reinterpretation', () async {
    final output = await ProcessingCoordinator(repository).process(
      [asset.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        mode: ProcessingMode.sizeFirst,
        longestSide: 4,
      ),
      displayName: '所有状态.png',
    );
    final relative =
        rows('processed_outputs').single['relative_path'] as String;
    await File('${root.path}/$relative.part')
        .writeAsBytes([1, 3, 5, 7], flush: true);
    hold = await repository.acquireRestoreHold();
    for (final state in [
      'writing',
      'prepared',
      'ready',
      'failed',
      'cancelled',
      'deleting',
    ]) {
      mutate(
        (db) => db.execute('UPDATE processed_outputs SET state=? WHERE id=?', [
          state,
          output.id,
        ]),
      );
      final snapshot = await capture();
      expect(snapshot.fileCount, 3);
      expect(
        rows('processed_outputs', path: snapshotPath(snapshot)).single['state'],
        state,
      );
      final record = payload();
      final entry = (record['files'] as List).cast<Map>().singleWhere(
        (e) => e['source'] == '$relative.part',
      );
      expect(
        await File('${root.path}/${record['directory']}/${entry['filename']}')
            .readAsBytes(),
        [1, 3, 5, 7],
      );
      await repository.verifyReplacementSnapshot(snapshot);
      await expectLater(capture(), throwsA(isA<BackupSnapshotFailure>()));
      await repository.discardReplacementSnapshot(snapshot);
    }
  });

  test('UT-080 partial a file appearing at a missing backup name is never deleted as an owned partial', () async {
    await File('${root.path}/${asset.deviceCopy.relativePath}').delete();
    final snapshot = await capture();
    final record = payload();
    final entry = (record['files'] as List).single as Map;
    final unexpected = File(
      '${root.path}/${record['directory']}/${entry['filename']}',
    );
    await unexpected.writeAsBytes([4, 2], flush: true);
    await expectLater(
      repository.discardReplacementSnapshot(snapshot),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(await unexpected.readAsBytes(), [4, 2]);
    expect(await File(snapshotPath(snapshot)).exists(), true);
    await unexpected.delete();
    await repository.discardReplacementSnapshot(snapshot);
  });

  test('UT-080 partial unknown trigger and incompatible text policy refuse any snapshot intent write', () async {
    mutate(
      (db) => db.execute(
        "CREATE TRIGGER unsafe_snapshot AFTER INSERT ON restore_operations BEGIN UPDATE assets SET display_name='不应写入'; END",
      ),
    );
    await expectLater(capture(), throwsA(isA<BackupSnapshotFailure>()));
    expect(rows('restore_operations'), isEmpty);
    expect(rows('assets').single['display_name'], '本机原始名称.png');
    mutate((db) {
      db.execute('DROP TRIGGER unsafe_snapshot');
      db.execute(
        "UPDATE library_metadata SET value='future-policy' WHERE key='text_policy'",
      );
    });
    await expectLater(capture(), throwsA(isA<BackupSnapshotFailure>()));
    expect(rows('restore_operations'), isEmpty);
    mutate(
      (db) => db.execute(
        "UPDATE library_metadata SET value='unicode-17-nfc-full-cf-v1' WHERE key='text_policy'",
      ),
    );
  });

  test('UT-080 partial ready internal snapshot blocks another merge prepare or commit under the same hold', () async {
    final portable = await repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    final package = File('${sandbox.path}/metadata.zip');
    try {
      await BackupZipWriter().write(portable, package);
    } finally {
      await portable.release();
    }
    final parent = await Directory('${sandbox.path}/preflight').create();
    final validated = await const BackupZipReader().preflight(
      package,
      parent,
      availableBytes: (_) async => 1 << 40,
    );
    try {
      hold = await repository.acquireRestoreHold();
      final preparation = await repository.prepareMergeRestore(
        hold: hold!,
        backup: validated,
      );
      final snapshot = await capture();
      await expectLater(
        repository.prepareMergeRestore(hold: hold!, backup: validated),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      await expectLater(
        repository.commitMergeRestore(
          preparation: preparation,
          availableBytes: (_) async => 1 << 40,
          publishExclusive: (_, _) async => throw StateError('不应发布'),
        ),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      await repository.verifyReplacementSnapshot(snapshot);
      await repository.discardReplacementSnapshot(snapshot);
    } finally {
      await validated.dispose();
    }
  });

  test('UT-080 partial secret colliding with a managed UUID is rejected before ordinary journal writes', () async {
    final physicalId = asset.deviceCopy.relativePath
        .substring('originals/'.length)
        .split('.')
        .first;
    await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '冲突账号',
      anonymous: false,
      credential: physicalId,
      persistence: CredentialPersistence.protected,
    );
    await expectLater(capture(), throwsA(isA<BackupSnapshotFailure>()));
    expect(rows('restore_operations'), isEmpty);
    expect(await Directory('${root.path}/staging').list().toList(), isEmpty);
    expect(
      await File('${root.path}/${asset.deviceCopy.relativePath}').exists(),
      true,
    );
  });

  test('UT-080 partial hold waits actual leased IO and snapshot rejects a foreign or released hold', () async {
    final lease = await repository.acquireAssetLease([
      asset.id,
    ], purpose: '实际字节读取');
    final bytes = await File(lease.pathsByVersion.values.single).readAsBytes();
    expect(bytes, isNotEmpty);
    var acquired = false;
    final holding = repository.acquireRestoreHold().then((value) {
      acquired = true;
      return value;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(acquired, false);
    await lease.release();
    hold = await holding;
    final snapshot = await capture();
    final other = await LibraryRepository.open(
      Directory('${sandbox.path}/other'),
    );
    try {
      await expectLater(
        other.verifyReplacementSnapshot(snapshot),
        throwsA(isA<BackupSnapshotFailure>()),
      );
    } finally {
      await other.close();
    }
    await repository.discardReplacementSnapshot(snapshot);
    await hold!.release();
    await expectLater(
      repository.captureReplacementSnapshot(
        hold: hold!,
        availableBytes: (_) async => 1 << 40,
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
  });

  test('UT-080 partial directory occupied after intent is never claimed or deleted during failure or restart', () async {
    String? occupiedPath;
    await expectLater(
      capture(
        progress: (phase, _, _) {
          if (phase != '内部快照意图已记录') return;
          final record = payload();
          expect(record['directoryState'], 'unclaimed');
          occupiedPath = '${root.path}/${record['directory']}';
          Directory(occupiedPath!).createSync();
          File('$occupiedPath/current.sqlite')
              .writeAsBytesSync([7, 8, 9], flush: true);
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(rows('restore_operations'), isEmpty);
    expect(await File('$occupiedPath/current.sqlite').readAsBytes(), [7, 8, 9]);
    await hold!.release();
    hold = null;
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(await File('$occupiedPath/current.sqlite').readAsBytes(), [7, 8, 9]);
    expect((await repository.listAssets()).items.single.id, asset.id);
  });

  test('UT-080 partial failed durable directory ownership preserves the unclaimed empty directory', () async {
    String? unclaimedPath;
    await expectLater(
      capture(
        progress: (phase, _, _) {
          if (phase != '内部快照意图已记录') return;
          unclaimedPath = '${root.path}/${payload()['directory']}';
          mutate(
            (db) => db.execute(
              "CREATE TRIGGER reject_ownership BEFORE UPDATE ON restore_operations BEGIN SELECT RAISE(ABORT, 'controlled'); END",
            ),
          );
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    mutate((db) => db.execute('DROP TRIGGER reject_ownership'));
    expect(rows('restore_operations'), isEmpty);
    expect(await Directory(unclaimedPath!).exists(), true);
    expect(await Directory(unclaimedPath!).list().toList(), isEmpty);
    expect(
      await File('${root.path}/${asset.deviceCopy.relativePath}').exists(),
      true,
    );
  });

  test('UT-080 partial startup drops an unclaimed intent without touching its ambiguous directory', () async {
    final snapshot = await capture();
    final record = payload();
    record['directoryState'] = 'unclaimed';
    record['databaseHash'] = null;
    record['databaseBytes'] = null;
    record['schemaHash'] = null;
    record['tableHashes'] = null;
    for (final entry in record['files'] as List) {
      if ((entry as Map)['state'] == 'ready') entry['state'] = 'pending';
    }
    mutate(
      (db) => db.execute(
        "UPDATE restore_operations SET phase='snapshot-writing', payload_json=?",
        [jsonEncode(record)],
      ),
    );
    final originalSnapshotBytes = await File(snapshotPath(snapshot))
        .readAsBytes();
    await hold!.release();
    hold = null;
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(rows('restore_operations'), isEmpty);
    expect(
      await File(snapshotPath(snapshot)).readAsBytes(),
      originalSnapshotBytes,
    );
    expect((await repository.listAssets()).items.single.id, asset.id);
  });

  test('UT-080 partial low capacity refuses snapshot before files and keeps current records', () async {
    await expectLater(
      capture(available: (_) async => 0),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(rows('restore_operations'), isEmpty);
    expect(rows('assets').single['id'], asset.id);
    expect(await Directory('${root.path}/staging').list().toList(), isEmpty);
  });

  test('UT-080 partial cancellation after real copy cleans only journaled snapshot bytes', () async {
    final cancellation = CancellationToken();
    await expectLater(
      capture(
        cancellation: cancellation,
        progress: (phase, done, total) {
          if (phase == '正在保管内部快照') cancellation.cancel();
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(rows('restore_operations'), isEmpty);
    expect(
      await File('${root.path}/${asset.deviceCopy.relativePath}').exists(),
      true,
    );
    expect(await Directory('${root.path}/staging').list().toList(), isEmpty);
  });

  test('UT-080 partial future SQLite and unknown table schema cannot produce ready snapshot', () async {
    mutate(
      (db) => db.execute('PRAGMA user_version=${librarySchemaVersion + 1}'),
    );
    await expectLater(capture(), throwsA(isA<BackupSnapshotFailure>()));
    expect(rows('restore_operations'), isEmpty);
    mutate((db) {
      db.execute('PRAGMA user_version=$librarySchemaVersion');
      db.execute('CREATE TABLE unknown_future (id TEXT)');
    });
    await expectLater(capture(), throwsA(isA<BackupSnapshotFailure>()));
    expect(rows('restore_operations'), isEmpty);
    mutate((db) => db.execute('DROP TABLE unknown_future'));
    expect(rows('assets').single['id'], asset.id);
  });

  test('UT-080 partial tampered SQLite or raw file never verifies', () async {
    var snapshot = await capture();
    mutate(
      (db) => db.execute("UPDATE assets SET display_name='篡改'"),
      path: snapshotPath(snapshot),
    );
    await expectLater(
      repository.verifyReplacementSnapshot(snapshot),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    await repository.discardReplacementSnapshot(snapshot);
    snapshot = await capture();
    final record = payload();
    final entry = (record['files'] as List).single as Map;
    await File('${root.path}/${record['directory']}/${entry['filename']}')
        .writeAsBytes([0, 1, 2], flush: true);
    await expectLater(
      repository.verifyReplacementSnapshot(snapshot),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    await repository.discardReplacementSnapshot(snapshot);
    expect(rows('assets').single['display_name'], '本机原始名称.png');
  });

  test('UT-080 partial unknown child and malformed later log entry preserve complete snapshot and current bytes', () async {
    final snapshot = await capture();
    final originalPayload =
        rows('restore_operations').single['payload_json'] as String;
    final record = payload();
    final unknown = File('${root.path}/${record['directory']}/unknown.bin');
    await unknown.writeAsBytes([9], flush: true);
    await expectLater(
      repository.verifyReplacementSnapshot(snapshot),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    await expectLater(
      repository.discardReplacementSnapshot(snapshot),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(await File(snapshotPath(snapshot)).exists(), true);
    expect(await unknown.readAsBytes(), [9]);
    await unknown.delete();
    (record['files'] as List).add({
      'source': '../external',
      'filename': '../foreign',
      'state': 'ready',
      'hash': 'a' * 64,
      'bytes': 1,
    });
    mutate(
      (db) => db.execute('UPDATE restore_operations SET payload_json=?', [
        jsonEncode(record),
      ]),
    );
    await expectLater(
      repository.discardReplacementSnapshot(snapshot),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(await File(snapshotPath(snapshot)).exists(), true);
    mutate(
      (db) => db.execute('UPDATE restore_operations SET payload_json=?', [
        originalPayload,
      ]),
    );
    await repository.discardReplacementSnapshot(snapshot);
  });

  test(
    'UT-080 partial linked source is refused without reading external bytes',
    () async {
      final original = File('${root.path}/${asset.deviceCopy.relativePath}');
      final external = File('${sandbox.path}/external.bin');
      await external.writeAsBytes([8, 6, 4], flush: true);
      await original.delete();
      final link = Link(original.path);
      try {
        await link.create(external.path);
      } on FileSystemException {
        markTestSkipped('当前Windows测试进程无符号链接创建权限，链接实测未执行。');
        return;
      }
      try {
        await expectLater(capture(), throwsA(isA<BackupSnapshotFailure>()));
        expect(rows('restore_operations'), isEmpty);
        expect(await external.readAsBytes(), [8, 6, 4]);
      } finally {
        await link.delete();
      }
    },
  );

  test('UT-080 partial closing waits real snapshot IO and holds the root lock until completion', () async {
    hold = await repository.acquireRestoreHold();
    final entered = Completer<void>(), resume = Completer<void>();
    final capturing = capture(
      available: (_) async {
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
    await capturing;
    await closing;
    expect(closed, true);
    await hold!.release();
    hold = null;
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(rows('restore_operations'), isEmpty);
    expect((await repository.listAssets()).items.single.id, asset.id);
    expect(
      await File('${root.path}/${asset.deviceCopy.relativePath}').exists(),
      true,
    );
  });
}
