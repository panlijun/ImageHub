import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory sandbox;
  late Directory root;
  late LibraryRepository repository;
  late ImageAsset asset;
  late File original;
  late List<int> bytes;
  final epoch = DateTime.utc(2026, 10, 4, 12);
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost_output_');
    root = Directory('${sandbox.path}/library');
    repository = await LibraryRepository.open(root);
    final picture = img.Image(width: 8, height: 6, numChannels: 4);
    img.fill(picture, color: img.ColorRgba8(38, 99, 179, 255));
    bytes = img.encodePng(picture);
    asset = (await repository.importResource(
      PlatformResource(
        displayName: 'source.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    original = (await repository.originalFor(asset));
  });
  tearDown(() async {
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  Future<ProcessedOutput> process({
    OutputRetention retention = OutputRetention.day,
    CancellationToken? cancellation,
  }) => withClock(
    Clock.fixed(epoch),
    () => ProcessingCoordinator(repository).process(
      [asset.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.crop,
        inputs: inputs,
        crop: const PixelCrop(1, 1, 3, 2),
      ),
      displayName: 'crop.png',
      retention: retention,
      cancellation: cancellation,
    ),
  );
  Future<void> reopen({
    OutputFaultHook? hook,
    ImportFaultHook? importHook,
  }) async {
    await repository.close();
    repository = await withClock(
      Clock.fixed(epoch),
      () => LibraryRepository.open(
        root,
        outputFaultHook: hook,
        faultHook: importHook,
      ),
    );
  }

  test('UT-034 / IT-003 real output metadata, digest, relative snapshot and restart identity', () async {
    final output = await process();
    expect(output.usable, true);
    expect(output.version!.width, 3);
    expect(output.version!.height, 2);
    expect(output.createdAt, epoch);
    expect(output.expiresAt, epoch.add(const Duration(hours: 24)));
    expect(output.beforeByteCount, bytes.length);
    expect(output.byteSavings, bytes.length - await output.file!.length());
    final resultBytes = await output.file!.readAsBytes();
    await repository.close();
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      final row = db
          .select('SELECT request_json FROM processed_outputs')
          .single;
      expect(row['request_json'], contains('originals/'));
      expect(row['request_json'], isNot(contains(sandbox.path)));
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      db.close();
    }
    repository = await withClock(
      Clock.fixed(epoch),
      () => LibraryRepository.open(root),
    );
    final restored = (await repository.listOutputs()).single;
    expect(restored.id, output.id);
    expect(restored.version, output.version);
    expect(restored.request.inputs.single.version, asset.version);
    expect(await restored.file!.readAsBytes(), resultBytes);
    expect(await original.readAsBytes(), bytes);
  });

  test('UT-034 missing/damaged output cannot preview save or acquire reading lease', () async {
    final output = await process();
    await output.file!.writeAsBytes([1, 2, 3], flush: true);
    var invalid = await repository.getOutput(output.id);
    expect(invalid.usable, false);
    expect(invalid.availability, CopyAvailability.damaged);
    await expectLater(repository.saveOutput(output.id), throwsStateError);
    await expectLater(
      repository.acquireOutputLease(output.id),
      throwsStateError,
    );
    await output.file!.delete();
    invalid = await repository.getOutput(output.id);
    expect(invalid.availability, CopyAvailability.missing);
    await reopen();
    expect((await repository.listOutputs()).single.usable, false);
    expect((await repository.listAssets()).total, 1);
  });

  test('UT-035 permanent save independently survives exact expiry and preserves ordered provenance', () async {
    final output = await process(retention: OutputRetention.hour);
    final result = await repository.saveOutput(output.id);
    expect(result.persisted, true);
    final permanent = result.asset!;
    expect(permanent.version.width, 3);
    expect(permanent.sourceType, 'processed');
    expect(
      (await repository.getOutput(output.id)).savedVersionId,
      permanent.version.id,
    );
    final savedFile = (await repository.originalFor(permanent));
    expect(savedFile.path, isNot(output.file!.path));
    final cleaned = await withClock(
      Clock.fixed(epoch.add(const Duration(hours: 1))),
      repository.cleanupOutputs,
    );
    expect(cleaned.removed, 1);
    expect(await output.file!.exists(), false);
    expect(await repository.verifyCopy(permanent), CopyAvailability.available);
    await reopen();
    final origins = await repository.savedOutputOrigins(permanent.version.id);
    expect(origins.single.inputs.single.version.id, asset.version.id);
    expect(origins.single.crop!.width, 3);
    expect(await savedFile.readAsBytes(), isNotEmpty);
  });

  test('UT-035 duplicate content save preserves organization and stores provenance once', () async {
    final output = await process();
    final first = await repository.saveOutput(output.id);
    await repository.setFavorite(first.asset!.id, true);
    final second = await repository.saveOutput(output.id);
    expect(second.status, ImportStatus.duplicate);
    expect(second.asset!.id, first.asset!.id);
    expect(second.asset!.favorite, true);
    expect(
      await repository.savedOutputOrigins(first.asset!.version.id),
      hasLength(1),
    );
  });

  test('UT-035 rejected permanent commit creates no usable asset and durable retry restores source relation', () async {
    final output = await process();
    await reopen(
      importHook: (boundary) async {
        if (boundary == ImportBoundary.beforeDbCommit) {
          throw StateError('injected');
        }
      },
    );
    final failed = await repository.saveOutput(output.id);
    expect(failed.persisted, false);
    expect((await repository.listAssets()).total, 1);
    // A ready import journal prevents expiry until recovery commits its verified bytes.
    final cleanup = await withClock(
      Clock.fixed(epoch.add(const Duration(days: 1))),
      repository.cleanupOutputs,
    );
    expect(cleanup.protected, 1);
    await reopen();
    final savedVersion = (await repository.getOutput(output.id))
        .savedVersionId!;
    final page = await repository.listAssets();
    expect(page.total, 2);
    final saved = page.items.singleWhere((a) => a.version.id == savedVersion);
    expect(await repository.verifyCopy(saved), CopyAvailability.available);
    expect(
      (await repository.savedOutputOrigins(savedVersion))
          .single
          .inputs
          .single
          .version
          .id,
      asset.version.id,
    );
  });

  test('UT-037 exact expiry, permanent reference, active lease and retryable delete failure', () async {
    final output = await process(retention: OutputRetention.hour);
    expect(
      (await withClock(
        Clock.fixed(epoch.add(const Duration(minutes: 59))),
        repository.cleanupOutputs,
      )).removed,
      0,
    );
    await repository.registerOutputProtection(
      outputId: output.id,
      ownerType: 'permanent',
      ownerId: 'external-permanent-ref',
    );
    expect(
      (await withClock(
        Clock.fixed(output.expiresAt),
        repository.cleanupOutputs,
      )).protected,
      1,
    );
    await reopen();
    await repository.releaseOutputProtection(
      outputId: output.id,
      ownerType: 'permanent',
      ownerId: 'external-permanent-ref',
    );
    final lease = await repository.acquireOutputLease(output.id);
    expect(
      (await withClock(
        Clock.fixed(output.expiresAt),
        repository.cleanupOutputs,
      )).protected,
      1,
    );
    await lease.release();
    await lease.release();
    await reopen(
      hook: (boundary) async {
        if (boundary == OutputBoundary.beforeDelete) {
          throw const FileSystemException('injected delete rejection');
        }
      },
    );
    final failed = await withClock(
      Clock.fixed(output.expiresAt),
      repository.cleanupOutputs,
    );
    expect(failed.failedIds, [output.id]);
    expect(await output.file!.exists(), true);
    expect((await repository.getOutput(output.id)).state, OutputState.deleting);
    await reopen();
    expect(
      (await withClock(
        Clock.fixed(output.expiresAt),
        repository.cleanupOutputs,
      )).removed,
      1,
    );
    expect(await repository.listOutputs(), isEmpty);
  });

  test('UT-038 protection contract persists all six nonterminal task owners until explicit safe release', () async {
    final output = await process(retention: OutputRetention.hour);
    for (final state in [
      'queued',
      'waiting',
      'paused',
      'running',
      'interrupted',
      'unknown',
    ]) {
      await repository.registerOutputProtection(
        outputId: output.id,
        ownerType: 'task',
        ownerId: state,
      );
    }
    await reopen();
    for (final state in [
      'queued',
      'waiting',
      'paused',
      'running',
      'interrupted',
    ]) {
      expect(
        (await withClock(
          Clock.fixed(output.expiresAt),
          repository.cleanupOutputs,
        )).protected,
        1,
      );
      await repository.releaseOutputProtection(
        outputId: output.id,
        ownerType: 'task',
        ownerId: state,
      );
    }
    expect(
      (await withClock(
        Clock.fixed(output.expiresAt),
        repository.cleanupOutputs,
      )).protected,
      1,
    );
    await repository.releaseOutputProtection(
      outputId: output.id,
      ownerType: 'task',
      ownerId: 'unknown',
    );
    expect(
      (await withClock(
        Clock.fixed(output.expiresAt),
        repository.cleanupOutputs,
      )).removed,
      1,
    );
  });

  for (final isOutput in [false, true]) {
    test(
      'UT-102 ${isOutput ? 'output' : 'source'} reader DB release failure keeps row but does not deadlock shutdown',
      () async {
        final output = await process();
        final outputLease = isOutput
            ? await repository.acquireOutputLease(output.id)
            : null;
        final sourceLease = isOutput
            ? null
            : await repository.acquireAssetLease([asset.id], purpose: '已完成读取');
        final blocker = sqlite3.open('${root.path}/library.sqlite');
        blocker.execute('BEGIN IMMEDIATE');
        try {
          await expectLater(
            isOutput ? outputLease!.release() : sourceLease!.release(),
            throwsA(isA<Exception>()),
          );
          final table = isOutput ? 'output_leases' : 'file_leases';
          expect(blocker.select('SELECT id FROM $table'), hasLength(1));
          await repository.close().timeout(const Duration(seconds: 2));
          expect(await output.file!.exists(), true);
        } finally {
          blocker.execute('ROLLBACK');
          blocker.close();
        }
        await reopen();
        expect((await repository.getOutput(output.id)).usable, true);
        final db = sqlite3.open('${root.path}/library.sqlite');
        try {
          expect(db.select('SELECT id FROM output_leases'), isEmpty);
          expect(db.select('SELECT id FROM file_leases'), isEmpty);
        } finally {
          db.close();
        }
      },
    );
  }

  for (final boundary in [
    OutputBoundary.prepared,
    OutputBoundary.published,
    OutputBoundary.committed,
  ]) {
    test(
      'UT-034 journal recovery after ${boundary.name} preserves confirmed identity and bytes',
      () async {
        await reopen(
          hook: (b) async {
            if (b == boundary) throw StateError('injected');
          },
        );
        final output = await process();
        expect(output.usable, boundary == OutputBoundary.committed);
        await reopen();
        final recovered = (await repository.listOutputs()).single;
        expect(recovered.id, output.id);
        expect(recovered.usable, true);
        expect(recovered.version!.width, 3);
        expect(repository.recoveryIssues, isEmpty);
        await reopen();
        expect((await repository.listOutputs()).single.id, output.id);
      },
    );
  }

  test('UT-034 cancellation waits for intent owner and leaves no usable or permanent result', () async {
    final token = CancellationToken();
    await reopen(
      hook: (b) async {
        if (b == OutputBoundary.intent) token.cancel();
      },
    );
    final output = await process(cancellation: token);
    expect(output.state, OutputState.cancelled);
    expect(output.file, null);
    expect((await repository.listAssets()).total, 1);
    expect(
      await Directory('${root.path}/cache/outputs').list().toList(),
      isEmpty,
    );
    await repository.removeAssets([asset.id]);
    expect(
      (await repository.purgeAssets(
        [asset.id],
        confirmCopies: true,
        confirmRecords: true,
      )).copiesRemoved,
      1,
    );
  });

  test('UT-053/087 real coordinators share frozen budget and cancelled waiting work releases only its lease', () async {
    final entered = Completer<void>(), gate = Completer<void>();
    var intentions = 0;
    await reopen(
      hook: (boundary) async {
        if (boundary == OutputBoundary.intent && intentions++ == 0) {
          entered.complete();
          await gate.future;
        }
      },
    );
    final first = process();
    await entered.future;
    final token = CancellationToken();
    final second = process(cancellation: token);
    final cancelled = expectLater(
      second,
      throwsA(
        isA<ProcessingFailure>().having(
          (e) => e.kind,
          'kind',
          ProcessingFailureKind.cancelled,
        ),
      ),
    );
    int leases() {
      final db = sqlite3.open(
        '${root.path}/library.sqlite',
        mode: OpenMode.readOnly,
      );
      try {
        return db.select('SELECT * FROM file_leases').length;
      } finally {
        db.close();
      }
    }

    try {
      for (var i = 0; i < 100 && leases() != 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(leases(), 2);
      final settings = await repository.loadSettings();
      await repository.saveSettings(
        settings,
        DeviceSettings(processingConcurrency: 4),
        defaultTargetIds: [],
      );
      expect(repository.processingScheduler.configuredConcurrency, 4);
      expect(repository.processingScheduler.activeCount, 1);
      expect(intentions, 1, reason: 'old job reserves original whole budget');
      token.cancel();
      await cancelled;
      expect(leases(), 1);
      expect(repository.processingScheduler.activeCount, 1);
    } finally {
      token.cancel();
      gate.complete();
      await cancelled;
    }
    expect((await first).usable, true);
    expect(repository.processingScheduler.activeCount, 0);
    expect(leases(), 0);
    expect((await process()).usable, true);
    expect((await repository.listOutputs()).length, 2);
  });

  test('UT-102 real closing drains active coordinator and refuses waiting output before pixel work', () async {
    final entered = Completer<void>(), gate = Completer<void>();
    var intentions = 0;
    await reopen(
      hook: (boundary) async {
        if (boundary == OutputBoundary.intent && intentions++ == 0) {
          entered.complete();
          await gate.future;
        }
      },
    );
    final first = process();
    await entered.future;
    final second = process();
    final refused = expectLater(second, throwsStateError);
    // Serial loading proves the second coordinator's lease acquisition settled.
    await repository.loadSettings();
    var closed = false;
    final closing = repository.close().then((_) => closed = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(closed, false);
      expect(repository.processingScheduler.activeCount, 1);
    } finally {
      gate.complete();
    }
    expect((await first).usable, true);
    await refused;
    await closing;
    expect(closed, true);
    expect(intentions, 1);
    await reopen();
    expect((await repository.listOutputs()).single.usable, true);
    expect(repository.processingScheduler.activeCount, 0);
  });

  test('UT-037 / UT-102 close waits for actual output reader and refuses new readers', () async {
    final output = await process();
    final lease = await repository.acquireOutputLease(output.id);
    var closed = false;
    final closing = repository.close().then((_) => closed = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(closed, false);
    await expectLater(
      repository.acquireOutputLease(output.id),
      throwsStateError,
    );
    await lease.release();
    await closing;
    expect(closed, true);
  });

  test(
    'IMG-004 animation crop preview reads the explicitly selected frame',
    () async {
      final palette = img.PaletteUint8(256, 3)
        ..setRgb(0, 255, 0, 0)
        ..setRgb(1, 0, 0, 255);
      final red = img.Image(
        width: 3,
        height: 2,
        numChannels: 1,
        palette: palette,
      );
      final blue = img.Image(
        width: 3,
        height: 2,
        numChannels: 1,
        palette: palette,
      );
      for (final pixel in blue) {
        blue.setPixelIndex(pixel.x, pixel.y, 1);
      }
      red.addFrame(blue);
      final animated = (await repository.importResource(
        PlatformResource(
          displayName: 'frames.gif',
          openRead: () => Stream.value(img.encodeGif(red)),
        ),
      )).asset!;
      expect(animated.version.frameCount, 2);
      final first = (await repository.thumbnailFor(animated))!;
      final second = (await repository.thumbnailFor(animated, frame: 1))!;
      expect(first.path, isNot(second.path));
      expect(
        img.decodePng(await first.readAsBytes())!.getPixel(0, 0).r,
        greaterThan(200),
      );
      expect(
        img.decodePng(await second.readAsBytes())!.getPixel(0, 0).b,
        greaterThan(200),
      );
      expect(
        () => repository.thumbnailFor(animated, frame: 2),
        throwsArgumentError,
      );
    },
  );

  test('UT-034 owned-output source protection lasts until independent output expiry', () async {
    final output = await process(retention: OutputRetention.hour);
    await repository.removeAssets([asset.id]);
    await expectLater(
      repository.purgeAssets(
        [asset.id],
        confirmCopies: true,
        confirmRecords: true,
      ),
      throwsStateError,
    );
    await withClock(Clock.fixed(output.expiresAt), repository.cleanupOutputs);
    expect(
      (await repository.purgeAssets(
        [asset.id],
        confirmCopies: true,
        confirmRecords: true,
      )).copiesRemoved,
      1,
    );
  });
}
