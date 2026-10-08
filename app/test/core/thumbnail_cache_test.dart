import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/storage/domain/storage_models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'png_orientation_fixture.dart';

void main() {
  late Directory sandbox, root;
  LibraryRepository? repository;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'imagehost-cache-generation-',
    );
    root = Directory('${sandbox.path}/library');
    repository = await LibraryRepository.open(root);
  });
  tearDown(() async {
    await repository?.close();
    await sandbox.delete(recursive: true);
  });
  List<Map<String, dynamic>> records() {
    final db = sqlite3.open(
      '${root.path}/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return [
        for (final row in db.select(
          "SELECT value FROM library_metadata WHERE key LIKE 'thumbnail_cache_v1/%' ORDER BY key",
        ))
          Map<String, dynamic>.from(jsonDecode(row['value'] as String) as Map),
      ];
    } finally {
      db.close();
    }
  }

  void put(Map<String, dynamic> record) {
    final db = sqlite3.open('${root.path}/library.sqlite');
    try {
      db.execute('UPDATE library_metadata SET value=? WHERE key=?', [
        jsonEncode(record),
        'thumbnail_cache_v1/${record['id']}',
      ]);
    } finally {
      db.close();
    }
  }

  File file(Map<String, dynamic> record) =>
      File('${root.path}/cache/thumbnails/${record['id']}.png');
  Future<void> reopen({CacheFaultHook? cacheFaultHook}) async {
    await repository!.close();
    repository = null;
    repository = await LibraryRepository.open(
      root,
      cacheFaultHook: cacheFaultHook,
    );
  }

  Future<ImageAsset> seed() async {
    final encoded = addPngExif(
      img.encodePng(orientationMatrix()),
      orientationTiff(6),
    );
    return (await repository!.importResource(
      PlatformResource(
        displayName: 'cache-direction.png',
        openRead: () => Stream.value(encoded),
      ),
    )).asset!;
  }

  Future<Map<String, dynamic>> wrongOldCache(
    ImageAsset asset, {
    int generation = 1,
  }) async {
    await repository!.thumbnailFor(asset);
    final record = records().single;
    final wrong = img.encodePng(orientationMatrix());
    await file(record).writeAsBytes(wrong, flush: true);
    record['formatVersion'] = generation;
    record['sha'] = sha256.convert(wrong).toString();
    record['bytes'] = wrong.length;
    put(record);
    return record;
  }

  void expectCorrectPixels(Uint8List encoded) {
    final image = img.decodePng(encoded)!;
    expect([image.width, image.height, image.numFrames], [3, 2, 1]);
    for (final pixel in image) {
      expect([
        pixel.r,
        pixel.g,
        pixel.b,
        pixel.a,
      ], matrixPixel(orientedPixelIndices[6]![pixel.y * 3 + pixel.x]));
    }
  }

  test('LIB-001/IMG-005 valid old format 1 wrong pixels regenerate format 2 without deleting old or unknown bytes', () async {
    final asset = await seed();
    final old = await wrongOldCache(asset);
    final oldBytes = await file(old).readAsBytes();
    final unknown = await File('${root.path}/cache/thumbnails/unregistered.png')
        .writeAsBytes([9, 8, 7]);
    final fresh = (await repository!.acquireThumbnailLease(asset))!;
    try {
      expect(fresh.file.path, isNot(file(old).path));
      expectCorrectPixels(await fresh.readBytes());
      expect(records(), hasLength(2));
      expect(records().singleWhere((r) => r['id'] == old['id']), old);
      expect(
        records().singleWhere((r) => r['id'] != old['id'])['formatVersion'],
        2,
      );
      expect(await file(old).readAsBytes(), oldBytes);
      expect(await unknown.readAsBytes(), [9, 8, 7]);
      final cleanup = await repository!.prepareThumbnailCleanup();
      expect(cleanup.count, 1);
      expect(cleanup.protectedCount, 1);
      expect(cleanup.untrackedBytes, 3);
      expect((await repository!.clearThumbnails(cleanup)).removed, 1);
      expect(await file(old).exists(), false);
      expect(await fresh.file.exists(), true);
      expect(await unknown.readAsBytes(), [9, 8, 7]);
    } finally {
      await fresh.release();
    }
    final reused = (await repository!.acquireThumbnailLease(asset))!;
    try {
      expect(reused.file.path, fresh.file.path);
      expect(records().single['formatVersion'], 2);
      expectCorrectPixels(await reused.readBytes());
    } finally {
      await reused.release();
    }
  });

  test('LIB-001/IMG-005 old cache actual read remains protected until it completes while format 2 generation proceeds', () async {
    final entered = Completer<void>(), resume = Completer<void>();
    var holdRead = false;
    await reopen(
      cacheFaultHook: (boundary) async {
        if (holdRead && boundary == CacheBoundary.reading) {
          if (!entered.isCompleted) entered.complete();
          await resume.future;
        }
      },
    );
    final asset = await seed();
    // Acquire the old producer's valid hash/bytes before switching its persisted
    // generation. The lease retains the precise bytes it already confirmed.
    final old = await wrongOldCache(asset, generation: 2);
    final oldLease = (await repository!.acquireThumbnailLease(asset))!;
    final oldBytes = await oldLease.file.readAsBytes();
    final persisted = records().single..['formatVersion'] = 1;
    put(persisted);
    holdRead = true;
    final reading = oldLease.readBytes();
    ThumbnailLease? fresh;
    try {
      await entered.future.timeout(const Duration(seconds: 5));
      fresh = (await repository!.acquireThumbnailLease(asset))!;
      expect(fresh.file.path, isNot(oldLease.file.path));
      final whileReading = await repository!.prepareThumbnailCleanup();
      expect(whileReading.count, 0);
      expect(whileReading.protectedCount, 2);
      expect((await repository!.clearThumbnails(whileReading)).removed, 0);
      var released = false;
      final releasing = oldLease.release().then((_) => released = true);
      await Future<void>.delayed(Duration.zero);
      expect(released, false);
      resume.complete();
      expect(await reading, oldBytes);
      await releasing;
      expect(released, true);
      holdRead = false;
      expectCorrectPixels(await fresh.readBytes());
      final cleanup = await repository!.prepareThumbnailCleanup();
      expect(cleanup.count, 1);
      expect((await repository!.clearThumbnails(cleanup)).removed, 1);
      expect(await file(old).exists(), false);
      expect(await fresh.file.exists(), true);
    } finally {
      if (!resume.isCompleted) resume.complete();
      await reading;
      await oldLease.release();
      await fresh?.release();
    }
  });

  test('LIB-001 old format 1 published recovery preserves its generation and new lookup only reuses 2', () async {
    final asset = await seed();
    final old = await wrongOldCache(asset);
    await repository!.close();
    repository = null;
    put({...old, 'state': 'published', 'stageOwned': true});
    repository = await LibraryRepository.open(root);
    final recovered = records().single;
    expect(recovered['state'], 'ready');
    expect(recovered['stageOwned'], false);
    expect(recovered['formatVersion'], 1);
    final fresh = (await repository!.acquireThumbnailLease(asset))!;
    try {
      expectCorrectPixels(await fresh.readBytes());
      expect(
        records().singleWhere((r) => r['id'] == old['id'])['formatVersion'],
        1,
      );
      expect(
        records().singleWhere((r) => r['id'] != old['id'])['formatVersion'],
        2,
      );
    } finally {
      await fresh.release();
    }
  });

  test('LIB-001 old format 1 cleanup journal keeps generation when deletion fails and retries safely', () async {
    final asset = await seed();
    final old = await wrongOldCache(asset);
    var observed = false;
    await reopen(
      cacheFaultHook: (boundary) async {
        if (boundary == CacheBoundary.beforeDelete) {
          observed = true;
          final deleting = records().single;
          expect(deleting['state'], 'deleting');
          expect(deleting['formatVersion'], 1);
          throw StateError('fixture deletion failure');
        }
      },
    );
    final result = await repository!.clearThumbnails(
      await repository!.prepareThumbnailCleanup(),
    );
    expect(observed, true);
    expect(result.removed, 0);
    expect(result.failed, 1);
    expect(records().single['formatVersion'], 1);
    expect(await file(old).exists(), true);
    await reopen();
    expect(records(), isEmpty);
    expect(await file(old).exists(), false);
  });

  test('LIB-001 old generation cache changed after confirmation retains its actual changed bytes', () async {
    final asset = await seed();
    final old = await wrongOldCache(asset);
    final fresh = (await repository!.acquireThumbnailLease(asset))!;
    try {
      final plan = await repository!.prepareThumbnailCleanup();
      expect(plan.count, 1);
      await file(old).writeAsBytes([1, 5, 9], flush: true);
      final result = await repository!.clearThumbnails(plan);
      expect(result.removed, 0);
      expect(result.failed, 1);
      expect(await file(old).readAsBytes(), [1, 5, 9]);
      expect(
        records().singleWhere((r) => r['id'] == old['id'])['formatVersion'],
        1,
      );
      expectCorrectPixels(await fresh.readBytes());
    } finally {
      await fresh.release();
    }
  });

  for (final generation in [0, 3]) {
    test(
      'LIB-001 unknown cache format $generation rejects before reuse or deletion and retains exact index/bytes',
      () async {
        final asset = await seed();
        final record = await wrongOldCache(asset, generation: generation);
        final before = records(), bytes = await file(record).readAsBytes();
        await expectLater(
          repository!.acquireThumbnailLease(asset),
          throwsA(isA<StorageFailure>()),
        );
        await expectLater(
          repository!.prepareThumbnailCleanup(),
          throwsA(isA<StorageFailure>()),
        );
        expect(records(), before);
        expect(await file(record).readAsBytes(), bytes);
        expect(await repository!.verifyCopy(asset), CopyAvailability.available);
      },
    );
  }
}
