import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashing;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/application/original_preview_reader.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.create());
  tearDown(() async => fixture.dispose());

  test('UT-026/IT-002 original encoded animation and fresh asset survive without thumbnail substitution', () async {
    fixture.withDatabase((db) {
      db.execute('UPDATE assets SET display_name = ? WHERE id = ?', [
        'fresh.gif',
        fixture.asset.id,
      ]);
    });
    final input = await OriginalPreviewReader(fixture.repository)
        .read(fixture.asset);
    try {
      expect(input.bytes, fixture.bytes);
      expect(input.asset.displayName, 'fresh.gif');
      expect(input.asset.version, fixture.asset.version);
      final decoded = img.decodeGif(input.bytes)!;
      expect(decoded.numFrames, 2);
      expect(decoded.getFrame(0).getPixel(0, 0).r, 255);
      expect(decoded.getFrame(1).getPixel(0, 0).b, 255);
      expect(fixture.leases, 0);
      expect(fixture.repository.processingScheduler.activeCount, 1);
      expect(input.memoryBudgetBytes, fixture.repository.processingBudgetBytes);
      expect(await fixture.original.readAsBytes(), fixture.bytes);
    } finally {
      input.release();
      input.release();
    }
    expect(fixture.repository.processingScheduler.activeCount, 0);
  });

  test('UT-026/IT-002 old asset version cannot preview a newly assigned permanent version', () async {
    final picture = img.Image(width: 3, height: 3);
    final other = (await fixture.repository.importResource(
      PlatformResource(
        displayName: 'second.png',
        openRead: () => Stream.value(img.encodePng(picture)),
      ),
    )).asset!;
    fixture.withDatabase((db) {
      db.execute('UPDATE assets SET version_id = ? WHERE id = ?', [
        other.version.id,
        fixture.asset.id,
      ]);
    });
    final decoder = _ChunkDecoder();
    await expectLater(
      OriginalPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read(fixture.asset),
      _fails(FailureKind.unavailable),
    );
    expect(decoder.calls, 0);
    expect(fixture.leases, 0);
    expect(fixture.repository.processingScheduler.activeCount, 0);
  });

  for (final missing in [false, true]) {
    test(
      'UT-026/IT-002 ${missing ? 'missing' : 'damaged'} permanent bytes refuse preview before decoding',
      () async {
        if (missing) {
          await fixture.original.delete();
        } else {
          final changed = Uint8List.fromList(fixture.bytes);
          changed[changed.length - 1] ^= 1;
          await fixture.original.writeAsBytes(changed, flush: true);
        }
        final decoder = _ChunkDecoder();
        await expectLater(
          OriginalPreviewReader(
            fixture.repository,
            decoder: decoder,
          ).read(fixture.asset),
          _fails(FailureKind.unavailable),
        );
        expect(decoder.calls, 0);
        expect(fixture.leases, 0);
        expect(fixture.repository.processingScheduler.activeCount, 0);
      },
    );
  }

  test('UT-026 production isolate revalidates SHA, length and bounded input budget', () async {
    const decoder = OriginalPreviewDecoder();
    final version = fixture.asset.version;
    Future<Uint8List> read({int? budget, String? digest, int? count}) =>
        decoder.read(
          fixture.original,
          memoryBudgetBytes: budget ?? fixture.repository.processingBudgetBytes,
          expectedSha256: digest ?? version.sha256,
          expectedByteCount: count ?? version.byteCount,
        );
    await expectLater(read(digest: '0' * 64), _fails(FailureKind.invalidImage));
    await expectLater(
      read(count: version.byteCount + 1),
      _fails(FailureKind.invalidImage),
    );
    await expectLater(
      read(budget: version.byteCount * 4 - 1),
      _fails(FailureKind.resourceBudget),
    );
    expect(await read(), fixture.bytes);
    await fixture.original.delete();
    await expectLater(read(), _fails(FailureKind.unavailable));
  });

  test('UT-026/IT-002 changed bytes after lease acquisition refuse successful input', () async {
    final decoder = _ChunkDecoder();
    final failed = expectLater(
      OriginalPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read(fixture.asset),
      _fails(FailureKind.invalidImage),
    );
    try {
      await decoder.entered.future.timeout(const Duration(seconds: 5));
      final changed = Uint8List.fromList(fixture.bytes);
      changed[changed.length - 1] ^= 1;
      await fixture.original.writeAsBytes(changed, flush: true);
    } finally {
      decoder.release();
      await failed;
    }
    expect(fixture.leases, 0);
    expect(fixture.repository.processingScheduler.activeCount, 0);
  });

  test('UT-026/IT-002 cancelled real chunk read protects purge until actual IO returns', () async {
    final decoder = _ChunkDecoder();
    final token = CancellationToken();
    final cancelled = expectLater(
      OriginalPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read(fixture.asset, cancellation: token),
      _fails(FailureKind.cancelled),
    );
    try {
      await decoder.entered.future.timeout(const Duration(seconds: 5));
      token.cancel();
      await fixture.repository.removeAssets([fixture.asset.id]);
      await expectLater(
        fixture.repository.purgeAssets(
          [fixture.asset.id],
          confirmRecords: true,
          confirmCopies: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(fixture.leases, 1);
      expect(fixture.repository.processingScheduler.activeCount, 1);
      expect(decoder.fileLoopFinished, false);
    } finally {
      decoder.release();
      await cancelled;
    }
    expect(decoder.fileLoopFinished, true);
    expect(fixture.leases, 0);
    expect(fixture.repository.processingScheduler.activeCount, 0);
    final purged = await fixture.repository.purgeAssets(
      [fixture.asset.id],
      confirmRecords: true,
      confirmCopies: true,
    );
    expect(purged.copiesRemoved, 1);
  });

  test('UT-026/IT-002 close waits for cancelled actual IO before releasing library', () async {
    final decoder = _ChunkDecoder();
    final token = CancellationToken();
    final cancelled = expectLater(
      OriginalPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read(fixture.asset, cancellation: token),
      _fails(FailureKind.cancelled),
    );
    Future<void>? closing;
    var closed = false;
    try {
      await decoder.entered.future.timeout(const Duration(seconds: 5));
      token.cancel();
      closing = fixture.repository.close().then((_) => closed = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(closed, false);
      expect(fixture.leases, 1);
      expect(decoder.fileLoopFinished, false);
    } finally {
      decoder.release();
      await cancelled;
      await closing;
    }
    expect(closed, true);
    expect(decoder.fileLoopFinished, true);
    expect(fixture.repository.processingScheduler.activeCount, 0);
  });

  test('UT-026 shared budget survives file release until SDK consumer releases input', () async {
    final input = await OriginalPreviewReader(fixture.repository)
        .read(fixture.asset);
    expect(fixture.leases, 0);
    var closed = false;
    final closing = fixture.repository.close().then((_) => closed = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(closed, false);
      expect(fixture.repository.processingScheduler.activeCount, 1);
    } finally {
      input.release();
      input.release();
      await closing;
    }
    expect(closed, true);
    expect(fixture.repository.processingScheduler.activeCount, 0);
  });

  test('UT-026 queued cancellation releases only its lease while first input owns budget', () async {
    final first = await OriginalPreviewReader(fixture.repository)
        .read(fixture.asset);
    final decoder = _ChunkDecoder();
    final token = CancellationToken();
    final cancelled = expectLater(
      OriginalPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read(fixture.asset, cancellation: token),
      _fails(FailureKind.cancelled),
    );
    try {
      await _waitFor(() => fixture.leases == 1);
      token.cancel();
      await cancelled;
      expect(fixture.leases, 0);
      expect(decoder.calls, 0);
      expect(fixture.repository.processingScheduler.activeCount, 1);
    } finally {
      token.cancel();
      first.release();
      await cancelled;
    }
    expect(fixture.repository.processingScheduler.activeCount, 0);
  });

  test('UT-026 decoder failure never stringifies unknown objects and drains protection', () async {
    final decoder = _ChunkDecoder(failure: _UnsafeError());
    final failed = expectLater(
      OriginalPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read(fixture.asset),
      _fails(FailureKind.storage),
    );
    try {
      await decoder.entered.future.timeout(const Duration(seconds: 5));
    } finally {
      decoder.release();
      await failed;
    }
    expect(fixture.leases, 0);
    expect(fixture.repository.processingScheduler.activeCount, 0);
  });

  test('UT-026/IT-002 lease SQL cleanup failure retains row but drains ended IO budget and close', () async {
    final decoder = _ChunkDecoder();
    final failed = expectLater(
      OriginalPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read(fixture.asset),
      _fails(FailureKind.storage),
    );
    try {
      await decoder.entered.future.timeout(const Duration(seconds: 5));
      fixture.withDatabase((db) {
        db.execute(
          "CREATE TRIGGER reject_preview_release BEFORE DELETE ON file_leases BEGIN SELECT RAISE(ABORT, 'injected'); END",
        );
      });
    } finally {
      decoder.release();
      await failed;
    }
    expect(decoder.fileLoopFinished, true);
    expect(fixture.leases, 1);
    expect(fixture.repository.processingScheduler.activeCount, 0);
    await fixture.repository.close().timeout(const Duration(seconds: 2));
    fixture.withDatabase(
      (db) => db.execute('DROP TRIGGER reject_preview_release'),
    );
  });
}

Matcher _fails(FailureKind kind) =>
    throwsA(isA<ResourceFailure>().having((e) => e.kind, 'kind', kind));

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), true);
}

/// Gates a real file chunk. Release then exercises the production isolate.
class _ChunkDecoder extends OriginalPreviewDecoder {
  _ChunkDecoder({this.failure});
  final Object? failure;
  final entered = Completer<void>();
  final gate = Completer<void>();
  int calls = 0;
  bool fileLoopFinished = false;
  void release() {
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<Uint8List> read(
    File file, {
    required int memoryBudgetBytes,
    required String expectedSha256,
    required int expectedByteCount,
  }) async {
    calls++;
    await for (final chunk in file.openRead()) {
      expect(chunk, isNotEmpty);
      if (!entered.isCompleted) entered.complete();
      await gate.future;
    }
    fileLoopFinished = true;
    if (failure != null) throw failure!;
    return super.read(
      file,
      memoryBudgetBytes: memoryBudgetBytes,
      expectedSha256: expectedSha256,
      expectedByteCount: expectedByteCount,
    );
  }
}

class _UnsafeError {
  @override
  String toString() =>
      throw StateError('Unknown objects must not be stringified');
}

class _Fixture {
  _Fixture(this.root, this.repository, this.asset, this.original, this.bytes);
  final Directory root;
  final LibraryRepository repository;
  final ImageAsset asset;
  final File original;
  final List<int> bytes;
  int get leases =>
      withDatabase((db) => db.select('SELECT id FROM file_leases').length);

  T withDatabase<T>(T Function(Database db) action) {
    final db = sqlite3.open('${root.path}/library/library.sqlite');
    try {
      return action(db);
    } finally {
      db.close();
    }
  }

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'imagehost_original_preview_',
    );
    final repository = await LibraryRepository.open(
      Directory('${root.path}/library'),
    );
    final red = img.Image(width: 40, height: 20, numChannels: 4);
    img.fill(red, color: img.ColorRgba8(255, 0, 0, 255));
    final blue = img.Image(width: 40, height: 20, numChannels: 4);
    img.fill(blue, color: img.ColorRgba8(0, 0, 255, 255));
    red.addFrame(blue);
    final bytes = img.encodeGif(red);
    final asset = (await repository.importResource(
      PlatformResource(
        displayName: 'animation.gif',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    expect(asset.version.frameCount, 2);
    expect(asset.version.sha256, hashing.sha256.convert(bytes).toString());
    return _Fixture(
      root,
      repository,
      asset,
      await repository.originalFor(asset),
      bytes,
    );
  }

  Future<void> dispose() async {
    await repository.close();
    await root.delete(recursive: true);
  }
}
