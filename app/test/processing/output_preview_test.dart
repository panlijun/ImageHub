import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/processing/application/output_preview_reader.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/processing/presentation/output_preview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('AT-002 actual output provider renders bounded in-memory image', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    await _mount(tester, fixture);
    await _wait(tester, () => find.byType(Image).evaluate().isNotEmpty);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    final pixels = img.decodePng((image.image as MemoryImage).bytes)!;
    expect([pixels.width, pixels.height], [8, 6]);
    expect(pixels.getPixel(0, 0).b, 179);
    expect(await _native(tester, () async => fixture.leases), 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'AT-002 unknown preview error uses safe copy and explicit retry actually rereads',
    (tester) async {
      final decoder = _RetryDecoder();
      final fixture = await _Fixture.create(tester, decoder: decoder);
      await _mount(tester, fixture);
      await _wait(tester, () => find.text('重试预览').evaluate().isNotEmpty);
      expect(find.text('结果预览读取失败，请重载检查；永久图片保留。'), findsOneWidget);
      expect(find.textContaining('secret-path'), findsNothing);
      expect(decoder.calls, 1);
      expect(await _native(tester, () async => fixture.leases), 0);
      await tester.tap(find.text('重试预览'));
      await _wait(tester, () => find.byType(Image).evaluate().isNotEmpty);
      expect(decoder.calls, 2);
      expect(decoder.actualReads, 1);
      expect(find.text('重试预览'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'AT-002 disposal during real file chunk keeps lease and close pending until IO completes',
    (tester) async {
      final decoder = _GateDecoder();
      final fixture = await _Fixture.create(
        tester,
        decoder: decoder,
        release: decoder.release,
      );
      Future<void>? closing;
      var closed = false;
      try {
        await _mount(tester, fixture);
        await _wait(tester, () => decoder.entered.isCompleted);
        expect(find.text('正在读取结果预览…'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(() async {
          closing = fixture.repository.close().then((_) {
            closed = true;
          });
        });
        await _tick(tester);
        await _tick(tester);
        expect(closed, false);
        expect(decoder.fileLoopFinished, false);
        expect(await _native(tester, () async => fixture.leases), 1);
        expect(fixture.repository.processingScheduler.activeCount, 1);
      } finally {
        decoder.release();
        if (closing != null) await _native(tester, () => closing!);
      }
      expect(closed, true);
      expect(decoder.fileLoopFinished, true);
      expect(await _native(tester, () async => fixture.leases), 0);
      expect(fixture.repository.processingScheduler.activeCount, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'AT-002 replacement revision refuses late old preview completion',
    (tester) async {
      final decoder = _RevisionDecoder();
      final fixture = await _Fixture.create(
        tester,
        decoder: decoder,
        release: decoder.release,
      );
      // Two smaller frozen permits let the invalidated old read and new read
      // overlap. This test exercises the revision notification contract; the
      // replacement byte source is an actual second PNG, not a restore commit.
      fixture.repository.processingScheduler.configure(2);
      await tester.runAsync(() async {
        final red = img.Image(width: 8, height: 6, numChannels: 4);
        img.fill(red, color: img.ColorRgba8(201, 42, 11, 255));
        decoder.replacementBytes = Uint8List.fromList(img.encodePng(red));
        decoder.replacementFile = File(
          '${fixture.root.path}/replacement-preview.png',
        );
        await decoder.replacementFile!.writeAsBytes(
          decoder.replacementBytes!,
          flush: true,
        );
      });
      try {
        await _mount(tester, fixture);
        await _wait(tester, () => decoder.entered.isCompleted);
        fixture.container
            .read(libraryReplacementRevisionProvider.notifier)
            .committed();
        await _wait(tester, () => find.byType(Image).evaluate().isNotEmpty);
        expect(decoder.calls, 2);
        expect(_displayedPixel(tester).r, 201);
        decoder.release();
        await _wait(
          tester,
          () => fixture.repository.processingScheduler.activeCount == 0,
        );
        expect(decoder.firstFinished, true);
        expect(_displayedPixel(tester).r, 201);
        expect(_displayedPixel(tester).b, 11);
        expect(find.text('重试预览'), findsNothing);
        expect(await _native(tester, () async => fixture.leases), 0);
        expect(tester.takeException(), isNull);
      } finally {
        decoder.release();
        await tester.pumpWidget(const SizedBox());
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

img.Pixel _displayedPixel(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  return img.decodePng((image.image as MemoryImage).bytes)!.getPixel(0, 0);
}

Future<void> _mount(WidgetTester tester, _Fixture fixture) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: fixture.container,
    child: MaterialApp(
      home: Scaffold(body: OutputPreview(outputId: fixture.output.id)),
    ),
  ),
);

Future<void> _tick(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250 && !ready(); i++) {
    await _tick(tester);
  }
  expect(
    ready(),
    true,
    reason: 'Actual native IO and fake-zone provider continuations must both drain.',
  );
  await _tick(tester);
}

Future<T> _native<T>(WidgetTester tester, Future<T> Function() action) async {
  var finished = false;
  T? result;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (value) {
          result = value;
          finished = true;
        },
        onError: (Object error) {
          failure = error;
          finished = true;
        },
      ),
    );
  });
  await _wait(tester, () => finished);
  if (failure != null) throw failure!;
  return result as T;
}

class _RetryDecoder extends OutputPreviewDecoder {
  int calls = 0;
  int actualReads = 0;
  @override
  Future<Uint8List> read(
    File file, {
    required int memoryBudgetBytes,
    required String expectedSha256,
    required int expectedByteCount,
  }) async {
    if (++calls == 1) throw _UnsafeError();
    actualReads++;
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
      throw StateError('secret-path must never be exposed or stringified');
}

class _GateDecoder extends OutputPreviewDecoder {
  final entered = Completer<void>();
  final gate = Completer<void>();
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
    await for (final chunk in file.openRead()) {
      expect(chunk, isNotEmpty);
      if (!entered.isCompleted) entered.complete();
      await gate.future;
    }
    fileLoopFinished = true;
    return super.read(
      file,
      memoryBudgetBytes: memoryBudgetBytes,
      expectedSha256: expectedSha256,
      expectedByteCount: expectedByteCount,
    );
  }
}

class _RevisionDecoder extends OutputPreviewDecoder {
  final entered = Completer<void>();
  final gate = Completer<void>();
  File? replacementFile;
  Uint8List? replacementBytes;
  int calls = 0;
  bool firstFinished = false;
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
    if (++calls == 1) {
      final original = await super.read(
        file,
        memoryBudgetBytes: memoryBudgetBytes,
        expectedSha256: expectedSha256,
        expectedByteCount: expectedByteCount,
      );
      entered.complete();
      await gate.future;
      firstFinished = true;
      return original;
    }
    return super.read(
      replacementFile!,
      memoryBudgetBytes: memoryBudgetBytes,
      expectedSha256: sha256.convert(replacementBytes!).toString(),
      expectedByteCount: replacementBytes!.length,
    );
  }
}

class _Fixture {
  _Fixture(this.root, this.repository, this.output, this.container);
  final Directory root;
  final LibraryRepository repository;
  final ProcessedOutput output;
  final ProviderContainer container;
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

  static Future<_Fixture> create(
    WidgetTester tester, {
    OutputPreviewDecoder decoder = const OutputPreviewDecoder(),
    void Function()? release,
  }) async {
    late Directory root;
    late LibraryRepository repository;
    late ProcessedOutput output;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('imagehost_preview_widget_');
      repository = await LibraryRepository.open(
        Directory('${root.path}/library'),
      );
      final picture = img.Image(width: 8, height: 6, numChannels: 4);
      img.fill(picture, color: img.ColorRgba8(38, 99, 179, 255));
      final asset = (await repository.importResource(
        PlatformResource(
          displayName: 'source.png',
          openRead: () => Stream.value(img.encodePng(picture)),
        ),
      )).asset!;
      output = await ProcessingCoordinator(repository).process(
        [asset.id],
        (inputs) => ProcessingRequest(
          operation: ProcessingOperation.crop,
          inputs: inputs,
          crop: const PixelCrop(0, 0, 8, 6),
        ),
        displayName: 'output.png',
      );
    });
    final session = LibrarySession(repository, const []);
    final container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith((_) async => session),
        outputPreviewDecoderProvider.overrideWithValue(decoder),
      ],
    );
    addTearDown(() async {
      release?.call();
      container.dispose();
      await _native(tester, session.close);
      await tester.runAsync(() => root.delete(recursive: true));
    });
    return _Fixture(root, repository, output, container);
  }
}
