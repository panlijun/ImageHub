import 'dart:async';
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
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'upload_repository_test.dart' show QueueTestSecrets;

class ReplacementTestSecrets extends QueueTestSecrets {
  bool failDeletes = false;
  @override
  Future<void> delete(String reference) async {
    if (failDeletes) throw const SecretStorageException();
    await super.delete(reference);
  }
}

void main() {
  late Directory sandbox, root;
  late LibraryRepository source, destination;
  late ReplacementTestSecrets secrets;
  late ImageAsset oldAsset, incoming;
  final backups = <ValidatedBackup>[];
  var packageNumber = 0;

  Future<ImageAsset> image(LibraryRepository repository, int marker) async {
    final pixels = img.Image(width: 8 + marker, height: 6);
    img.fill(pixels, color: img.ColorRgb8(marker, 90, 110));
    final bytes = img.encodePng(pixels);
    final result = await repository.importResource(
      PlatformResource(
        displayName: '独立图-$marker.png',
        openRead: () => Stream.value(bytes),
      ),
    );
    expect(result.status, ImportStatus.saved);
    return result.asset!;
  }

  List<Map<String, Object?>> rows(String table) {
    final db = sqlite3.open(
      '${root.path}/library.sqlite',
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

  Map<String, List<Map<String, Object?>>> state() {
    final db = sqlite3.open(
      '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    late List<String> tables;
    try {
      tables = db
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name!='restore_operations'",
          )
          .map((r) => r['name'] as String)
          .toList();
    } finally {
      db.close();
    }
    return {for (final table in tables) table: rows(table)};
  }

  Future<Map<String, String>> bytes() async {
    final result = <String, String>{};
    await for (final file in Directory('${root.path}/originals').list()) {
      if (file is File) {
        result[file.path] = sha256.convert(await file.readAsBytes()).toString();
      }
    }
    return result;
  }

  Future<ValidatedBackup> package({BackupMode mode = BackupMode.full}) async {
    final snapshot = await source.captureBackupSnapshot(mode: mode);
    final archive = File('${sandbox.path}/package-${packageNumber++}.zip');
    try {
      await BackupZipWriter().write(snapshot, archive);
    } finally {
      await snapshot.release();
    }
    final backup = await const BackupZipReader().preflight(
      archive,
      await Directory('${sandbox.path}/preflight').create(),
      availableBytes: (_) async => 1 << 40,
    );
    backups.add(backup);
    return backup;
  }

  // Deterministic test transport. Native no-replace publication is separately IT-005.
  Future<bool> publish(File stage, File target) async {
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    await stage.rename(target.path);
    return true;
  }

  Future<MergeRestoreReport> replace(
    ValidatedBackup backup, {
    RestoreFaultHook? faultHook,
    CancellationToken? cancellation,
    Future<bool> Function(File, File)? publisher,
    Future<int> Function(Directory)? capacity,
  }) async {
    final hold = await destination.acquireRestoreHold();
    ReplacementRestorePreparation? preparation;
    try {
      preparation = await destination.prepareReplacementRestore(
        hold: hold,
        backup: backup,
        availableBytes: (_) async => 1 << 40,
      );
      return await destination.commitReplacementRestore(
        preparation: preparation,
        availableBytes: capacity ?? (_) async => 1 << 40,
        publishExclusive: publisher ?? publish,
        cancellation: cancellation,
        faultHook: faultHook,
      );
    } finally {
      if (preparation != null) {
        try {
          await destination.discardReplacementPreparation(preparation);
        } catch (_) {
          /* Pending recovery evidence must remain. */
        }
      }
      await hold.release();
    }
  }

  Future<void> reopen() async {
    await destination.close();
    destination = await LibraryRepository.open(root, secretStore: secrets);
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-real-replace-');
    root = Directory('${sandbox.path}/current');
    secrets = ReplacementTestSecrets();
    source = await LibraryRepository.open(
      Directory('${sandbox.path}/incoming'),
    );
    destination = await LibraryRepository.open(root, secretStore: secrets);
    incoming = await image(source, 1);
    oldAsset = await image(destination, 2);
    await destination.updateOrganization(
      [oldAsset.id],
      favorite: true,
      replaceTags: ['原标签'],
    );
    final account = await destination.saveTarget(
      service: ImageHostService.imgbb,
      alias: '原账号',
      anonymous: false,
      credential: 'synthetic-old-replacement-key-0123456789',
      persistence: CredentialPersistence.protected,
    );
    await destination.enqueueUploads(
      intentId: const Uuid().v4(),
      assetIds: [oldAsset.id],
      targetIds: [account],
      allowOriginalMetadata: true,
    );
    // Holding/releasing pauses durable work; capture the expected paused state.
    final hold = await destination.acquireRestoreHold();
    await hold.release();
    backups.clear();
  });

  tearDown(() async {
    for (final backup in backups) {
      await backup.dispose();
    }
    await source.close();
    await destination.close();
    await sandbox.delete(recursive: true);
  });

  test('UT-073/083 actual replacement restores portable device policy and invalidates old settings snapshot', () async {
    final local = DeviceSettings(uploadConcurrency: 2, quality: 61);
    final incomingPolicy = DeviceSettings(uploadConcurrency: 7, quality: 39);
    await destination.saveSettings(
      await destination.loadSettings(),
      local,
      defaultTargetIds: [],
    );
    await source.saveSettings(
      await source.loadSettings(),
      incomingPolicy,
      defaultTargetIds: [],
    );
    final oldPlan = await destination.loadSettings();
    final diagnostic = DiagnosticEvent(
      id: const Uuid().v4(),
      occurredAt: DateTime.now().toUtc(),
      kind: DiagnosticKind.system,
      level: DiagnosticLevel.info,
      code: 'fixture.local',
      summary: '本机诊断须独立保留。',
      recoveryAction: '请核查本机诊断。',
    );
    await destination.recordDiagnostic(diagnostic);
    final oldDiagnosticPlan = await destination.prepareDiagnosticSelection(
      query: DiagnosticQuery(kind: DiagnosticKind.system),
    );
    final localDiagnosticRows = rows('diagnostic_records');
    final backup = await package();
    await expectLater(
      replace(
        backup,
        faultHook: (boundary) async {
          if (boundary == RestoreBoundary.published) {
            throw StateError('fixture');
          }
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect((await destination.loadSettings()).values, local);
    await replace(backup);
    expect((await destination.loadSettings()).values, incomingPolicy);
    expect(rows('diagnostic_records'), localDiagnosticRows);
    expect(
      (await destination.loadDiagnostics(
        query: DiagnosticQuery(kind: DiagnosticKind.system),
      )).items.single.toJson(),
      diagnostic.toJson(),
    );
    await expectLater(
      destination.diagnosticExport(oldDiagnosticPlan),
      throwsA(isA<DiagnosticFailure>()),
    );
    await expectLater(
      destination.clearDiagnostics(oldDiagnosticPlan),
      throwsA(isA<DiagnosticFailure>()),
    );
    expect(rows('diagnostic_records'), localDiagnosticRows);
    await expectLater(
      destination.saveSettings(
        oldPlan,
        DeviceSettings.defaults,
        defaultTargetIds: [],
      ),
      throwsA(isA<SettingsFailure>()),
    );
    final diagnosticsAfterRejectedSave = rows('diagnostic_records');
    expect(diagnosticsAfterRejectedSave.length, localDiagnosticRows.length + 1);
    final originalIds = localDiagnosticRows.map((row) => row['id']).toSet();
    expect(
      diagnosticsAfterRejectedSave
          .where((row) => originalIds.contains(row['id']))
          .toList(),
      localDiagnosticRows,
    );
    expect(
      diagnosticsAfterRejectedSave.singleWhere(
        (row) => !originalIds.contains(row['id']),
      )['code'],
      'settings.save.failed',
    );
    await reopen();
    expect(destination.currentDeviceSettings, incomingPolicy);
    expect((await destination.loadSettings()).values, incomingPolicy);
    expect(rows('diagnostic_records'), diagnosticsAfterRejectedSave);
  });

  test('UT-073/075 partial replacement preserves distinct asset identities sharing one content version', () async {
    final duplicateId = const Uuid().v4();
    final db = sqlite3.open('${sandbox.path}/incoming/library.sqlite');
    try {
      final columns = db
          .select('PRAGMA table_info(assets)')
          .map((r) => r['name'] as String)
          .toList();
      final names = columns.map((c) => '"$c"').join(',');
      final expressions = columns
          .map((c) => c == 'id' ? '?' : '"$c"')
          .join(',');
      db.execute(
        'INSERT INTO assets ($names) SELECT $expressions FROM assets WHERE id=?',
        [duplicateId, incoming.id],
      );
    } finally {
      db.close();
    }
    final backup = await package();
    expect(backup.manifest.assets, hasLength(2));
    expect(backup.manifest.versions, hasLength(1));
    final report = await replace(backup);
    expect(report.addedAssets, 2);
    expect(report.savedCopies, 1);
    expect((await destination.listAssets()).total, 2);
    expect(
      (await destination.getAsset(duplicateId))!.version.id,
      incoming.version.id,
    );
    expect(
      (await destination.getAsset(incoming.id))!.version.id,
      incoming.version.id,
    );
    await reopen();
    expect((await destination.listAssets()).total, 2);
  });

  for (final boundary in RestoreBoundary.values.where(
    (b) => b != RestoreBoundary.committed,
  )) {
    for (final cancel in [false, true]) {
      test(
        'UT-073/075 IT-005 partial replacement ${boundary.name} ${cancel ? "cancel" : "fault"} preserves SQL bytes secrets and epoch',
        () async {
          final backup = await package();
          final before = state(), originals = await bytes();
          final protected = Map<String, String>.from(secrets.values);
          final epoch = destination.executionEpoch;
          final token = CancellationToken();
          await expectLater(
            replace(
              backup,
              cancellation: token,
              faultHook: (actual) async {
                if (actual != boundary) return;
                if (cancel) {
                  token.cancel();
                } else {
                  throw StateError('injected');
                }
              },
            ),
            throwsA(isA<BackupSnapshotFailure>()),
          );
          expect(state(), before);
          expect(await bytes(), originals);
          expect(secrets.values, protected);
          expect(destination.executionEpoch, epoch);
          expect(rows('restore_operations'), isEmpty);
          await reopen();
          expect(state(), before);
          expect(await bytes(), originals);
          expect((await destination.getAsset(oldAsset.id))!.favorite, true);
          expect(rows('upload_batches').single['paused'], 1);
        },
      );
    }
  }

  test('UT-073/075 IT-005 partial real full replacement retains incoming identities and rejects old epoch after reopen', () async {
    final target = await source.saveTarget(
      service: ImageHostService.catbox,
      alias: '新账号',
      anonymous: false,
      credential: 'SyntheticAccountFixture0123456789',
      persistence: CredentialPersistence.session,
    );
    expect(target, isNotEmpty);
    await source.updateOrganization(
      [incoming.id],
      favorite: true,
      replaceTags: ['新标签'],
    );
    final backup = await package();
    final epoch = destination.executionEpoch;
    final lateEvent = Completer<void>();
    final oldCallback = destination.runInExecutionEpoch(epoch, () async {
      await lateEvent.future;
      await destination.updateOrganization([incoming.id], favorite: false);
    });
    final rejectedCallback = expectLater(oldCallback, throwsA(anything));
    final report = await replace(backup);
    lateEvent.complete();
    await rejectedCallback;
    expect(report.addedAssets, 1);
    expect(report.savedCopies, 1);
    expect(report.cleanupPending, false);
    expect(destination.executionEpoch, isNot(epoch));
    await expectLater(
      destination.runInExecutionEpoch(
        epoch,
        () => destination.getAsset(incoming.id),
      ),
      throwsA(anything),
    );
    expect(await destination.getAsset(oldAsset.id), isNull);
    final actual = (await destination.getAsset(incoming.id))!;
    expect(actual.favorite, true);
    expect(actual.version.id, incoming.version.id);
    expect(actual.deviceCopy.id, isNot(incoming.deviceCopy.id));
    expect(await destination.verifyCopy(actual), CopyAvailability.available);
    expect(actual.tags.single.name, '新标签');
    expect(secrets.values, isEmpty);
    expect(rows('upload_publications'), isEmpty);
    expect(rows('provider_targets').single['id'], target);
    expect((await destination.listTargets()).single.enabled, false);
    expect(rows('restore_operations'), isEmpty);
    expect(
      await File('${root.path}/${oldAsset.deviceCopy.relativePath}').exists(),
      false,
    );
    await reopen();
    expect(
      await destination.verifyCopy((await destination.getAsset(incoming.id))!),
      CopyAvailability.available,
    );
    expect(await destination.getAsset(oldAsset.id), isNull);
  });

  test('UT-073/075 partial replacement metadata mode never reuses old bytes even matching incoming content', () async {
    // Same content is deliberately imported into both independent roots.
    final same = await image(destination, 1);
    expect(same.version.sha256, incoming.version.sha256);
    final backup = await package(mode: BackupMode.metadata);
    final report = await replace(backup);
    expect(report.metadataOnly, true);
    expect(report.savedCopies, 0);
    final actual = (await destination.getAsset(incoming.id))!;
    expect(await destination.verifyCopy(actual), CopyAvailability.missing);
    expect(await bytes(), isEmpty);
    await reopen();
    expect(
      await destination.verifyCopy((await destination.getAsset(incoming.id))!),
      CopyAvailability.missing,
    );
  });

  for (final cancel in [false, true]) {
    test(
      'UT-075 partial committed ${cancel ? "late cancellation" : "callback fault"} preserves success',
      () async {
        final backup = await package();
        final token = CancellationToken();
        final report = await replace(
          backup,
          cancellation: token,
          faultHook: (boundary) async {
            if (boundary != RestoreBoundary.committed) return;
            if (cancel) {
              token.cancel();
            } else {
              throw StateError('late callback');
            }
          },
        );
        expect(report.cleanupPending, false);
        expect(await destination.getAsset(oldAsset.id), isNull);
        expect(
          await destination.verifyCopy(
            (await destination.getAsset(incoming.id))!,
          ),
          CopyAvailability.available,
        );
        expect(secrets.values, isEmpty);
      },
    );
  }

  test('UT-074/075 partial secret cleanup failure keeps committed library and retries after reopen', () async {
    final backup = await package();
    secrets.failDeletes = true;
    final report = await replace(backup);
    expect(report.cleanupPending, true);
    expect(
      rows('restore_operations').map((r) => r['phase']),
      contains('replace-committed'),
    );
    expect(await destination.getAsset(oldAsset.id), isNull);
    expect(
      await destination.verifyCopy((await destination.getAsset(incoming.id))!),
      CopyAvailability.available,
    );
    expect(secrets.values, isNotEmpty);
    secrets.failDeletes = false;
    await reopen();
    expect(rows('restore_operations'), isEmpty);
    expect(secrets.values, isEmpty);
    expect(
      await destination.verifyCopy((await destination.getAsset(incoming.id))!),
      CopyAvailability.available,
    );
  });

  test('UT-074/075 partial exclusive collision preserves foreign target and restores original library', () async {
    final backup = await package();
    final before = state(), originals = await bytes();
    File? foreign;
    await expectLater(
      replace(
        backup,
        publisher: (stage, target) async {
          foreign = target;
          await target.writeAsBytes([70, 71, 72], flush: true);
          return false;
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(state(), before);
    expect(await foreign!.readAsBytes(), [70, 71, 72]);
    for (final item in originals.entries) {
      expect(
        sha256.convert(await File(item.key).readAsBytes()).toString(),
        item.value,
      );
    }
    expect(rows('restore_operations'), isEmpty);
  });

  test('UT-074/075 partial insufficient commit capacity rolls back before publication', () async {
    final backup = await package();
    final before = state(), originals = await bytes();
    await expectLater(
      replace(backup, capacity: (_) async => 0),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(state(), before);
    expect(await bytes(), originals);
    expect(rows('restore_operations'), isEmpty);
  });

  test('UT-075 partial confirmed cleaned marker tolerates already missing snapshot payload', () async {
    final backup = await package();
    secrets.failDeletes = true;
    await replace(backup);
    secrets.failDeletes = false;
    // Model interruption AFTER the durable cleanup marker. Remaining snapshot
    // bytes can be incomplete; current replacement data must never roll back.
    final operation = rows('restore_operations')
        .singleWhere((r) => r['phase'] == 'replace-committed');
    final payload = jsonDecode(operation['payload_json'] as String) as Map;
    final snapshot = rows('restore_operations')
        .singleWhere((r) => r['id'] == payload['snapshotId']);
    final snapshotPayload =
        jsonDecode(snapshot['payload_json'] as String) as Map;
    for (final reference in secrets.values.keys.toList()) {
      await secrets.delete(reference);
    }
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      db.execute(
        "UPDATE restore_operations SET phase='replace-cleaned' WHERE id=?",
        [operation['id']],
      );
    } finally {
      db.close();
    }
    await File('${root.path}/${snapshotPayload['directory']}/current.sqlite')
        .delete();
    await reopen();
    expect(rows('restore_operations'), isEmpty);
    expect(await destination.getAsset(oldAsset.id), isNull);
    expect(
      await destination.verifyCopy((await destination.getAsset(incoming.id))!),
      CopyAvailability.available,
    );
  });
}
