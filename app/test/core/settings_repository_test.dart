import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

class _HeldAdapter implements ProviderAdapter {
  final calls = <(CancelToken, Completer<ProviderUploadResult>)>[];
  @override
  ImageHostService get service => ImageHostService.catbox;
  @override
  ProviderUploadLimits get limits =>
      ProviderUploadLimits(maximumBytes: 1024 * 1024, formats: {'PNG'});
  @override
  Future<ProviderUploadResult> upload({
    required File file,
    required String actualFormat,
    required int expectedBytes,
    required ResolvedTarget target,
    required CancelToken cancelToken,
    UploadActivityCallback? onActivity,
  }) {
    final gate = Completer<ProviderUploadResult>();
    calls.add((cancelToken, gate));
    return gate.future;
  }

  void complete(int index) => calls[index].$2.complete(
    ProviderUploadSuccess(
      service: service,
      remoteId: 'fixture$index.png',
      directUrl: Uri.parse('https://files.catbox.moe/fixture$index.png'),
    ),
  );
}

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late QueueTestSecrets secrets;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-settings-repo-');
    root = Directory('${sandbox.path}/library');
    secrets = QueueTestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });
  void sql(void Function(Database) action) {
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      action(db);
    } finally {
      db.close();
    }
  }

  Future<void> save(
    DeviceSettings value, {
    Iterable<String> targets = const [],
  }) async => repository.saveSettings(
    await repository.loadSettings(),
    value,
    defaultTargetIds: targets,
  );
  Future<void> reopen() async {
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  }

  Future<String> target({bool selected = false, bool enabled = true}) =>
      repository.saveTarget(
        service: ImageHostService.catbox,
        alias: '重复别名',
        anonymous: false,
        credential: 'SyntheticAccountFixture0123456789',
        enabled: enabled,
        selectedByDefault: selected,
      );
  Future<String> asset(int width) async => (await repository.importResource(
    PlatformResource(
      displayName: 'fixture$width.png',
      openRead: () =>
          Stream.value(img.encodePng(img.Image(width: width, height: 4))),
    ),
  )).asset!.id;
  Future<void> until(bool Function() predicate) async {
    for (var i = 0; i < 500 && !predicate(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(predicate(), isTrue, reason: '真实处理/调度应当收尾');
  }

  test(
    'UT-083 reading defaults never creates durable empty overwrite or actors',
    () async {
      final snapshot = await repository.loadSettings();
      expect(snapshot.values, DeviceSettings.defaults);
      expect(snapshot.targets, isEmpty);
      sql(
        (db) => expect(
          db.select(
            "SELECT * FROM library_metadata WHERE key='device_settings_v1'",
          ),
          isEmpty,
        ),
      );
      final session = LibrarySession(repository, const []);
      expect(session.existingUploads, isNull);
      expect(session.existingLinkProbes, isNull);
      await session.close();
    },
  );
  test('UT-063/083/087 complete settings and same alias target identity atomically persist and reopen', () async {
    final first = await target(), second = await target();
    final values = DeviceSettings(
      uploadConcurrency: 8,
      processingConcurrency: 4,
      quality: 97,
      longestSide: 2048,
      processingMode: ProcessingMode.sizeFirst,
      networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
    );
    await save(values, targets: [second]);
    expect(repository.currentDeviceSettings, values);
    expect(repository.processingScheduler.effectiveConcurrency, 4);
    await reopen();
    final loaded = await repository.loadSettings();
    expect(loaded.values, values);
    expect(loaded.defaultTargetIds, {second});
    expect(
      loaded.targets.firstWhere((t) => t.id == first).selectedByDefault,
      isFalse,
    );
    final session = LibrarySession(repository, const []);
    expect(session.existingUploads, isNull);
    expect(session.uploads.concurrency, 8);
    expect(session.uploads.networkAllowed, isFalse);
    await session.close();
  });
  test('UT-083 actual target trigger rollback retains both settings flags and runtime then retries', () async {
    final id = await target();
    final plan = await repository.loadSettings();
    sql(
      (db) => db.execute(
        "CREATE TRIGGER reject_settings BEFORE UPDATE OF selected_by_default ON provider_targets BEGIN SELECT RAISE(ABORT,'controlled refusal'); END",
      ),
    );
    var signals = 0;
    final subscription = repository.settingsChanges.listen((_) => signals++);
    await expectLater(
      repository.saveSettings(
        plan,
        DeviceSettings(uploadConcurrency: 1, quality: 61),
        defaultTargetIds: [id],
      ),
      throwsA(isA<SettingsFailure>()),
    );
    expect(signals, 0);
    expect(repository.currentDeviceSettings, DeviceSettings.defaults);
    expect((await repository.loadSettings()).defaultTargetIds, isEmpty);
    sql((db) => db.execute('DROP TRIGGER reject_settings'));
    await repository.saveSettings(
      plan,
      DeviceSettings(uploadConcurrency: 1, quality: 61),
      defaultTargetIds: [id],
    );
    expect(signals, 1);
    expect(repository.currentDeviceSettings.quality, 61);
    await subscription.cancel();
    await reopen();
    expect((await repository.loadSettings()).defaultTargetIds, {id});
  });
  test('UT-083 stale foreign and reopened settings plans cannot overwrite later valid changes', () async {
    final stale = await repository.loadSettings();
    await save(DeviceSettings(quality: 62));
    await expectLater(
      repository.saveSettings(
        stale,
        DeviceSettings(quality: 90),
        defaultTargetIds: [],
      ),
      throwsA(isA<SettingsFailure>()),
    );
    final current = await repository.loadSettings();
    final foreign = await LibraryRepository.open(
      Directory('${sandbox.path}/foreign'),
      secretStore: QueueTestSecrets(),
    );
    try {
      await expectLater(
        foreign.saveSettings(
          current,
          DeviceSettings.defaults,
          defaultTargetIds: [],
        ),
        throwsA(isA<SettingsFailure>()),
      );
    } finally {
      await foreign.close();
    }
    await reopen();
    await expectLater(
      repository.saveSettings(
        current,
        DeviceSettings.defaults,
        defaultTargetIds: [],
      ),
      throwsA(isA<SettingsFailure>()),
    );
    expect(repository.currentDeviceSettings.quality, 62);
  });
  test('UT-083 changed target review and newly disabled defaults reject while unchanged inactive defaults remain', () async {
    final inactive = await target(selected: true, enabled: false),
        other = await target(enabled: false);
    final before = await repository.loadSettings();
    await repository.saveSettings(
      before,
      DeviceSettings(quality: 70),
      defaultTargetIds: [inactive],
    );
    await expectLater(
      save(DeviceSettings(quality: 80), targets: [other]),
      throwsA(isA<SettingsFailure>()),
    );
    final stale = await repository.loadSettings();
    await repository.saveTarget(
      id: other,
      service: ImageHostService.catbox,
      alias: '后来改名',
      enabled: true,
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    await expectLater(
      repository.saveSettings(
        stale,
        DeviceSettings.defaults,
        defaultTargetIds: [other],
      ),
      throwsA(isA<SettingsFailure>()),
    );
    expect(repository.currentDeviceSettings.quality, 70);
  });
  test('UT-083 pending credential preserves unchanged default but refuses changing its selection', () async {
    final id = await target(selected: true);
    sql(
      (db) => db.execute(
        "INSERT INTO credential_operations(id,target_id,action,proposal_json,created_utc) "
        "VALUES('00000000-0000-4000-8000-000000000083',?,'update','{}',1)",
        [id],
      ),
    );
    try {
      final snapshot = await repository.loadSettings();
      expect(snapshot.targets.single.pendingOperation, isTrue);
      await repository.saveSettings(
        snapshot,
        DeviceSettings(quality: 75),
        defaultTargetIds: [id],
      );
      await expectLater(
        save(DeviceSettings(quality: 76)),
        throwsA(isA<SettingsFailure>()),
      );
      expect(repository.currentDeviceSettings.quality, 75);
      expect((await repository.loadSettings()).defaultTargetIds, {id});
    } finally {
      sql((db) => db.execute('DELETE FROM credential_operations'));
    }
  });
  test('UT-090 malformed or future durable settings never fall back and overwrite valid data', () async {
    await save(DeviceSettings(quality: 64));
    final unknown = jsonEncode({
      ...DeviceSettings.defaults.toJson(),
      'formatVersion': 4,
    });
    sql(
      (db) => db.execute(
        "UPDATE library_metadata SET value=? WHERE key='device_settings_v1'",
        [unknown],
      ),
    );
    await expectLater(
      repository.loadSettings(),
      throwsA(isA<SettingsFailure>()),
    );
    expect(repository.currentDeviceSettings.quality, 64);
    await repository.close();
    await expectLater(
      LibraryRepository.open(root, secretStore: secrets),
      throwsA(isA<LibraryOpenException>()),
    );
    sql((db) {
      expect(
        db
            .select(
              "SELECT value FROM library_metadata WHERE key='device_settings_v1'",
            )
            .single['value'],
        unknown,
      );
      db.execute(
        "UPDATE library_metadata SET value=? WHERE key='device_settings_v1'",
        [jsonEncode(DeviceSettings(quality: 64).toJson())],
      );
    });
    repository = await LibraryRepository.open(root, secretStore: secrets);
  });
  test('UT-063/087/093 malformed network policy preserves last valid settings and exact stored value across failed reopen', () async {
    final valid = DeviceSettings(
      quality: 66,
      networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
    );
    await save(valid);
    for (final malformed in [
      {...valid.toJson(), 'networkUploadPolicy': 'future'},
      {...valid.toJson(), 'networkUploadPolicy': 3},
      {...valid.toJson(), 'networkUploadPolicy': null},
      {...valid.toJson()}..remove('networkUploadPolicy'),
      {...valid.toJson(), 'extra': false},
    ]) {
      final original = jsonEncode(malformed);
      sql(
        (db) => db.execute(
          "UPDATE library_metadata SET value=? WHERE key='device_settings_v1'",
          [original],
        ),
      );
      await expectLater(
        repository.loadSettings(),
        throwsA(isA<SettingsFailure>()),
      );
      expect(repository.currentDeviceSettings, valid);
      await repository.close();
      await expectLater(
        LibraryRepository.open(root, secretStore: secrets),
        throwsA(isA<LibraryOpenException>()),
      );
      sql((db) {
        expect(
          db
              .select(
                "SELECT value FROM library_metadata WHERE key='device_settings_v1'",
              )
              .single['value'],
          original,
        );
        db.execute(
          "UPDATE library_metadata SET value=? WHERE key='device_settings_v1'",
          [jsonEncode(valid.toJson())],
        );
      });
      repository = await LibraryRepository.open(root, secretStore: secrets);
      expect((await repository.loadSettings()).values, valid);
    }
  });
  for (final version in [1, 2]) {
    test(
      'UT-063/087 project settings format $version reads default policy without durable rewrite',
      () async {
        final prior = DeviceSettings(quality: 69).toJson()
          ..['formatVersion'] = version
          ..remove('networkUploadPolicy');
        if (version == 1) {
          prior.remove('cacheLimitMiB');
          prior.remove('defaultOutputRetention');
        }
        final original = jsonEncode(prior);
        sql(
          (db) => db.execute(
            "INSERT INTO library_metadata(key,value) VALUES('device_settings_v1',?)",
            [original],
          ),
        );
        await reopen();
        final loaded = await repository.loadSettings();
        expect(loaded.values.quality, 69);
        expect(
          loaded.values.networkUploadPolicy,
          NetworkUploadPolicy.wifiAndEthernet,
        );
        sql(
          (db) => expect(
            db
                .select(
                  "SELECT value FROM library_metadata WHERE key='device_settings_v1'",
                )
                .single['value'],
            original,
          ),
        );
      },
    );
  }
  test('UT-083/097 protected backend outage hides target prose while local settings remain usable', () async {
    const key = 'synthetic-settings-key-012345';
    await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: 'alias-$key',
      anonymous: false,
      credential: key,
    );
    secrets.failReads = true;
    final snapshot = await repository.loadSettings();
    expect(snapshot.targets.single.alias, isNot(contains(key)));
    expect(
      snapshot.targets.single.alias,
      anyOf(SecretRedactor.unavailable, 'alias-[已隐藏]'),
    );
    await repository.saveSettings(
      snapshot,
      DeviceSettings(quality: 63),
      defaultTargetIds: [],
    );
    expect(repository.currentDeviceSettings.quality, 63);
    secrets.failReads = false;
  });
  test('UT-081/083 new defaults keep existing output input frozen and captured portable settings immutable', () async {
    final id = await asset(8);
    final output = await ProcessingCoordinator(repository).process(
      [id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        mode: ProcessingMode.sizeFirst,
        outputFormat: ProcessingFormat.jpeg,
        quality: 85,
        inputs: inputs,
      ),
      displayName: 'frozen.jpg',
    );
    expect(output.usable, isTrue);
    final before = (await repository.getOutput(output.id)).request.toSnapshot();
    await save(
      DeviceSettings(quality: 40, longestSide: 800, processingConcurrency: 4),
    );
    expect(
      (await repository.getOutput(output.id)).request.toSnapshot(),
      before,
    );
    expect(repository.processingScheduler.activeCount, 0);
    final snapshot = await repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    try {
      final json = jsonDecode(utf8.decode(snapshot.manifestBytes)) as Map;
      expect(json.containsKey('deviceSettings'), isFalse);
      expect(json['formatVersion'], 2);
      expect(
        (json['settings'] as Map)['values'],
        repository.currentDeviceSettings.toJson(),
      );
      final captured = snapshot.manifest.settings!.values;
      expect(captured.quality, 40);
      expect(captured.longestSide, 800);
      await save(DeviceSettings(quality: 41));
      expect(snapshot.manifest.settings!.values, captured);
      expect(snapshot.manifest.settings!.values.quality, 40);
      expect(
        (await repository.getOutput(output.id)).request.toSnapshot(),
        before,
      );
    } finally {
      await snapshot.release();
    }
  });
  test('UT-053/083 settings default flag and lower concurrency do not revoke actual held upload', () async {
    final ids = [for (var i = 0; i < 5; i++) await asset(4 + i)];
    final id = await target();
    final adapter = _HeldAdapter();
    final actor = UploadCoordinator(
      LibraryUploadQueueStore(repository),
      adapters: [adapter],
      initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
    );
    final session = LibrarySession(repository, const [], uploads: actor);
    var accountEvents = 0;
    final subscription = repository.accountChanges.listen(
      (_) => accountEvents++,
    );
    try {
      await repository.enqueueUploads(
        intentId: 'settings-dynamic-fixture',
        assetIds: ids,
        targetIds: [id],
        allowOriginalMetadata: true,
      );
      await actor.setNetworkAllowed(true);
      await until(() => adapter.calls.length == 3);
      await save(DeviceSettings(uploadConcurrency: 1), targets: [id]);
      expect(actor.concurrency, 1);
      expect(accountEvents, 0);
      expect(adapter.calls.every((c) => !c.$1.isCancelled), isTrue);
      adapter.complete(0);
      adapter.complete(1);
      await until(() => actor.activeCount == 1);
      expect(adapter.calls, hasLength(3));
      adapter.complete(2);
      await until(() => adapter.calls.length == 4);
      adapter.complete(3);
      await until(() => adapter.calls.length == 5);
      adapter.complete(4);
      await until(() => actor.activeCount == 0);
      expect(await repository.listUploadResults(), hasLength(5));
    } finally {
      await actor.setNetworkAllowed(false);
      for (var i = 0; i < adapter.calls.length; i++) {
        if (!adapter.calls[i].$2.isCompleted) adapter.complete(i);
      }
      await subscription.cancel();
      await session.close();
    }
  });
}
