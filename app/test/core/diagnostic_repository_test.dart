import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

void main() {
  late Directory sandbox, root;
  late DateTime now;
  LibraryRepository? repository;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-diagnostics-');
    root = Directory('${sandbox.path}/library');
    now = DateTime.now().toUtc();
  });
  tearDown(() async {
    await repository?.close();
    repository = null;
    await sandbox.delete(recursive: true);
  });

  Future<T> at<T>(DateTime instant, Future<T> Function() action) =>
      withClock(Clock.fixed(instant), action);

  DiagnosticEvent event(
    int number, {
    DateTime? occurredAt,
    DiagnosticKind kind = DiagnosticKind.system,
    DiagnosticLevel level = DiagnosticLevel.info,
    String? batchId,
    String? attemptId,
    String summary = '真实本机诊断。',
    Object? details,
  }) => DiagnosticEvent(
    id: _id(number),
    occurredAt: occurredAt ?? now,
    kind: kind,
    level: level,
    code: 'fixture.recorded',
    summary: summary,
    recoveryAction: '请核查本机记录后重试。',
    batchId: batchId,
    attemptId: attemptId,
    details: details,
  );

  void mutate(void Function(Database) action) {
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      action(db);
    } finally {
      db.close();
    }
  }

  List<Map<String, Object?>> rows(String table) {
    final db = sqlite3.open(
      '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return db
          .select('SELECT * FROM "$table" ORDER BY id')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
    } finally {
      db.close();
    }
  }

  final picture = img.encodePng(img.Image(width: 4, height: 3));

  test('UT-089 actual default 10 MB payload window removes oldest without claiming SQLite pages reclaimed', () async {
    repository = await LibraryRepository.open(root);
    final details = List.filled(14, 'x' * 4096);
    final sample = event(1, details: details);
    final eventSize = utf8.encode(jsonEncode(sample.toJson())).length;
    expect(eventSize, lessThan(65536));
    final count = LibraryDiagnostics.maxContentBytes ~/ eventSize + 1;
    mutate((db) {
      db.execute('BEGIN');
      try {
        for (var i = 1; i <= count; i++) {
          final item = event(i, details: details);
          final payload = jsonEncode(item.toJson());
          db.execute(
            'INSERT INTO diagnostic_records(id,occurred_utc,kind,level,code,payload_json,content_bytes) VALUES(?,?,?,?,?,?,?)',
            [
              item.id,
              item.occurredAt.millisecondsSinceEpoch,
              item.kind.name,
              item.level.name,
              item.code,
              payload,
              utf8.encode(payload).length,
            ],
          );
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    });
    final page = await repository!.loadDiagnostics();
    expect(page.total, count - 1);
    expect(page.contentBytes, (count - 1) * eventSize);
    expect(page.contentBytes, lessThan(10000000));
    expect(rows('diagnostic_records').first['id'], _id(2));
    expect(rows('diagnostic_records').last['id'], _id(count));
  });

  test('UT-085 unavailable owned credential backend refuses diagnostic view and export with evidence intact', () async {
    final secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    await repository!.recordDiagnostic(event(1));
    await repository!.saveTarget(
      service: ImageHostService.catbox,
      alias: '受保护目标',
      anonymous: false,
      credential: 'synthetic-private-diagnostic-key-0123456789',
      persistence: CredentialPersistence.protected,
    );
    final plan = await repository!.prepareDiagnosticSelection();
    final evidence = rows('diagnostic_records');
    secrets.failReads = true;
    await expectLater(
      repository!.loadDiagnostics(),
      throwsA(isA<DiagnosticFailure>()),
    );
    await expectLater(
      repository!.diagnosticExport(plan),
      throwsA(isA<DiagnosticFailure>()),
    );
    expect(rows('diagnostic_records'), evidence);
    secrets.failReads = false;
    expect((await repository!.diagnosticExport(plan)).count, plan.count);
  });
  Future<ImportResult> importPicture() => repository!.importResource(
    PlatformResource(
      displayName: '独立图片.png',
      openRead: () => Stream.value(picture),
    ),
  );

  test('UT-084 real committed import logs the actual asset UUID and failed import excludes raw error and source path', () async {
    repository = await LibraryRepository.open(root);
    final saved = await importPicture();
    expect(saved.status, ImportStatus.saved);
    final success = (await repository!.loadDiagnostics(
      query: DiagnosticQuery(kind: DiagnosticKind.importImage),
    )).items.single;
    expect(success.entityId, saved.asset!.id);
    expect(success.code, 'import.saved.completed');
    expect(success.level, DiagnosticLevel.info);
    expect(
      await (await repository!.originalFor(saved.asset!)).readAsBytes(),
      picture,
    );

    const rawError = 'private-raw-error-key-012345';
    const sourcePath = r'C:\private-source\original.png';
    final failed = await repository!.importResource(
      PlatformResource(
        displayName: sourcePath,
        openRead: () => Stream.error(StateError('$rawError $sourcePath')),
      ),
    );
    expect(failed.status, ImportStatus.failed);
    final page = await repository!.loadDiagnostics(
      query: DiagnosticQuery(
        kind: DiagnosticKind.importImage,
        level: DiagnosticLevel.error,
      ),
    );
    expect(page.total, 1);
    expect(page.items.single.code, 'import.failed.failed');
    expect(page.items.single.entityId, isNull);
    expect(page.items.single.recoveryAction, isNotEmpty);
    final persisted = jsonEncode(rows('diagnostic_records'));
    expect(persisted, isNot(contains(rawError)));
    expect(persisted, isNot(contains('private-source')));
    expect((await repository!.listAssets()).items.single.id, saved.asset!.id);
  });

  test('UT-084/085 UUID batch and attempt predicates intersect before count and stable pagination', () async {
    repository = await LibraryRepository.open(root);
    final batch = _id(50), attempt = _id(60);
    final fixtures = [
      event(
        1,
        kind: DiagnosticKind.upload,
        level: DiagnosticLevel.error,
        batchId: batch,
        attemptId: attempt,
      ),
      event(
        2,
        kind: DiagnosticKind.upload,
        level: DiagnosticLevel.error,
        batchId: batch,
        attemptId: attempt,
      ),
      event(
        3,
        kind: DiagnosticKind.upload,
        level: DiagnosticLevel.warning,
        batchId: batch,
        attemptId: attempt,
      ),
      event(
        4,
        kind: DiagnosticKind.upload,
        level: DiagnosticLevel.error,
        batchId: _id(51),
        attemptId: attempt,
      ),
      event(
        5,
        kind: DiagnosticKind.upload,
        level: DiagnosticLevel.error,
        batchId: batch,
        attemptId: _id(61),
      ),
      event(
        6,
        kind: DiagnosticKind.system,
        level: DiagnosticLevel.error,
        batchId: batch,
        attemptId: attempt,
      ),
    ];
    for (final fixture in fixtures.reversed) {
      await at(now, () => repository!.recordDiagnostic(fixture));
    }
    final query = DiagnosticQuery(
      kind: DiagnosticKind.upload,
      level: DiagnosticLevel.error,
      batchId: batch,
      attemptId: attempt,
    );
    final first = await repository!.loadDiagnostics(query: query, limit: 1);
    final second = await repository!.loadDiagnostics(
      query: query,
      offset: 1,
      limit: 1,
    );
    final last = await repository!.loadDiagnostics(
      query: query,
      offset: 2,
      limit: 1,
    );
    expect(first.items.single.id, _id(1));
    expect(second.items.single.id, _id(2));
    expect(last.items, isEmpty);
    for (final page in [first, second, last]) {
      expect(page.total, 2);
      expect(
        page.contentBytes,
        rows('diagnostic_records')
            .where((row) => [_id(1), _id(2)].contains(row['id']))
            .fold<int>(
              0,
              (sum, row) =>
                  sum + utf8.encode(row['payload_json'] as String).length,
            ),
      );
    }
    expect(
      (await repository!.loadDiagnostics(
        query: DiagnosticQuery(batchId: batch),
      )).total,
      5,
    );
    expect(
      (await repository!.loadDiagnostics(
        query: DiagnosticQuery(attemptId: attempt),
      )).total,
      5,
    );
    expect(
      (await repository!.loadDiagnostics(
        query: DiagnosticQuery(batchId: _id(999)),
      )).total,
      0,
    );
  });

  test('UT-085 frozen clear excludes later logs and preserves actual images tasks attempts events and ordinary result after reopen', () async {
    final secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final asset = (await importPicture()).asset!;
    final target = await repository!.saveTarget(
      service: ImageHostService.catbox,
      alias: '本机目标',
      anonymous: false,
      credential: 'synthetic-diagnostic-target-key',
    );
    final batch = await repository!.enqueueUploads(
      intentId: 'diagnostics-clear-fixture',
      assetIds: [asset.id],
      targetIds: [target],
      allowOriginalMetadata: true,
    );
    final execution = (await repository!.beginUploadAttempt(
      batch.items.single.id,
    ))!;
    try {
      expect(
        await repository!.authorizeUploadRequest(execution.attemptId),
        true,
      );
      await repository!.finishUploadAttempt(
        execution,
        ProviderUploadSuccess(
          service: ImageHostService.catbox,
          remoteId: 'diagnostic.png',
          directUrl: Uri.parse('https://files.catbox.moe/diagnostic.png'),
        ),
        accumulatedRunning: const Duration(seconds: 1),
      );
    } finally {
      await execution.release();
    }
    const retainedTables = [
      'assets',
      'versions',
      'device_copies',
      'upload_batches',
      'upload_publications',
      'upload_attempts',
      'upload_events',
      'remote_upload_results',
    ];
    final before = {for (final table in retainedTables) table: rows(table)};
    for (final table in retainedTables) {
      expect(
        before[table],
        isNotEmpty,
        reason: '$table must be a real fixture',
      );
    }
    final ordinaryResult = (await repository!.listUploadResults()).single;
    final original = await repository!.originalFor(asset);
    final plan = await repository!.prepareDiagnosticSelection();
    expect(plan.count, greaterThan(0));
    final later = event(100);
    await repository!.recordDiagnostic(later);
    final exported = await repository!.diagnosticExport(plan);
    expect(exported.count, plan.count);
    expect(utf8.decode(exported.bytes), isNot(contains(later.id)));
    expect(await repository!.clearDiagnostics(plan), plan.count);
    expect((await repository!.loadDiagnostics()).items.single.id, later.id);
    expect({for (final table in retainedTables) table: rows(table)}, before);
    expect(await original.readAsBytes(), picture);
    expect(
      (await repository!.listUploadResults()).single.id,
      ordinaryResult.id,
    );
    await repository!.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(
      (await repository!.loadDiagnostics()).items.single.toJson(),
      later.toJson(),
    );
    expect({for (final table in retainedTables) table: rows(table)}, before);
    expect(await (await repository!.originalFor(asset)).readAsBytes(), picture);
  });

  test('UT-089 exact thirty day cutoff expires while one millisecond younger remains across normal close and reopen', () async {
    final created = DateTime.utc(2030, 1, 1);
    repository = await at(created, () => LibraryRepository.open(root));
    final cutoff = event(1, occurredAt: created);
    final younger = event(
      2,
      occurredAt: created.add(const Duration(milliseconds: 1)),
    );
    await at(created, () => repository!.recordDiagnostic(cutoff));
    await at(created, () => repository!.recordDiagnostic(younger));
    final almost = await at(
      created
          .add(const Duration(days: 30))
          .subtract(const Duration(milliseconds: 1)),
      () => repository!.loadDiagnostics(),
    );
    expect(almost.total, 2);
    await repository!.close();
    repository = await at(
      created.add(const Duration(days: 30)),
      () => LibraryRepository.open(root),
    );
    final page = await at(
      created.add(const Duration(days: 30)),
      () => repository!.loadDiagnostics(),
    );
    expect(page.items.single.id, younger.id);
    expect(rows('diagnostic_records').single['id'], younger.id);
  });

  for (final margin in [0, 1]) {
    test(
      'UT-089 actual multibyte UTF8 cap ${margin == 0 ? "at equality evicts" : "one byte below retains"} with stable oldest UTC UUID order',
      () async {
        final first = event(1, summary: '汉😀' * 30);
        final second = event(2, summary: '汉😀' * 30);
        final each = utf8.encode(jsonEncode(first.toJson())).length;
        expect(each, greaterThan(jsonEncode(first.toJson()).length));
        expect(utf8.encode(jsonEncode(second.toJson())).length, each);
        repository = await LibraryRepository.open(
          root,
          diagnosticMaxBytes: each * 2 + margin,
        );
        // Same UTC: id ascending is oldest, independent of insertion order.
        await repository!.recordDiagnostic(second);
        await repository!.recordDiagnostic(first);
        final page = await repository!.loadDiagnostics();
        expect(
          page.items.map((row) => row.id),
          margin == 0 ? [_id(2)] : [_id(1), _id(2)],
        );
        final stored = rows('diagnostic_records');
        for (final row in stored) {
          expect(
            row['content_bytes'],
            utf8.encode(row['payload_json'] as String).length,
          );
        }
        expect(page.contentBytes, each * (margin == 0 ? 1 : 2));
        expect(page.contentBytes, lessThan(each * 2 + margin));
        if (margin == 0) {
          final newest = event(
            3,
            occurredAt: now.add(const Duration(milliseconds: 1)),
            summary: '汉😀' * 30,
          );
          await repository!.recordDiagnostic(newest);
          expect(
            (await repository!.loadDiagnostics()).items.single.id,
            newest.id,
          );
        }
      },
    );
  }

  for (final corruption in ['future format', 'byte count', 'indexed code']) {
    test(
      'UT-084/085 corrupt $corruption rejects reading export and clear and retains the original SQL evidence',
      () async {
        repository = await LibraryRepository.open(root);
        await repository!.recordDiagnostic(event(1));
        final plan = await repository!.prepareDiagnosticSelection();
        mutate((db) {
          if (corruption == 'future format') {
            final payload = jsonDecode(
              db
                      .select('SELECT payload_json FROM diagnostic_records')
                      .single['payload_json']
                  as String,
            ) as Map<String, dynamic>;
            payload['schemaVersion'] = DiagnosticEvent.schemaVersion + 1;
            final text = jsonEncode(payload);
            db.execute(
              'UPDATE diagnostic_records SET payload_json=?, content_bytes=?',
              [text, utf8.encode(text).length],
            );
          } else if (corruption == 'byte count') {
            db.execute(
              'UPDATE diagnostic_records SET content_bytes=content_bytes+1',
            );
          } else {
            db.execute("UPDATE diagnostic_records SET code='tampered.index'");
          }
        });
        final evidence = rows('diagnostic_records');
        if (corruption != 'byte count') {
          expect(
            evidence.single['content_bytes'],
            utf8.encode(evidence.single['payload_json'] as String).length,
          );
        }
        await expectLater(
          repository!.loadDiagnostics(),
          throwsA(isA<DiagnosticFailure>()),
        );
        await expectLater(
          repository!.diagnosticExport(plan),
          throwsA(isA<DiagnosticFailure>()),
        );
        await expectLater(
          repository!.clearDiagnostics(plan),
          throwsA(isA<DiagnosticFailure>()),
        );
        await expectLater(
          repository!.recordDiagnostic(event(2)),
          throwsA(isA<DiagnosticFailure>()),
        );
        expect(rows('diagnostic_records'), evidence);
        await repository!.close();
        repository = await LibraryRepository.open(root);
        expect(repository!.diagnosticWarning, isNotNull);
        expect(rows('diagnostic_records'), evidence);
        await expectLater(
          repository!.loadDiagnostics(),
          throwsA(isA<DiagnosticFailure>()),
        );
        expect(rows('diagnostic_records'), evidence);
      },
    );
  }

  for (final persistence in CredentialPersistence.values) {
    test(
      'UT-084/085 export execution re-masks ${persistence.name} secret registered after prepare and excludes image raw body URLs and paths',
      () async {
        final secrets = QueueTestSecrets();
        repository = await LibraryRepository.open(root, secretStore: secrets);
        const secret = 'known-diagnostic-secret+/=%終';
        final encoded = Uri.encodeComponent(secret);
        final twice = Uri.encodeComponent(encoded);
        const userhash = 'unknown-userhash-012345';
        const deletionUrl = 'https://ibb.co/private/unknown-delete-token';
        const imageData = 'data:image/png;base64,privateImageBytes012345';
        const body = 'privateRawResponseBody012345';
        const windows = r'C:\private-diagnostic\source.png';
        const unc = r'\\private-server\share\source.png';
        const posix = '/private-diagnostic/source.png';
        final fixture = event(
          1,
          summary: '已确认 $secret',
          details: {
            'ordinary': [
              secret,
              encoded,
              twice,
              {'nested': secret},
            ],
            'userhash': userhash,
            'delete_url': deletionUrl,
            'windowsLocation': windows,
            'uncLocation': unc,
            'posixLocation': posix,
            'image': imageData,
            'rawBody': body,
            'publicUrl': 'https://files.catbox.moe/public.png?private=discarded-query#discarded-fragment',
            'count': 7,
          },
        );
        await repository!.recordDiagnostic(fixture);
        final plan = await repository!.prepareDiagnosticSelection();
        // Prove this is execution-time masking, not only insert-time masking.
        final before = utf8.decode(
          (await repository!.diagnosticExport(plan)).bytes,
        );
        expect(before, contains(secret));
        await repository!.saveTarget(
          service: ImageHostService.catbox,
          alias: '真实注册',
          anonymous: false,
          credential: secret,
          persistence: persistence,
        );
        final exported = await repository!.diagnosticExport(plan);
        final json = utf8.decode(exported.bytes);
        final persistedDiagnostics = jsonEncode(rows('diagnostic_records'));
        for (final known in [secret, encoded, twice]) {
          expect(persistedDiagnostics, isNot(contains(known)));
        }
        for (final forbidden in [
          secret,
          encoded,
          twice,
          userhash,
          deletionUrl,
          'privateImageBytes012345',
          body,
          'private-diagnostic',
          'private-server',
          'discarded-query',
          'discarded-fragment',
        ]) {
          expect(json, isNot(contains(forbidden)), reason: forbidden);
        }
        final document = jsonDecode(json) as Map<String, dynamic>;
        expect(document['formatVersion'], 1);
        expect(document['eventCount'], 1);
        final safe = DiagnosticEvent.fromJson(
          (document['events'] as List).single,
        );
        expect(safe.id, fixture.id);
        expect((safe.details as Map)['count'], 7);
        expect(
          (safe.details as Map)['publicUrl'],
          'https://files.catbox.moe/public.png',
        );
        expect((safe.details as Map)['ordinary'], isA<List>());
        expect((safe.details as Map).containsKey('image'), false);
        expect((safe.details as Map).containsKey('rawBody'), false);
        expect(exported.count, 1);
      },
    );
  }

  test('UT-085 foreign owner and close reopen invalidate diagnostic plans without deleting or exporting current evidence', () async {
    repository = await LibraryRepository.open(root);
    await repository!.recordDiagnostic(event(1));
    final plan = await repository!.prepareDiagnosticSelection();
    final foreign = await LibraryRepository.open(
      Directory('${sandbox.path}/foreign'),
    );
    try {
      await foreign.recordDiagnostic(event(2));
      await expectLater(
        foreign.diagnosticExport(plan),
        throwsA(isA<DiagnosticFailure>()),
      );
      await expectLater(
        foreign.clearDiagnostics(plan),
        throwsA(isA<DiagnosticFailure>()),
      );
      expect((await foreign.loadDiagnostics()).items.single.id, _id(2));
    } finally {
      await foreign.close();
    }
    final epoch = repository!.executionEpoch;
    final evidence = rows('diagnostic_records');
    await repository!.close();
    repository = await LibraryRepository.open(root);
    expect(repository!.executionEpoch, isNot(epoch));
    await expectLater(
      repository!.diagnosticExport(plan),
      throwsA(isA<DiagnosticFailure>()),
    );
    await expectLater(
      repository!.clearDiagnostics(plan),
      throwsA(isA<DiagnosticFailure>()),
    );
    expect(rows('diagnostic_records'), evidence);
  });

  test('UT-084 diagnostic INSERT rollback fault cannot change committed import or upload enqueue and warns without recursive logs', () async {
    repository = await LibraryRepository.open(root);
    mutate(
      (db) => db.execute(
        "CREATE TRIGGER fail_diagnostics BEFORE INSERT ON diagnostic_records BEGIN SELECT RAISE(ROLLBACK, 'private-trigger-error'); END",
      ),
    );
    final saved = await importPicture();
    expect(saved.status, ImportStatus.saved);
    expect((await repository!.listAssets()).items.single.id, saved.asset!.id);
    expect(
      await (await repository!.originalFor(saved.asset!)).readAsBytes(),
      picture,
    );
    expect(repository!.diagnosticWarning, isNotNull);
    expect(
      repository!.diagnosticWarning,
      isNot(contains('private-trigger-error')),
    );
    expect(rows('diagnostic_records'), isEmpty);
    await expectLater(
      repository!.recordDiagnostic(event(1)),
      throwsA(anything),
    );
    expect(rows('diagnostic_records'), isEmpty);
    expect(repository!.diagnosticWarning, isNotNull);
    final target = await repository!.saveTarget(
      service: ImageHostService.catbox,
      alias: '故障隔离目标',
      anonymous: false,
      credential: 'synthetic-diagnostic-session-key',
      persistence: CredentialPersistence.session,
    );
    final batch = await repository!.enqueueUploads(
      intentId: 'diagnostic-rollback-enqueue',
      assetIds: [saved.asset!.id],
      targetIds: [target],
      allowOriginalMetadata: true,
    );
    expect((await repository!.listUploadBatches()).single.id, batch.id);
    expect(rows('upload_batches').single['id'], batch.id);
    expect(rows('upload_publications').single['id'], batch.items.single.id);
    expect(rows('upload_events'), isNotEmpty);
    expect(rows('version_references'), isNotEmpty);
    expect(repository!.diagnosticWarning, isNotNull);
    expect(rows('diagnostic_records'), isEmpty);
    mutate((db) => db.execute('DROP TRIGGER fail_diagnostics'));
    final duplicate = await importPicture();
    expect(duplicate.status, ImportStatus.duplicate);
    expect(duplicate.asset!.id, saved.asset!.id);
    expect(repository!.diagnosticWarning, isNull);
    expect(
      (await repository!.loadDiagnostics()).items.single.code,
      'import.duplicate.completed',
    );
    await repository!.close();
    repository = await LibraryRepository.open(root);
    expect((await repository!.listUploadBatches()).single.id, batch.id);
    expect(rows('upload_events'), isNotEmpty);
    expect(rows('version_references'), isNotEmpty);
    expect(
      await (await repository!.originalFor(saved.asset!)).readAsBytes(),
      picture,
    );
  });
}
