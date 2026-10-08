import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/managed_file_store.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/settings/domain/device_settings.dart';
import 'package:imagehost/features/storage/domain/storage_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory sandbox, root;
  LibraryRepository? repository;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-storage-');
    root = Directory(p.join(sandbox.path, 'library'));
  });
  tearDown(() async {
    await repository?.close();
    repository = null;
    // Only the test-created temporary directory is recursively removed.
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, sandbox.absolute.path),
      true,
    );
    await sandbox.delete(recursive: true);
  });

  List<int> picture(int red) {
    final image = img.Image(width: 8, height: 6, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(red, 40, 90, 255));
    return img.encodePng(image);
  }

  Future<ImageAsset> add(int red) async {
    final result = await repository!.importResource(
      PlatformResource(
        displayName: '$red.png',
        openRead: () => Stream.value(picture(red)),
      ),
    );
    expect(result.status, ImportStatus.saved);
    return result.asset!;
  }

  List<Map<String, Object?>> sql(String query) {
    final db = sqlite3.open(
      p.join(root.path, 'library.sqlite'),
      mode: OpenMode.readOnly,
    );
    try {
      return [for (final row in db.select(query)) Map<String, Object?>.of(row)];
    } finally {
      db.close();
    }
  }

  List<Map<String, dynamic>> cacheRows() => [
    for (final row in sql(
      "SELECT value FROM library_metadata WHERE key LIKE 'thumbnail_cache_v1/%' ORDER BY key",
    ))
      Map<String, dynamic>.from(jsonDecode(row['value']! as String) as Map),
  ];

  void mutate(void Function(Database db) action) {
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      action(db);
    } finally {
      db.close();
    }
  }

  Future<void> close() async {
    await repository!.close();
    repository = null;
  }

  Future<int> physicalBytes() async {
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) ==
          FileSystemEntityType.file) {
        total += await File(entity.path).length();
      }
    }
    return total;
  }

  Future<File> loose(String relative, List<int> value) async {
    final file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(value, flush: true);
  }

  test('UT-086 SQL relationships classify disjoint real bytes and logical diagnostics separately', () async {
    repository = await LibraryRepository.open(root);
    final active = await add(10),
        recycled = await add(20),
        retained = await add(30);
    await repository!.removeAssets([recycled.id, retained.id]);
    await repository!.purgeAssets([retained.id], confirmRecords: true);
    final thumbnail = (await repository!.thumbnailFor(active))!;
    final output = await ProcessingCoordinator(repository!).process(
      [active.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.crop,
        inputs: inputs,
        crop: const PixelCrop(0, 0, 3, 2),
      ),
      displayName: 'crop.png',
    );
    expect(output.usable, true);
    await loose('staging/unclaimed.bin', [1, 2, 3]);
    await loose('other.bin', [4, 5]);
    final report = await repository!.loadStorageReport();
    expect(report.fileBytes.keys.toSet(), StorageCategory.values.toSet());
    expect(
      report.fileBytes[StorageCategory.permanent],
      active.version.byteCount,
    );
    expect(
      report.fileBytes[StorageCategory.recycled],
      recycled.version.byteCount,
    );
    expect(
      report.fileBytes[StorageCategory.retained],
      retained.version.byteCount,
    );
    expect(
      report.fileBytes[StorageCategory.thumbnails],
      await thumbnail.length(),
    );
    expect(
      report.fileBytes[StorageCategory.temporaryResults],
      await output.file!.length(),
    );
    expect(report.fileBytes[StorageCategory.staging], 3);
    expect(report.fileBytes[StorageCategory.untracked], 2);
    expect(report.fileBytes[StorageCategory.database], greaterThan(0));
    expect(report.totalFileBytes, await physicalBytes());
    final logical = sql('SELECT content_bytes FROM diagnostic_records')
        .fold<int>(0, (n, row) => n + (row['content_bytes']! as int));
    expect(report.diagnosticContentBytes, logical);
    expect(logical, greaterThan(0));
    expect(report.availableBytes, isNull);
    expect(report.warning, contains('未接入'));
    expect(sql('SELECT id FROM assets'), hasLength(2));
    expect(sql('SELECT id FROM versions'), hasLength(3));
  });

  test('UT-086 cleanup freezes selection and preserves later cache and unregistered files', () async {
    repository = await LibraryRepository.open(root);
    final a = await add(10), b = await add(20);
    final old = (await repository!.thumbnailFor(a))!;
    final unknown = await loose('cache/thumbnails/legacy.png', [7, 8, 9]);
    final plan = await repository!.prepareThumbnailCleanup();
    final later = (await repository!.thumbnailFor(b))!;
    expect(plan.count, 1);
    expect(plan.bytes, await old.length());
    expect(plan.untrackedBytes, 3);
    final result = await repository!.clearThumbnails(plan);
    expect(result.removed, 1);
    expect(result.failed, 0);
    expect(await old.exists(), false);
    expect(await later.exists(), true);
    expect(await unknown.readAsBytes(), [7, 8, 9]);
    expect(await repository!.verifyCopy(a), CopyAvailability.available);
  });

  test('UT-086 visible lease protects cache and requires reconfirmation after touch', () async {
    repository = await LibraryRepository.open(root);
    final asset = await add(10);
    final lease = (await repository!.acquireThumbnailLease(asset))!;
    try {
      final plan = await repository!.prepareThumbnailCleanup();
      expect(plan.count, 0);
      expect(plan.protectedCount, 1);
      expect(
        (await repository!.loadStorageReport()).protectedThumbnailBytes,
        await lease.file.length(),
      );
      expect((await repository!.clearThumbnails(plan)).protected, 1);
      expect(await lease.file.exists(), true);
    } finally {
      await lease.release();
    }
    final beforeTouch = await repository!.prepareThumbnailCleanup();
    final renewed = (await repository!.acquireThumbnailLease(asset))!;
    try {
      await expectLater(
        repository!.clearThumbnails(beforeTouch),
        throwsA(isA<StorageFailure>()),
      );
      expect(await renewed.file.exists(), true);
    } finally {
      await renewed.release();
    }
    expect(
      (await repository!.clearThumbnails(
        await repository!.prepareThumbnailCleanup(),
      )).removed,
      1,
    );
  });

  test('UT-086 one changed digest produces partial failure without deleting changed bytes', () async {
    repository = await LibraryRepository.open(root);
    final a = await add(10), b = await add(20);
    final changed = (await repository!.thumbnailFor(a))!;
    final valid = (await repository!.thumbnailFor(b))!;
    final plan = await repository!.prepareThumbnailCleanup();
    final original = await changed.readAsBytes();
    final changedBytes = original.toList()..[original.length - 1] ^= 1;
    await changed.writeAsBytes(changedBytes, flush: true);
    final result = await repository!.clearThumbnails(plan);
    expect(result.removed, 1);
    expect(result.failed, 1);
    expect(await valid.exists(), false);
    expect(await changed.readAsBytes(), changedBytes);
    expect(cacheRows(), hasLength(1));
    expect((await repository!.prepareThumbnailCleanup()).protectedCount, 1);
  });

  test('UT-086 cleanup plan owner and reopen epoch cannot authorize another session', () async {
    repository = await LibraryRepository.open(root);
    await repository!.thumbnailFor(await add(10));
    final plan = await repository!.prepareThumbnailCleanup();
    await close();
    repository = await LibraryRepository.open(root);
    await expectLater(
      repository!.clearThumbnails(plan),
      throwsA(isA<StorageFailure>()),
    );
    expect(cacheRows(), hasLength(1));
  });

  for (final boundary in [
    CacheBoundary.intent,
    CacheBoundary.stageOwned,
    CacheBoundary.prepared,
    CacheBoundary.published,
    CacheBoundary.ready,
  ]) {
    test(
      'UT-088 / IT-001 durable ${boundary.name} cache boundary recovers after normal close and reopen',
      () async {
        repository = await LibraryRepository.open(
          root,
          cacheFaultHook: (value) async {
            if (value == boundary) throw StateError('injected interruption');
          },
        );
        final asset = await add(10);
        expect(await repository!.thumbnailFor(asset), isNull);
        final oldRow = cacheRows().single;
        await close();
        repository = await LibraryRepository.open(root);
        final recovered = await repository!.thumbnailFor(asset);
        expect(recovered, isNotNull);
        expect(img.decodePng(await recovered!.readAsBytes()), isNotNull);
        expect(cacheRows().single['state'], 'ready');
        if ([CacheBoundary.published, CacheBoundary.ready].contains(boundary)) {
          expect(cacheRows().single['id'], oldRow['id']);
        } else {
          expect(cacheRows().single['id'], isNot(oldRow['id']));
        }
        expect(await File('${recovered.path}.part').exists(), false);
        expect(await repository!.verifyCopy(asset), CopyAvailability.available);
      },
    );
  }

  test(
    'UT-088 deletion journal resumes only the confirmed digest after reopen',
    () async {
      repository = await LibraryRepository.open(
        root,
        cacheFaultHook: (value) async {
          if (value == CacheBoundary.beforeDelete) {
            throw StateError('injected interruption');
          }
        },
      );
      final file = (await repository!.thumbnailFor(await add(10)))!;
      final result = await repository!.clearThumbnails(
        await repository!.prepareThumbnailCleanup(),
      );
      expect(result.failed, 1);
      expect(cacheRows().single['state'], 'deleting');
      expect(await file.exists(), true);
      await close();
      repository = await LibraryRepository.open(root);
      expect(await file.exists(), false);
      expect(cacheRows(), isEmpty);
    },
  );

  for (final boundary in [
    CacheBoundary.prepared,
    CacheBoundary.published,
    CacheBoundary.ready,
  ]) {
    test(
      'UT-086 ${boundary.name} changed hash is preserved by restart recovery',
      () async {
        repository = await LibraryRepository.open(
          root,
          cacheFaultHook: (value) async {
            if (value == boundary) throw StateError('injected interruption');
          },
        );
        final asset = await add(10);
        expect(await repository!.thumbnailFor(asset), isNull);
        final row = cacheRows().single;
        final suffix = boundary == CacheBoundary.prepared
            ? '.png.part'
            : '.png';
        final evidence = File(
          p.join(root.path, 'cache', 'thumbnails', '${row['id']}$suffix'),
        );
        final original = await evidence.readAsBytes();
        final changed = original.toList()..[original.length - 1] ^= 1;
        await evidence.writeAsBytes(changed, flush: true);
        await close();
        repository = await LibraryRepository.open(root);
        expect(await evidence.readAsBytes(), changed);
        expect(cacheRows().single['id'], row['id']);
        expect(cacheRows().single['state'], row['state']);
        expect((await repository!.prepareThumbnailCleanup()).count, 0);
        expect((await repository!.prepareThumbnailCleanup()).protectedCount, 1);
        expect(await repository!.verifyCopy(asset), CopyAvailability.available);
      },
    );
  }

  test(
    'UT-086 unacknowledged stage ownership is never reclaimed on reopen',
    () async {
      repository = await LibraryRepository.open(
        root,
        cacheFaultHook: (boundary) async {
          if (boundary == CacheBoundary.intent) {
            throw StateError('injected interruption');
          }
        },
      );
      final asset = await add(10);
      expect(await repository!.thumbnailFor(asset), isNull);
      final row = cacheRows().single;
      expect(row['stageOwned'], false);
      final stage = await loose('cache/thumbnails/${row['id']}.png.part', [
        11,
        22,
        33,
      ]);
      await close();
      repository = await LibraryRepository.open(root);
      expect(await stage.readAsBytes(), [11, 22, 33]);
      expect(cacheRows().single['state'], 'writing');
      expect(cacheRows().single['stageOwned'], false);
      expect((await repository!.prepareThumbnailCleanup()).protectedCount, 1);
      expect(
        (await repository!.loadStorageReport()).untrackedThumbnailBytes,
        3,
      );
      expect(await repository!.verifyCopy(asset), CopyAvailability.available);
    },
  );

  test('UT-086 before-delete rechecks same-length changed bytes and preserves journal', () async {
    File? thumbnail;
    List<int>? tampered;
    repository = await LibraryRepository.open(
      root,
      cacheFaultHook: (value) async {
        if (value == CacheBoundary.beforeDelete) {
          final value = await thumbnail!.readAsBytes();
          tampered = value.toList()..[value.length - 1] ^= 1;
          await thumbnail!.writeAsBytes(tampered!, flush: true);
        }
      },
    );
    thumbnail = (await repository!.thumbnailFor(await add(10)))!;
    final result = await repository!.clearThumbnails(
      await repository!.prepareThumbnailCleanup(),
    );
    expect(result.failed, 1);
    await close();
    repository = await LibraryRepository.open(root);
    expect(await thumbnail.readAsBytes(), tampered);
    expect(cacheRows().single['state'], 'deleting');
    expect((await repository!.loadStorageReport()).warning, isNotNull);
  });

  for (final future in [false, true]) {
    test(
      'UT-086 ${future ? 'future' : 'corrupt'} cache registration cannot overwrite index or files',
      () async {
        repository = await LibraryRepository.open(root);
        final asset = await add(10);
        final thumbnail = (await repository!.thumbnailFor(asset))!;
        final original = await thumbnail.readAsBytes();
        final row = cacheRows().single;
        await close();
        final invalid = future
            ? jsonEncode(row..['formatVersion'] = 99)
            : '{broken';
        mutate(
          (db) => db.execute(
            'UPDATE library_metadata SET value=? WHERE key=?',
            [invalid, 'thumbnail_cache_v1/${row['id']}'],
          ),
        );
        repository = await LibraryRepository.open(root);
        await expectLater(
          repository!.loadStorageReport(),
          throwsA(isA<StorageFailure>()),
        );
        await expectLater(
          repository!.prepareThumbnailCleanup(),
          throwsA(isA<StorageFailure>()),
        );
        expect(await repository!.thumbnailFor(asset), isNull);
        expect(
          sql(
            "SELECT value FROM library_metadata WHERE key LIKE 'thumbnail_cache_v1/%'",
          ).single['value'],
          invalid,
        );
        expect(await thumbnail.readAsBytes(), original);
      },
    );
  }

  test('UT-088 persisted use order survives backwards UTC and drives actual LRU deletion', () async {
    final newer = DateTime.utc(2026, 10, 7), older = DateTime.utc(2026, 10, 6);
    final deletions = <String>[];
    repository = await LibraryRepository.open(
      root,
      cacheFaultHook: (boundary) async {
        if (boundary == CacheBoundary.beforeDelete) {
          deletions.add(
            cacheRows().singleWhere((r) => r['state'] == 'deleting')['id']
                as String,
          );
        }
      },
    );
    final settings = await repository!.loadSettings();
    await repository!.saveSettings(
      settings,
      DeviceSettings(cacheLimitMiB: 64),
      defaultTargetIds: [],
    );
    final a = await add(10), b = await add(20), c = await add(30);
    await withClock(Clock.fixed(newer), () => repository!.thumbnailFor(a));
    await withClock(Clock.fixed(newer), () => repository!.thumbnailFor(b));
    final bRow = cacheRows().singleWhere((r) => r['versionId'] == b.version.id);
    await withClock(Clock.fixed(older), () => repository!.thumbnailFor(a));
    final aRow = cacheRows().singleWhere((r) => r['versionId'] == a.version.id);
    expect(aRow['lastUsedUtc'], lessThan(bRow['lastUsedUtc'] as int));
    expect(aRow['lastUseOrder'], greaterThan(bRow['lastUseOrder'] as int));
    await close();
    repository = await LibraryRepository.open(
      root,
      cacheFaultHook: (boundary) async {
        if (boundary == CacheBoundary.beforeDelete) {
          deletions.add(
            cacheRows().singleWhere((r) => r['state'] == 'deleting')['id']
                as String,
          );
        }
      },
    );
    expect(
      cacheRows().singleWhere((r) => r['id'] == aRow['id'])['lastUseOrder'],
      aRow['lastUseOrder'],
    );
    final unknown = await loose('cache/thumbnails/unknown-large.bin', []);
    final handle = await unknown.open(mode: FileMode.write);
    try {
      await handle.truncate(64 * 1024 * 1024);
    } finally {
      await handle.close();
    }
    // Logical length validates admission accounting, not allocated disk clusters.
    expect(await repository!.thumbnailFor(c), isNull);
    expect(deletions.first, bRow['id']);
    expect(await unknown.length(), 64 * 1024 * 1024);
    expect(
      (await repository!.loadStorageReport()).untrackedThumbnailBytes,
      64 * 1024 * 1024,
    );
    expect(await repository!.verifyCopy(a), CopyAvailability.available);
  });

  test('UT-088 capacity enforcement preserves display-held cache and charges unknown bytes', () async {
    repository = await LibraryRepository.open(root);
    final settings = await repository!.loadSettings();
    await repository!.saveSettings(
      settings,
      DeviceSettings(cacheLimitMiB: 64),
      defaultTargetIds: [],
    );
    final a = await add(10), b = await add(20);
    final lease = (await repository!.acquireThumbnailLease(a))!;
    try {
      final fileBytes = await lease.file.length();
      final unknown = await loose('cache/thumbnails/unregistered.bin', []);
      final handle = await unknown.open(mode: FileMode.write);
      try {
        await handle.truncate(64 * 1024 * 1024 - fileBytes);
      } finally {
        await handle.close();
      }
      expect(await repository!.thumbnailFor(b), isNull);
      expect(await lease.file.exists(), true);
      expect(cacheRows(), hasLength(1));
      final report = await repository!.loadStorageReport();
      expect(report.protectedThumbnailBytes, fileBytes);
      expect(report.untrackedThumbnailBytes, 64 * 1024 * 1024 - fileBytes);
      expect(report.warning, isNotNull);
      expect(
        (await repository!.clearThumbnails(
          await repository!.prepareThumbnailCleanup(),
        )).removed,
        0,
      );
      expect(await unknown.exists(), true);
    } finally {
      await lease.release();
    }
  });

  for (final chunkNumber in [0, 1, 2]) {
    test(
      'UT-086 low space at ${chunkNumber == 0 ? 'intent' : 'chunk $chunkNumber'} creates no fake asset and retry stays singular',
      () async {
        var available = chunkNumber == 0 ? 0 : 1024 * 1024 * 1024;
        repository = await LibraryRepository.open(
          root,
          availableStorageBytes: (_) async => available,
        );
        final bytes = picture(10);
        var progress = 0;
        Stream<List<int>> chunks() async* {
          if (chunkNumber == 1) available = 0;
          yield bytes.sublist(0, bytes.length ~/ 2);
          if (chunkNumber == 2) available = 0;
          yield bytes.sublist(bytes.length ~/ 2);
        }

        final result = await repository!.importResource(
          PlatformResource(displayName: 'source.png', openRead: chunks),
          onProgress: (p) {
            progress = p.bytesCopied;
          },
        );
        expect(result.status, ImportStatus.failed);
        expect(result.failure!.kind, FailureKind.lowSpace);
        expect((await repository!.listAssets()).total, 0);
        expect(sql('SELECT id FROM import_operations'), isEmpty);
        if (chunkNumber == 2) expect(progress, bytes.length ~/ 2);
        if (chunkNumber < 2) expect(progress, 0);
        available = 1024 * 1024 * 1024;
        await add(10);
        await close();
        repository = await LibraryRepository.open(
          root,
          availableStorageBytes: (_) async => available,
        );
        expect((await repository!.listAssets()).total, 1);
        expect(sql('SELECT id FROM import_operations'), isEmpty);
      },
    );
  }

  for (final invalid in ['throws', 'negative']) {
    test(
      'UT-086 $invalid free-space probe gives fixed failure and unknown report',
      () async {
        repository = await LibraryRepository.open(
          root,
          availableStorageBytes: (_) async {
            if (invalid == 'throws') {
              throw StateError('private synthetic secret');
            }
            return -1;
          },
        );
        final result = await repository!.importResource(
          PlatformResource(
            displayName: 'source.png',
            openRead: () => Stream.value(picture(10)),
          ),
        );
        expect(result.failure!.kind, FailureKind.storageUnavailable);
        expect(
          result.failure!.message,
          isNot(contains('private synthetic secret')),
        );
        expect(sql('SELECT id FROM import_operations'), isEmpty);
        final report = await repository!.loadStorageReport();
        expect(report.availableBytes, isNull);
        expect(report.warning, contains('无法确认'));
      },
    );
  }

  test('UT-086 processing checks required bytes before pixel output intent and releases input lease', () async {
    var available = 1024 * 1024 * 1024;
    var outputIntent = false;
    repository = await LibraryRepository.open(
      root,
      availableStorageBytes: (_) async => available,
      outputFaultHook: (_) async {
        outputIntent = true;
      },
    );
    final asset = await add(10);
    // Enough for margin alone, too small for the planned output and margin.
    available = 32 * 1024 * 1024;
    await expectLater(
      ProcessingCoordinator(repository!).process(
        [asset.id],
        (inputs) => ProcessingRequest(
          operation: ProcessingOperation.crop,
          inputs: inputs,
          crop: const PixelCrop(0, 0, 3, 2),
        ),
        displayName: 'crop.png',
      ),
      throwsA(
        isA<ResourceFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.lowSpace,
        ),
      ),
    );
    expect(outputIntent, false);
    expect(sql('SELECT id FROM processed_outputs'), isEmpty);
    expect(sql('SELECT id FROM file_leases'), isEmpty);
    expect(await repository!.verifyCopy(asset), CopyAvailability.available);
  });

  test('UT-086 exclusive cache publisher collision keeps existing target and prepared evidence', () async {
    File? collision;
    repository = await LibraryRepository.open(
      root,
      publishCacheExclusive: (source, target) async {
        collision = target;
        await target.writeAsBytes([8, 9, 10], flush: true);
        return false;
      },
    );
    final asset = await add(10);
    expect(await repository!.thumbnailFor(asset), isNull);
    expect(await collision!.readAsBytes(), [8, 9, 10]);
    expect(cacheRows().single['state'], 'prepared');
    await close();
    repository = await LibraryRepository.open(root);
    expect(await collision!.readAsBytes(), [8, 9, 10]);
    expect(cacheRows().any((row) => row['state'] == 'prepared'), true);
    expect((await repository!.loadStorageReport()).warning, isNotNull);
    expect(await repository!.verifyCopy(asset), CopyAvailability.available);
  });

  test('UT-086 equal-digest publication collision does not prove ownership on reopen', () async {
    File? collision, stage;
    List<int>? bytes;
    repository = await LibraryRepository.open(
      root,
      publishCacheExclusive: (source, target) async {
        stage = source;
        collision = target;
        bytes = await source.readAsBytes();
        // The destination exists independently. Equal content grants no ownership.
        await target.writeAsBytes(bytes!, flush: true);
        return false;
      },
    );
    final asset = await add(10);
    expect(await repository!.thumbnailFor(asset), isNull);
    final record = cacheRows().single;
    expect(record['state'], 'prepared');
    await close();
    repository = await LibraryRepository.open(root);
    expect(cacheRows().single['id'], record['id']);
    expect(cacheRows().single['state'], 'prepared');
    expect(await collision!.readAsBytes(), bytes);
    expect(await stage!.readAsBytes(), bytes);
    final plan = await repository!.prepareThumbnailCleanup();
    expect(plan.count, 0);
    expect(plan.protectedCount, 1);
    expect((await repository!.clearThumbnails(plan)).removed, 0);
    expect(await collision!.readAsBytes(), bytes);
    expect(await stage!.readAsBytes(), bytes);
    expect(await repository!.verifyCopy(asset), CopyAvailability.available);
    expect(await repository!.thumbnailFor(asset), isNull);
    expect(cacheRows().single['id'], record['id']);
    expect(await collision!.readAsBytes(), bytes);
    expect(await stage!.readAsBytes(), bytes);
  });

  test('UT-088 a protected cache read does not wait behind a later thumbnail writer', () async {
    final entered = Completer<void>(), resume = Completer<void>();
    var blockNext = false;
    repository = await LibraryRepository.open(
      root,
      cacheFaultHook: (boundary) async {
        if (blockNext && boundary == CacheBoundary.stageOwned) {
          if (!entered.isCompleted) entered.complete();
          await resume.future;
        }
      },
    );
    final first = await add(10), second = await add(20);
    final lease = (await repository!.acquireThumbnailLease(first))!;
    final expected = await lease.file.readAsBytes();
    blockNext = true;
    final writing = repository!.thumbnailFor(second);
    try {
      await entered.future.timeout(const Duration(seconds: 5));
      expect(
        await lease.readBytes().timeout(const Duration(seconds: 5)),
        expected,
      );
      expect(resume.isCompleted, false);
    } finally {
      if (!resume.isCompleted) resume.complete();
      await writing;
      await lease.release();
    }
  });

  test('UT-088 maintenance rejects a fresh read on an earlier display-only cache token', () async {
    repository = await LibraryRepository.open(root);
    final lease = (await repository!.acquireThumbnailLease(await add(10)))!;
    final hold = await repository!.acquireRestoreHold();
    try {
      await expectLater(lease.readBytes(), throwsA(isA<StorageFailure>()));
    } finally {
      await lease.release();
      await hold.release();
    }
    expect(
      await repository!.verifyCopy(
        (await repository!.listAssets()).items.single,
      ),
      CopyAvailability.available,
    );
  });

  for (final restoring in [false, true]) {
    test(
      'UT-088 actual file read blocks release and ${restoring ? 'restore drain' : 'close'} until chunk hook finishes',
      () async {
        final entered = Completer<void>(), resume = Completer<void>();
        repository = await LibraryRepository.open(
          root,
          cacheFaultHook: (boundary) async {
            if (boundary == CacheBoundary.reading) {
              if (!entered.isCompleted) entered.complete();
              await resume.future;
            }
          },
        );
        final asset = await add(10);
        final lease = (await repository!.acquireThumbnailLease(asset))!;
        final reading = lease.readBytes();
        Future<void>? releasing, closing;
        Future<LibraryRestoreHold>? holding;
        LibraryRestoreHold? hold;
        var released = false, drained = false;
        try {
          await entered.future.timeout(const Duration(seconds: 5));
          releasing = lease.release().then((_) {
            released = true;
          });
          if (restoring) {
            holding = repository!.acquireRestoreHold().then((value) {
              drained = true;
              return value;
            });
          } else {
            closing = repository!.close().then((_) {
              drained = true;
            });
          }
          await Future<void>.delayed(const Duration(milliseconds: 40));
          expect(released, false);
          expect(drained, false);
          await expectLater(
            repository!.acquireThumbnailLease(asset),
            throwsA(anything),
          );
        } finally {
          if (!resume.isCompleted) resume.complete();
          expect(await reading, isNotEmpty);
          await (releasing ?? lease.release());
          if (holding != null) {
            hold = await holding;
            await hold.release();
          }
          await closing;
        }
        expect(released, true);
        expect(drained, true);
      },
    );
  }

  test(
    'UT-088 display-only thumbnail hold does not obstruct library close',
    () async {
      repository = await LibraryRepository.open(root);
      final lease = (await repository!.acquireThumbnailLease(await add(10)))!;
      try {
        await repository!.close().timeout(const Duration(seconds: 5));
        // The read is rejected by the closed session, never starts real IO.
        await expectLater(lease.readBytes(), throwsA(anything));
      } finally {
        await lease.release();
      }
    },
  );

  test('UT-086 linked cache target is refused without following or deleting external bytes', () async {
    repository = await LibraryRepository.open(root);
    final asset = await add(10);
    final thumbnail = (await repository!.thumbnailFor(asset))!;
    final external = File(p.join(sandbox.path, 'external.png'));
    final bytes = await thumbnail.readAsBytes();
    await external.writeAsBytes(bytes, flush: true);
    await thumbnail.delete();
    final link = Link(thumbnail.path);
    var created = false;
    try {
      try {
        await link.create(external.path);
        created = true;
      } on FileSystemException {
        // No OS symlink privilege: still verify the fixed path guard contract.
        final files = await ManagedFileStore.open(
          Directory(p.join(sandbox.path, 'guard')),
        );
        try {
          await expectLater(
            files.file('../external.png'),
            throwsA(isA<ResourceFailure>()),
          );
        } finally {
          await files.close();
        }
        return;
      }
      await expectLater(
        repository!.prepareThumbnailCleanup(),
        throwsA(isA<ResourceFailure>()),
      );
      expect(await external.readAsBytes(), bytes);
      expect(
        await FileSystemEntity.type(link.path, followLinks: false),
        FileSystemEntityType.link,
      );
    } finally {
      if (created) await link.delete();
    }
  });
}
