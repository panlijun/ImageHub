import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/links/domain/remote_deletion.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;
import '../support/legacy_anonymous_fixture.dart';

/// Shared real-file fixture; gateways in these tests never contact a service.
class RemoteDeletionFixture {
  static const prefix = 'imagehost-remote-delete-';
  static const credential = 'synthetic-remote-delete-userhash-A';
  late Directory sandbox, root;
  late LibraryRepository repository;
  final secrets = QueueTestSecrets();
  late ImageAsset asset;
  late String target;
  var sequence = 0;

  Future<void> open() async {
    sandbox = await Directory.systemTemp.createTemp(prefix);
    root = Directory(p.join(sandbox.path, 'library'));
    repository = await LibraryRepository.open(root, secretStore: secrets);
    final bytes = img.encodePng(img.Image(width: 5, height: 4));
    asset = (await repository.importResource(
      PlatformResource(
        displayName: '远端删除保留原图.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    target = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '原账号',
      anonymous: false,
      credential: credential,
    );
  }

  Future<String> result({String? targetId, String? directUrl}) async {
    final filename = 'fixture${sequence++}.png';
    final batch = await repository.enqueueUploads(
      intentId: 'remote-delete-fixture-$sequence',
      assetIds: [asset.id],
      targetIds: [targetId ?? target],
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
          remoteId: filename,
          directUrl: Uri.parse(
            directUrl ?? 'https://files.catbox.moe/$filename',
          ),
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

  Future<RemoteDeletionExecution> begin(RemoteDeletionPlan plan) =>
      repository.beginRemoteDeletion(
        plan,
        confirmNetwork: true,
        confirmRemoteDeletion: true,
      );

  List<Map<String, Object?>> rows(String table) {
    final database = sqlite3.open(
      p.join(root.path, 'library.sqlite'),
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
    final database = sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      action(database);
    } finally {
      database.close();
    }
  }

  List<Map<String, Object?>> auditRows() =>
      rows('library_metadata')
          .where((r) => (r['key']! as String).startsWith('remote_delete_v1/'))
          .toList();

  Future<void> reopen() async {
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  }

  Future<void> dispose() async {
    await repository.close();
    // Only this fixture's resolved directory immediately beneath SystemTemp.
    final temporaryRoot = p.normalize(
      await Directory.systemTemp.resolveSymbolicLinks(),
    );
    final actual = p.normalize(await sandbox.resolveSymbolicLinks());
    if (!p.isAbsolute(actual) ||
        !p.isWithin(temporaryRoot, actual) ||
        !p.equals(p.dirname(actual), temporaryRoot) ||
        !p.basename(actual).startsWith(prefix)) {
      throw StateError('Refusing to delete a directory outside this fixture.');
    }
    await Directory(actual).delete(recursive: true);
  }
}

void main() {
  late RemoteDeletionFixture f;
  setUp(() async {
    f = RemoteDeletionFixture();
    await f.open();
  });
  tearDown(() => f.dispose());

  for (final confirmations in [(false, true), (true, false), (false, false)]) {
    test(
      'UT-050 missing independent confirmations $confirmations create no audit',
      () async {
        final id = await f.result(),
            plan = await f.repository.prepareRemoteDeletion(id);
        final before = f.rows('remote_upload_results');
        await expectLater(
          f.repository.beginRemoteDeletion(
            plan,
            confirmNetwork: confirmations.$1,
            confirmRemoteDeletion: confirmations.$2,
          ),
          throwsA(isA<UploadQueueFailure>()),
        );
        expect(f.auditRows(), isEmpty);
        expect(f.rows('remote_upload_results'), before);
      },
    );
  }

  test('UT-050 preparation is inert and current target secret is only in protected execution', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    expect(f.auditRows(), isEmpty);
    expect(plan.result.target.id, f.target);
    final execution = await f.begin(plan);
    try {
      expect(execution.record.state, RemoteDeletionState.prepared);
      expect(execution.request.userhash, RemoteDeletionFixture.credential);
      expect(execution.request.filename, plan.result.remoteId);
      expect(
        execution.toString(),
        isNot(contains(RemoteDeletionFixture.credential)),
      );
      expect(
        execution.request.toString(),
        isNot(contains(RemoteDeletionFixture.credential)),
      );
      expect(
        (await f.repository.listRemoteDeletions()).single.state,
        RemoteDeletionState.prepared,
      );
    } finally {
      await f.repository.finishRemoteDeletion(
        execution,
        RemoteDeletionOutcome.cancelled,
      );
    }
  });

  test('UT-050 foreign repository and reopened owner reject plan before creating audit', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    final other = await LibraryRepository.open(
      Directory(p.join(f.sandbox.path, 'other')),
      secretStore: f.secrets,
    );
    try {
      await expectLater(
        other.beginRemoteDeletion(
          plan,
          confirmNetwork: true,
          confirmRemoteDeletion: true,
        ),
        throwsA(isA<UploadQueueFailure>()),
      );
      expect(await other.listRemoteDeletions(), isEmpty);
    } finally {
      await other.close();
    }
    await f.reopen();
    await expectLater(f.begin(plan), throwsA(isA<UploadQueueFailure>()));
    expect(f.auditRows(), isEmpty);
  });

  test('UT-050 changed generation rejects confirmed plan without replacing historical identity', () async {
    final id = await f.result(),
        plan = await f.repository.prepareRemoteDeletion(id);
    await f.repository.saveTarget(
      id: f.target,
      service: ImageHostService.catbox,
      alias: '新别名',
      anonymous: false,
      credential: 'synthetic-remote-delete-userhash-B',
    );
    await expectLater(f.begin(plan), throwsA(isA<UploadQueueFailure>()));
    expect(f.auditRows(), isEmpty);
    expect((await f.repository.listUploadResults()).single.target.id, f.target);
  });

  test(
    'UT-050 same alias new UUID cannot authorize removed original target',
    () async {
      final id = await f.result();
      await f.repository.removeTarget(f.target);
      final replacement = await f.repository.saveTarget(
        service: ImageHostService.catbox,
        alias: '原账号',
        anonymous: false,
        credential: 'synthetic-replacement-userhash',
      );
      expect(replacement, isNot(f.target));
      await expectLater(
        f.repository.prepareRemoteDeletion(id),
        throwsA(isA<UploadQueueFailure>()),
      );
      expect(f.auditRows(), isEmpty);
      expect(
        (await f.repository.listUploadResults()).single.target.id,
        f.target,
      );
    },
  );

  test('UT-050 missing current authorization and anonymous result have no deletion capability', () async {
    final id = await f.result(), saved = Map.of(f.secrets.values);
    f.secrets.values.clear();
    await expectLater(
      f.repository.prepareRemoteDeletion(id),
      throwsA(isA<UploadQueueFailure>()),
    );
    f.secrets.values.addAll(saved);
    final anonymous = await f.repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '匿名',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    final anonymousResult = await f.result(targetId: anonymous);
    markLegacyAnonymous(f.root, anonymous);
    await expectLater(
      f.repository.prepareRemoteDeletion(anonymousResult),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(f.auditRows(), isEmpty);
  });

  for (final url in [
    'https://files.catbox.moe/fixture0.png?token=x',
    'https://files.catbox.moe/another.png',
    'https://example.com/fixture0.png',
  ]) {
    test(
      'UT-050 unsupported strict direct URL $url refuses deletion',
      () async {
        final id = await f.result();
        // Upload confirmation itself already rejects these URLs. Seed a
        // damaged ordinary row to exercise the deletion read boundary.
        f.mutate(
          (db) => db.execute(
            'UPDATE remote_upload_results SET direct_url=? WHERE id=?',
            [url, id],
          ),
        );
        await expectLater(
          f.repository.prepareRemoteDeletion(id),
          throwsA(isA<UploadQueueFailure>()),
        );
        expect(f.auditRows(), isEmpty);
      },
    );
  }

  test(
    'UT-050 full ordinary fingerprint change rejects plan without new record',
    () async {
      final id = await f.result(),
          plan = await f.repository.prepareRemoteDeletion(id);
      f.mutate((db) {
        final row = db.select(
          'SELECT target_json FROM remote_upload_results WHERE id=?',
          [id],
        ).single;
        final target =
            jsonDecode(row['target_json'] as String) as Map<String, dynamic>;
        target['alias'] = 'changed';
        db.execute(
          'UPDATE remote_upload_results SET target_json=? WHERE id=?',
          [jsonEncode(target), id],
        );
      });
      await expectLater(f.begin(plan), throwsA(isA<UploadQueueFailure>()));
      expect(f.auditRows(), isEmpty);
    },
  );

  test('UT-050 authorization rereads current protected value before marking sending', () async {
    final id = await f.result(),
        execution = await f.begin(await f.repository.prepareRemoteDeletion(id));
    try {
      f.secrets.values.updateAll((_, value) => 'synthetic-mutated-userhash');
      await expectLater(
        f.repository.authorizeRemoteDeletion(execution),
        throwsA(isA<UploadQueueFailure>()),
      );
      expect(
        (await f.repository.listRemoteDeletions()).single.state,
        RemoteDeletionState.prepared,
      );
    } finally {
      await f.repository.finishRemoteDeletion(
        execution,
        const RemoteDeletionOutcome(
          RemoteDeletionState.notSent,
          RemoteDeletionReason.authorizationChanged,
        ),
      );
    }
  });

  test('UT-050 HTTP 200 remains unknown and preserves assets bytes secrets tasks and ordinary link', () async {
    final id = await f.result();
    final before = {
      for (final table in [
        'assets',
        'versions',
        'device_copies',
        'provider_targets',
        'upload_batches',
        'upload_publications',
        'upload_attempts',
        'upload_events',
      ])
        table: f.rows(table),
    };
    final original = await f.repository.originalFor(f.asset);
    final bytes = await original.readAsBytes(),
        secrets = Map.of(f.secrets.values);
    final execution = await f.begin(
      await f.repository.prepareRemoteDeletion(id),
    );
    await f.repository.authorizeRemoteDeletion(execution);
    expect(
      (await f.repository.listRemoteDeletions()).single.state,
      RemoteDeletionState.sending,
    );
    final record = await f.repository.finishRemoteDeletion(
      execution,
      const RemoteDeletionOutcome(
        RemoteDeletionState.unknown,
        RemoteDeletionReason.unconfirmed,
        httpStatus: 200,
      ),
    );
    expect(record.state, RemoteDeletionState.unknown);
    expect(record.httpStatus, 200);
    expect((await f.repository.listUploadResults()).single.id, id);
    for (final entry in before.entries) {
      expect(f.rows(entry.key), entry.value, reason: entry.key);
    }
    expect(await original.readAsBytes(), bytes);
    expect(f.secrets.values, secrets);
    final allOrdinary = jsonEncode([
      f.rows('remote_upload_results'),
      f.auditRows(),
      f.rows('diagnostic_records'),
    ]);
    expect(allOrdinary, isNot(contains(RemoteDeletionFixture.credential)));
    final snapshot = await f.repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    try {
      final portable = utf8.decode(snapshot.manifestBytes);
      expect(portable, isNot(contains(RemoteDeletionFixture.credential)));
      expect(portable, isNot(contains('remote_delete_v1')));
      expect((jsonDecode(portable) as Map)['results'], hasLength(1));
    } finally {
      await snapshot.release();
    }
    await f.reopen();
    expect(
      (await f.repository.listRemoteDeletions(resultId: id)).single.state,
      RemoteDeletionState.unknown,
    );
  });

  test('UT-050 prepared execution close waits for actual finish then preserves notSent audit', () async {
    final id = await f.result(),
        execution = await f.begin(await f.repository.prepareRemoteDeletion(id));
    var closed = false;
    final closing = f.repository.close().then((_) => closed = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, false);
    await f.repository.finishRemoteDeletion(
      execution,
      RemoteDeletionOutcome.cancelled,
    );
    await closing;
    await f.reopen();
    expect(
      (await f.repository.listRemoteDeletions()).single.state,
      RemoteDeletionState.notSent,
    );
  });

  test('UT-050 active deletion blocks local removal and probes and drains before restore', () async {
    final id = await f.result(),
        probe = await f.repository.prepareLinkProbe([id]);
    final execution = await f.begin(
      await f.repository.prepareRemoteDeletion(id),
    );
    await expectLater(
      f.repository.removeLocalLinkResults([id], confirmLocalRemoval: true),
      throwsA(isA<UploadQueueFailure>()),
    );
    await expectLater(
      f.repository.beginLinkProbe(probe, id, confirmNetwork: true),
      throwsA(isA<UploadQueueFailure>()),
    );
    var ready = false;
    final acquiring = f.repository.acquireRestoreHold().then((hold) {
      ready = true;
      return hold;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ready, false);
    await f.repository.finishRemoteDeletion(
      execution,
      RemoteDeletionOutcome.cancelled,
    );
    final hold = await acquiring;
    await hold.release();
    expect((await f.repository.listUploadResults()).single.id, id);
  });

  test('UT-050 unsettled cleanup protection rejects close and restore until independently settled finish', () async {
    final id = await f.result(),
        execution = await f.begin(await f.repository.prepareRemoteDeletion(id));
    await f.repository.authorizeRemoteDeletion(execution);
    f.repository.retainUnsettledRemoteDeletion(execution);
    await expectLater(f.repository.close(), throwsA(isA<UploadQueueFailure>()));
    await expectLater(
      f.repository.acquireRestoreHold(),
      throwsA(isA<UploadQueueFailure>()),
    );
    await expectLater(
      f.repository.prepareRemoteDeletion(id),
      throwsA(isA<UploadQueueFailure>()),
    );
    // No real gateway was started; this explicit finish represents independent
    // proof that the injected execution has no outstanding network IO.
    await f.repository.finishRemoteDeletion(
      execution,
      RemoteDeletionOutcome.unknown,
    );
    final hold = await f.repository.acquireRestoreHold();
    await hold.release();
  });

  for (final state in [
    RemoteDeletionState.prepared,
    RemoteDeletionState.sending,
  ]) {
    test(
      'UT-050 reopening seeded durable $state evidence classifies interrupted without replay',
      () async {
        final id = await f.result(),
            execution = await f.begin(
              await f.repository.prepareRemoteDeletion(id),
            );
        await f.repository.finishRemoteDeletion(
          execution,
          RemoteDeletionOutcome.cancelled,
        );
        await f.repository.close();
        final audit = f.auditRows().single;
        final raw =
            jsonDecode(audit['value']! as String) as Map<String, dynamic>;
        raw.addAll({
          'state': state.name,
          'finishedUtc': null,
          'reason': null,
          'httpStatus': null,
        });
        f.mutate(
          (db) => db.execute(
            'UPDATE library_metadata SET value=? WHERE key=?',
            [jsonEncode(raw), audit['key']],
          ),
        );
        await f.reopen();
        final recovered = (await f.repository.listRemoteDeletions()).single;
        expect(
          recovered.state,
          state == RemoteDeletionState.prepared
              ? RemoteDeletionState.notSent
              : RemoteDeletionState.unknown,
        );
        expect(recovered.reason, RemoteDeletionReason.interrupted);
        expect((await f.repository.listUploadResults()).single.id, id);
        expect(f.rows('upload_attempts'), hasLength(1));
      },
    );
  }

  for (final defect in ['future', 'extra', 'invalidIdentity', 'inconsistent']) {
    test(
      'UT-050 $defect durable audit rejects reopen and preserves exact SQLite evidence',
      () async {
        final id = await f.result(),
            execution = await f.begin(
              await f.repository.prepareRemoteDeletion(id),
            );
        await f.repository.finishRemoteDeletion(
          execution,
          RemoteDeletionOutcome.cancelled,
        );
        await f.repository.close();
        final audit = f.auditRows().single;
        final raw =
            jsonDecode(audit['value']! as String) as Map<String, dynamic>;
        switch (defect) {
          case 'future':
            raw['formatVersion'] = 2;
          case 'extra':
            raw['unrecognized'] = true;
          case 'invalidIdentity':
            raw['targetId'] = '../external';
          case 'inconsistent':
            raw['state'] = 'sending';
        }
        f.mutate(
          (db) => db.execute(
            'UPDATE library_metadata SET value=? WHERE key=?',
            [jsonEncode(raw), audit['key']],
          ),
        );
        final before = f.auditRows(),
            ordinary = f.rows('remote_upload_results');
        // An unfinished-attempt fixture would normally be classified during
        // startup. Unreadable deletion evidence must stop before that write.
        f.mutate(
          (db) => db.execute('UPDATE upload_attempts SET ended_utc=NULL'),
        );
        final attemptsBefore = f.rows('upload_attempts');
        await expectLater(
          LibraryRepository.open(f.root, secretStore: f.secrets),
          throwsA(isA<LibraryOpenException>()),
        );
        expect(f.auditRows(), before);
        expect(f.rows('remote_upload_results'), ordinary);
        expect(f.rows('upload_attempts'), attemptsBefore);
        // Restore the original valid record solely so fixture teardown can reopen.
        f.mutate(
          (db) => db.execute(
            'UPDATE library_metadata SET value=? WHERE key=?',
            [audit['value'], audit['key']],
          ),
        );
        await f.reopen();
      },
    );
  }
}
