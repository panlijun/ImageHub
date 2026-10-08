import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/backup/domain/backup_merge_plan.dart';
import 'package:imagehost/features/backup/domain/backup_restore_plan.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/domain/version_description_policy.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'png_orientation_fixture.dart';
import 'upload_repository_test.dart' show QueueTestSecrets;

String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
ImageVersion _version({
  int id = 1,
  int orientation = 1,
  int? width,
  int? height,
  int frames = 1,
  String format = 'PNG',
  String hash = 'a',
  int bytes = 100,
}) => ImageVersion(
  id: _id(id),
  sha256: hash * 64,
  byteCount: bytes,
  format: format,
  width: width ?? (orientation >= 5 ? 3 : 2),
  height: height ?? (orientation >= 5 ? 2 : 3),
  frameCount: frames,
  orientation: orientation,
);
FrozenUploadInput _input(ImageVersion v) => FrozenUploadInput(
  kind: UploadInputKind.original,
  referenceId: _id(10),
  displayName: '冻结名称.png',
  version: v,
  policyKey: 'frozen-policy',
);
TargetSnapshot _target() =>
    TargetSnapshot(_id(40), ImageHostService.catbox, '冻结账号', false);
BackupRemoteResult _result(ImageVersion v, {int id = 50}) => BackupRemoteResult(
  id: _id(id),
  attemptId: _id(id + 100),
  input: _input(v),
  target: _target(),
  remoteId: 'audit.png',
  directUrl: Uri.parse('https://files.catbox.moe/audit.png'),
  confirmedUtc: 300,
  late: false,
);
BackupTaskHistory _history(ImageVersion v) => BackupTaskHistory(
  id: _id(70),
  batchId: _id(80),
  position: 0,
  input: _input(v),
  target: _target(),
  state: PublishState.succeeded,
  attempts: [
    BackupAttemptHistory(
      id: _id(150),
      generation: 1,
      startedUtc: 200,
      endedUtc: 300,
      outcome: 'confirmed',
    ),
  ],
  createdUtc: 100,
  updatedUtc: 300,
);
BackupManifest _manifest({
  List<ImageVersion> versions = const [],
  List<BackupOrigin> origins = const [],
  List<BackupRemoteResult> results = const [],
  List<BackupTaskHistory> history = const [],
}) => BackupManifest(
  packageId: _id(900),
  createdUtc: 400,
  mode: BackupMode.metadata,
  versions: versions,
  assets: const [],
  categories: const [],
  tags: const [],
  origins: origins,
  accounts: const [],
  results: results,
  history: history,
  images: const [],
);
BackupOrigin _origin(ImageVersion output, ImageVersion input, {int id = 60}) =>
    BackupOrigin(
      outputId: _id(id),
      versionId: output.id,
      createdUtc: 200,
      processing: BackupProcessingSnapshot(
        operation: ProcessingOperation.compress,
        inputs: [BackupProcessingInput(assetId: _id(10), version: input)],
        mode: ProcessingMode.fidelity,
        outputFormat: ProcessingFormat.png,
        longestSide: 100,
        quality: null,
        crop: null,
        layout: StitchLayout.horizontal,
        gap: 0,
        backgroundArgb: 0xffffffff,
        backgroundConfirmed: true,
        explicitStaticConversion: false,
      ),
    );

void main() {
  group('IMG-005 BAK-004 PNG frozen audit correction boundary', () {
    for (var orientation = 2; orientation <= 8; orientation++) {
      test('only known encoded dimensions accept orientation $orientation', () {
        final earlier = _version();
        final confirmed = _version(orientation: orientation);
        expect(
          VersionDescriptionPolicy.isPngOrientationCorrection(
            earlier,
            confirmed,
          ),
          true,
        );
        final decoded = BackupManifest.decode(
          _manifest(
            versions: [confirmed],
            results: [_result(earlier)],
            history: [_history(earlier)],
            origins: [_origin(confirmed, earlier)],
          ).encode(redactor: SecretRedactor()),
        );
        expect(decoded.versions.single, confirmed);
        expect(decoded.results.single.input.version, earlier);
        expect(decoded.history.single.input.version, earlier);
        expect(
          decoded.origins.single.processing.inputs.single.version,
          earlier,
        );
        expect(
          () => _manifest(versions: [earlier], results: [_result(confirmed)]),
          throwsA(isA<BackupFailure>()),
        );
      });
    }

    test(
      'every other descriptor contradiction and unknown direction rejects',
      () {
        final earlier = _version();
        final invalid = [
          _version(orientation: 6, width: 4),
          _version(orientation: 6, height: 4),
          _version(orientation: 6, frames: 2),
          _version(orientation: 6, format: 'JPEG'),
          _version(orientation: 6, hash: 'b'),
          _version(orientation: 6, bytes: 101),
          _version(orientation: 0),
          _version(orientation: 9),
        ];
        for (final other in invalid) {
          expect(
            VersionDescriptionPolicy.auditCompatible(earlier, other),
            false,
          );
          expect(
            () => _manifest(versions: [other], results: [_result(earlier)]),
            throwsA(isA<BackupFailure>()),
          );
        }
        expect(
          () => _manifest(
            results: [_result(_version(orientation: 6))],
            history: [_history(_version(orientation: 8))],
          ),
          throwsA(isA<BackupFailure>()),
        );
      },
    );

    test(
      'permanent content conflict stays blocking, even with a legacy audit',
      () {
        final current = _manifest(
          versions: [_version(orientation: 6)],
          results: [_result(_version())],
        );
        final incoming = _manifest(versions: [_version(id: 2)]);
        expect(
          BackupMergePlanner.plan(
            current: current,
            incoming: incoming,
          ).canCommit,
          false,
        );
        expect(
          BackupRestorePlanner.plan(
            current: current,
            incoming: incoming,
          ).canCommit,
          false,
        );
      },
    );

    test(
      'a single frozen processing plan cannot mix same UUID generations',
      () {
        final output = _version(id: 3, hash: 'b');
        final p = _origin(output, _version()).processing;
        final mixed = BackupProcessingSnapshot(
          operation: p.operation,
          inputs: [
            ...p.inputs,
            BackupProcessingInput(
              assetId: _id(11),
              version: _version(orientation: 6),
            ),
          ],
          mode: p.mode,
          outputFormat: p.outputFormat,
          longestSide: p.longestSide,
          quality: p.quality,
          crop: p.crop,
          layout: p.layout,
          gap: p.gap,
          backgroundArgb: p.backgroundArgb,
          backgroundConfirmed: p.backgroundConfirmed,
          explicitStaticConversion: p.explicitStaticConversion,
        );
        expect(
          () => _manifest(
            versions: [output],
            origins: [
              BackupOrigin(
                outputId: _id(60),
                versionId: output.id,
                createdUtc: 200,
                processing: mixed,
              ),
            ],
          ),
          throwsA(isA<BackupFailure>()),
        );
      },
    );

    for (final reversed in [false, true]) {
      test('audit-only generations remain frozen in both orders $reversed', () {
        final old = _version(), confirmed = _version(orientation: 6);
        final audits = [_result(old), _result(confirmed, id: 51)];
        final current = _manifest(
          results: reversed ? audits.reversed.toList() : audits,
        );
        final decoded = BackupManifest.decode(
          current.encode(redactor: SecretRedactor()),
        );
        expect(
          decoded.results.map((r) => r.input.version.orientation),
          reversed ? [6, 1] : [1, 6],
        );
        final incoming = _manifest(versions: [confirmed]);
        final plan = BackupRestorePlanner.plan(
          current: current,
          incoming: incoming,
        );
        expect(plan.canCommit, true);
        expect(plan.metadata!.versions.single, confirmed);
        expect(
          {
            for (final r in plan.metadata!.results)
              r.id: r.input.version.orientation,
          },
          {_id(50): 1, _id(51): 6},
        );
        final emptyMerge = BackupRestorePlanner.plan(
          current: _manifest(),
          incoming: current,
        );
        expect(emptyMerge.canCommit, true);
        expect(
          {
            for (final r in emptyMerge.metadata!.results)
              r.id: r.input.version.orientation,
          },
          {_id(50): 1, _id(51): 6},
        );
      });
      test(
        'audit-only source result and history prefer confirmed comparison $reversed',
        () {
          final old = _version(), confirmed = _version(orientation: 6);
          final output = _version(id: 3, hash: 'b');
          final origins = [
            _origin(output, old),
            _origin(output, confirmed, id: 61),
          ];
          final current = _manifest(
            versions: [output],
            origins: reversed ? origins.reversed.toList() : origins,
            results: [_result(reversed ? confirmed : old)],
            history: [_history(reversed ? old : confirmed)],
          );
          final incoming = _manifest(versions: [confirmed]);
          final plan = BackupRestorePlanner.plan(
            current: current,
            incoming: incoming,
          );
          expect(plan.canCommit, true);
          final metadata = BackupManifest.decode(
            plan.metadata!.encode(redactor: SecretRedactor()),
          );
          expect(
            metadata.origins.map(
              (o) => o.processing.inputs.single.version.orientation,
            ),
            reversed ? [6, 1] : [1, 6],
          );
          expect(
            metadata.results.single.input.version.orientation,
            reversed ? 6 : 1,
          );
          expect(
            metadata.history.single.input.version.orientation,
            reversed ? 1 : 6,
          );
          expect(
            metadata.versions.singleWhere((v) => v.id == old.id).orientation,
            6,
          );
        },
      );
    }

    test('origin, ordinary result and history remap only the frozen UUID', () {
      final old = _version(), corrected = _version(orientation: 6);
      final output = _version(id: 3, hash: 'b');
      final incoming = _manifest(
        versions: [corrected, output],
        origins: [_origin(output, old)],
        results: [_result(old)],
        history: [_history(old)],
      );
      final current = _manifest(versions: [_version(id: 2, orientation: 6)]);
      final plan = BackupRestorePlanner.plan(
        current: current,
        incoming: incoming,
      );
      expect(plan.canCommit, true);
      final metadata = plan.metadata!;
      for (final v in [
        metadata.results.single.input.version,
        metadata.history.single.input.version,
        metadata.origins.single.processing.inputs.single.version,
      ]) {
        expect(v.id, _id(2));
        expect(VersionDescriptionPolicy.same(v, old), true);
      }
      expect(metadata.results.single.id, _id(50));
      expect(metadata.results.single.attemptId, _id(150));
      expect(metadata.history.single.attempts.single.id, _id(150));
      final repeat = BackupRestorePlanner.plan(
        current: metadata,
        incoming: incoming,
      );
      expect(repeat.canCommit, true);
      expect(repeat.metadata!.results, hasLength(1));
      expect(repeat.metadata!.history, hasLength(1));
      expect(repeat.metadata!.origins, hasLength(1));
    });
  });

  test('IT-005 BAK-004 real PNG correction preserves SQL audits through full metadata merge replacement and rebackup', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'imagehost-png-audit-backup-',
    );
    final sourceRoot = Directory('${sandbox.path}/source');
    final secrets = QueueTestSecrets();
    LibraryRepository? source;
    final destinations = <LibraryRepository>[];
    final backups = <ValidatedBackup>[];
    final bytes = addPngExif(
      img.encodePng(orientationMatrix()),
      orientationTiff(6),
    );
    var archiveNumber = 0;
    Future<ImageAsset> import(LibraryRepository repository) async =>
        (await repository.importResource(
          PlatformResource(
            displayName: '保留名称.png',
            openRead: () => Stream.value(bytes),
          ),
        )).asset!;
    Future<ValidatedBackup> package(
      LibraryRepository repository,
      BackupMode mode,
    ) async {
      final snapshot = await repository.captureBackupSnapshot(mode: mode);
      final archive = File('${sandbox.path}/${archiveNumber++}.zip');
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

    Future<bool> publish(File staged, File target) async {
      if (await target.exists()) return false;
      await staged.rename(target.path);
      return true;
    }

    Future<MergeRestoreReport> merge(
      LibraryRepository destination,
      ValidatedBackup backup,
    ) async {
      final hold = await destination.acquireRestoreHold();
      try {
        final prepared = await destination.prepareMergeRestore(
          hold: hold,
          backup: backup,
        );
        expect(prepared.plan.canCommit, true);
        return await destination.commitMergeRestore(
          preparation: prepared,
          availableBytes: (_) async => 1 << 40,
          publishExclusive: publish,
        );
      } finally {
        await hold.release();
      }
    }

    void check(
      BackupManifest manifest,
      String expectedVersionId,
      String resultId,
      String attemptId,
    ) {
      expect(manifest.versions.single.id, expectedVersionId);
      expect(manifest.versions.single.orientation, 6);
      expect(manifest.versions.single.width, 3);
      expect(manifest.versions.single.height, 2);
      expect(manifest.results.single.id, resultId);
      expect(manifest.results.single.attemptId, attemptId);
      expect(manifest.history.single.attempts.single.id, attemptId);
      for (final frozen in [
        manifest.results.single.input.version,
        manifest.history.single.input.version,
      ]) {
        expect(frozen.id, expectedVersionId);
        expect(frozen.orientation, 1);
        expect(frozen.width, 2);
        expect(frozen.height, 3);
      }
    }

    try {
      source = await LibraryRepository.open(sourceRoot, secretStore: secrets);
      final original = await import(source);
      final category = await source.createCategory('保留分类');
      await source.updateOrganization(
        [original.id],
        setCategory: true,
        categoryId: category.id,
        replaceTags: ['保留标签'],
        favorite: true,
      );
      final account = await source.saveTarget(
        service: ImageHostService.catbox,
        alias: '合成账号',
        anonymous: false,
        credential: 'synthetic-png-backup-test-key-0123456789',
      );
      final batch = await source.enqueueUploads(
        intentId: _id(901),
        assetIds: [original.id],
        targetIds: [account],
        allowOriginalMetadata: true,
      );
      final execution = (await source.beginUploadAttempt(
        batch.items.single.id,
      ))!;
      try {
        expect(await source.authorizeUploadRequest(execution.attemptId), true);
        // Persist controlled ordinary evidence; no HTTP request is made.
        await source.finishUploadAttempt(
          execution,
          ProviderUploadSuccess(
            service: ImageHostService.catbox,
            remoteId: 'png-audit.png',
            directUrl: Uri.parse('https://files.catbox.moe/png-audit.png'),
          ),
          accumulatedRunning: const Duration(seconds: 1),
        );
      } finally {
        await execution.release();
      }
      final resultId = (await source.listUploadResults()).single.id;
      await source.close();
      source = null;
      final db = sqlite3.open('${sourceRoot.path}/library.sqlite');
      final frozenBefore = <String, String>{};
      try {
        db.execute(
          'UPDATE versions SET width=2,height=3,orientation=1 WHERE id=?',
          [original.version.id],
        );
        for (final table in ['upload_publications', 'remote_upload_results']) {
          for (final row in db.select('SELECT id,input_json FROM $table')) {
            final input =
                jsonDecode(row['input_json'] as String) as Map<String, dynamic>;
            final version = input['version'] as Map<String, dynamic>;
            version['width'] = 2;
            version['height'] = 3;
            version['orientation'] = 1;
            final frozen = jsonEncode(input);
            frozenBefore['$table:${row['id']}'] = frozen;
            db.execute('UPDATE $table SET input_json=? WHERE id=?', [
              frozen,
              row['id'],
            ]);
          }
        }
      } finally {
        db.close();
      }
      source = await LibraryRepository.open(sourceRoot, secretStore: secrets);
      final repaired = await import(source);
      expect(repaired.id, original.id);
      expect(repaired.version.id, original.version.id);
      expect(repaired.version.orientation, 6);
      expect(repaired.favorite, true);
      expect(repaired.category, '保留分类');
      expect(repaired.tags.single.name, '保留标签');
      expect(await (await source.originalFor(repaired)).readAsBytes(), bytes);
      final read = sqlite3.open(
        '${sourceRoot.path}/library.sqlite',
        mode: OpenMode.readOnly,
      );
      try {
        for (final table in ['upload_publications', 'remote_upload_results']) {
          for (final row in read.select('SELECT id,input_json FROM $table')) {
            expect(row['input_json'], frozenBefore['$table:${row['id']}']);
          }
        }
      } finally {
        read.close();
      }
      final full = await package(source, BackupMode.full);
      final metadata = await package(source, BackupMode.metadata);
      check(full.manifest, original.version.id, resultId, execution.attemptId);
      check(
        metadata.manifest,
        original.version.id,
        resultId,
        execution.attemptId,
      );
      for (final existing in [false, true]) {
        final destination = await LibraryRepository.open(
          Directory('${sandbox.path}/merge-$existing'),
        );
        destinations.add(destination);
        final local = existing ? await import(destination) : null;
        if (local != null) {
          expect(local.version.id, isNot(original.version.id));
          await destination.updateOrganization(
            [local.id],
            replaceTags: ['本机标签'],
            favorite: true,
          );
        }
        await merge(destination, full);
        final versionId = local?.version.id ?? original.version.id;
        final again = await package(destination, BackupMode.full);
        check(again.manifest, versionId, resultId, execution.attemptId);
        final restored = (await destination.getAsset(
          local?.id ?? original.id,
        ))!;
        expect(restored.favorite, true);
        expect(restored.category, '保留分类');
        expect(restored.tags.map((t) => t.name), contains('保留标签'));
        expect(
          await (await destination.originalFor(restored)).readAsBytes(),
          bytes,
        );
        final repeated = await merge(destination, full);
        expect(repeated.addedAssets, 0);
        expect(repeated.addedResults, 0);
        expect(repeated.importedHistories, 0);
        check(
          (await package(destination, BackupMode.metadata)).manifest,
          versionId,
          resultId,
          execution.attemptId,
        );
      }
      for (final existing in [false, true]) {
        final destination = await LibraryRepository.open(
          Directory('${sandbox.path}/metadata-merge-$existing'),
        );
        destinations.add(destination);
        final local = existing ? await import(destination) : null;
        await merge(destination, metadata);
        final versionId = local?.version.id ?? original.version.id;
        check(
          (await package(destination, BackupMode.metadata)).manifest,
          versionId,
          resultId,
          execution.attemptId,
        );
        final restored = (await destination.getAsset(
          local?.id ?? original.id,
        ))!;
        if (existing) {
          expect(
            await (await destination.originalFor(restored)).readAsBytes(),
            bytes,
          );
          check(
            (await package(destination, BackupMode.full)).manifest,
            versionId,
            resultId,
            execution.attemptId,
          );
        } else {
          expect(
            await destination.verifyCopy(restored),
            CopyAvailability.missing,
          );
        }
        final repeated = await merge(destination, metadata);
        expect(repeated.addedAssets, 0);
        expect(repeated.addedResults, 0);
        expect(repeated.importedHistories, 0);
      }
      final destination = await LibraryRepository.open(
        Directory('${sandbox.path}/replace'),
      );
      destinations.add(destination);
      final hold = await destination.acquireRestoreHold();
      ReplacementRestorePreparation? prepared;
      try {
        prepared = await destination.prepareReplacementRestore(
          hold: hold,
          backup: full,
          availableBytes: (_) async => 1 << 40,
        );
        await destination.commitReplacementRestore(
          preparation: prepared,
          availableBytes: (_) async => 1 << 40,
          publishExclusive: publish,
        );
      } finally {
        if (prepared != null) {
          await destination.discardReplacementPreparation(prepared);
        }
        await hold.release();
      }
      check(
        (await package(destination, BackupMode.full)).manifest,
        original.version.id,
        resultId,
        execution.attemptId,
      );
    } finally {
      for (final backup in backups) {
        await backup.dispose();
      }
      for (final destination in destinations) {
        await destination.close();
      }
      await source?.close();
      await sandbox.delete(recursive: true);
    }
  });
}
