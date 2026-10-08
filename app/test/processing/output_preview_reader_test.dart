import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/output_preview_reader.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.create());
  tearDown(() async => fixture.dispose());

  test(
    'UT-034 bounded real output preview preserves pixels and source bytes',
    () async {
      final before = await fixture.output.file!.readAsBytes();
      final preview = await OutputPreviewReader(fixture.repository)
          .read(fixture.output.id);
      expect(preview.length, lessThanOrEqualTo(2 * 1024 * 1024));
      final decoded = img.decodePng(preview)!;
      expect(decoded.width, 480);
      expect(decoded.height, 320);
      final pixel = decoded.getPixel(240, 160);
      expect([pixel.r, pixel.g, pixel.b, pixel.a], [38, 99, 179, 255]);
      expect(await fixture.output.file!.readAsBytes(), before);
      expect(await fixture.original.readAsBytes(), fixture.originalBytes);
      expect(fixture.leases, 0);
      expect(fixture.repository.processingScheduler.activeCount, 0);
    },
  );

  test(
    'UT-034 same-size changed bytes fail production decoder SHA validation',
    () async {
      final bytes = await fixture.output.file!.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      await fixture.output.file!.writeAsBytes(bytes, flush: true);
      final version = fixture.output.version!;
      await expectLater(
        const OutputPreviewDecoder().read(
          fixture.output.file!,
          memoryBudgetBytes: 128 * 1024 * 1024,
          expectedSha256: version.sha256,
          expectedByteCount: version.byteCount,
        ),
        throwsA(
          isA<ResourceFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.invalidImage,
          ),
        ),
      );
      expect(await fixture.output.file!.length(), version.byteCount);
    },
  );

  test('UT-034 missing and unusable outputs never enter decoder or leak protection', () async {
    final decoder = _ChunkDecoder();
    await fixture.output.file!.delete();
    await expectLater(
      OutputPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read(fixture.output.id),
      throwsA(isA<ProcessingFailure>()),
    );
    expect(
      (await fixture.repository.getOutput(fixture.output.id)).usable,
      false,
    );
    await expectLater(
      OutputPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read('absent-output'),
      throwsA(isA<ProcessingFailure>()),
    );
    expect(decoder.calls, 0);
    expect(fixture.leases, 0);
    expect(fixture.repository.processingScheduler.activeCount, 0);
  });

  test('UT-037 cancellation during real chunk IO retains lease and expiry protection until return', () async {
    final decoder = _ChunkDecoder();
    final token = CancellationToken();
    final read = OutputPreviewReader(
      fixture.repository,
      decoder: decoder,
    ).read(fixture.output.id, cancellation: token);
    final cancelled = expectLater(
      read,
      throwsA(
        isA<ProcessingFailure>().having(
          (e) => e.kind,
          'kind',
          ProcessingFailureKind.cancelled,
        ),
      ),
    );
    try {
      await decoder.entered.future.timeout(const Duration(seconds: 5));
      token.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fixture.leases, 1);
      expect(fixture.repository.processingScheduler.activeCount, 1);
      final cleanup = await withClock(
        Clock.fixed(fixture.output.expiresAt),
        fixture.repository.cleanupOutputs,
      );
      expect(cleanup.removed, 0);
      expect(cleanup.protected, 1);
      expect(await fixture.output.file!.exists(), true);
    } finally {
      decoder.release();
      await cancelled;
    }
    expect(decoder.fileLoopFinished, true);
    expect(fixture.leases, 0);
    expect(fixture.repository.processingScheduler.activeCount, 0);
    final cleanup = await withClock(
      Clock.fixed(fixture.output.expiresAt),
      fixture.repository.cleanupOutputs,
    );
    expect(cleanup.removed, 1);
  });

  for (final restore in [false, true]) {
    test(
      'UT-102 ${restore ? 'restore drain' : 'close'} waits for actual preview file loop and decoder',
      () async {
        final decoder = _ChunkDecoder();
        final reading = OutputPreviewReader(
          fixture.repository,
          decoder: decoder,
        ).read(fixture.output.id);
        var settled = false;
        LibraryRestoreHold? hold;
        Future<void>? draining;
        try {
          await decoder.entered.future.timeout(const Duration(seconds: 5));
          draining =
              (restore
                      ? fixture.repository.acquireRestoreHold().then((value) {
                          hold = value;
                        })
                      : fixture.repository.close())
                  .then((_) {
                    settled = true;
                  });
          await Future<void>.delayed(const Duration(milliseconds: 40));
          expect(settled, false);
          expect(decoder.fileLoopFinished, false);
          expect(fixture.leases, 1);
          expect(fixture.repository.processingScheduler.activeCount, 1);
        } finally {
          decoder.release();
          await reading;
          await draining;
          await hold?.release();
        }
        expect(settled, true);
        expect(decoder.fileLoopFinished, true);
        expect(fixture.leases, 0);
        expect(fixture.repository.processingScheduler.activeCount, 0);
      },
    );
  }

  test('UT-102 queued preview cancellation releases only its own lease and never takes running permit', () async {
    final decoder = _ChunkDecoder();
    final reader = OutputPreviewReader(fixture.repository, decoder: decoder);
    final first = reader.read(fixture.output.id);
    final token = CancellationToken();
    Future<void>? cancelled;
    try {
      await decoder.entered.future.timeout(const Duration(seconds: 5));
      final second = reader.read(fixture.output.id, cancellation: token);
      cancelled = expectLater(
        second,
        throwsA(
          isA<ProcessingFailure>().having(
            (e) => e.kind,
            'kind',
            ProcessingFailureKind.cancelled,
          ),
        ),
      );
      for (var i = 0; i < 100 && fixture.leases != 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(fixture.leases, 2);
      expect(decoder.calls, 1);
      token.cancel();
      await cancelled;
      expect(fixture.leases, 1);
      expect(fixture.repository.processingScheduler.activeCount, 1);
      expect(decoder.calls, 1);
    } finally {
      token.cancel();
      decoder.release();
      await cancelled;
      await first;
    }
    expect(fixture.leases, 0);
    expect(fixture.repository.processingScheduler.activeCount, 0);
  });

  test('UT-034 unknown decoder failure is safe and releases lease and budget for next read', () async {
    final decoder = _ChunkDecoder(failure: _UnsafeError());
    final failed = expectLater(
      OutputPreviewReader(
        fixture.repository,
        decoder: decoder,
      ).read(fixture.output.id),
      throwsA(
        isA<ProcessingFailure>().having(
          (e) => e.message,
          'message',
          '结果预览无法安全读取，请重载检查；永久图片保留。',
        ),
      ),
    );
    try {
      await decoder.entered.future.timeout(const Duration(seconds: 5));
    } finally {
      decoder.release();
      await failed;
    }
    expect(fixture.leases, 0);
    expect(fixture.repository.processingScheduler.activeCount, 0);
    expect(
      await OutputPreviewReader(fixture.repository).read(fixture.output.id),
      isNotEmpty,
    );
  });
}

/// Gates a real File.openRead chunk, then exercises the production isolate.
/// The gate is at the replaceable decoder boundary, not inside that isolate.
class _ChunkDecoder extends OutputPreviewDecoder {
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
      throw StateError('Unknown errors must never be stringified');
}

class _Fixture {
  _Fixture(
    this.root,
    this.repository,
    this.output,
    this.original,
    this.originalBytes,
  );
  final Directory root;
  final LibraryRepository repository;
  final ProcessedOutput output;
  final File original;
  final List<int> originalBytes;
  int get leases {
    final db = sqlite3.open(
      '${root.path}/library/library.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      return db.select('SELECT id FROM output_leases').length;
    } finally {
      db.close();
    }
  }

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'imagehost_preview_reader_',
    );
    final repository = await LibraryRepository.open(
      Directory('${root.path}/library'),
    );
    final picture = img.Image(width: 960, height: 640, numChannels: 4);
    img.fill(picture, color: img.ColorRgba8(38, 99, 179, 255));
    final bytes = img.encodePng(picture);
    final ImageAsset asset = (await repository.importResource(
      PlatformResource(
        displayName: 'source.png',
        openRead: () => Stream.value(bytes),
      ),
    )).asset!;
    final output = await ProcessingCoordinator(repository).process(
      [asset.id],
      (inputs) => ProcessingRequest(
        operation: ProcessingOperation.crop,
        inputs: inputs,
        crop: const PixelCrop(0, 0, 960, 640),
      ),
      displayName: 'output.png',
      retention: OutputRetention.hour,
    );
    return _Fixture(
      root,
      repository,
      output,
      await repository.originalFor(asset),
      bytes,
    );
  }

  Future<void> dispose() async {
    await repository.close();
    await root.delete(recursive: true);
  }
}
