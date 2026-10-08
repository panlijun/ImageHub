import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
import 'package:imagehost/features/links/domain/link_query.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/link_format.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

final class _Secrets extends QueueTestSecrets {
  bool failDeletes = false;
  final deleted = <String>[];
  @override
  Future<void> delete(String reference) async {
    if (failDeletes) throw const SecretStorageException();
    deleted.add(reference);
    await super.delete(reference);
  }
}

void main() {
  late Directory sandbox, root;
  late LibraryRepository repository;
  late _Secrets secrets;
  late ImageAsset a, b, c;
  late String cat, imgbb;
  var serial = 0;
  const managementToken = 'SyntheticLinkManagementToken0123456789';

  Future<ImageAsset> image(String name, int marker) async {
    final pixels = img.Image(width: 8 + marker, height: 6);
    img.fill(pixels, color: img.ColorRgb8(marker, 30, 80));
    final result = await repository.importResource(
      PlatformResource(
        displayName: name,
        openRead: () => Stream.value(img.encodePng(pixels)),
      ),
    );
    expect(result.status, ImportStatus.saved);
    return result.asset!;
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-local-links-');
    root = Directory('${sandbox.path}/library');
    secrets = _Secrets();
    repository = await LibraryRepository.open(root, secretStore: secrets);
    a = await image('Cafe\u0301 Straße A.png', 1);
    b = await image('B%literal.png', 2);
    c = await image('没有链接 C.png', 3);
    cat = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '同名历史',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    imgbb = await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '同名历史',
      anonymous: false,
      credential: 'SyntheticLinkApiCredential0123456789',
    );
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  List<Map<String, Object?>> rows(String table, {String? database}) {
    final db = sqlite3.open(
      database ?? '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return db
          .select('SELECT * FROM "$table" ORDER BY 1')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } finally {
      db.close();
    }
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

  Future<void> reopen() async {
    await repository.close();
    repository = await LibraryRepository.open(root, secretStore: secrets);
  }

  Future<RemoteUploadResult> success(
    ImageAsset asset,
    String target, {
    String? slug,
    String? outputId,
    bool management = false,
  }) async {
    final ordinal = ++serial;
    final batch = await repository.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: outputId == null ? [asset.id] : [],
      outputIds: outputId == null ? [] : [outputId],
      targetIds: [target],
      allowOriginalMetadata: true,
      forceAgain: true,
    );
    final execution = (await repository.beginUploadAttempt(
      batch.items.single.id,
    ))!;
    try {
      expect(
        await repository.authorizeUploadRequest(execution.attemptId),
        true,
      );
      final service = execution.item.target.service;
      final name = slug ?? 'ordinary$ordinal';
      await repository.finishUploadAttempt(
        execution,
        ProviderUploadSuccess(
          service: service,
          remoteId: service == ImageHostService.catbox ? '$name.png' : name,
          directUrl: Uri.parse(
            service == ImageHostService.catbox
                ? 'https://files.catbox.moe/$name.png'
                : 'https://i.ibb.co/$name/ordinary.png',
          ),
          viewerUrl: service == ImageHostService.imgbb
              ? Uri.parse('https://ibb.co/$name')
              : null,
          managementSecret: management
              ? SensitiveManagementSecret(
                  'https://ibb.co/$name/$managementToken',
                )
              : null,
        ),
        accumulatedRunning: Duration.zero,
      );
    } finally {
      await execution.release();
    }
    // Synthetic confirmation seeds the real repository; no adapter or HTTP
    // client is called by any test in this file.
    return (await repository.listUploadResults()).singleWhere(
      (r) => r.attemptId == execution.attemptId,
    );
  }

  String reference(RemoteUploadResult result) =>
      rows('remote_upload_results')
              .singleWhere((r) => r['id'] == result.id)['secret_reference']
          as String;

  Map<String, List<Map<String, Object?>>> protectedState() => {
    for (final table in [
      'assets',
      'versions',
      'device_copies',
      'upload_batches',
      'upload_attempts',
      'upload_events',
    ])
      table: rows(table),
  };

  test('UT-069 partial NFC casefold name direct URL and frozen alias queries intersect stable target service and kind', () async {
    final first = await success(a, cat, slug: 'searchable');
    final second = await success(b, imgbb, slug: 'remoteB');
    await repository.saveTarget(
      id: cat,
      service: ImageHostService.catbox,
      alias: '后来账号名',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    for (final keyword in [
      'CAFÉ STRASSE',
      'cafe\u0301 straße',
      'SEARCHABLE',
      '同名历史',
    ]) {
      final page = await repository.listLinkResults(
        query: LinkResultQuery(
          keyword: keyword,
          targetId: cat,
          service: ImageHostService.catbox,
          inputKind: UploadInputKind.original,
        ),
      );
      expect(page.items.map((r) => r.id), [first.id]);
      expect(page.total, 1);
    }
    expect(
      (await repository.listLinkResults(
        query: const LinkResultQuery(keyword: '后来账号名'),
      )).total,
      0,
    );
    expect(
      (await repository.listLinkResults(
        query: LinkResultQuery(
          keyword: '同名历史',
          targetId: cat,
          service: ImageHostService.imgbb,
        ),
      )).total,
      0,
    );
    expect(
      (await repository.listLinkResults(
        query: const LinkResultQuery(inputKind: UploadInputKind.processed),
      )).total,
      0,
    );
    expect(
      (await repository.listLinkResults(
        query: LinkResultQuery(targetId: imgbb),
      )).items.single.id,
      second.id,
    );
  });

  test('UT-069 SEC secret values are absent from search and percent wildcard stays literal', () async {
    await success(a, cat);
    final result = await success(b, imgbb, management: true);
    for (final keyword in [
      managementToken,
      secrets.values[reference(result)]!,
      'SyntheticLinkApiCredential0123456789',
    ]) {
      expect(
        (await repository.listLinkResults(
          query: LinkResultQuery(keyword: keyword),
        )).total,
        0,
      );
    }
    final page = await repository.listLinkResults(
      query: const LinkResultQuery(keyword: '%'),
    );
    expect(page.total, 1);
    expect(page.items.single.id, result.id);
    expect(
      (await repository.listLinkResults(
        query: const LinkResultQuery(keyword: '_'),
      )).total,
      0,
    );
  });

  test('UT-069 partial removed same-alias account never merges historical UUID with a new account', () async {
    final first = await success(a, cat);
    final second = await success(a, imgbb);
    await repository.removeTarget(cat);
    final replacement = await repository.saveTarget(
      service: ImageHostService.catbox,
      alias: '同名历史',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    expect(replacement, isNot(cat));
    final historical = await repository.listLinkTargets();
    expect(historical.map((t) => t.id).toSet(), {cat, imgbb});
    expect(historical.every((t) => t.alias == '同名历史'), true);
    expect(
      (await repository.listLinkResults(
        query: LinkResultQuery(targetId: replacement),
      )).total,
      0,
    );
    expect(
      (await repository.listLinkResults(query: LinkResultQuery(targetId: cat)))
          .items
          .single
          .id,
      first.id,
    );
    expect(
      (await repository.listLinkResults(
        query: LinkResultQuery(targetId: imgbb),
      )).items.single.id,
      second.id,
    );
    await reopen();
    expect((await repository.listLinkTargets()).map((t) => t.id).toSet(), {
      cat,
      imgbb,
    });
  });

  test('UT-069 partial count uses the same filters as stable pagination and all sort ties use result UUID', () async {
    final seeded = [
      await success(a, cat),
      await success(a, cat),
      await success(a, cat),
      await success(b, imgbb),
    ];
    mutate(
      (db) =>
          db.execute('UPDATE remote_upload_results SET confirmed_utc=12345'),
    );
    final ids = seeded.take(3).map((r) => r.id).toList()..sort();
    for (final sort in LinkResultSort.values) {
      for (final ascending in [false, true]) {
        final query = LinkResultQuery(
          targetId: cat,
          sort: sort,
          ascending: ascending,
        );
        final first = await repository.listLinkResults(query: query, limit: 2);
        final second = await repository.listLinkResults(
          query: query,
          limit: 2,
          offset: 2,
        );
        expect(first.total, 3);
        expect(second.total, 3);
        expect([...first.items, ...second.items].map((r) => r.id), ids);
        expect(
          (await repository.listLinkResults(query: query, offset: 10)).items,
          isEmpty,
        );
      }
    }
    for (final invalid in [(-1, 1), (0, 0)]) {
      await expectLater(
        repository.listLinkResults(offset: invalid.$1, limit: invalid.$2),
        throwsA(isA<UploadQueueFailure>()),
      );
    }
  });

  test('UT-070 partial visible copy uses only explicit ordered IDs and reports missing and duplicate URLs', () async {
    final first = await success(a, cat, slug: 'same');
    final duplicate = await success(b, cat, slug: 'same');
    final distinct = await success(b, imgbb, slug: 'distinct');
    await success(c, cat, slug: 'hidden');
    final missing = const Uuid().v4();
    final plan = await repository.prepareVisibleLinkCopy([
      distinct.id,
      missing,
      first.id,
      duplicate.id,
      first.id,
    ], UploadLinkFormat.url);
    expect(plan.scope, LinkCopyScope.visibleResults);
    expect(plan.confirmedResultIds, [
      distinct.id,
      missing,
      first.id,
      duplicate.id,
    ]);
    expect(plan.batch.text, '${distinct.directUrl}\n${first.directUrl}');
    expect(plan.batch.copied, 2);
    expect(plan.batch.skipped, 1);
    expect(plan.batch.duplicates, 1);
    expect(plan.batch.text, isNot(contains('hidden')));
    await repository.validateLinkCopyPlan(plan);
    await expectLater(
      repository.prepareVisibleLinkCopy(['invalid'], UploadLinkFormat.url),
      throwsA(isA<UploadQueueFailure>()),
    );
  });

  test('UT-070 partial asset plan obeys B A C order then explicit target order and does not add processed versions', () async {
    final ac = await success(a, cat, slug: 'Acat');
    final ai = await success(a, imgbb, slug: 'Aimg');
    final bc = await success(b, cat, slug: 'Bcat');
    final bi = await success(b, imgbb, slug: 'Bimg');
    final output = await ProcessingCoordinator(repository).process(
      [a.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: inputs,
        mode: ProcessingMode.sizeFirst,
        longestSide: 3,
      ),
      displayName: '另一个处理版本.png',
    );
    final processed = await success(
      a,
      imgbb,
      slug: 'processed',
      outputId: output.id,
    );
    final plan = await repository.prepareAssetLinkCopy(
      [b.id, a.id, c.id],
      [imgbb, cat],
      UploadLinkFormat.url,
    );
    expect(plan.confirmedResultIds, [bi.id, bc.id, ai.id, ac.id]);
    expect(plan.targets.map((t) => t.id), [imgbb, cat]);
    expect(plan.assetNames, [b.displayName, a.displayName, c.displayName]);
    expect(
      plan.batch.text,
      [bi, bc, ai, ac].map((r) => r.directUrl).join('\n'),
    );
    expect(plan.batch.skipped, 2);
    expect(plan.batch.copied, 4);
    expect(plan.confirmedResultIds, isNot(contains(processed.id)));
    final originals = await repository.prepareAssetLinkCopy(
      [a.id],
      [imgbb],
      UploadLinkFormat.url,
      inputKind: UploadInputKind.original,
    );
    expect(originals.confirmedResultIds, [ai.id]);
    final none = await repository.prepareAssetLinkCopy(
      [a.id],
      [imgbb],
      UploadLinkFormat.url,
      inputKind: UploadInputKind.processed,
    );
    expect(none.batch.copied, 0);
    expect(none.batch.skipped, 1);
    await expectLater(
      repository.prepareAssetLinkCopy(
        [a.id],
        [const Uuid().v4()],
        UploadLinkFormat.url,
      ),
      throwsA(isA<UploadQueueFailure>()),
    );
  });

  test('UT-070 partial asset selection matches exact current digest and bytes and preserves missing asset skips', () async {
    final good = await success(a, cat, slug: 'good');
    final wrong = await success(a, cat, slug: 'wrong');
    mutate(
      (db) => db.execute(
        'UPDATE remote_upload_results SET byte_count=byte_count+1 WHERE id=?',
        [wrong.id],
      ),
    );
    var plan = await repository.prepareAssetLinkCopy(
      [a.id],
      [cat],
      UploadLinkFormat.url,
    );
    expect(plan.confirmedResultIds, [good.id]);
    mutate(
      (db) => db.execute(
        'UPDATE remote_upload_results SET version_digest=? WHERE id=?',
        ['f' * 64, good.id],
      ),
    );
    plan = await repository.prepareAssetLinkCopy(
      [a.id, const Uuid().v4()],
      [cat],
      UploadLinkFormat.url,
    );
    expect(plan.batch.copied, 0);
    expect(plan.batch.skipped, 2);
    expect(plan.assetNames.last, '资产记录已缺失');
  });

  test('UT-070 SEC changed confirmation or a newly registered secret invalidates an already reviewed copy plan', () async {
    final result = await success(
      a,
      cat,
      slug: 'ordinarySecretCollision0123456789',
    );
    final plan = await repository.prepareVisibleLinkCopy([
      result.id,
    ], UploadLinkFormat.url);
    mutate(
      (db) => db.execute(
        'UPDATE remote_upload_results SET direct_url=? WHERE id=?',
        ['https://files.catbox.moe/changed.png', result.id],
      ),
    );
    await expectLater(
      repository.validateLinkCopyPlan(plan),
      throwsA(isA<UploadQueueFailure>()),
    );
    mutate(
      (db) => db.execute(
        'UPDATE remote_upload_results SET direct_url=? WHERE id=?',
        [result.directUrl.toString(), result.id],
      ),
    );
    await repository.validateLinkCopyPlan(plan);
    await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '另一个账号',
      anonymous: false,
      credential: 'ordinarySecretCollision0123456789',
    );
    await expectLater(
      repository.validateLinkCopyPlan(plan),
      throwsA(isA<UploadQueueFailure>()),
    );
  });

  test('UT-069/070 SEC later registered credential masks frozen name and alias before SQL keyword count and invalidates old plan', () async {
    const futureSecret = 'FutureOrdinaryNameCollision0123456789';
    final named = await image('$futureSecret.png', 5);
    await repository.saveTarget(
      id: cat,
      service: ImageHostService.catbox,
      alias: '别名$futureSecret',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
    );
    final result = await success(named, cat, slug: 'futureNameSafeUrl');
    final plan = await repository.prepareVisibleLinkCopy([
      result.id,
    ], UploadLinkFormat.markdown);
    expect(plan.batch.text, contains(futureSecret));
    expect(
      (await repository.listLinkResults(
        query: const LinkResultQuery(keyword: futureSecret),
      )).total,
      1,
    );
    await repository.saveTarget(
      service: ImageHostService.imgbb,
      alias: '新凭据',
      anonymous: false,
      credential: futureSecret,
    );
    final filtered = await repository.listLinkResults(
      query: const LinkResultQuery(keyword: futureSecret),
    );
    expect(filtered.total, 0);
    expect(filtered.items, isEmpty);
    final ordinary = (await repository.listLinkResults()).items.single;
    expect(ordinary.input.displayName, '[已隐藏].png');
    expect(ordinary.target.alias, '别名[已隐藏]');
    final stored = rows('remote_upload_results').single;
    expect(stored['input_json'] as String, isNot(contains(futureSecret)));
    expect(stored['target_json'] as String, isNot(contains(futureSecret)));
    expect((await repository.listLinkTargets()).single.alias, '别名[已隐藏]');
    await expectLater(
      repository.validateLinkCopyPlan(plan),
      throwsA(isA<UploadQueueFailure>()),
    );
    await reopen();
    expect(
      (await repository.listLinkResults(
        query: const LinkResultQuery(keyword: futureSecret),
      )).total,
      0,
    );
    expect(
      (await repository.listUploadResults()).single.input.displayName,
      '[已隐藏].png',
    );
  });

  test('UT-070 SEC unconfirmed or intent-fault local removal keeps ordinary rows secrets and all histories', () async {
    final result = await success(a, imgbb, management: true);
    final before = protectedState(),
        ordinary = rows('remote_upload_results'),
        secretValues = Map.of(secrets.values);
    await expectLater(
      repository.removeLocalLinkResults([
        result.id,
      ], confirmLocalRemoval: false),
      throwsA(isA<UploadQueueFailure>()),
    );
    await expectLater(
      repository.removeLocalLinkResults(
        [result.id],
        confirmLocalRemoval: true,
        faultHook: (boundary) async {
          if (boundary == LocalLinkRemovalBoundary.intent) {
            throw StateError('controlled');
          }
        },
      ),
      throwsA(isA<UploadQueueFailure>()),
    );
    expect(rows('remote_upload_results'), ordinary);
    expect(protectedState(), before);
    expect(secrets.values, secretValues);
    expect(rows('upload_result_operations'), isEmpty);
  });

  test('UT-070 SEC removal is local only and unlinks publication while keeping pixels assets attempts and events', () async {
    final result = await success(a, imgbb, management: true);
    final secretReference = reference(result),
        otherSecrets = Map.of(secrets.values)..remove(secretReference);
    final before = protectedState(),
        bytes = await File('${root.path}/${a.deviceCopy.relativePath}')
            .readAsBytes();
    final report = await repository.removeLocalLinkResults([
      result.id,
      result.id,
      const Uuid().v4(),
    ], confirmLocalRemoval: true);
    expect(report.removed, 1);
    expect(report.missing, 1);
    expect(report.cleanupPending, 0);
    expect(rows('remote_upload_results'), isEmpty);
    expect(rows('upload_result_operations'), isEmpty);
    expect(rows('upload_publications').single['result_id'], isNull);
    expect(rows('upload_publications').single['state'], 'succeeded');
    expect(protectedState(), before);
    expect(
      await File('${root.path}/${a.deviceCopy.relativePath}').readAsBytes(),
      bytes,
    );
    expect(secrets.values, otherSecrets);
    expect(secrets.deleted, [secretReference]);
    final again = await repository.removeLocalLinkResults([
      result.id,
    ], confirmLocalRemoval: true);
    expect(again.removed, 0);
    expect(again.missing, 1);
    expect(again.cleanupPending, 0);
  });

  test('UT-070 SEC secret read failure occurs before ordinary deletion or journal creation', () async {
    final result = await success(a, imgbb, management: true);
    final before = rows('remote_upload_results'),
        values = Map.of(secrets.values);
    secrets.failReads = true;
    await expectLater(
      repository.removeLocalLinkResults([result.id], confirmLocalRemoval: true),
      throwsA(isA<UploadQueueFailure>()),
    );
    secrets.failReads = false;
    expect(rows('remote_upload_results'), before);
    expect(rows('upload_result_operations'), isEmpty);
    expect(secrets.values, values);
    expect(secrets.deleted, isEmpty);
  });

  for (final boundary in [
    LocalLinkRemovalBoundary.recordsRemoved,
    LocalLinkRemovalBoundary.secretDeleted,
  ]) {
    test(
      'UT-070 SEC ${boundary.name} fault keeps durable cleanup evidence and reopen completes idempotently',
      () async {
        final result = await success(a, imgbb, management: true);
        final secretReference = reference(result);
        final report = await repository.removeLocalLinkResults(
          [result.id],
          confirmLocalRemoval: true,
          faultHook: (point) async {
            if (point == boundary) throw StateError('controlled');
          },
        );
        expect(report.removed, 1);
        expect(report.cleanupPending, 1);
        expect(rows('remote_upload_results'), isEmpty);
        expect(rows('upload_result_operations'), hasLength(1));
        expect(rows('upload_publications').single['result_id'], isNull);
        expect(
          secrets.values.containsKey(secretReference),
          boundary == LocalLinkRemovalBoundary.recordsRemoved,
        );
        await reopen();
        expect(rows('upload_result_operations'), isEmpty);
        expect(rows('remote_upload_results'), isEmpty);
        expect(secrets.values.containsKey(secretReference), false);
        expect(
          secrets.deleted.where((r) => r == secretReference),
          hasLength(1),
        );
        await reopen();
        expect(rows('upload_result_operations'), isEmpty);
      },
    );
  }

  test('UT-070 SEC delete failure preserves secret and pending journal then reopen retries without touching other credentials', () async {
    final result = await success(a, imgbb, management: true);
    final secretReference = reference(result), values = Map.of(secrets.values);
    secrets.failDeletes = true;
    final report = await repository.removeLocalLinkResults([
      result.id,
    ], confirmLocalRemoval: true);
    expect(report.removed, 1);
    expect(report.cleanupPending, 1);
    expect(rows('remote_upload_results'), isEmpty);
    expect(rows('upload_result_operations'), hasLength(1));
    expect(secrets.values, values);
    await reopen();
    expect(rows('upload_result_operations'), hasLength(1));
    expect(secrets.values, values);
    secrets.failDeletes = false;
    await reopen();
    expect(rows('upload_result_operations'), isEmpty);
    expect(secrets.values, Map.of(values)..remove(secretReference));
    expect(secrets.deleted, [secretReference]);
  });

  test('UT-070 SEC changed management hash protects the altered value and journal on every restart', () async {
    final result = await success(a, imgbb, management: true);
    final secretReference = reference(result);
    await repository.removeLocalLinkResults(
      [result.id],
      confirmLocalRemoval: true,
      faultHook: (boundary) async {
        if (boundary == LocalLinkRemovalBoundary.recordsRemoved) {
          secrets.values[secretReference] =
              'https://ibb.co/otherID/DifferentSyntheticManagement012345';
        }
      },
    );
    final changed = secrets.values[secretReference];
    expect(rows('upload_result_operations'), hasLength(1));
    expect(secrets.deleted, isEmpty);
    await reopen();
    expect(secrets.values[secretReference], changed);
    expect(rows('upload_result_operations'), hasLength(1));
    expect(secrets.deleted, isEmpty);
    expect(rows('remote_upload_results'), isEmpty);
  });

  test('UT-070 SEC shared secret reference blocks management deletion and retains the other ordinary result', () async {
    final first = await success(a, imgbb, management: true);
    final second = await success(b, imgbb, management: true);
    final shared = reference(first), otherReference = reference(second);
    mutate(
      (db) => db.execute(
        'UPDATE remote_upload_results SET secret_reference=? WHERE id=?',
        [shared, second.id],
      ),
    );
    final report = await repository.removeLocalLinkResults([
      first.id,
    ], confirmLocalRemoval: true);
    expect(report.cleanupPending, 1);
    expect(rows('upload_result_operations'), hasLength(1));
    expect(rows('remote_upload_results').single['id'], second.id);
    expect(secrets.values.keys, containsAll([shared, otherReference]));
    expect(secrets.deleted, isEmpty);
    await reopen();
    expect(rows('upload_result_operations'), hasLength(1));
    expect(secrets.values.keys, contains(shared));
    expect(secrets.deleted, isEmpty);
  });

  test('UT-070 SEC tampered cleanup payload preserves its secret and journal without affecting account credentials', () async {
    final result = await success(a, imgbb, management: true);
    await repository.removeLocalLinkResults(
      [result.id],
      confirmLocalRemoval: true,
      faultHook: (boundary) async {
        if (boundary == LocalLinkRemovalBoundary.recordsRemoved) {
          throw StateError('controlled');
        }
      },
    );
    final operation = rows('upload_result_operations').single;
    final data = jsonDecode(operation['proposal_json'] as String) as Map;
    data['unexpected'] = 'field';
    mutate(
      (db) => db.execute(
        'UPDATE upload_result_operations SET proposal_json=?',
        [jsonEncode(data)],
      ),
    );
    final before = Map.of(secrets.values);
    await reopen();
    expect(rows('upload_result_operations'), hasLength(1));
    expect(secrets.values, before);
    expect(secrets.deleted, isEmpty);
    expect(rows('remote_upload_results'), isEmpty);
  });

  test('UT-070 SEC a tampered removal reference and matching hash never grant ownership of account credentials', () async {
    final result = await success(a, imgbb, management: true);
    await repository.removeLocalLinkResults(
      [result.id],
      confirmLocalRemoval: true,
      faultHook: (boundary) async {
        if (boundary == LocalLinkRemovalBoundary.recordsRemoved) {
          throw StateError('controlled');
        }
      },
    );
    final accountReference =
        rows('provider_targets')
                .singleWhere((r) => r['id'] == imgbb)['secret_reference']
            as String;
    final operation = rows('upload_result_operations').single;
    final data = jsonDecode(operation['proposal_json'] as String) as Map;
    data['secretHash'] = sha256
        .convert(utf8.encode(secrets.values[accountReference]!))
        .toString();
    mutate(
      (db) => db.execute(
        'UPDATE upload_result_operations SET proposal_json=?, secret_reference=?',
        [jsonEncode(data), accountReference],
      ),
    );
    final values = Map.of(secrets.values);
    await reopen();
    expect(rows('upload_result_operations'), hasLength(1));
    expect(secrets.values, values);
    expect(secrets.deleted, isEmpty);
    expect(rows('remote_upload_results'), isEmpty);
  });

  test('UT-070 SEC pending local removal blocks restore until cleanup; clean snapshot recovery preserves ordinary deletion and unrelated secret association', () async {
    final result = await success(a, imgbb, management: true);
    final managementReference = reference(result);
    final credentialReference =
        rows('provider_targets')
                .singleWhere((r) => r['id'] == imgbb)['secret_reference']
            as String;
    secrets.failDeletes = true;
    await repository.removeLocalLinkResults([
      result.id,
    ], confirmLocalRemoval: true);
    final pending = rows('upload_result_operations');
    final secretValues = Map.of(secrets.values);
    await expectLater(
      repository.acquireRestoreHold(),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(rows('remote_upload_results'), isEmpty);
    expect(rows('upload_result_operations'), pending);
    expect(secrets.values, secretValues);
    secrets.failDeletes = false;
    await reopen();
    expect(rows('upload_result_operations'), isEmpty);
    expect(secrets.values.containsKey(managementReference), false);
    expect(
      secrets.values[credentialReference],
      secretValues[credentialReference],
    );
    final hold = await repository.acquireRestoreHold();
    ReplacementSnapshot? snapshot;
    try {
      snapshot = await repository.captureReplacementSnapshot(
        hold: hold,
        availableBytes: (_) async => 1 << 40,
      );
      await repository.verifyReplacementSnapshot(snapshot);
      final dbPath =
          '${root.path}/staging/replacement-${snapshot.id}/current.sqlite';
      expect(rows('remote_upload_results', database: dbPath), isEmpty);
      expect(rows('upload_result_operations', database: dbPath), isEmpty);
      expect(
        rows(
          'provider_targets',
          database: dbPath,
        ).singleWhere((r) => r['id'] == imgbb)['secret_reference'],
        credentialReference,
      );
      expect(
        rows('upload_publications', database: dbPath).single['result_id'],
        isNull,
      );
      await repository.proveReplacementSnapshotRecovery(
        snapshot,
        availableBytes: (_) async => 1 << 40,
      );
      expect(rows('remote_upload_results'), isEmpty);
      expect(
        secrets.values[credentialReference],
        secretValues[credentialReference],
      );
    } finally {
      if (snapshot != null) {
        await repository.discardReplacementSnapshot(snapshot);
      }
      await hold.release();
    }
    await reopen();
    expect((await repository.listAssets()).items, hasLength(3));
    expect(rows('remote_upload_results'), isEmpty);
    expect(
      secrets.values[credentialReference],
      secretValues[credentialReference],
    );
    // After pending cleanup, an actual metadata replacement failure executes
    // the durable rollback path rather than restoring removed ordinary links.
    final beforeRollback = protectedState();
    final ordinary = await repository.captureBackupSnapshot(
      mode: BackupMode.metadata,
    );
    final package = File('${sandbox.path}/after-local-removal.zip');
    try {
      await BackupZipWriter().write(ordinary, package);
    } finally {
      await ordinary.release();
    }
    final backup = await const BackupZipReader().preflight(
      package,
      await Directory('${sandbox.path}/replacement-preflight').create(),
      availableBytes: (_) async => 1 << 40,
    );
    final replacementHold = await repository.acquireRestoreHold();
    ReplacementRestorePreparation? preparation;
    try {
      preparation = await repository.prepareReplacementRestore(
        hold: replacementHold,
        backup: backup,
        availableBytes: (_) async => 1 << 40,
      );
      await expectLater(
        repository.commitReplacementRestore(
          preparation: preparation,
          availableBytes: (_) async => 1 << 40,
          publishExclusive: (_, _) async => false,
          faultHook: (boundary) async {
            if (boundary == RestoreBoundary.beforeCommit) {
              throw StateError('controlled rollback');
            }
          },
        ),
        throwsA(isA<BackupSnapshotFailure>()),
      );
    } finally {
      if (preparation != null) {
        await repository.discardReplacementPreparation(preparation);
      }
      await replacementHold.release();
      await backup.dispose();
    }
    expect(protectedState(), beforeRollback);
    expect(rows('remote_upload_results'), isEmpty);
    expect(rows('upload_result_operations'), isEmpty);
    expect(rows('upload_publications').single['result_id'], isNull);
    expect(
      secrets.values[credentialReference],
      secretValues[credentialReference],
    );
    expect(
      await File('${root.path}/${a.deviceCopy.relativePath}').exists(),
      true,
    );
  });
}
