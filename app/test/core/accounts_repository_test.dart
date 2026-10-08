import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_store.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_database.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:sqlite3/sqlite3.dart';

class TestSecrets implements SecretStore {
  final values = <String, String>{};
  bool unavailable = false;
  bool failAfterWrite = false;
  bool failDelete = false;
  @override
  Future<void> write(String reference, String value) async {
    if (unavailable) throw const SecretStorageException();
    values[reference] = value;
    if (failAfterWrite) throw const SecretStorageException();
  }

  @override
  Future<String?> read(String reference) async {
    if (unavailable) throw const SecretStorageException();
    return values[reference];
  }

  @override
  Future<void> delete(String reference) async {
    if (unavailable || failDelete) throw const SecretStorageException();
    values.remove(reference);
  }
}

void main() {
  late Directory sandbox;
  late Directory root;
  late TestSecrets secrets;
  late LibraryRepository repository;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-accounts-');
    root = Directory('${sandbox.path}/library');
    secrets = TestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });
  Future<String> add({
    String alias = '同名',
    String key = 'synthetic-secret-A',
    bool anonymous = false,
    bool defaultTarget = false,
    CredentialPersistence persistence = CredentialPersistence.protected,
  }) => repository.saveTarget(
    service: ImageHostService.catbox,
    alias: alias,
    anonymous: anonymous,
    credential: anonymous ? null : key,
    selectedByDefault: defaultTarget,
    persistence: persistence,
  );
  Future<void> reopen({AccountFaultHook? fault}) async {
    await repository.close();
    repository = await LibraryRepository.open(
      root,
      secretStore: secrets,
      accountFaultHook: fault,
    );
  }

  test('UT-039 configuration never implies harmless health verification or unknown capability support', () {
    for (final info in ProviderInformation.values) {
      expect(info.harmlessCredentialCheck, CapabilitySupport.unknown);
      expect(info.resumableUpload, CapabilitySupport.unknown);
      expect(info.remoteListing, CapabilitySupport.unknown);
      // Source implementation is available; it does not verify health, exact
      // provider limits or a real service contract.
      expect(info.uploadImplemented, isTrue);
      expect(info.deletionFor(anonymous: true), CapabilitySupport.unknown);
      expect(
        info.deletionFor(anonymous: false),
        info.service == ImageHostService.catbox
            ? CapabilitySupport.supported
            : CapabilitySupport.unknown,
      );
    }
  });
  test('UT-040 same names and services retain distinct account identity and credentials on reopen', () async {
    final first = await add();
    final second = await add(key: 'synthetic-secret-B');
    final third = await add(key: 'synthetic-secret-C');
    final imgbb = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '同名',
      anonymous: false,
      credential: 'synthetic-imgbb-key',
    );
    expect({first, second, third, imgbb}.length, 4);
    await reopen();
    final targets = await repository.listTargets();
    expect(targets.length, 4);
    expect(targets.map((e) => e.identityMarker).toSet().length, 4);
    expect(
      (await repository.resolveTarget(first)).credential,
      'synthetic-secret-A',
    );
    expect(
      (await repository.resolveTarget(second)).credential,
      'synthetic-secret-B',
    );
    expect(
      (await repository.resolveTarget(third)).credential,
      'synthetic-secret-C',
    );
    expect(targets.every((e) => e.health == AccountHealth.unverified), isTrue);
  });
  test('UT-041 blank credentials and unsupported anonymous mode reject before persistent target creation', () async {
    await expectLater(
      repository.saveTarget(
        service: ImageHostService.imgbb,
        alias: '账号',
        anonymous: false,
        credential: '  ',
      ),
      throwsA(isA<AccountFailure>()),
    );
    await expectLater(
      repository.saveTarget(
        service: ImageHostService.imgbb,
        alias: '匿名',
        anonymous: true,
      ),
      throwsA(isA<AccountFailure>()),
    );
    expect(await repository.listTargets(), isEmpty);
    expect(secrets.values, isEmpty);
  });
  test('UT-042 new enabled targets do not mutate a previously captured explicit selection', () async {
    final first = await add(defaultTarget: true);
    final frozen = List.unmodifiable(
      (await repository.listTargets())
          .where((e) => e.enabled && e.selectedByDefault)
          .map((e) => e.snapshot),
    );
    await add(key: 'synthetic-secret-B', defaultTarget: true);
    expect(frozen.map((e) => e.id), [first]);
  });
  test('UT-043 rename preserves old snapshot while dispatch reads replacement credential and disabled state', () async {
    final id = await add();
    final old = (await repository.listTargets()).single.snapshot;
    await repository.saveTarget(
      id: id,
      service: ImageHostService.catbox,
      alias: '新名称',
      anonymous: false,
      credential: 'synthetic-secret-B',
    );
    expect(old.alias, '同名');
    expect(old.id, id);
    expect(
      (await repository.resolveTarget(id)).credential,
      'synthetic-secret-B',
    );
    expect(secrets.values.values, ['synthetic-secret-B']);
    await repository.saveTarget(
      id: id,
      service: ImageHostService.catbox,
      alias: '新名称',
      anonymous: false,
      enabled: false,
    );
    await expectLater(
      repository.resolveTarget(id),
      throwsA(isA<AccountFailure>()),
    );
  });
  test('UT-043 / UT-095 removal tombstone blocks dispatch immediately and retries secret cleanup without identity reuse', () async {
    final id = await add();
    secrets.failDelete = true;
    await expectLater(
      repository.removeTarget(id),
      throwsA(isA<SecretStorageException>()),
    );
    final removed = (await repository.listTargets(includeRemoved: true)).single;
    expect(removed.removed, isTrue);
    expect(removed.enabled, isFalse);
    expect(removed.pendingOperation, isTrue);
    await expectLater(
      repository.removeTarget(id),
      throwsA(isA<SecretStorageException>()),
    );
    await expectLater(
      repository.resolveTarget(id),
      throwsA(isA<AccountFailure>()),
    );
    secrets.failDelete = false;
    await reopen();
    expect(secrets.values, isEmpty);
    expect(await repository.listTargets(), isEmpty);
    final newId = await add();
    expect(newId, isNot(id));
    expect((await repository.listTargets(includeRemoved: true)).length, 2);
  });
  test('UT-095 inaccessible secure backend leaves local library available and permits explicit separate session target', () async {
    secrets.unavailable = true;
    await expectLater(add(), throwsA(isA<SecretStorageException>()));
    final sessionId = await add(
      key: 'synthetic-session-only',
      persistence: CredentialPersistence.session,
    );
    expect(
      (await repository.resolveTarget(sessionId)).credential,
      'synthetic-session-only',
    );
    expect((await repository.listAssets()).total, 0);
    await reopen();
    expect((await repository.listAssets()).total, 0);
    await expectLater(
      repository.resolveTarget(sessionId),
      throwsA(isA<AccountFailure>()),
    );
  });
  test('UT-095 replacing protected credential with explicit session cannot resurrect old key after restart', () async {
    final id = await add();
    await repository.saveTarget(
      id: id,
      service: ImageHostService.catbox,
      alias: '同名',
      anonymous: false,
      credential: 'synthetic-session-only',
      persistence: CredentialPersistence.session,
    );
    expect(
      (await repository.resolveTarget(id)).credential,
      'synthetic-session-only',
    );
    expect(secrets.values, isEmpty);
    await reopen();
    await expectLater(
      repository.resolveTarget(id),
      throwsA(isA<AccountFailure>()),
    );
    expect(
      (await repository.listTargets()).single.health,
      AccountHealth.unconfigured,
    );
  });
  test('UT-095 native partial write is recovered using safe journal and confirmed secure read', () async {
    secrets.failAfterWrite = true;
    await expectLater(add(), throwsA(isA<SecretStorageException>()));
    secrets.failAfterWrite = false;
    await reopen();
    final target = (await repository.listTargets()).single;
    expect(
      (await repository.resolveTarget(target.id)).credential,
      'synthetic-secret-A',
    );
  });
  test('UT-041 invalid secure value fails dispatch locally while unrelated target remains available', () async {
    final id = await add();
    final unrelated = await add(
      key: 'synthetic-session-B',
      persistence: CredentialPersistence.session,
    );
    secrets.values.updateAll((reference, value) => ' ');
    await expectLater(
      repository.resolveTarget(id),
      throwsA(isA<AccountFailure>()),
    );
    expect(
      (await repository.listTargets()).singleWhere((t) => t.id == id).health,
      AccountHealth.unconfigured,
    );
    expect(
      (await repository.resolveTarget(unrelated)).credential,
      'synthetic-session-B',
    );
  });
  for (final boundary in AccountBoundary.values) {
    test(
      'UT-043 / UT-091 credential replacement recovery at ${boundary.name} preserves stable target and safe ownership',
      () async {
        final id = await add();
        await reopen(
          fault: (point) async {
            if (point == boundary) throw const AccountFailure('注入中断。');
          },
        );
        await expectLater(
          repository.saveTarget(
            id: id,
            service: ImageHostService.catbox,
            alias: '新名',
            anonymous: false,
            credential: 'synthetic-secret-B',
          ),
          throwsA(isA<AccountFailure>()),
        );
        await reopen();
        final expected = boundary == AccountBoundary.intent
            ? 'synthetic-secret-A'
            : 'synthetic-secret-B';
        expect((await repository.resolveTarget(id)).credential, expected);
        expect(secrets.values.values, [expected]);
        expect(
          (await repository.listTargets()).single.pendingOperation,
          isFalse,
        );
      },
    );
  }
  test('UT-097 ordinary SQLite target and operation records never contain raw registered or session secrets', () async {
    final id = await add(alias: 'synthetic-secret-A');
    expect((await repository.listTargets()).single.alias, '[已隐藏]');
    await repository.saveTarget(
      id: id,
      service: ImageHostService.catbox,
      alias: '安全别名',
      anonymous: false,
      credential: 'synthetic-secret-B',
    );
    await add(
      key: 'synthetic-session-only',
      persistence: CredentialPersistence.session,
    );
    await repository.close();
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      final text = [
        db.select('SELECT * FROM provider_targets'),
        db.select('SELECT * FROM credential_operations'),
      ].toString();
      for (final secret in [
        'synthetic-secret-A',
        'synthetic-secret-B',
        'synthetic-session-only',
      ]) {
        expect(text, isNot(contains(secret)));
      }
    } finally {
      db.close();
    }
  });
  test('UT-093 own schema 3 to current preserves library state without importing any prior application format', () async {
    final bytes = img.encodePng(img.Image(width: 8, height: 6));
    final asset = (await repository.importResource(
      PlatformResource(
        displayName: '本版升级夹具.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    await repository.updateOrganization([asset.id], replaceTags: ['保留标签']);
    await repository.setFavorite(asset.id, true);
    final before = (await repository.getAsset(asset.id))!;
    final output = await ProcessingCoordinator(repository).process(
      [asset.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        mode: ProcessingMode.sizeFirst,
        inputs: inputs,
        longestSide: 4,
      ),
      displayName: '保留输出.png',
    );
    await repository.close();
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      for (final table in [
        'diagnostic_records',
        'restore_operations',
        'imported_upload_histories',
        'restored_output_origins',
        'upload_events',
        'upload_result_operations',
        'remote_upload_results',
        'upload_attempts',
        'upload_publications',
        'upload_batches',
      ]) {
        db.execute('DROP TABLE $table');
      }
      db.execute('DROP TABLE credential_operations');
      db.execute('DROP TABLE provider_targets');
      db.execute('PRAGMA user_version=3');
    } finally {
      db.close();
    }
    await reopen();
    expect(await repository.listTargets(), isEmpty);
    expect((await repository.listOutputs()).single.id, output.id);
    expect((await repository.getOutput(output.id)).usable, isTrue);
    expect(await repository.getAsset(asset.id), before);
    expect(await repository.verifyCopy(before), CopyAvailability.available);
    expect(await (await repository.originalFor(before)).readAsBytes(), bytes);
    await repository.close();
    final checked = sqlite3.open('${root.path}/library.sqlite');
    try {
      expect(
        checked.select('PRAGMA user_version').single.values.single,
        librarySchemaVersion,
      );
      expect(
        checked.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
    } finally {
      checked.close();
    }
  });
}
