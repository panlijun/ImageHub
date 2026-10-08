import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/links/application/link_probe_coordinator.dart';
import 'package:imagehost/features/links/data/link_probe_gateway.dart';
import 'package:imagehost/features/links/domain/link_availability.dart';
import 'package:imagehost/features/links/domain/link_query.dart';
import 'package:imagehost/features/upload/domain/link_format.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

const _reachable = LinkProbeOutcome(
  LinkAvailability.accessible,
  LinkProbeReason.reachable,
  httpStatus: 200,
);
const _gone = LinkProbeOutcome(
  LinkAvailability.deleted,
  LinkProbeReason.gone,
  httpStatus: 410,
);

class _Gateway implements LinkProbeGateway {
  int calls = 0;
  final entered = Completer<void>();
  final gate = Completer<void>();
  bool held = false;
  LinkProbeOutcome outcome = _reachable;
  @override
  Future<LinkProbeOutcome> check({
    required Uri url,
    required ImageHostService service,
    required CancelToken cancelToken,
  }) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    if (held) await gate.future;
    return outcome;
  }
}

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late QueueTestSecrets secrets;
  late ImageAsset asset;
  late String target;
  var sequence = 0;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost-probe-repository-',
    );
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final bytes = img.encodePng(img.Image(width: 4, height: 3));
    asset = (await repository.importResource(
      PlatformResource(
        displayName: '检测保留原图.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    target = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '冻结目标',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  Future<String> result() async {
    final batch = await repository.enqueueUploads(
      intentId: 'probe-fixture-${sequence++}',
      assetIds: [asset.id],
      targetIds: [target],
      allowOriginalMetadata: true,
      forceAgain: true,
    );
    final execution = (await repository.beginUploadAttempt(
      batch.items.single.id,
    ))!;
    try {
      await repository.authorizeUploadRequest(execution.attemptId);
      await repository.finishUploadAttempt(
        execution,
        ProviderUploadSuccess(
          service: ImageHostService.catbox,
          remoteId: 'fixture$sequence.png',
          directUrl: Uri.parse('https://files.catbox.moe/fixture$sequence.png'),
        ),
        accumulatedRunning: Duration.zero,
      );
    } finally {
      await execution.release();
    }
    return (await repository.listUploadResults())
        .firstWhere((r) => r.attemptId == execution.attemptId)
        .id;
  }

  List<Map<String, Object?>> rows(String table) {
    final database = sqlite3.open(
      '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return database
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } finally {
      database.close();
    }
  }

  void mutate(void Function(Database) action) {
    final database = sqlite3.open('${root.path}/library.sqlite');
    try {
      action(database);
    } finally {
      database.close();
    }
  }

  Future<bool> observe(String id, LinkProbeOutcome outcome) async {
    final plan = await repository.prepareLinkProbe([id]);
    final execution = await repository.beginLinkProbe(
      plan,
      id,
      confirmNetwork: true,
    );
    return repository.finishLinkProbe(execution, outcome);
  }

  Future<void> reopen() async {
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  }

  void oldSchema6(Database database) {
    database.execute(
      'ALTER TABLE upload_publications DROP COLUMN processing_job_id',
    );
    database.execute('DROP TABLE upload_processing_jobs');
    database.execute('DROP TABLE diagnostic_records');
    database.execute('ALTER TABLE upload_publications DROP COLUMN user_paused');
    for (final column in [
      'link_state',
      'link_reason',
      'link_checked_utc',
      'last_accessible_utc',
      'probe_generation',
      'probe_http_status',
    ]) {
      database.execute('ALTER TABLE remote_upload_results DROP COLUMN $column');
    }
    database.execute('PRAGMA user_version=6');
  }

  test('UT-072 recorded presence and preparing a plan never request network or change confirmation history', () async {
    final id = await result(), before = rows('remote_upload_results');
    final gateway = _Gateway(),
        coordinator = LinkProbeCoordinator(repository, gateway);
    final plan = await repository.prepareLinkProbe([id, id]);
    expect(plan.results, hasLength(1));
    expect(() => plan.results.clear(), throwsUnsupportedError);
    expect(plan.results.single.availability.state, LinkAvailability.recorded);
    expect(gateway.calls, 0);
    expect(
      (await coordinator.run(plan, confirmNetwork: false)).status,
      LinkProbeBatchStatus.rejected,
    );
    expect(rows('remote_upload_results'), before);
    expect(gateway.calls, 0);
    await coordinator.close();
    await expectLater(
      repository.prepareLinkProbe([]),
      throwsA(isA<UploadQueueFailure>()),
    );
    await expectLater(
      repository.prepareLinkProbe(['../x']),
      throwsA(isA<UploadQueueFailure>()),
    );
  });

  test('UT-072 reachable then failed evidence retains past accessibility confirmation bytes organization and copy', () async {
    final category = await repository.createCategory('检测分类');
    await repository.updateOrganization(
      [asset.id],
      setCategory: true,
      categoryId: category.id,
      replaceTags: ['保留'],
      favorite: true,
    );
    final id = await result();
    final before = {
      for (final table in [
        'assets',
        'versions',
        'device_copies',
        'categories',
        'tags',
        'asset_tags',
        'upload_publications',
        'upload_attempts',
        'upload_events',
        'provider_targets',
      ])
        table: rows(table),
    };
    final bytes = await (await repository.originalFor(asset)).readAsBytes();
    final first = DateTime.utc(2026, 10, 6, 12),
        second = DateTime.utc(2026, 10, 6, 11);
    await withClock(Clock.fixed(first), () => observe(id, _reachable));
    await withClock(
      Clock.fixed(second),
      () => observe(id, LinkProbeOutcome.unconfirmed),
    );
    final current = (await repository.listUploadResults()).single;
    expect(current.availability.state, LinkAvailability.unknown);
    expect(current.availability.checkedAt, second);
    expect(
      current.availability.lastAccessibleAt,
      first,
      reason: 'UTC setbacks are not IO duration or fabricated freshness',
    );
    for (final item in before.entries) {
      expect(rows(item.key), item.value, reason: item.key);
    }
    expect(await (await repository.originalFor(asset)).readAsBytes(), bytes);
    expect(
      (await repository.prepareVisibleLinkCopy([
        id,
      ], UploadLinkFormat.url)).batch.copied,
      1,
    );
    await reopen();
    expect(
      (await repository.listUploadResults())
          .single
          .availability
          .lastAccessibleAt,
      first,
    );
    expect((await repository.getAsset(asset.id))!.favorite, true);
  });

  test('UT-072 service Gone persists deleted evidence without removing any ordinary result or source', () async {
    final id = await result();
    await observe(id, _gone);
    final current = (await repository.listUploadResults()).single;
    expect(current.availability.state, LinkAvailability.deleted);
    expect(current.availability.httpStatus, 410);
    expect(current.directUrl.scheme, 'https');
    expect(
      (await repository.listAssets()).items.single.confirmedRemoteResultCount,
      1,
    );
    expect(
      (await repository.prepareVisibleLinkCopy([
        id,
      ], UploadLinkFormat.url)).batch.copied,
      1,
    );
    await reopen();
    expect(
      (await repository.listUploadResults()).single.availability.reason,
      LinkProbeReason.gone,
    );
  });

  test('UT-017/072 availability is intersected before SQL count and paging across fifty results', () async {
    final ids = <String>[];
    for (var i = 0; i < 55; i++) {
      ids.add(await result());
    }
    await observe(ids[1], _reachable);
    await observe(ids[53], _reachable);
    await observe(ids[54], _gone);
    const query = LinkResultQuery(
      availability: LinkAvailability.accessible,
      service: ImageHostService.catbox,
      keyword: '检测',
    );
    final page = await repository.listLinkResults(query: query, limit: 1);
    final next = await repository.listLinkResults(
      query: query,
      limit: 1,
      offset: 1,
    );
    expect(page.total, 2);
    expect(next.total, 2);
    expect({page.items.single.id, next.items.single.id}, {ids[1], ids[53]});
    expect(
      (await repository.listLinkResults(
        query: query.copyWith(availability: null),
      )).total,
      55,
    );
    expect(
      (await repository.listLinkResults(
        query: query.copyWith(availability: LinkAvailability.deleted),
      )).items.single.id,
      ids[54],
    );
  });

  test('UT-072 newest generation wins while a late older probe only releases its own guard', () async {
    final id = await result(), plan = await repository.prepareLinkProbe([id]);
    final older = await repository.beginLinkProbe(
      plan,
      id,
      confirmNetwork: true,
    );
    final newer = await repository.beginLinkProbe(
      plan,
      id,
      confirmNetwork: true,
    );
    expect(await repository.finishLinkProbe(newer, _gone), true);
    expect(await repository.finishLinkProbe(older, _reachable), false);
    expect(
      (await repository.listUploadResults()).single.availability.state,
      LinkAvailability.deleted,
    );
    await expectLater(
      repository.finishLinkProbe(older, _reachable),
      throwsA(isA<UploadQueueFailure>()),
    );
  });

  test('UT-072 stale and foreign plans fail before gateway without implicit replacement or upload', () async {
    final id = await result(), plan = await repository.prepareLinkProbe([id]);
    await repository.removeLocalLinkResults([id], confirmLocalRemoval: true);
    final gateway = _Gateway(),
        coordinator = LinkProbeCoordinator(repository, gateway);
    expect(
      (await coordinator.run(plan, confirmNetwork: true)).status,
      LinkProbeBatchStatus.failed,
    );
    expect(gateway.calls, 0);
    await coordinator.close();
    final other = await LibraryRepository.open(
      Directory('${sandbox.path}/other'),
    );
    try {
      await expectLater(
        other.beginLinkProbe(plan, id, confirmNetwork: true),
        throwsA(isA<UploadQueueFailure>()),
      );
    } finally {
      await other.close();
    }
    expect(rows('upload_publications'), hasLength(1));
  });

  test(
    'UT-072 reopening refuses an old owner plan before another request',
    () async {
      final id = await result(), plan = await repository.prepareLinkProbe([id]);
      await reopen();
      final gateway = _Gateway(),
          coordinator = LinkProbeCoordinator(repository, gateway);
      expect(
        (await coordinator.run(plan, confirmNetwork: true)).status,
        LinkProbeBatchStatus.failed,
      );
      expect(gateway.calls, 0);
      await coordinator.close();
      expect(
        (await repository.listUploadResults()).single.availability.state,
        LinkAvailability.recorded,
      );
    },
  );

  test('UT-072 actual transport return rather than cancel state drains repository close', () async {
    final id = await result(), plan = await repository.prepareLinkProbe([id]);
    final gateway = _Gateway()..held = true;
    final coordinator = LinkProbeCoordinator(repository, gateway);
    final running = coordinator.run(plan, confirmNetwork: true);
    await gateway.entered.future;
    coordinator.cancel();
    var closed = false;
    final closing = repository.close().then((_) => closed = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, false);
    gateway.gate.complete();
    expect((await running).status, LinkProbeBatchStatus.cancelled);
    await closing;
    await coordinator.close();
    await reopen();
    expect(
      (await repository.listUploadResults()).single.availability.reason,
      LinkProbeReason.cancelled,
    );
  });

  test('UT-072 actual probe finish settles behind a maintenance barrier and unblocks safe restore', () async {
    final id = await result(), plan = await repository.prepareLinkProbe([id]);
    final gateway = _Gateway()..held = true;
    final coordinator = LinkProbeCoordinator(repository, gateway);
    final running = coordinator.run(plan, confirmNetwork: true);
    await gateway.entered.future;
    var ready = false;
    final acquiring = repository.acquireRestoreHold().then((hold) {
      ready = true;
      return hold;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ready, false);
    await expectLater(
      repository.prepareLinkProbe([id]),
      throwsA(isA<Exception>()),
    );
    gateway.gate.complete();
    await running;
    final hold = await acquiring;
    await hold.release();
    await coordinator.close();
    expect(
      (await repository.listUploadResults()).single.availability.state,
      LinkAvailability.accessible,
    );
  });

  test('UT-072 unsafe cleanup failure retains guard and wakes close to fail instead of deadlock', () async {
    final id = await result(), plan = await repository.prepareLinkProbe([id]);
    final execution = await repository.beginLinkProbe(
      plan,
      id,
      confirmNetwork: true,
    );
    final closing = repository.close();
    final expectedFailure = expectLater(
      closing,
      throwsA(isA<UploadQueueFailure>()),
    );
    repository.retainUnsettledLinkProbe(execution);
    await expectedFailure;
    await expectLater(
      repository.prepareLinkProbe([id]),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(
      (await repository.listUploadResults()).single.availability.reason,
      LinkProbeReason.interrupted,
    );
    // The test now supplies independent proof of actual IO completion. The
    // application never releases this guard merely because cancellation fired.
    await repository.finishLinkProbe(execution, LinkProbeOutcome.cancelled);
  });

  test('UT-072 status transaction failure leaves interrupted evidence and drains ended IO', () async {
    final id = await result(), plan = await repository.prepareLinkProbe([id]);
    final execution = await repository.beginLinkProbe(
      plan,
      id,
      confirmNetwork: true,
    );
    mutate(
      (db) => db.execute(
        "CREATE TRIGGER fail_probe_update BEFORE UPDATE ON remote_upload_results BEGIN SELECT RAISE(ABORT,'synthetic write failure'); END",
      ),
    );
    try {
      await expectLater(
        repository.finishLinkProbe(execution, _reachable),
        throwsA(isA<UploadQueueFailure>()),
      );
    } finally {
      mutate((db) => db.execute('DROP TRIGGER fail_probe_update'));
    }
    await reopen();
    expect(
      (await repository.listUploadResults()).single.availability.reason,
      LinkProbeReason.interrupted,
    );
    expect(await repository.getAsset(asset.id), isNotNull);
  });

  test('UT-072 session close cancels its actor and waits real gateway while library remains protected', () async {
    final id = await result(), plan = await repository.prepareLinkProbe([id]);
    final gateway = _Gateway()..held = true;
    final session = LibrarySession(repository, const []);
    final coordinator = session.linkProbesWith(gateway);
    final running = coordinator.run(plan, confirmNetwork: true);
    await gateway.entered.future;
    var closed = false;
    final closing = session.close().then((_) => closed = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, false);
    gateway.gate.complete();
    await running;
    await closing;
    await reopen();
    expect(
      (await repository.listUploadResults()).single.availability.reason,
      LinkProbeReason.cancelled,
    );
    expect(session.existingUploads, isNull);
  });

  test('UT-093 own schema6 actual migration preserves ordinary identity credentials and original bytes', () async {
    final id = await result();
    final bytes = await (await repository.originalFor(asset)).readAsBytes();
    await repository.close();
    mutate(oldSchema6);
    final before = rows('remote_upload_results'),
        protected = Map.of(secrets.values);
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final row = rows('remote_upload_results').single;
    expect({
      for (final key in before.single.keys) key: row[key],
    }, before.single);
    expect((await repository.listUploadResults()).single.id, id);
    expect(
      (await repository.listUploadResults()).single.availability.state,
      LinkAvailability.recorded,
    );
    expect(secrets.values, protected);
    expect(await (await repository.originalFor(asset)).readAsBytes(), bytes);
  });

  test('UT-093 own schema6 pending recovery journal refuses mutation and preserves all old evidence', () async {
    await result();
    await repository.close();
    mutate((db) {
      oldSchema6(db);
      db.execute('INSERT INTO restore_operations VALUES (?,?,?,?)', [
        '00000000-0000-4000-8000-000000000001',
        'replace-rollback',
        '{}',
        1,
      ]);
    });
    final before = rows('remote_upload_results'),
        journal = rows('restore_operations');
    await expectLater(
      LibraryRepository.open(root, secretStore: secrets),
      throwsA(isA<LibraryOpenException>()),
    );
    expect(rows('remote_upload_results'), before);
    expect(rows('restore_operations'), journal);
    mutate((db) {
      expect(db.select('PRAGMA user_version').single.values.single, 6);
      db.execute('DELETE FROM restore_operations');
    });
    repository = await LibraryRepository.open(root, secretStore: secrets);
  });

  for (final mode in BackupMode.values) {
    test(
      'UT-072/073 $mode portable restore retains ordinary confirmation without importing local reachability',
      () async {
        final id = await result();
        await observe(id, _reachable);
        final original = (await repository.listLinkResults()).items.single;
        final snapshot = await repository.captureBackupSnapshot(mode: mode);
        final archive = File('${sandbox.path}/${mode.name}.zip');
        try {
          final manifest = jsonDecode(
            utf8.decode(snapshot.manifestBytes),
          ) as Map<String, dynamic>;
          expect(manifest['formatVersion'], 2);
          expect(
            snapshot.manifest.settings!.values,
            repository.currentDeviceSettings,
          );
          final portable = (manifest['results'] as List).single as Map;
          for (final field in [
            'availability',
            'linkState',
            'linkReason',
            'linkCheckedUtc',
            'lastAccessibleUtc',
            'probeGeneration',
            'probeHttpStatus',
          ]) {
            expect(portable.containsKey(field), isFalse);
          }
          await BackupZipWriter().write(snapshot, archive);
        } finally {
          await snapshot.release();
        }
        final preflight = await const BackupZipReader().preflight(
          archive,
          await Directory('${sandbox.path}/preflight-${mode.name}').create(),
          availableBytes: (_) async => 1 << 40,
        );
        final destination = await LibraryRepository.open(
          Directory('${sandbox.path}/destination-${mode.name}'),
          secretStore: QueueTestSecrets(),
        );
        try {
          final hold = await destination.acquireRestoreHold();
          try {
            final preparation = await destination.prepareMergeRestore(
              hold: hold,
              backup: preflight,
            );
            expect(preparation.plan.canCommit, isTrue);
            await destination.commitMergeRestore(
              preparation: preparation,
              availableBytes: (_) async => 1 << 40,
              publishExclusive: (staged, target) async {
                // Controlled publication; actual Windows no-replace is covered by IT.
                if (await target.exists()) return false;
                await staged.rename(target.path);
                return true;
              },
            );
          } finally {
            await hold.release();
          }
          final restored = (await destination.listLinkResults()).items.single;
          expect(restored.id, id);
          expect(restored.directUrl, original.directUrl);
          expect(restored.availability.state, LinkAvailability.recorded);
          expect(restored.availability.checkedAt, isNull);
          expect(restored.availability.lastAccessibleAt, isNull);
          expect(
            (await repository.listLinkResults())
                .items
                .single
                .availability
                .state,
            LinkAvailability.accessible,
          );
        } finally {
          await destination.close();
          await preflight.dispose();
        }
      },
    );
  }

  test('UT-072 future or inconsistent observation refuses display without rewriting confirmation', () async {
    await result();
    final before = rows('remote_upload_results').single;
    mutate(
      (db) => db.execute(
        "UPDATE remote_upload_results SET link_state='future-state'",
      ),
    );
    await expectLater(
      repository.listLinkResults(),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(
      rows('remote_upload_results').single['direct_url'],
      before['direct_url'],
    );
    mutate(
      (db) =>
          db.execute("UPDATE remote_upload_results SET link_state='recorded'"),
    );
  });
}
