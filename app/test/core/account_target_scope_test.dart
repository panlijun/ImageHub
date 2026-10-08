import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/legacy_anonymous_fixture.dart';
import 'accounts_repository_test.dart' show TestSecrets;

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late TestSecrets secrets;
  late ImageAsset asset;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-account-scope-');
    root = Directory('${sandbox.path}/library');
    secrets = TestSecrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    asset = (await repository.importResource(
      PlatformResource(
        displayName: 'scope.png',
        openRead: () =>
            Stream.value(img.encodePng(img.Image(width: 3, height: 2))),
      ),
    )).asset!;
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });
  Future<String> account() => repository.saveTarget(
    service: ImageHostService.catbox,
    alias: '同名',
    anonymous: false,
    credential: 'SyntheticTargetScopeCredential',
    selectedByDefault: true,
  );
  Future<String> item(String target, String intent) async =>
      (await repository.enqueueUploads(
        intentId: intent,
        assetIds: [asset.id],
        targetIds: [target],
        allowOriginalMetadata: true,
        forceAgain: true,
      )).items.single.id;
  void mutate(void Function(Database) action) {
    final database = sqlite3.open('${root.path}/library.sqlite');
    try {
      action(database);
    } finally {
      database.close();
    }
  }

  test('UT-040/041 anonymous creation and editing reject before protected IO or persistent changes', () async {
    await expectLater(
      repository.saveTarget(
        service: ImageHostService.catbox,
        alias: '拒绝新匿名',
        anonymous: true,
        credential: 'MustNeverWriteAnonymousCredential',
      ),
      throwsA(isA<AccountFailure>()),
    );
    expect(await repository.listTargets(), isEmpty);
    expect(secrets.values, isEmpty);
    final id = await account();
    markLegacyAnonymous(root, id);
    final before = Map.of(secrets.values);
    await expectLater(
      repository.saveTarget(
        id: id,
        service: ImageHostService.catbox,
        alias: '试图变账号',
        anonymous: false,
        credential: 'MustNeverReplaceLegacyCredential',
      ),
      throwsA(isA<AccountFailure>()),
    );
    await expectLater(
      repository.saveTarget(
        id: id,
        service: ImageHostService.catbox,
        alias: '试图启用',
        anonymous: true,
        enabled: true,
      ),
      throwsA(isA<AccountFailure>()),
    );
    expect(secrets.values, before);
    final target = (await repository.listTargets()).single;
    expect(target.anonymous, isTrue);
    expect(target.enabled, isFalse);
    expect(target.selectedByDefault, isFalse);
    expect(target.alias, '同名');
    mutate((db) {
      final row = db.select(
        'SELECT anonymous,enabled,selected_by_default FROM provider_targets WHERE id=?',
        [id],
      ).single;
      expect(row['anonymous'], 1);
      expect(row['enabled'], 1);
      expect(row['selected_by_default'], 1);
    });
  });

  test('UT-042/043 legacy anonymous cannot become default or enqueue; reopened frozen intent waits without attempt', () async {
    final id = await account();
    final pending = await item(id, 'legacy-frozen');
    markLegacyAnonymous(root, id);
    await expectLater(
      repository.resolveTarget(id),
      throwsA(isA<AccountFailure>()),
    );
    await expectLater(
      item(id, 'new-anonymous-intent'),
      throwsA(isA<UploadQueueFailure>()),
    );
    final settings = await repository.loadSettings();
    expect(settings.defaultTargetIds, isEmpty);
    await expectLater(
      repository.saveSettings(
        settings,
        DeviceSettings.defaults,
        defaultTargetIds: [id],
      ),
      throwsA(isA<SettingsFailure>()),
    );
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    expect(await repository.beginUploadAttempt(pending), isNull);
    expect(await repository.listUploadAttempts(pending), isEmpty);
    final batch = (await repository.listUploadBatches()).single;
    expect(batch.items.single.state, PublishState.waiting);
    expect(batch.items.single.target.anonymous, isTrue);
    expect((await repository.listTargets()).single.id, id);
  });

  test('UT-043 impact reads stable UUID publication counts only; same-name targets and terminals remain separate', () async {
    final first = await account(), second = await account();
    var ordinal = 0;
    for (final state in [
      'queued',
      'waiting',
      'paused',
      'interrupted',
      'running',
      'unknown',
      'succeeded',
      'failed',
      'cancelled',
    ]) {
      final id = await item(first, 'impact-${ordinal++}');
      mutate(
        (db) => db.execute(
          'UPDATE upload_publications SET state=? WHERE id=?',
          [state, id],
        ),
      );
    }
    await item(second, 'same-name-other');
    final before = Map.of(secrets.values);
    final impact = await repository.targetUploadImpact(first);
    expect(impact.targetId, first);
    expect(impact.pending, 4);
    expect(impact.running, 1);
    expect(impact.unknown, 1);
    final other = await repository.targetUploadImpact(second);
    expect(other.pending, 1);
    expect(other.running, 0);
    expect(other.unknown, 0);
    expect(secrets.values, before);
    mutate((db) {
      expect(
        db.select('SELECT COUNT(*) AS n FROM upload_attempts').single['n'],
        0,
      );
      expect(db.select('SELECT COUNT(*) AS n FROM file_leases').single['n'], 0);
    });
    await repository.removeTarget(second);
    await expectLater(
      repository.targetUploadImpact(second),
      throwsA(isA<AccountFailure>()),
    );
    await expectLater(
      repository.targetUploadImpact('invalid'),
      throwsA(isA<AccountFailure>()),
    );
  });
}
