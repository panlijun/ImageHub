import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/domain/backup_settings.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
final version = ImageVersion(
  id: id(1),
  sha256: 'a' * 64,
  byteCount: 100,
  format: 'PNG',
  width: 10,
  height: 20,
  frameCount: 1,
  orientation: 1,
);
final historicalVersion = ImageVersion(
  id: id(2),
  sha256: 'b' * 64,
  byteCount: 200,
  format: 'JPEG',
  width: 30,
  height: 40,
  frameCount: 2,
  orientation: 8,
);
const key = 'fixture-credential-K';
const deletion = 'fixture-deletion-D';
final target = TargetSnapshot(
  id(20),
  ImageHostService.imgbb,
  '账号 $key $deletion',
  false,
);
final input = FrozenUploadInput(
  kind: UploadInputKind.processed,
  referenceId: id(30),
  displayName: '历史 $key $deletion',
  version: historicalVersion,
  policyKey: 'f' * 64,
  processingSummary: '压缩 $key $deletion',
);

BackupManifest fixture({
  BackupMode mode = BackupMode.full,
  BackupDeviceSettings? settings,
}) => BackupManifest(
  packageId: id(100),
  createdUtc: 1700000000000,
  mode: mode,
  settings: settings,
  versions: [version],
  assets: [
    BackupAsset(
      id: id(10),
      versionId: version.id,
      displayName: '${'文件' * 80} $key $deletion',
      sourceType: 'selected',
      importedUtc: 1700000000000,
      updatedUtc: 1700000000100,
      favorite: true,
      categoryId: id(11),
      tagIds: [id(12)],
      recycled: true,
      recycledUtc: 1700000000100,
    ),
  ],
  categories: [BackupName(id: id(11), name: '类别 $key')],
  tags: [BackupName(id: id(12), name: '标签 $deletion')],
  origins: [
    BackupOrigin(
      outputId: id(31),
      versionId: version.id,
      createdUtc: 1700000000000,
      processing: BackupProcessingSnapshot(
        operation: ProcessingOperation.crop,
        inputs: [
          BackupProcessingInput(
            assetId: id(999),
            version: historicalVersion,
            selectedFrame: 1,
          ),
        ],
        mode: ProcessingMode.fidelity,
        outputFormat: ProcessingFormat.png,
        longestSide: 1600,
        quality: null,
        crop: const PixelCrop(0, 0, 10, 10),
        layout: StitchLayout.grid,
        gap: 0,
        backgroundArgb: 0xffffffff,
        backgroundConfirmed: false,
        explicitStaticConversion: true,
      ),
    ),
  ],
  accounts: [
    BackupAccount(
      id: target.id,
      service: target.service,
      alias: target.alias,
      anonymous: false,
    ),
  ],
  results: [
    for (var i = 0; i < 2; i++)
      BackupRemoteResult(
        id: id(40 + i),
        attemptId: id(50 + i),
        input: input,
        target: target,
        remoteId: 'remote-$i',
        directUrl: Uri.parse('https://example.org/image.png'),
        viewerUrl: Uri.parse('https://example.org/view'),
        confirmedUtc: 1700000000300,
        late: i == 1,
      ),
  ],
  history: [
    BackupTaskHistory(
      id: id(60),
      batchId: id(70),
      position: 0,
      input: input,
      target: target,
      state: PublishState.cancelled,
      attempts: [
        BackupAttemptHistory(
          id: id(51),
          generation: 1,
          startedUtc: 1700000000000,
          endedUtc: 1700000000200,
          outcome: '完成 $key $deletion',
        ),
      ],
      createdUtc: 1700000000000,
      updatedUtc: 1700000000200,
      message: '取消 $key $deletion',
    ),
  ],
  images: mode == BackupMode.metadata
      ? []
      : [
          BackupImageEntry(
            versionId: version.id,
            name: 'images/${version.id}.png',
            byteCount: version.byteCount,
            sha256: version.sha256,
          ),
        ],
);

Map<String, dynamic> raw({BackupMode mode = BackupMode.full}) => jsonDecode(
  utf8.decode(fixture(mode: mode).encode(redactor: SecretRedactor())),
) as Map<String, dynamic>;
Matcher failure([BackupFailureKind kind = BackupFailureKind.invalidManifest]) =>
    isA<BackupFailure>().having((f) => f.kind, 'kind', kind);

/// Contract-only partial coverage. No ZIP, repository consistency, disk space,
/// file hash verification, merge/replace or four-device restore is simulated.
void main() {
  test('UT-078/081 partial BAK-005: current format two settings and project format one read strictly', () {
    expect(BackupManifest.formatVersion, 2);
    final settings = BackupDeviceSettings(
      values: DeviceSettings(quality: 72),
      availability: {
        BackupSetting.quality: {BackupPlatform.windows},
      },
    );
    final original = fixture(settings: settings);
    final decoded = BackupManifest.decode(
      original.encode(redactor: SecretRedactor()),
    );
    expect(decoded.settings!.values, settings.values);
    expect(decoded.settings!.availability, settings.availability);
    expect(raw()['settings'], isNull);
    final prior = raw()..['formatVersion'] = 1;
    expect(() => BackupManifest.fromJson(prior), throwsA(failure()));
    prior.remove('settings');
    final old = BackupManifest.fromJson(prior);
    expect(old.settings, isNull);
    final upgraded = old.toJson(redactor: SecretRedactor());
    expect(upgraded['formatVersion'], 2);
    expect(upgraded.containsKey('settings'), isTrue);
    expect(upgraded['settings'], isNull);
    final missing = raw()..remove('settings');
    expect(() => BackupManifest.fromJson(missing), throwsA(failure()));
    final invalid = raw()..['settings'] = {'formatVersion': 1};
    expect(() => BackupManifest.fromJson(invalid), throwsA(failure()));
  });

  test('UT-078/081 partial BAK-005: settings structural secret conflicts refuse export without rewriting policies', () {
    final settings = BackupDeviceSettings(values: DeviceSettings(quality: 72));
    final original = fixture(settings: settings);
    for (final secret in ['72', 'wifiAndEthernet', 'windows']) {
      final redactor = SecretRedactor()..register(secret);
      expect(() => original.encode(redactor: redactor), throwsA(failure()));
      expect(original.settings!.values.quality, 72);
      expect(
        original.settings!.availability[BackupSetting.quality],
        BackupPlatform.values.toSet(),
      );
    }
  });

  test('UT-073 partial: full/metadata immutable contract round trips', () {
    for (final mode in BackupMode.values) {
      final original = fixture(mode: mode);
      final decoded = BackupManifest.decode(
        original.encode(redactor: SecretRedactor()),
      );
      expect(decoded.mode, mode);
      expect(decoded.versions.single, version);
      expect(decoded.assets.single.displayName.runes.length, greaterThan(64));
      expect(decoded.assets.single.recycled, isTrue);
      expect(decoded.images.length, mode == BackupMode.full ? 1 : 0);
      expect(decoded.results, hasLength(2));
      expect(
        decoded.origins.single.processing.inputs.single.version,
        historicalVersion,
      );
      expect(
        decoded.versions.map((v) => v.id),
        isNot(contains(historicalVersion.id)),
      );
      expect(() => decoded.assets.clear(), throwsUnsupportedError);
      expect(
        () => decoded.assets.single.tagIds.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => decoded.history.single.attempts.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => decoded.origins.single.processing.inputs.clear(),
        throwsUnsupportedError,
      );
    }
  });

  test('UT-073 partial: actual image format labels remain unchanged with lowercase package suffixes', () {
    for (final format in ['PNG', 'JPEG', 'WebP', 'GIF', 'BMP']) {
      final map = raw();
      map['versions'][0]['format'] = format;
      map['images'][0]['name'] = 'images/${version.id}.${format.toLowerCase()}';
      final manifest = BackupManifest.fromJson(map);
      final restored = BackupManifest.decode(
        manifest.encode(redactor: SecretRedactor()),
      );
      expect(restored.versions.single.format, format);
      expect(
        restored.images.single.name,
        'images/${version.id}.${format.toLowerCase()}',
      );
      map['images'][0]['name'] = 'images/${version.id}.$format';
      expect(() => BackupManifest.fromJson(map), throwsA(failure()));
    }
  });

  test(
    'UT-073 partial: every permanent version has exactly one full image',
    () {
      final missing = raw()..['images'] = [];
      expect(() => BackupManifest.fromJson(missing), throwsA(failure()));
      final duplicate = raw();
      (duplicate['images'] as List).add((duplicate['images'] as List).first);
      expect(() => BackupManifest.fromJson(duplicate), throwsA(failure()));
      final metadataWithImages = raw()..['mode'] = 'metadata';
      expect(
        () => BackupManifest.fromJson(metadataWithImages),
        throwsA(failure()),
      );
      final wrongDigest = raw();
      wrongDigest['images'][0]['sha256'] = 'c' * 64;
      expect(() => BackupManifest.fromJson(wrongDigest), throwsA(failure()));
      final wrongBytes = raw();
      wrongBytes['images'][0]['byteCount'] = 99;
      expect(() => BackupManifest.fromJson(wrongBytes), throwsA(failure()));
    },
  );

  test('UT-074 partial: all ordinary display outlets mask registered K/D', () {
    final redactor = SecretRedactor()
      ..register(key)
      ..register(deletion);
    final json = utf8.decode(fixture().encode(redactor: redactor));
    expect(json, isNot(contains(key)));
    expect(json, isNot(contains(deletion)));
    expect(json, contains(SecretRedactor.hidden));
    final restored = BackupManifest.decode(utf8.encode(json));
    expect(restored.packageId, id(100));
    expect(restored.versions.single.sha256, version.sha256);
    expect(restored.assets.single.tagIds, [id(12)]);
    expect(restored.results.map((r) => r.id), [id(40), id(41)]);
    expect(
      restored.accounts.single.alias,
      '账号 ${SecretRedactor.hidden} ${SecretRedactor.hidden}',
    );
    for (final forbidden in [
      'secretReference',
      'credential',
      'deleteUrl',
      'managementAvailable',
      'deviceCopy',
      'relativePath',
      'path',
      'enabled',
      'health',
      'selectedByDefault',
      'waitReason',
      'retryDelay',
      'currentAttemptId',
      'requestMayHaveStarted',
      'accumulatedRunning',
      'temporaryDirectory',
    ]) {
      expect(json, isNot(contains('"$forbidden"')), reason: forbidden);
    }
  });

  test(
    'UT-074 partial: unknown and secret fields rejected at each boundary',
    () {
      final setters = <void Function(Map<String, dynamic>)>[
        (m) => m['secretReference'] = key,
        (m) => m['versions'][0]['path'] = 'C:\\secret',
        (m) => m['assets'][0]['deviceCopy'] = id(99),
        (m) => m['categories'][0]['key'] = key,
        (m) => m['accounts'][0]['enabled'] = true,
        (m) => m['accounts'][0]['secretReference'] = key,
        (m) =>
            m['origins'][0]['processing']['inputs'][0]['path'] = 'C:\\secret',
        (m) => m['origins'][0]['processing']['crop']['file'] = 'outside',
        (m) => m['results'][0]['managementAvailable'] = true,
        (m) => m['results'][0]['deleteUrl'] = deletion,
        (m) => m['results'][0]['input']['credential'] = key,
        (m) => m['results'][0]['target']['health'] = 'available',
        (m) => m['history'][0]['retryDelay'] = 10,
        (m) => m['history'][0]['attempts'][0]['requestMayHaveStarted'] = true,
        (m) => m['images'][0]['symlink'] = false,
      ];
      for (final set in setters) {
        final map = raw();
        set(map);
        expect(() => BackupManifest.fromJson(map), throwsA(failure()));
      }
    },
  );

  test('UT-074 partial: only ended attempts of three terminal states', () {
    for (final state in PublishState.values) {
      final map = raw();
      map['history'][0]['state'] = state.name;
      if (state.terminal) {
        expect(BackupManifest.fromJson(map).history.single.state, state);
      } else {
        expect(() => BackupManifest.fromJson(map), throwsA(failure()));
      }
    }
    for (final ended in [null, 1699999999999, 1.5]) {
      final map = raw();
      map['history'][0]['attempts'][0]['endedUtc'] = ended;
      expect(() => BackupManifest.fromJson(map), throwsA(failure()));
    }
  });

  test(
    'UT-074 partial: same URL retains independent confirmation identities',
    () {
      final manifest = BackupManifest.fromJson(raw());
      expect(manifest.results, hasLength(2));
      expect(manifest.results[0].directUrl, manifest.results[1].directUrl);
      expect(
        manifest.results[0].attemptId,
        isNot(manifest.results[1].attemptId),
      );
      final duplicateId = raw();
      duplicateId['results'][1]['id'] = id(40);
      expect(() => BackupManifest.fromJson(duplicateId), throwsA(failure()));
      final duplicateAttempt = raw();
      duplicateAttempt['results'][1]['attemptId'] = id(50);
      expect(
        () => BackupManifest.fromJson(duplicateAttempt),
        throwsA(failure()),
      );
    },
  );

  test(
    'UT-075 partial: unsupported envelope fields and damaged JSON fail safely',
    () {
      for (final change in <MapEntry<String, Object>>[
        const MapEntry('format', 'other'),
        const MapEntry('formatVersion', 3),
        const MapEntry('textPolicy', 'unicode-future'),
        const MapEntry('scope', 'selected'),
        const MapEntry('mode', 'future'),
      ]) {
        final map = raw();
        map[change.key] = change.value;
        expect(
          () => BackupManifest.fromJson(map),
          throwsA(failure(BackupFailureKind.unsupportedFormat)),
        );
      }
      expect(() => BackupManifest.decode([0xff]), throwsA(failure()));
      expect(() => BackupManifest.decode(utf8.encode('{')), throwsA(failure()));
      expect(
        () => BackupManifest.fromJson(_NeverStringify()),
        throwsA(failure()),
      );
      final hostile = raw()..['mode'] = _NeverStringify();
      expect(() => BackupManifest.fromJson(hostile), throwsA(failure()));
      expect(
        () => BackupManifest.fromJson({'versions': double.nan}),
        throwsA(failure()),
      );
    },
  );

  test(
    'UT-075 partial: injected manifest/count/image budgets reject overflow',
    () {
      final map = raw();
      expect(
        () => BackupManifest.fromJson(
          map,
          budgets: const BackupBudgets(maxManifestBytes: 10),
        ),
        throwsA(failure(BackupFailureKind.resourceBudget)),
      );
      expect(
        () => BackupManifest.fromJson(
          map,
          budgets: const BackupBudgets(maxRecords: 1),
        ),
        throwsA(failure(BackupFailureKind.resourceBudget)),
      );
      expect(
        () => BackupManifest.fromJson(
          map,
          budgets: const BackupBudgets(maximumTotalImageBytes: 99),
        ),
        throwsA(failure(BackupFailureKind.resourceBudget)),
      );
      expect(
        BackupManifest.fromJson(
          map,
          budgets: const BackupBudgets(maximumTotalImageBytes: 100),
        ).images,
        hasLength(1),
      );
      expect(
        () => fixture().encode(
          redactor: SecretRedactor(),
          budgets: const BackupBudgets(maxManifestBytes: 1),
        ),
        throwsA(failure(BackupFailureKind.resourceBudget)),
      );
      expect(
        () => BackupManifest.decode([
          1,
          2,
        ], budgets: const BackupBudgets(maxManifestBytes: 1)),
        throwsA(failure(BackupFailureKind.resourceBudget)),
      );
      final cyclic = <String, Object?>{};
      cyclic['cycle'] = cyclic;
      expect(() => BackupManifest.fromJson(cyclic), throwsA(failure()));
    },
  );

  test(
    'UT-075 partial: UUID, digest, dimensions, finite integers are strict',
    () {
      for (final value in [
        0,
        -1,
        1.0,
        double.nan,
        double.infinity,
        9007199254740992,
      ]) {
        for (final field in ['byteCount', 'width', 'height', 'frameCount']) {
          final map = raw();
          map['versions'][0][field] = value;
          expect(
            () => BackupManifest.fromJson(map),
            throwsA(failure()),
            reason: '$field numeric boundary',
          );
        }
      }
      for (final value in [0, 9, 1.5]) {
        final map = raw();
        map['versions'][0]['orientation'] = value;
        expect(() => BackupManifest.fromJson(map), throwsA(failure()));
      }
      for (final field in ['packageId', 'createdUtc']) {
        final map = raw();
        map[field] = field == 'packageId' ? '../outside' : 1.5;
        expect(() => BackupManifest.fromJson(map), throwsA(failure()));
      }
      for (final value in [
        '',
        'png',
        'jpeg',
        'WEBP',
        'unknown',
        'a' * 17,
        '../PNG',
      ]) {
        final map = raw();
        map['versions'][0]['format'] = value;
        expect(() => BackupManifest.fromJson(map), throwsA(failure()));
      }
      final badDigest = raw();
      badDigest['versions'][0]['sha256'] = 'z' * 64;
      expect(() => BackupManifest.fromJson(badDigest), throwsA(failure()));
    },
  );

  test('UT-075 partial: exact package image names reject path attacks', () {
    for (final name in [
      '../image.png',
      '/images/${version.id}.png',
      'C:\\images\\${version.id}.png',
      'images\\${version.id}.png',
      'images/../${version.id}.png',
      'images/${version.id}.jpeg',
      'images/${id(99)}.png',
      'images/%2e%2e.png',
      'images/${version.id}.png/',
    ]) {
      final map = raw();
      map['images'][0]['name'] = name;
      expect(
        () => BackupManifest.fromJson(map),
        throwsA(failure()),
        reason: name,
      );
    }
  });

  test('UT-075 partial: asset relations, duplicate identities and version conflicts', () {
    final setters = <void Function(Map<String, dynamic>)>[
      (m) => m['assets'][0]['versionId'] = id(500),
      (m) => m['assets'][0]['categoryId'] = id(500),
      (m) => m['assets'][0]['tagIds'] = [id(500)],
      (m) => m['assets'][0]['tagIds'] = [id(12), id(12)],
      (m) => m['assets'][0]['recycledUtc'] = null,
      (m) => m['origins'][0]['versionId'] = historicalVersion.id,
      (m) => m['versions'].add(m['versions'][0]),
      (m) => m['assets'].add(m['assets'][0]),
      (m) => m['accounts'].add(m['accounts'][0]),
      (m) => m['history'].add(m['history'][0]),
      (m) => m['history'][0]['attempts'].add(m['history'][0]['attempts'][0]),
      (m) => m['results'][0]['input']['version']['width'] = 31,
    ];
    for (final set in setters) {
      final map = raw();
      set(map);
      expect(() => BackupManifest.fromJson(map), throwsA(failure()));
    }
    final sameContent = raw();
    final second = Map<String, dynamic>.from(sameContent['versions'][0] as Map)
      ..['id'] = id(3);
    sameContent['versions'].add(second);
    expect(() => BackupManifest.fromJson(sameContent), throwsA(failure()));
  });

  test(
    'UT-075 partial: TextPolicy canonical names, full folding and 50 tag limit',
    () {
      for (final name in ['', ' spaced ', 'e\u0301', 'x' * 65]) {
        final map = raw();
        map['tags'][0]['name'] = name;
        expect(() => BackupManifest.fromJson(map), throwsA(failure()));
      }
      final folded = raw();
      folded['tags'] = [
        {'id': id(12), 'name': 'ß'},
        {'id': id(13), 'name': 'SS'},
      ];
      expect(() => BackupManifest.fromJson(folded), throwsA(failure()));
      final many = raw();
      many['tags'] = [
        for (var i = 0; i < 51; i++) {'id': id(200 + i), 'name': '标签$i'},
      ];
      many['assets'][0]['tagIds'] = [for (var i = 0; i < 51; i++) id(200 + i)];
      expect(() => BackupManifest.fromJson(many), throwsA(failure()));
      many['assets'][0]['tagIds'] = [for (var i = 0; i < 50; i++) id(200 + i)];
      expect(BackupManifest.fromJson(many).assets.single.tagIds, hasLength(50));
    },
  );

  test(
    'UT-074 partial: redaction never truncates invalid names or merges names',
    () {
      final map = raw();
      map['tags'][0]['name'] = 'x' * 64;
      final manifest = BackupManifest.fromJson(map);
      final redactor = SecretRedactor()..register('x');
      expect(() => manifest.encode(redactor: redactor), throwsA(failure()));
      final collision = raw();
      collision['tags'] = [
        {'id': id(12), 'name': key},
        {'id': id(13), 'name': deletion},
      ];
      final original = BackupManifest.fromJson(collision);
      final both = SecretRedactor()
        ..register(key)
        ..register(deletion);
      expect(() => original.encode(redactor: both), throwsA(failure()));
    },
  );

  test('UT-074 partial: structural secret matches refuse encoding without rewriting identity', () {
    final manifest = fixture();
    for (final secret in [
      version.sha256,
      version.id,
      manifest.packageId,
      ProcessingOperation.crop.name,
      StitchLayout.grid.name,
      version.byteCount.toString(),
      manifest.createdUtc.toString(),
    ]) {
      final redactor = SecretRedactor()..register(secret);
      expect(() => manifest.encode(redactor: redactor), throwsA(failure()));
      expect(() => manifest.toJson(redactor: redactor), throwsA(failure()));
      expect(manifest.versions.single.id, version.id);
      expect(manifest.versions.single.sha256, version.sha256);
      expect(manifest.packageId, id(100));
    }
  });

  test('UT-074 partial: valid large whitelist is not truncated at redactor node limit', () {
    final map = raw();
    map['accounts'] = [
      for (var i = 0; i < 2500; i++)
        {
          'id': id(10000 + i),
          'service': 'imgbb',
          'alias': '普通账号 $key $deletion',
          'anonymous': false,
        },
    ];
    final manifest = BackupManifest.fromJson(map);
    final redactor = SecretRedactor()
      ..register(key)
      ..register(deletion);
    final bytes = manifest.encode(redactor: redactor);
    final decoded = BackupManifest.decode(bytes);
    expect(decoded.accounts, hasLength(2500));
    expect(decoded.accounts.last.id, id(12499));
    expect(utf8.decode(bytes), isNot(contains(key)));
    expect(utf8.decode(bytes), isNot(contains(deletion)));
    expect(utf8.decode(bytes), isNot(contains(SecretRedactor.unavailable)));
  });

  test(
    'UT-074 partial: ordinary URLs cannot carry management/registered secrets',
    () {
      for (final url in [
        'file:///outside',
        'https://user:pass@example.org/a',
        'https://example.org/a?token=hidden',
        'https://ibb.co/a/delete',
        'https://example.org/a#fragment',
      ]) {
        final map = raw();
        map['results'][0]['directUrl'] = url;
        expect(() => BackupManifest.fromJson(map), throwsA(failure()));
      }
      final map = raw();
      map['results'][0]['directUrl'] = 'https://example.org/$key.png';
      final manifest = BackupManifest.fromJson(map);
      expect(
        () => manifest.encode(redactor: SecretRedactor()..register(key)),
        throwsA(failure()),
      );
    },
  );

  test('UT-081 partial: processing and accounts contain no device resources/runtime', () {
    final request = ProcessingRequest(
      operation: ProcessingOperation.crop,
      inputs: [
        ProcessingInput(
          file: File('C:\\external\\private.png'),
          assetId: id(10),
          version: version,
        ),
      ],
      crop: const PixelCrop(0, 0, 2, 2),
    );
    final snapshot = BackupProcessingSnapshot.fromRequest(request);
    final json = snapshot.toJson();
    expect(jsonEncode(json), isNot(contains('private.png')));
    expect(jsonEncode(json), isNot(contains('path')));
    final restored = BackupProcessingSnapshot.fromJson(json);
    expect(restored.inputs.single.assetId, id(10));
    expect(restored.inputs.single.version, version);
    (json['inputs'] as List).first['path'] = '/outside';
    expect(() => BackupProcessingSnapshot.fromJson(json), throwsA(failure()));
    final map = raw();
    expect((map['accounts'][0] as Map).keys.toSet(), {
      'id',
      'service',
      'alias',
      'anonymous',
    });
    expect((map['assets'][0] as Map).keys, isNot(contains('relativePath')));
    expect(
      (map['results'][0]['input'] as Map).keys,
      isNot(contains('deviceCopy')),
    );
  });
}

final class _NeverStringify {
  @override
  String toString() =>
      throw StateError('Unknown input must not be stringified');
}
