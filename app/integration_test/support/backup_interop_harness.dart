import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_store.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/application/backup_coordinator.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

typedef InteropCapacity = Future<int> Function(Directory);
typedef InteropPublication = Future<bool> Function(File, File);

void interopRequire(bool condition, String code) {
  if (!condition) {
    throw StateError('Backup interoperability check failed: $code');
  }
}

Future<String> interopSha(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

const interopExportPrefix = 'IMAGEHUB_BACKUP_EXPORTED_FIXTURE:';
const _interopPlatforms = {'windows', 'macos', 'android', 'ios'};
const _smallPackageLimit = 1024 * 1024;

Map<String, Object?> _fields(Object? value, Set<String> fields) {
  interopRequire(
    value is Map &&
        value.length == fields.length &&
        value.keys.every(fields.contains),
    'payload-fields',
  );
  return Map<String, Object?>.from(value as Map);
}

void validateInteropExpectation(Map<String, Object?> expectation) {
  final top = _fields(expectation, {
    'fixtureVersion',
    'originPlatform',
    'packages',
  });
  interopRequire(
    top['fixtureVersion'] == 1 &&
        _interopPlatforms.contains(top['originPlatform']),
    'fixture-version-origin',
  );
  final packages = _fields(top['packages'], {'full', 'metadata'});
  for (final mode in ['full', 'metadata']) {
    final row = _fields(packages[mode], {
      'fileName',
      'byteCount',
      'sha256',
      'manifest',
    });
    interopRequire(
      row['fileName'] is String &&
          (row['fileName'] == '$mode.zip' ||
              (RegExp(r'^ImageHub-(full|metadata)-[0-9a-f-]{36}\.zip$')
                      .hasMatch(row['fileName'] as String) &&
                  (row['fileName'] as String).startsWith('ImageHub-$mode-'))) &&
          row['byteCount'] is int &&
          (row['byteCount'] as int) > 0 &&
          (row['byteCount'] as int) < _smallPackageLimit &&
          row['sha256'] is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(row['sha256'] as String),
      'package-fields',
    );
    interopRequire(
      row['manifest'] is Map && (row['manifest'] as Map)['formatVersion'] == 2,
      'fixture-manifest-version',
    );
    final manifest = BackupManifest.fromJson(row['manifest']);
    interopRequire(
      manifest.mode.name == mode &&
          manifest.versions.length == 5 &&
          manifest.assets.length == 4 &&
          manifest.categories.length == 1 &&
          manifest.categories.single.name == '互读分类 é 中文' &&
          manifest.tags.length == 2 &&
          manifest.tags.map((t) => t.name).toSet().containsAll({
            '标签 Σ',
            '海边 é',
          }) &&
          manifest.accounts.length == 1 &&
          manifest.accounts.single.alias == '互读合成账号' &&
          manifest.accounts.single.service == ImageHostService.imgbb &&
          !manifest.accounts.single.anonymous &&
          manifest.origins.isEmpty &&
          manifest.results.isEmpty &&
          manifest.history.isEmpty &&
          manifest.settings != null,
      'synthetic-fixture-shape',
    );
    final versions = manifest.versions.toList()
      ..sort((a, b) => a.width.compareTo(b.width));
    for (var index = 0; index < 5; index++) {
      final version = versions[index];
      final format = ['PNG', 'JPEG', 'GIF', 'BMP', 'PNG'][index];
      interopRequire(
        version.width == 13 + index &&
            version.height == 9 &&
            version.frameCount == 1 &&
            version.orientation == 1 &&
            version.format == format,
        'synthetic-version-shape',
      );
      if (index < 4) {
        final assets = manifest.assets
            .where((a) => a.versionId == version.id)
            .toList();
        interopRequire(assets.length == 1, 'synthetic-asset-identity');
        final asset = assets.single;
        interopRequire(
          asset.displayName == '互读-$index.${format.toLowerCase()}' &&
              asset.sourceType == 'file' &&
              asset.favorite == index.isEven &&
              asset.recycled == (index == 3) &&
              asset.categoryId == manifest.categories.single.id &&
              asset.tagIds.length == 2 &&
              asset.tagIds.toSet().containsAll(manifest.tags.map((t) => t.id)),
          'synthetic-asset-shape',
        );
      }
    }
  }
}

final class BackupInteropPayload {
  BackupInteropPayload._(this.expectation, this.bytes, this.encoded);
  final Map<String, Object?> expectation;
  final Map<String, Uint8List> bytes;
  final String encoded;
  String get originPlatform => expectation['originPlatform'] as String;

  static BackupInteropPayload decode(String encoded) {
    try {
      return _decode(encoded);
    } catch (_) {
      throw StateError('Backup interoperability check failed: invalid-payload');
    }
  }

  static BackupInteropPayload _decode(String encoded) {
    interopRequire(
      encoded.isNotEmpty &&
          encoded.length <= 6 * 1024 * 1024 &&
          RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(encoded),
      'bounded-base64-envelope',
    );
    final raw = base64Decode(encoded);
    interopRequire(
      raw.length <= 4 * 1024 * 1024 && base64Encode(raw) == encoded,
      'canonical-envelope',
    );
    final envelope = _fields(jsonDecode(utf8.decode(raw)), {
      'fixtureVersion',
      'expectation',
      'bytes',
    });
    interopRequire(envelope['fixtureVersion'] == 1, 'envelope-version');
    final expectation = Map<String, Object?>.from(
      envelope['expectation'] as Map,
    );
    validateInteropExpectation(expectation);
    final values = _fields(envelope['bytes'], {'full', 'metadata'});
    final packages = expectation['packages'] as Map;
    final bytes = <String, Uint8List>{};
    for (final mode in ['full', 'metadata']) {
      final value = values[mode];
      interopRequire(
        value is String && value.length < 2 * _smallPackageLimit,
        'bounded-package-base64',
      );
      final decoded = base64Decode(value as String);
      final row = packages[mode] as Map;
      interopRequire(
        decoded.length < _smallPackageLimit &&
            decoded.length == row['byteCount'] &&
            base64Encode(decoded) == value &&
            sha256.convert(decoded).toString() == row['sha256'],
        'package-digest',
      );
      bytes[mode] = decoded;
    }
    return BackupInteropPayload._(
      expectation,
      Map.unmodifiable(bytes),
      encoded,
    );
  }
}

Future<String> encodeInteropPayload(
  Map<String, Object?> expectation,
  Directory exports,
) async {
  validateInteropExpectation(expectation);
  final packages = expectation['packages'] as Map;
  final bytes = <String, String>{};
  for (final mode in ['full', 'metadata']) {
    final row = packages[mode] as Map;
    final file = File(p.join(exports.path, row['fileName'] as String));
    interopRequire(
      await FileSystemEntity.type(file.path, followLinks: false) ==
              FileSystemEntityType.file &&
          await file.length() == row['byteCount'] &&
          await file.length() < _smallPackageLimit,
      'closed-small-package',
    );
    final value = await file.readAsBytes();
    interopRequire(
      sha256.convert(value).toString() == row['sha256'],
      'export-package-digest',
    );
    bytes[mode] = base64Encode(value);
  }
  final encoded = base64Encode(
    utf8.encode(
      jsonEncode({
        'fixtureVersion': 1,
        'expectation': expectation,
        'bytes': bytes,
      }),
    ),
  );
  return BackupInteropPayload.decode(encoded).encoded;
}

List<BackupInteropPayload> validateInteropMatrix(List<String> encoded) {
  interopRequire(
    encoded.isNotEmpty && encoded.length <= 4,
    'matrix-platform-count',
  );
  final payloads = encoded.map(BackupInteropPayload.decode).toList();
  interopRequire(
    payloads.map((p) => p.originPlatform).toSet().length == payloads.length,
    'matrix-duplicate-origin',
  );
  return payloads;
}

BackupInteropPayload captureInteropPayload(Iterable<String> lines) {
  final payloads = <String>[];
  for (final line in lines) {
    final index = line.indexOf(interopExportPrefix);
    if (index < 0) continue;
    interopRequire(
      line.indexOf(interopExportPrefix, index + interopExportPrefix.length) < 0,
      'capture-multiple-prefixes',
    );
    payloads.add(line.substring(index + interopExportPrefix.length).trim());
    interopRequire(payloads.length == 1, 'capture-multiple-payloads');
  }
  interopRequire(payloads.length == 1, 'capture-one-payload-required');
  return BackupInteropPayload.decode(payloads.single);
}

/// Records only known, closed test files. Whole-tree comparison refuses unknown
/// files, substitutions and links; failures keep the scene for inspection.
final class InteropOwnedScene {
  InteropOwnedScene._(this.directory, this.parent, this.token);
  final Directory directory, parent;
  final String token;
  final _directories = <String>{};
  final _files = <String, ({int bytes, String sha})>{};
  static Future<InteropOwnedScene> create(Directory selectedParent) async {
    final parent = Directory(await selectedParent.resolveSymbolicLinks());
    final directory = await parent.createTemp('imagehub-backup-interop-');
    final token = const Uuid().v4();
    final scene = InteropOwnedScene._(directory, parent, token);
    final marker = File(p.join(directory.path, '.interop-owner'));
    await marker.create(exclusive: true);
    await marker.writeAsString(token, flush: true);
    await scene.recordFile(marker);
    return scene;
  }

  String _key(String path) {
    final absolute = p.normalize(p.absolute(path));
    interopRequire(p.isWithin(directory.path, absolute), 'scene-containment');
    return p.relative(absolute, from: directory.path);
  }

  Future<void> recordDirectory(Directory value) async {
    interopRequire(
      await FileSystemEntity.type(value.path, followLinks: false) ==
              FileSystemEntityType.directory &&
          p.equals(await value.resolveSymbolicLinks(), value.absolute.path),
      'scene-directory',
    );
    _directories.add(_key(value.path));
  }

  Future<void> recordFile(File value) async {
    interopRequire(
      await FileSystemEntity.type(value.path, followLinks: false) ==
          FileSystemEntityType.file,
      'scene-ordinary-file',
    );
    _files[_key(value.path)] = (
      bytes: await value.length(),
      sha: await interopSha(value),
    );
  }

  Future<void> recordClosedLibrary(
    Directory root,
    Iterable<File> permanentFiles,
  ) async {
    await recordDirectory(root);
    for (final suffix in [
      'originals',
      'staging',
      'cache',
      'cache/thumbnails',
      'cache/outputs',
    ]) {
      await recordDirectory(Directory(p.join(root.path, suffix)));
    }
    for (final file in permanentFiles) {
      await recordFile(file);
    }
    for (final suffix in [
      '.library.lock',
      'library.sqlite',
      'library.sqlite-wal',
      'library.sqlite-shm',
    ]) {
      final file = File(p.join(root.path, suffix));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await recordFile(file);
      }
    }
  }

  Future<void> removeAfterSuccess() async {
    final marker = File(p.join(directory.path, '.interop-owner'));
    interopRequire(
      await FileSystemEntity.type(directory.path, followLinks: false) ==
              FileSystemEntityType.directory &&
          await FileSystemEntity.type(marker.path, followLinks: false) ==
              FileSystemEntityType.file &&
          p.dirname(directory.path) == parent.path &&
          p.equals(await directory.resolveSymbolicLinks(), directory.path) &&
          await marker.readAsString() == token,
      'scene-owner',
    );
    final directories = <String>{}, files = <String>{};
    await for (final value in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      final key = _key(value.path);
      final type = await FileSystemEntity.type(value.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        interopRequire(
          _directories.contains(key) &&
              p.equals(
                await Directory(value.path).resolveSymbolicLinks(),
                value.path,
              ),
          'scene-unknown-directory',
        );
        directories.add(key);
      } else {
        interopRequire(
          type == FileSystemEntityType.file && _files.containsKey(key),
          'scene-unknown-file',
        );
        final file = File(value.path);
        final record = _files[key]!;
        interopRequire(
          await file.length() == record.bytes &&
              await interopSha(file) == record.sha,
          'scene-changed-file',
        );
        files.add(key);
      }
    }
    interopRequire(
      directories.length == _directories.length &&
          files.length == _files.length,
      'scene-missing-item',
    );
    await directory.delete(recursive: true);
  }
}

/// Test-only synthetic credentials; never an operating-system storage substitute.
final class InteropSecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<void> write(String reference, String value) async {
    values[reference] = value;
  }

  @override
  Future<String?> read(String reference) async => values[reference];
  @override
  Future<void> delete(String reference) async {
    values.remove(reference);
  }
}

/// All roots belong to the caller's newly allocated verification workspace.
final class BackupInteropHarness {
  const BackupInteropHarness({
    required this.availableBytes,
    required this.publishExclusive,
  });
  final InteropCapacity availableBytes;
  final InteropPublication publishExclusive;

  Future<LibraryRepository> open(Directory root, {SecretStore? secrets}) =>
      LibraryRepository.open(
        root,
        secretStore: secrets,
        availableStorageBytes: availableBytes,
        publishCacheExclusive: publishExclusive,
      );

  Future<Map<String, Object?>> exportFixtures(
    Directory workspace, {
    InteropOwnedScene? scene,
  }) async {
    final secrets = InteropSecrets();
    final sourceRoot = Directory(p.join(workspace.path, 'source'));
    final permanentFiles = <String, File>{};
    final repository = await open(sourceRoot, secrets: secrets);
    try {
      final category = await repository.createCategory('互读分类 é 中文');
      final ids = <String>[];
      for (var index = 0; index < 5; index++) {
        final image = img.Image(width: 13 + index, height: 9, numChannels: 3);
        img.fill(image, color: img.ColorRgb8(20 + index * 30, 90, 160));
        final format = ['PNG', 'JPEG', 'GIF', 'BMP', 'PNG'][index];
        final bytes = switch (format) {
          'JPEG' => img.encodeJpg(image, quality: 91),
          'GIF' => img.encodeGif(image),
          'BMP' => img.encodeBmp(image),
          _ => img.encodePng(image),
        };
        final imported = await repository.importResource(
          PlatformResource(
            displayName: '互读-$index.${format.toLowerCase()}',
            openRead: () => Stream.value(bytes),
          ),
        );
        interopRequire(imported.status == ImportStatus.saved, 'fixture-import');
        ids.add(imported.asset!.id);
        await repository.updateOrganization(
          [imported.asset!.id],
          setCategory: true,
          categoryId: category.id,
          replaceTags: ['标签 Σ', '海边 é'],
          favorite: index.isEven,
        );
      }
      await repository.removeAssets([ids[3], ids[4]]);
      await repository.purgeAssets([ids[4]], confirmRecords: true);
      await repository.saveTarget(
        service: ImageHostService.imgbb,
        alias: '互读合成账号',
        anonymous: false,
        credential: 'interop-synthetic-key-0123456789',
        persistence: CredentialPersistence.session,
      );
      await repository.saveSettings(
        await repository.loadSettings(),
        DeviceSettings(
          uploadConcurrency: 5,
          processingConcurrency: 2,
          quality: 73,
          longestSide: 2300,
          processingMode: ProcessingMode.sizeFirst,
          cacheLimitMiB: 384,
          defaultOutputRetention: OutputRetention.week,
          networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
        ),
        defaultTargetIds: const [],
      );
      final exports = await Directory(p.join(workspace.path, 'exports'))
          .create();
      final packages = <String, Object?>{};
      for (final mode in BackupMode.values) {
        Map<String, Object?>? expected;
        final report = await BackupCoordinator(
          capture: (mode, token, progress) async {
            final snapshot = await repository.captureBackupSnapshot(
              mode: mode,
              cancellation: token,
              onVerification: progress,
            );
            expected = Map<String, Object?>.from(
              jsonDecode(utf8.decode(snapshot.manifestBytes)) as Map,
            );
            permanentFiles.addAll(snapshot.permanentFiles);
            return snapshot;
          },
          availableBytes: availableBytes,
          publishExclusive: publishExclusive,
        ).export(exports, mode);
        interopRequire(!report.cleanupPending, 'export-cleanup');
        packages[mode.name] = {
          'fileName': p.basename(report.file.path),
          'byteCount': await report.file.length(),
          'sha256': await interopSha(report.file),
          'manifest': expected,
        };
        if (scene != null) {
          await scene.recordFile(report.file);
        }
      }
      if (scene != null) {
        await scene.recordDirectory(exports);
      }
      return {
        'fixtureVersion': 1,
        'originPlatform': Platform.operatingSystem,
        'packages': packages,
      };
    } finally {
      await repository.close();
      secrets.values.clear();
      if (scene != null) {
        await scene.recordClosedLibrary(sourceRoot, permanentFiles.values);
      }
    }
  }

  /// Reads the exact exported file, never regenerates its source data locally.
  Future<Map<String, Object?>> verifyPackage(
    File package,
    Map<String, Object?> expectation,
    Directory workspace, {
    required String originPlatform,
    InteropOwnedScene? scene,
  }) async {
    interopRequire(
      {'windows', 'macos', 'android', 'ios'}.contains(originPlatform),
      'origin-platform',
    );
    interopRequire(
      await package.length() == expectation['byteCount'] &&
          await interopSha(package) == expectation['sha256'],
      'transport-bytes',
    );
    final expected = BackupManifest.fromJson(expectation['manifest']);
    final stage = await Directory(p.join(workspace.path, 'preflight')).create();
    final validated = await const BackupZipReader().preflight(
      package,
      stage,
      availableBytes: availableBytes,
    );
    LibraryRepository? repository;
    var verified = false;
    final root = Directory(p.join(workspace.path, 'restored'));
    final permanentFiles = <File>[];
    try {
      interopRequire(
        jsonEncode(validated.manifest.toJson(redactor: SecretRedactor())) ==
            jsonEncode(expected.toJson(redactor: SecretRedactor())),
        'portable-manifest',
      );
      final secrets = InteropSecrets();
      repository = await open(root, secrets: secrets);
      final settingsPlan = repository.planBackupSettings(expected.settings);
      final hold = await repository.acquireRestoreHold();
      try {
        final prepared = await repository.prepareMergeRestore(
          hold: hold,
          backup: validated,
        );
        interopRequire(prepared.plan.canCommit, 'restore-plan');
        final report = await repository.commitMergeRestore(
          preparation: prepared,
          availableBytes: availableBytes,
          publishExclusive: publishExclusive,
        );
        interopRequire(
          !report.cleanupPending &&
              report.addedAssets == expected.assets.length &&
              report.savedCopies ==
                  (expected.mode == BackupMode.full
                      ? expected.versions.length
                      : 0),
          'restore-commit',
        );
        interopRequire(
          report.settings!.restored.length == settingsPlan.restored.length &&
              report.settings!.skipped.length == settingsPlan.skipped.length,
          'settings-report',
        );
      } finally {
        await hold.release();
      }
      await repository.close();
      repository = null;
      repository = await open(root, secrets: secrets);
      interopRequire(
        (await repository.loadSettings()).values == settingsPlan.values,
        'reopened-settings',
      );
      for (final asset in expected.assets) {
        final actual = await repository.getAsset(
          asset.id,
          includeRecycled: true,
        );
        interopRequire(
          actual != null &&
              actual.version ==
                  expected.versions.singleWhere(
                    (v) => v.id == asset.versionId,
                  ) &&
              actual.displayName == asset.displayName &&
              actual.favorite == asset.favorite &&
              actual.categoryId == asset.categoryId &&
              actual.recycled == asset.recycled &&
              actual.importedAt.millisecondsSinceEpoch == asset.importedUtc &&
              actual.updatedAt.millisecondsSinceEpoch == asset.updatedUtc &&
              actual.recycledAt?.millisecondsSinceEpoch == asset.recycledUtc &&
              actual.sourceType == asset.sourceType &&
              jsonEncode(actual.tags.map((t) => t.id).toList()) ==
                  jsonEncode(asset.tagIds),
          'reopened-asset',
        );
        interopRequire(
          !p.isAbsolute(actual!.deviceCopy.relativePath) &&
              actual.deviceCopy.relativePath.startsWith('originals/'),
          'local-copy-position',
        );
      }
      final captured = await repository.captureBackupSnapshot(
        mode: expected.mode,
      );
      try {
        permanentFiles.addAll(captured.permanentFiles.values);
        interopRequire(
          captured.manifest.versions.length == expected.versions.length &&
              captured.manifest.categories.length ==
                  expected.categories.length &&
              captured.manifest.tags.length == expected.tags.length,
          'reopened-graph',
        );
        for (final name in expected.categories) {
          interopRequire(
            captured.manifest.categories.any(
              (n) => n.id == name.id && n.name == name.name,
            ),
            'category',
          );
        }
        for (final name in expected.tags) {
          interopRequire(
            captured.manifest.tags.any(
              (n) => n.id == name.id && n.name == name.name,
            ),
            'tag',
          );
        }
        for (final version in expected.versions) {
          interopRequire(
            captured.manifest.versions.contains(version),
            'permanent-version',
          );
          if (expected.mode == BackupMode.full) {
            final file = captured.permanentFiles[version.id]!;
            interopRequire(
              await file.length() == version.byteCount &&
                  await interopSha(file) == version.sha256,
              'permanent-bytes',
            );
          }
        }
      } finally {
        await captured.release();
      }
      if (expected.mode == BackupMode.metadata) {
        interopRequire(
          (await Directory(
            p.join(root.path, 'originals'),
          ).list().toList()).isEmpty,
          'metadata-missing-bytes',
        );
        for (final asset in expected.assets) {
          interopRequire(
            await repository.verifyCopy(
                  (await repository.getAsset(asset.id, includeRecycled: true))!,
                ) ==
                CopyAvailability.missing,
            'metadata-copy-state',
          );
        }
      }
      final targets = await repository.listTargets();
      for (final account in expected.accounts) {
        interopRequire(
          targets.any(
            (t) =>
                t.id == account.id &&
                t.alias == account.alias &&
                t.service == account.service &&
                t.anonymous == account.anonymous,
          ),
          'account-identity',
        );
      }
      interopRequire(
        targets.length == expected.accounts.length &&
            targets.every(
              (t) => !t.enabled && t.health == AccountHealth.unconfigured,
            ) &&
            secrets.values.isEmpty &&
            (await repository.listUploadBatches()).isEmpty,
        'no-secret-or-execution',
      );
      verified = true;
      return {
        'originPlatform': originPlatform,
        'consumerPlatform': Platform.operatingSystem,
        'mode': expected.mode.name,
        'sha256': expectation['sha256'],
        'byteCount': expectation['byteCount'],
        'assets': expected.assets.length,
        'versions': expected.versions.length,
        'restoredSettings': settingsPlan.restored.map((s) => s.name).toList(),
        'skippedSettings': settingsPlan.skipped.map((s) => s.name).toList(),
        'closedAndReopened': true,
      };
    } finally {
      await repository?.close();
      if (verified) {
        await validated.dispose();
        if (scene != null) {
          await scene.recordClosedLibrary(root, permanentFiles);
          await scene.recordDirectory(stage);
        }
      }
    }
  }
}
