import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/backup/application/backup_coordinator.dart';
import 'package:imagehost/features/backup/application/restore_coordinator.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/application/original_preview_reader.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/output_preview_reader.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/platform/image_preview_codec.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:imagehost/platform/system_network_monitor.dart';
import 'package:imagehost/platform/system_secret_store.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// Emulator backend evidence only: no ARM64 device PT, hardware performance,
// external image-host confirmation, uploads, probes or remote deletions.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'UT/IT partial Android emulator native secrets storage SQLite codec isolate backup restore and passive network',
    (tester) async {
      expect(
        Platform.isAndroid,
        true,
        reason: 'This test requires the actual Android plugin backends.',
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Android 私有后端验证'))),
      );
      final temporary = await getTemporaryDirectory();
      final canonicalTemporary = await temporary.resolveSymbolicLinks();
      final testId = const Uuid().v4();
      final sandbox = await Directory(canonicalTemporary)
          .createTemp('imagehost-android-native-$testId-');
      final canonicalSandbox = await sandbox.resolveSymbolicLinks();
      expect(p.dirname(canonicalSandbox), canonicalTemporary);
      expect(
        p.basename(canonicalSandbox),
        startsWith('imagehost-android-native-$testId-'),
      );
      const capacity = StorageCapacity();
      final secrets = SystemSecretStore();
      final secretReference = const Uuid().v4();
      final syntheticSecret = 'native-test-${const Uuid().v4()}';
      final root = Directory(p.join(canonicalSandbox, 'source-library'));
      final restoredRoot = Directory(
        p.join(canonicalSandbox, 'restored-library'),
      );
      LibraryRepository? source;
      LibraryRepository? restored;
      UploadCoordinator? uploads;
      OutputFileLease? outstanding;
      Future<void>? pendingClose;
      final network = SystemNetworkMonitor();
      try {
        // Address only a fresh test UUID. Boolean assertions keep even failure
        // output from printing the synthetic secret; never enumerate storage.
        expect(await secrets.read(secretReference) == null, true);
        await secrets.write(secretReference, syntheticSecret);
        expect(
          await SystemSecretStore().read(secretReference) == syntheticSecret,
          true,
        );
        await SystemSecretStore().delete(secretReference);
        expect(await SystemSecretStore().read(secretReference) == null, true);

        expect(capacity.supportsPlatform, true);
        expect(
          await capacity.availableBytes(sandbox),
          greaterThan(32 * 1024 * 1024),
        );
        final existing = await File(p.join(canonicalSandbox, 'existing.bin'))
            .writeAsBytes([1, 2, 3], flush: true);
        final staged = await File(
          p.join(canonicalSandbox, 'publication 中文📷.partial'),
        ).writeAsBytes([4, 5, 6], flush: true);
        // Native failures expose only fixed stage/kind codes, never provider
        // text or file paths. Keep that evidence visible in the backend check.
        expect(
          await const MethodChannel('io.imagehost/storage_capacity')
              .invokeMethod<bool>('publishExclusive', {
                'source': staged.path,
                'destination': existing.path,
              }),
          false,
        );
        expect(await existing.readAsBytes(), [1, 2, 3]);
        expect(await staged.readAsBytes(), [4, 5, 6]);
        final published = File(p.join(canonicalSandbox, 'published 中文📷.bin'));
        expect(
          await const MethodChannel('io.imagehost/storage_capacity')
              .invokeMethod<bool>('publishExclusive', {
                'source': staged.path,
                'destination': published.path,
              }),
          true,
        );
        expect(await published.readAsBytes(), [4, 5, 6]);
        expect(await staged.exists(), false);

        final initial = await _open(root, capacity);
        source = initial;
        final bytes = _png(27);
        final external = await File(p.join(canonicalSandbox, '来源 é 中文📷.png'))
            .writeAsBytes(bytes, flush: true);
        final imported = await initial.importResource(
          PlatformResource.file(external),
        );
        expect(imported.status, ImportStatus.saved);
        final asset = imported.asset!;
        expect(asset.displayName, '来源 é 中文📷.png');
        expect(asset.version.sha256, sha256.convert(bytes).toString());
        expect(asset.version.byteCount, bytes.length);
        expect(asset.deviceCopy.relativePath, startsWith('originals/'));
        final originalFile = File(
          p.join(root.path, asset.deviceCopy.relativePath),
        );
        expect(
          p.normalize(originalFile.absolute.path),
          isNot(p.normalize(external.absolute.path)),
        );
        expect(await originalFile.readAsBytes(), bytes);
        // The original source grant/file is unnecessary once the copy commits.
        await external.delete();
        expect(await initial.verifyCopy(asset), CopyAvailability.available);

        final category = await initial.createCategory('  分类 e\u0301 中文📷  ');
        expect(category.name, '分类 é 中文📷');
        await initial.updateOrganization(
          [asset.id],
          setCategory: true,
          categoryId: category.id,
          favorite: true,
          replaceTags: ['  标签 e\u0301  ', 'UTF8 中文📷'],
        );
        final organized = (await initial.getAsset(asset.id))!;
        expect(
          organized.tags.map((tag) => tag.name),
          unorderedEquals(['标签 é', 'UTF8 中文📷']),
        );
        final settings = DeviceSettings(
          uploadConcurrency: 2,
          processingConcurrency: 1,
          quality: 73,
          longestSide: 32,
          processingMode: ProcessingMode.sizeFirst,
          cacheLimitMiB: 128,
          defaultOutputRetention: OutputRetention.week,
          networkUploadPolicy: NetworkUploadPolicy.anyKnownNetwork,
        );
        await initial.saveSettings(
          await initial.loadSettings(),
          settings,
          defaultTargetIds: const [],
        );
        expect(initial.currentDeviceSettings, settings);

        final thumbnail = await initial.acquireThumbnailLease(organized);
        expect(thumbnail, isNotNull);
        final thumbnailLease = thumbnail!;
        try {
          expect(await thumbnailLease.file.exists(), true);
          await _assertSdkPixels(await thumbnailLease.readBytes(), 9, 6);
        } finally {
          await thumbnailLease.release();
        }
        final preview = await OriginalPreviewReader(initial).read(organized);
        ui.Codec? previewCodec;
        try {
          expect(preview.asset.version, organized.version);
          expect(preview.bytes, bytes);
          previewCodec = await decodeOriginalPreview(
            preview.bytes,
            memoryBudgetBytes: preview.memoryBudgetBytes,
          );
          expect(previewCodec.frameCount, 1);
          final frame = await previewCodec.getNextFrame();
          try {
            expect(frame.image.width, 9);
            expect(frame.image.height, 6);
            expect(
              await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba),
              isNotNull,
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          previewCodec?.dispose();
          preview.release();
        }

        final output = await ProcessingCoordinator(initial).process(
          [asset.id],
          (inputs) => ProcessingRequest(
            operation: ProcessingOperation.compress,
            inputs: inputs,
            mode: ProcessingMode.sizeFirst,
            longestSide: 6,
          ),
          displayName: '独立处理 é 中文.png',
        );
        expect(output.state, OutputState.ready);
        expect(output.usable, true);
        expect(output.version!.width, 6);
        expect(output.version!.height, 4);
        expect(output.file!.path, isNot(originalFile.path));
        expect(await initial.verifyCopy(organized), CopyAvailability.available);
        await _assertSdkPixels(
          await OutputPreviewReader(initial).read(output.id),
          6,
          4,
        );

        final lease = await initial.acquireOutputLease(output.id);
        outstanding = lease;
        var closeFinished = false;
        final closing = initial.close().then<void>((_) {
          closeFinished = true;
        });
        pendingClose = closing;
        try {
          // This delay only checks the lease barrier, never performance.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(
            closeFinished,
            false,
            reason: 'A real output lease must keep the library open.',
          );
          final leasedBytes = await lease.output.file!.readAsBytes();
          expect(
            sha256.convert(leasedBytes).toString(),
            output.version!.sha256,
          );
          expect(leasedBytes.length, output.version!.byteCount);
        } finally {
          await lease.release();
          outstanding = null;
          await closing;
          pendingClose = null;
        }
        expect(closeFinished, true);
        source = null;
        final reopened = await _open(root, capacity);
        source = reopened;
        await _assertAsset(reopened, organized, bytes, sameDeviceCopy: true);
        expect((await reopened.getOutput(output.id)).version, output.version);
        expect((await reopened.getOutput(output.id)).usable, true);
        expect((await reopened.loadSettings()).values, settings);

        final exports = await Directory(p.join(canonicalSandbox, 'exports'))
            .create();
        final preflight = await Directory(p.join(canonicalSandbox, 'preflight'))
            .create();
        final backup = await BackupCoordinator(
          capture: (mode, token, progress) => reopened.captureBackupSnapshot(
            mode: mode,
            cancellation: token,
            onVerification: progress,
          ),
          availableBytes: capacity.availableBytes,
          publishExclusive: capacity.publishExclusive,
        ).export(exports, BackupMode.full);
        expect(backup.cleanupPending, false);
        expect(backup.assets, 1);
        expect(backup.versions, 1);
        expect(await backup.file.length(), backup.byteCount);
        // Successful strict preflight proves the emitted ZIP is closed and its
        // directory/CRC/SHA/pixel evidence agrees; this is not yet a restore.
        final validated = await const BackupZipReader().preflight(
          backup.file,
          preflight,
          availableBytes: capacity.availableBytes,
        );
        try {
          expect(validated.manifest.assets.single.id, organized.id);
          expect(validated.manifest.versions.single, organized.version);
          expect(validated.manifest.categories.single.id, organized.categoryId);
          expect(
            validated.manifest.tags.map((tag) => tag.id),
            unorderedEquals(organized.tags.map((tag) => tag.id)),
          );
          expect(validated.manifest.settings!.values, settings);
          expect(validated.imageFiles.length, 1);
          expect(validated.manifest.accounts, isEmpty);
          expect(validated.manifest.results, isEmpty);
          expect(validated.manifest.history, isEmpty);
        } finally {
          await validated.dispose();
        }

        final destination = await _open(restoredRoot, capacity);
        restored = destination;
        final actor = UploadCoordinator(
          LibraryUploadQueueStore(destination),
          adapters: const [],
        );
        uploads = actor;
        expect(actor.networkAllowed, false);
        expect(actor.activeCount, 0);
        expect(await destination.listUploadBatches(), isEmpty);
        var replacementCallback = false;
        final restore = RestoreCoordinator(
          repository: destination,
          pauseUploads: actor.holdForRestore,
          availableBytes: capacity.availableBytes,
          publishExclusive: capacity.publishExclusive,
          afterReplacement: () async {
            await actor.close();
            replacementCallback = true;
          },
        );
        var mergeConfirmed = false;
        final merged = await restore.merge(
          backup.file,
          preflight,
          confirm: (manifest, plan) async {
            expect(manifest.mode, BackupMode.full);
            expect(plan.canCommit, true);
            expect(plan.assetIds[organized.id], organized.id);
            expect(plan.versionIds[organized.version.id], organized.version.id);
            mergeConfirmed = true;
            return true;
          },
        );
        expect(mergeConfirmed, true);
        expect(merged, isNotNull);
        expect(merged!.cleanupPending, false);
        expect(merged.report.addedAssets, 1);
        expect(merged.report.savedCopies, 1);
        expect(merged.report.metadataOnly, false);
        expect(merged.report.conflicts, 0);
        final mergedAsset = await _assertAsset(destination, organized, bytes);
        expect((await destination.loadSettings()).values, settings);
        expect(actor.networkAllowed, false);

        final extra = await destination.importResource(
          PlatformResource(
            displayName: '替换前独有.png',
            openRead: () => Stream.value(_png(89)),
          ),
        );
        expect(extra.status, ImportStatus.saved);
        await destination.updateOrganization(
          [organized.id],
          replaceTags: ['替换前本机标签'],
          favorite: false,
        );
        var replaceConfirmed = false;
        final replacementPhases = <String>[];
        final replaced = await restore.replace(
          backup.file,
          preflight,
          confirm: (prepared) async {
            expect(prepared.currentAssets, 2);
            expect(prepared.currentFiles, greaterThanOrEqualTo(2));
            expect(prepared.metadata.assets.single.id, organized.id);
            replaceConfirmed = true;
            return true;
          },
          onProgress: (phase, _, _) {
            // Production coordinator phases are fixed phrases without paths,
            // provider data or SDK exception text.
            replacementPhases.add(phase);
          },
        );
        expect(replacementPhases, contains('正在验证当前快照可恢复'));
        expect(replaceConfirmed, true);
        expect(replacementCallback, true);
        expect(replaced, isNotNull);
        expect(replaced!.replaced, true);
        expect(replaced.cleanupPending, false);
        expect(replaced.report.savedCopies, 1);
        expect((await destination.listAssets()).total, 1);
        expect(await destination.getAsset(extra.asset!.id), isNull);
        final replacedAsset = await _assertAsset(destination, organized, bytes);
        expect(replacedAsset.deviceCopy.id, isNot(mergedAsset.deviceCopy.id));
        expect((await destination.loadSettings()).values, settings);
        expect(await destination.listUploadBatches(), isEmpty);
        expect(actor.networkAllowed, false);
        await actor.close();
        uploads = null;
        await destination.close();
        restored = null;
        final reopenedDestination = await _open(restoredRoot, capacity);
        restored = reopenedDestination;
        await _assertAsset(
          reopenedDestination,
          replacedAsset,
          bytes,
          sameDeviceCopy: true,
        );
        expect((await reopenedDestination.loadSettings()).values, settings);
        expect(reopenedDestination.recoveryIssues, isEmpty);

        // Read/listen handshake uses the real Android channels; there is no
        // request to any host or synthetic snapshot injected into the monitor.
        await network.start();
        await network.refresh();
        for (
          var i = 0;
          i < 20 && network.current.status == NetworkStatus.unknown;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(
          network.current.status,
          anyOf(NetworkStatus.offline, NetworkStatus.connected),
        );
        if (network.current.status == NetworkStatus.connected) {
          expect(network.current.transports, isNotEmpty);
          expect(
            network.current.transports.every(NetworkTransport.values.contains),
            true,
          );
        } else {
          expect(network.current.transports, isEmpty);
        }
        await network.close();
        expect(tester.takeException(), isNull);
      } finally {
        // Await every owned IO finalizer before removing the unique sandbox.
        // If closure is uncertain, this path fails and retains its directory.
        await outstanding?.release();
        await pendingClose;
        await uploads?.close();
        await restored?.close();
        await source?.close();
        await network.close();
        await SystemSecretStore().delete(secretReference);
        expect(await SystemSecretStore().read(secretReference) == null, true);
        await tester.pumpWidget(const SizedBox());
        expect(await sandbox.resolveSymbolicLinks(), canonicalSandbox);
        expect(p.dirname(canonicalSandbox), canonicalTemporary);
        expect(
          p.basename(canonicalSandbox),
          startsWith('imagehost-android-native-$testId-'),
        );
        expect(
          await FileSystemEntity.type(canonicalSandbox, followLinks: false),
          FileSystemEntityType.directory,
        );
        await sandbox.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<LibraryRepository> _open(Directory root, StorageCapacity capacity) =>
    LibraryRepository.open(
      root,
      secretStore: SystemSecretStore(),
      availableStorageBytes: capacity.availableBytes,
      publishCacheExclusive: capacity.publishExclusive,
    );

Uint8List _png(int red) {
  final image = img.Image(width: 9, height: 6, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(red, 71, 133, 255));
  return Uint8List.fromList(img.encodePng(image));
}

Future<void> _assertSdkPixels(Uint8List bytes, int width, int height) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    expect(codec.frameCount, 1);
    final frame = await codec.getNextFrame();
    try {
      expect(frame.image.width, width);
      expect(frame.image.height, height);
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(pixels, isNotNull);
      expect(pixels!.lengthInBytes, width * height * 4);
      expect(pixels.buffer.asUint8List(pixels.offsetInBytes, 4), [
        27,
        71,
        133,
        255,
      ]);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<ImageAsset> _assertAsset(
  LibraryRepository repository,
  ImageAsset expected,
  Uint8List bytes, {
  bool sameDeviceCopy = false,
}) async {
  final actual = await repository.getAsset(expected.id);
  expect(actual, isNotNull);
  expect(actual!.id, expected.id);
  expect(actual.displayName, expected.displayName);
  expect(actual.version, expected.version);
  expect(actual.categoryId, expected.categoryId);
  expect(actual.category, expected.category);
  expect(actual.tags, unorderedEquals(expected.tags));
  expect(actual.favorite, expected.favorite);
  if (sameDeviceCopy) expect(actual.deviceCopy, expected.deviceCopy);
  expect(await repository.verifyCopy(actual), CopyAvailability.available);
  final lease = await repository.acquireAssetLease([
    actual.id,
  ], purpose: 'Android native smoke byte verification');
  try {
    final file = File(lease.pathsByVersion[actual.version.id]!);
    final actualBytes = await file.readAsBytes();
    expect(actualBytes, bytes);
    expect(sha256.convert(actualBytes).toString(), expected.version.sha256);
  } finally {
    await lease.release();
  }
  return actual;
}
