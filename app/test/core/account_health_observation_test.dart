import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_store.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.create());
  tearDown(() async => fixture.dispose());

  test('UT-041 valid confirmation commits available and persists only health without authorization event', () async {
    final healthEvents = <AccountHealth>[];
    final accountEvents = <String>[];
    final health = fixture.repository.accountHealthChanges.listen((_) {
      healthEvents.add(fixture.rawHealth());
    });
    final accounts = fixture.repository.accountChanges.listen(
      accountEvents.add,
    );
    final before = fixture.targetRow();
    final execution = await fixture.begin();
    await fixture.finish(execution, _success());
    await Future<void>.delayed(Duration.zero);
    expect(fixture.rawHealth(), AccountHealth.available);
    expect(healthEvents, [AccountHealth.available]);
    expect(accountEvents, isEmpty);
    final after = fixture.targetRow();
    for (final key in before.keys.where((key) => key != 'health')) {
      expect(after[key], before[key], reason: key);
    }
    // Duplicate completion and unchanged newer confirmation do not emit.
    await fixture.finish(execution, _success());
    final newer = await fixture.begin();
    await fixture.finish(newer, _success('second.png'));
    await Future<void>.delayed(Duration.zero);
    expect(healthEvents, hasLength(1));
    await health.cancel();
    await accounts.cancel();
    await fixture.reopen();
    expect(
      (await fixture.repository.listTargets()).single.health,
      AccountHealth.available,
    );
  });

  for (final entry in <UploadFailureKind, AccountHealth>{
    UploadFailureKind.authorization: AccountHealth.authorizationInvalid,
    UploadFailureKind.network: AccountHealth.temporarilyUnavailable,
    UploadFailureKind.rateLimited: AccountHealth.temporarilyUnavailable,
    UploadFailureKind.timeout: AccountHealth.temporarilyUnavailable,
    UploadFailureKind.targetUnavailable: AccountHealth.temporarilyUnavailable,
  }.entries) {
    test(
      'UT-041 typed ${entry.key.name} observes ${entry.value.name}',
      () async {
        final execution = await fixture.begin();
        await fixture.finish(
          execution,
          ProviderUploadFailure(
            entry.key,
            UploadDeliveryEvidence.confirmedRejected,
          ),
        );
        expect(fixture.rawHealth(), entry.value);
        expect(
          (await fixture.repository.listTargets()).single.health,
          entry.value,
        );
      },
    );
  }

  for (final result in <ProviderUploadResult>[
    const ProviderUploadUnknown(UploadFailureKind.network),
    const ProviderUploadFailure(
      UploadFailureKind.authorization,
      UploadDeliveryEvidence.uncertain,
    ),
    const ProviderUploadFailure(
      UploadFailureKind.fileUnavailable,
      UploadDeliveryEvidence.notSent,
    ),
    const ProviderUploadFailure(
      UploadFailureKind.capabilityUnknown,
      UploadDeliveryEvidence.notSent,
    ),
    const ProviderUploadFailure(
      UploadFailureKind.protocol,
      UploadDeliveryEvidence.confirmedRejected,
    ),
    const ProviderUploadFailure(
      UploadFailureKind.formatUnsupported,
      UploadDeliveryEvidence.notSent,
    ),
    const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
  ]) {
    test(
      'UT-041 non-health evidence ${result.runtimeType} ${result is ProviderUploadFailure ? result.kind.name : ''} leaves observation unchanged',
      () async {
        final execution = await fixture.begin();
        fixture.withDatabase(
          (db) => db.execute(
            'UPDATE provider_targets SET health = ? WHERE id = ?',
            [AccountHealth.available.name, fixture.target],
          ),
        );
        await fixture.finish(execution, result);
        expect(fixture.rawHealth(), AccountHealth.available);
      },
    );
  }

  test('UT-041 invalid success cannot fabricate available', () async {
    final execution = await fixture.begin();
    await fixture.finish(
      execution,
      ProviderUploadSuccess(
        service: ImageHostService.catbox,
        remoteId: 'wrong.png',
        directUrl: _wrongUrl,
      ),
    );
    expect(fixture.rawHealth(), AccountHealth.unverified);
    expect(await fixture.repository.listUploadResults(), isEmpty);
  });

  test(
    'UT-041 old credential generation cannot rewrite replacement status',
    () async {
      final execution = await fixture.begin();
      await fixture.repository.saveTarget(
        id: fixture.target,
        service: ImageHostService.catbox,
        alias: 'same name',
        anonymous: false,
        credential: 'synthetic-new-key',
      );
      final generation = fixture.targetRow()['generation'];
      await fixture.finish(
        execution,
        const ProviderUploadFailure(
          UploadFailureKind.authorization,
          UploadDeliveryEvidence.confirmedRejected,
        ),
      );
      expect(fixture.rawHealth(), AccountHealth.unverified);
      expect(fixture.targetRow()['generation'], generation);
    },
  );

  test('UT-041 removed target and same-name new target do not inherit late confirmation', () async {
    final execution = await fixture.begin();
    await fixture.repository.removeTarget(fixture.target);
    final old = fixture.targetRow();
    final newTarget = await fixture.repository.saveTarget(
      service: ImageHostService.catbox,
      alias: 'same name',
      anonymous: false,
      credential: 'synthetic-new-key',
    );
    await fixture.finish(execution, _success());
    expect(fixture.targetRow(), old);
    expect(fixture.rawHealth(target: newTarget), AccountHealth.unverified);
    expect(await fixture.repository.listUploadResults(), hasLength(1));
  });

  test(
    'UT-041 pending credential operation prevents observing current target',
    () async {
      final execution = await fixture.begin();
      fixture.withDatabase((db) {
        db.execute(
          'INSERT INTO credential_operations(id,target_id,action,proposal_json,created_utc) VALUES(?,?,?,?,?)',
          ['health-pending', fixture.target, 'update', '{}', 1],
        );
      });
      try {
        await fixture.finish(execution, _success());
        expect(fixture.rawHealth(), AccountHealth.unverified);
      } finally {
        fixture.withDatabase(
          (db) => db.execute(
            "DELETE FROM credential_operations WHERE id = 'health-pending'",
          ),
        );
      }
    },
  );

  for (final newerEndsFirst in [false, true]) {
    test(
      'UT-041 ${newerEndsFirst ? 'newer completed' : 'newer running'} attempt blocks older late health evidence',
      () async {
        final old = await fixture.begin();
        final newer = await fixture.begin();
        if (newerEndsFirst) {
          await fixture.finish(
            newer,
            const ProviderUploadFailure(
              UploadFailureKind.authorization,
              UploadDeliveryEvidence.confirmedRejected,
            ),
          );
        }
        await fixture.finish(old, _success());
        expect(
          fixture.rawHealth(),
          newerEndsFirst
              ? AccountHealth.authorizationInvalid
              : AccountHealth.unverified,
        );
        if (!newerEndsFirst) {
          await fixture.finish(
            newer,
            const ProviderUploadFailure(
              UploadFailureKind.authorization,
              UploadDeliveryEvidence.confirmedRejected,
            ),
          );
        }
        expect(fixture.rawHealth(), AccountHealth.authorizationInvalid);
      },
    );
  }

  test('UT-041 equal UTC uses greatest UUID as latest started even across completion order', () async {
    final first = await fixture.begin();
    final second = await fixture.begin();
    fixture.withDatabase((db) {
      db.execute('UPDATE upload_attempts SET started_utc = 1000');
      // Simulate attempts from before the start-marker implementation.
      db.execute(
        "DELETE FROM library_metadata WHERE key LIKE 'account_health_started_v1/%'",
      );
    });
    // Explicit stable order is UTC then UUID, not completion arrival or a claim
    // of monotonic causal order. Both real attempts here have equal UTC.
    final latest = first.attemptId.compareTo(second.attemptId) > 0
        ? first
        : second;
    final older = identical(latest, first) ? second : first;
    await fixture.finish(
      latest,
      const ProviderUploadFailure(
        UploadFailureKind.authorization,
        UploadDeliveryEvidence.confirmedRejected,
      ),
    );
    await fixture.finish(older, _success());
    expect(fixture.rawHealth(), AccountHealth.authorizationInvalid);
  });

  test(
    'UT-041 stale execution epoch rejects ordinary and health writes',
    () async {
      final execution = await fixture.begin();
      final stale = UploadExecution(
        item: execution.item,
        attemptId: execution.attemptId,
        generation: execution.generation,
        target: execution.target,
        file: execution.file,
        release: execution.release,
        libraryEpoch: 'stale-health-epoch',
      );
      try {
        await expectLater(
          fixture.repository.finishUploadAttempt(
            stale,
            _success(),
            accumulatedRunning: const Duration(seconds: 1),
          ),
          throwsA(isA<UploadQueueFailure>()),
        );
        expect(fixture.rawHealth(), AccountHealth.unverified);
        expect(await fixture.repository.listUploadResults(), isEmpty);
      } finally {
        await execution.release();
      }
    },
  );

  test('UT-041 session health displays current observation but reopen without session becomes unconfigured', () async {
    final sessionTarget = await fixture.repository.saveTarget(
      service: ImageHostService.catbox,
      alias: 'session target',
      anonymous: false,
      credential: 'synthetic-session-key',
      persistence: CredentialPersistence.session,
    );
    final execution = await fixture.begin(target: sessionTarget);
    await fixture.finish(execution, _success());
    expect(
      (await fixture.repository.listTargets())
          .singleWhere((t) => t.id == sessionTarget)
          .health,
      AccountHealth.available,
    );
    await fixture.reopen();
    expect(
      (await fixture.repository.listTargets())
          .singleWhere((t) => t.id == sessionTarget)
          .health,
      AccountHealth.unconfigured,
    );
  });

  test('UT-041 valid ordinary success survives management storage failure and result journal recovery observes health', () async {
    final target = await fixture.repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: 'management fixture',
      anonymous: false,
      credential: 'synthetic-imgbb-key',
    );
    final execution = await fixture.begin(target: target);
    fixture.secrets.failReads = true;
    fixture.secrets.failWrites = true;
    await fixture.finish(
      execution,
      ProviderUploadSuccess(
        service: ImageHostService.imgbb,
        remoteId: 'healthRemote',
        directUrl: Uri.parse('https://i.ibb.co/healthRemote/fixture.png'),
        viewerUrl: Uri.parse('https://ibb.co/healthRemote'),
        managementSecret: SensitiveManagementSecret(
          'https://ibb.co/healthRemote/managementToken0123456789',
        ),
      ),
    );
    expect(fixture.rawHealth(target: target), AccountHealth.available);
    expect(await fixture.repository.listUploadResults(), hasLength(1));
    expect(
      fixture.withDatabase(
        (db) => db.select('SELECT id FROM upload_result_operations'),
      ),
      hasLength(1),
    );
    fixture.withDatabase(
      (db) => db.execute(
        'UPDATE provider_targets SET health = ? WHERE id = ?',
        [AccountHealth.unverified.name, target],
      ),
    );
    fixture.secrets.failReads = false;
    fixture.secrets.failWrites = false;
    await fixture.reopen();
    expect(fixture.rawHealth(target: target), AccountHealth.available);
    expect(
      fixture.withDatabase(
        (db) => db.select('SELECT id FROM upload_result_operations'),
      ),
      isEmpty,
    );
  });

  test('UT-041 health update is atomic with failure outcome and emits no rolled-back event', () async {
    var events = 0;
    final subscription = fixture.repository.accountHealthChanges.listen(
      (_) => events++,
    );
    final execution = await fixture.begin();
    fixture.withDatabase(
      (db) => db.execute(
        "CREATE TRIGGER reject_health BEFORE UPDATE OF health ON provider_targets BEGIN SELECT RAISE(ABORT, 'injected'); END",
      ),
    );
    try {
      await expectLater(
        fixture.repository.finishUploadAttempt(
          execution,
          const ProviderUploadFailure(
            UploadFailureKind.authorization,
            UploadDeliveryEvidence.confirmedRejected,
          ),
          accumulatedRunning: const Duration(seconds: 1),
        ),
        throwsA(isA<Exception>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.rawHealth(), AccountHealth.unverified);
      expect(
        fixture.withDatabase(
          (db) => db
              .select('SELECT ended_utc FROM upload_attempts')
              .single['ended_utc'],
        ),
        isNull,
      );
      expect(events, 0);
    } finally {
      fixture.withDatabase((db) => db.execute('DROP TRIGGER reject_health'));
      await execution.release();
      await subscription.cancel();
    }
  });

  test('UT-041 persisted watermark rejects older late evidence after newer completed history is cleared', () async {
    final older = await fixture.begin();
    // Keep the old IO lease active on its own version: it must not protect the
    // independent newer asset whose completed history is being cleared.
    final newerBytes = img.encodePng(img.Image(width: 9, height: 6));
    final newerAsset = (await fixture.repository.importResource(
      PlatformResource(
        displayName: 'newer-health.png',
        openRead: () => Stream.value(newerBytes),
      ),
    )).asset!;
    expect(newerAsset.version.id, isNot(fixture.asset.version.id));
    final newer = await fixture.begin(asset: newerAsset);
    await fixture.finish(newer, _success());
    final before = fixture.observations();
    final plan = await fixture.repository.prepareUploadHistoryClear(
      publicationIds: [newer.item.id],
      importedHistoryIds: const [],
    );
    expect(plan.eligibleCount, 1);
    await fixture.repository.clearUploadHistory(
      plan,
      confirmHistoryRemoval: true,
    );
    expect(
      fixture.withDatabase(
        (db) => db.select('SELECT id FROM upload_attempts WHERE id = ?', [
          newer.attemptId,
        ]),
      ),
      isEmpty,
    );
    await fixture.finish(
      older,
      const ProviderUploadFailure(
        UploadFailureKind.authorization,
        UploadDeliveryEvidence.confirmedRejected,
      ),
    );
    expect(fixture.rawHealth(), AccountHealth.available);
    expect(fixture.observations(), before);
    await fixture.reopen();
    expect(fixture.observations(), before);
    expect(
      (await fixture.repository.listTargets()).single.health,
      AccountHealth.available,
    );
  });

  test(
    'UT-041 a new credential generation supersedes the old ordinary watermark',
    () async {
      await fixture.finish(await fixture.begin(), _success());
      final previous =
          jsonDecode(fixture.observations().single['value'] as String) as Map;
      await fixture.repository.saveTarget(
        id: fixture.target,
        service: ImageHostService.catbox,
        alias: 'same name',
        anonymous: false,
        credential: 'synthetic-replacement-key',
      );
      await fixture.finish(
        await fixture.begin(),
        const ProviderUploadFailure(
          UploadFailureKind.authorization,
          UploadDeliveryEvidence.confirmedRejected,
        ),
      );
      final current =
          jsonDecode(fixture.observations().single['value'] as String) as Map;
      expect(
        current['targetGeneration'],
        greaterThan(previous['targetGeneration'] as int),
      );
      expect(current['health'], AccountHealth.authorizationInvalid.name);
    },
  );

  for (final namespace in ['observation', 'started']) {
    for (final malformed in [
      'json',
      'future',
      'attempt',
      'key',
      'extra',
      if (namespace == 'observation') 'unobservedHealth',
    ]) {
      test(
        'UT-041 $malformed $namespace record refuses writes and open without resetting bytes',
        () async {
          final execution = await fixture.begin();
          var key = 'account_health_${namespace}_v1/${fixture.target}';
          final value = <String, Object>{
            'formatVersion': 1,
            'targetGeneration': fixture.targetRow()['generation'] as int,
            'startedUtc': 1,
            'attemptId': execution.attemptId,
            if (namespace == 'observation')
              'health': AccountHealth.available.name,
          };
          if (malformed == 'future') value['formatVersion'] = 2;
          if (malformed == 'attempt') value['attemptId'] = 'invalid-attempt';
          if (malformed == 'key') {
            key = 'account_health_${namespace}_v1/not-a-uuid';
          }
          if (malformed == 'extra') value['unexpected'] = 'field';
          if (malformed == 'unobservedHealth') {
            value['health'] = AccountHealth.unverified.name;
          }
          final encoded = malformed == 'json' ? '{invalid' : jsonEncode(value);
          fixture.withDatabase(
            (db) => db.execute(
              'INSERT OR REPLACE INTO library_metadata(key,value) VALUES(?,?)',
              [key, encoded],
            ),
          );
          try {
            await expectLater(
              fixture.repository.finishUploadAttempt(
                execution,
                _success(),
                accumulatedRunning: const Duration(seconds: 1),
              ),
              throwsA(isA<AccountFailure>()),
            );
            expect(await fixture.repository.listUploadResults(), isEmpty);
            expect(
              fixture.withDatabase(
                (db) => db.select(
                  'SELECT ended_utc FROM upload_attempts WHERE id = ?',
                  [execution.attemptId],
                ).single['ended_utc'],
              ),
              isNull,
            );
          } finally {
            await execution.release();
          }
          await expectLater(
            fixture.reopen(),
            throwsA(isA<LibraryOpenException>()),
          );
          expect(
            fixture.withDatabase(
              (db) => db.select(
                'SELECT value FROM library_metadata WHERE key = ?',
                [key],
              ).single['value'],
            ),
            encoded,
          );
          fixture.withDatabase(
            (db) =>
                db.execute('DELETE FROM library_metadata WHERE key = ?', [key]),
          );
        },
      );
    }
  }

  test('UT-041 writer start marker rejects late older completion despite wall-clock rollback', () async {
    final established = await fixture.begin(at: DateTime.utc(2030));
    await fixture.finish(established, _success('established.png'));
    final older = await fixture.begin(at: DateTime.utc(2031));
    final newer = await fixture.begin(at: DateTime.utc(2020));
    await fixture.finish(
      newer,
      const ProviderUploadFailure(
        UploadFailureKind.authorization,
        UploadDeliveryEvidence.confirmedRejected,
      ),
    );
    expect(fixture.rawHealth(), AccountHealth.authorizationInvalid);
    final marker = fixture.startedMarkers();
    await fixture.finish(older, _success('older.png'));
    expect(fixture.rawHealth(), AccountHealth.authorizationInvalid);
    expect(fixture.startedMarkers(), marker);
  });

  test('UT-041 start marker survives latest history cleanup and failed marker write rolls back attempt and lease', () async {
    final newest = await fixture.begin();
    await fixture.finish(newest, _success());
    final marker = fixture.startedMarkers();
    final plan = await fixture.repository.prepareUploadHistoryClear(
      publicationIds: [newest.item.id],
      importedHistoryIds: const [],
    );
    await fixture.repository.clearUploadHistory(
      plan,
      confirmHistoryRemoval: true,
    );
    expect(fixture.startedMarkers(), marker);
    final batch = await fixture.repository.enqueueUploads(
      intentId: 'marker-write-failure',
      assetIds: [fixture.asset.id],
      targetIds: [fixture.target],
      allowOriginalMetadata: true,
      forceAgain: true,
    );
    fixture.withDatabase(
      (db) => db.execute(
        "CREATE TRIGGER reject_health_start BEFORE INSERT ON library_metadata WHEN NEW.key LIKE 'account_health_started_v1/%' BEGIN SELECT RAISE(ABORT, 'injected'); END",
      ),
    );
    try {
      await expectLater(
        fixture.repository.beginUploadAttempt(batch.items.single.id),
        throwsA(isA<Exception>()),
      );
      expect(
        fixture.withDatabase(
          (db) => db.select('SELECT id FROM upload_attempts'),
        ),
        isEmpty,
      );
      expect(
        fixture.withDatabase((db) => db.select('SELECT id FROM file_leases')),
        isEmpty,
      );
      expect(
        fixture.withDatabase(
          (db) => db.select(
            'SELECT current_attempt_id,state FROM upload_publications WHERE id = ?',
            [batch.items.single.id],
          ).single['current_attempt_id'],
        ),
        isNull,
      );
      expect(fixture.startedMarkers(), marker);
    } finally {
      fixture.withDatabase(
        (db) => db.execute('DROP TRIGGER reject_health_start'),
      );
    }
    await fixture.reopen();
    expect(fixture.startedMarkers(), marker);
  });

  test('UT-041/073 portable backup excludes observation namespace and merge preserves local watermark', () async {
    await fixture.finish(await fixture.begin(), _success());
    final before = fixture.observations();
    final beforeStarted = fixture.startedMarkers();
    final backup = await fixture.backup();
    try {
      final hold = await fixture.repository.acquireRestoreHold();
      try {
        final prepared = await fixture.repository.prepareMergeRestore(
          hold: hold,
          backup: backup,
        );
        await fixture.repository.commitMergeRestore(
          preparation: prepared,
          availableBytes: (_) async => 1 << 40,
          publishExclusive: _publish,
        );
      } finally {
        await hold.release();
      }
      expect(fixture.observations(), before);
      expect(fixture.startedMarkers(), beforeStarted);
      await fixture.reopen();
      expect(fixture.observations(), before);
    } finally {
      await backup.dispose();
    }
  });

  for (final fail in [false, true]) {
    test(
      'UT-041/080 replacement ${fail ? 'rollback restores' : 'commit clears'} local observation watermark',
      () async {
        await fixture.finish(await fixture.begin(), _success());
        final before = fixture.observations();
        final beforeStarted = fixture.startedMarkers();
        final backup = await fixture.backup();
        final original = await fixture.repository.originalFor(fixture.asset);
        final originalBytes = await original.readAsBytes();
        try {
          Future<void> replace() async {
            final hold = await fixture.repository.acquireRestoreHold();
            ReplacementRestorePreparation? prepared;
            try {
              prepared = await fixture.repository.prepareReplacementRestore(
                hold: hold,
                backup: backup,
                availableBytes: (_) async => 1 << 40,
              );
              await fixture.repository.commitReplacementRestore(
                preparation: prepared,
                availableBytes: (_) async => 1 << 40,
                publishExclusive: _publish,
                faultHook: (boundary) async {
                  if (fail && boundary == RestoreBoundary.metadataWritten) {
                    throw StateError('synthetic metadata transaction failure');
                  }
                },
              );
            } finally {
              if (prepared != null) {
                await fixture.repository.discardReplacementPreparation(
                  prepared,
                );
              }
              await hold.release();
            }
          }

          if (fail) {
            await expectLater(replace(), throwsA(isA<BackupSnapshotFailure>()));
            expect(fixture.observations(), before);
            expect(fixture.startedMarkers(), beforeStarted);
            expect(fixture.rawHealth(), AccountHealth.available);
            expect(await original.readAsBytes(), originalBytes);
          } else {
            await replace();
            expect(fixture.observations(), isEmpty);
            expect(fixture.startedMarkers(), isEmpty);
          }
          await fixture.reopen();
          expect(fixture.observations(), fail ? before : isEmpty);
        } finally {
          await backup.dispose();
        }
      },
    );
  }
}

// Fixture publication is deterministic, not native atomicity evidence.
Future<bool> _publish(File staged, File target) async {
  if (await FileSystemEntity.type(target.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return false;
  }
  await staged.rename(target.path);
  return true;
}

final _wrongUrl = Uri.parse('https://wrong.invalid/wrong.png');

ProviderUploadSuccess _success([String name = 'health.png']) =>
    ProviderUploadSuccess(
      service: ImageHostService.catbox,
      remoteId: name,
      directUrl: Uri.parse('https://files.catbox.moe/$name'),
    );

class _TestSecrets implements SecretStore {
  final values = <String, String>{};
  bool failReads = false, failWrites = false;
  @override
  Future<String?> read(String reference) async {
    if (failReads) throw const SecretStorageException();
    return values[reference];
  }

  @override
  Future<void> write(String reference, String value) async {
    if (failWrites) throw const SecretStorageException();
    values[reference] = value;
  }

  @override
  Future<void> delete(String reference) async {
    values.remove(reference);
  }
}

class _Fixture {
  _Fixture(this.root, this.repository, this.secrets, this.asset, this.target);
  final Directory root;
  LibraryRepository repository;
  final _TestSecrets secrets;
  final ImageAsset asset;
  final String target;
  int _sequence = 0;
  final executions = <UploadExecution>[];
  final _startedByAttempt = <String, DateTime>{};

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('imagehost-health-');
    final secrets = _TestSecrets();
    final repository = await LibraryRepository.open(
      Directory('${root.path}/library'),
      secretStore: secrets,
    );
    final bytes = img.encodePng(img.Image(width: 8, height: 6));
    final asset = (await repository.importResource(
      PlatformResource(
        displayName: 'health.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    final target = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: 'same name',
      anonymous: false,
      credential: 'synthetic-health-key',
    );
    return _Fixture(root, repository, secrets, asset, target);
  }

  Future<UploadExecution> begin({
    String? target,
    ImageAsset? asset,
    DateTime? at,
  }) async {
    final sequence = ++_sequence;
    final started = at ?? DateTime.utc(2026, 10, 7, 12, 0, sequence);
    // One clock covers intent creation and attempt start, so audit chronology
    // is valid independently of when the test actually runs on the host.
    final execution = (await withClock(Clock.fixed(started), () async {
      final batch = await repository.enqueueUploads(
        intentId: 'health-intent-$sequence',
        assetIds: [(asset ?? this.asset).id],
        targetIds: [target ?? this.target],
        allowOriginalMetadata: true,
        forceAgain: true,
      );
      return repository.beginUploadAttempt(batch.items.single.id);
    }))!;
    executions.add(execution);
    _startedByAttempt[execution.attemptId] = started;
    return execution;
  }

  Future<void> finish(
    UploadExecution execution,
    ProviderUploadResult result,
  ) async {
    try {
      await withClock(
        Clock.fixed(
          _startedByAttempt[execution.attemptId]!.add(
            const Duration(seconds: 1),
          ),
        ),
        () => repository.finishUploadAttempt(
          execution,
          result,
          accumulatedRunning: const Duration(seconds: 1),
        ),
      );
    } finally {
      await execution.release();
    }
  }

  T withDatabase<T>(T Function(Database) action) {
    final db = sqlite3.open('${root.path}/library/library.sqlite');
    try {
      return action(db);
    } finally {
      db.close();
    }
  }

  Map<String, Object?> targetRow({String? target}) => withDatabase(
    (db) => Map<String, Object?>.from(
      db.select('SELECT * FROM provider_targets WHERE id = ?', [
        target ?? this.target,
      ]).single,
    ),
  );
  AccountHealth rawHealth({String? target}) => AccountHealth.values.byName(
    targetRow(target: target)['health'] as String,
  );

  List<Map<String, Object?>> observations() => withDatabase(
    (db) => db
        .select(
          "SELECT key,value FROM library_metadata WHERE key LIKE 'account_health_observation_v1/%' ORDER BY key",
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList(),
  );

  List<Map<String, Object?>> startedMarkers() => withDatabase(
    (db) => db
        .select(
          "SELECT key,value FROM library_metadata WHERE key LIKE 'account_health_started_v1/%' ORDER BY key",
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList(),
  );

  Future<ValidatedBackup> backup() async {
    final snapshot = await repository.captureBackupSnapshot(
      mode: BackupMode.full,
    );
    final archive = File('${root.path}/portable-${++_sequence}.zip');
    try {
      expect(
        utf8.decode(snapshot.manifestBytes),
        isNot(contains('account_health_observation_v1/')),
      );
      expect(
        utf8.decode(snapshot.manifestBytes),
        isNot(contains('account_health_started_v1/')),
      );
      await BackupZipWriter().write(snapshot, archive);
    } finally {
      await snapshot.release();
    }
    return const BackupZipReader().preflight(
      archive,
      await Directory('${root.path}/preflight-$_sequence').create(),
      availableBytes: (_) async => 1 << 40,
    );
  }

  Future<void> reopen() async {
    await repository.close();
    repository = await LibraryRepository.open(
      Directory('${root.path}/library'),
      secretStore: secrets,
    );
  }

  Future<void> dispose() async {
    for (final execution in executions) {
      await execution.release();
    }
    await repository.close();
    await root.delete(recursive: true);
  }
}
