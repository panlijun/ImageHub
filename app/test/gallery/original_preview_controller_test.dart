import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/application/original_preview_reader.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/original_preview_controller.dart';
import 'package:imagehost/platform/image_preview_codec.dart';

void main() {
  testWidgets(
    'UT-026/IT-002 SDK previews real PNG JPEG WebP GIF BMP permanent bytes',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      for (final format in ['png', 'jpg', 'webp', 'gif', 'bmp']) {
        final asset = await fixture.import(tester, format: format);
        var stage = 'reader';
        final decoder = _DiagnosticDecoder();
        final controller = fixture.controller(
          asset,
          loader: (token) async {
            try {
              final input = await OriginalPreviewReader(
                fixture.repository,
                decoder: decoder,
              ).read(asset, cancellation: token);
              stage = 'codec';
              return input;
            } catch (failure) {
              stage =
                  'reader/${_failureCategory(failure)}; decoder=${decoder.failureCategory ?? 'none'}';
              rethrow;
            }
          },
          codecFactory: (input) async {
            try {
              final codec = await _decode(input);
              stage = 'first-frame';
              return codec;
            } catch (failure) {
              stage = 'codec/${_failureCategory(failure)}';
              rethrow;
            }
          },
        );
        unawaited(controller.start());
        await _wait(
          tester,
          () => controller.image != null || controller.error != null,
        );
        expect(controller.error, isNull, reason: '$format; $stage');
        expect([controller.image!.width, controller.image!.height], [8, 6]);
        expect(controller.frameCount, 1, reason: format);
        expect(controller.playing, false);
        final pixel = await _pixel(tester, controller);
        expect(pixel[0], greaterThan(245), reason: format);
        expect(pixel[1], lessThan(10), reason: format);
        expect(pixel[2], lessThan(10), reason: format);
        expect(fixture.repository.processingScheduler.activeCount, 1);
        await _native(tester, controller.close);
        expect(fixture.repository.processingScheduler.activeCount, 0);
      }
    },
  );

  testWidgets(
    'UT-026/IT-002 SDK plays original animated GIF and WebP sequential pixels',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      for (final format in ['gif', 'webp']) {
        final asset = await fixture.import(
          tester,
          format: format,
          animated: true,
        );
        expect(asset.version.frameCount, 2);
        final controller = fixture.controller(asset);
        unawaited(controller.start());
        await _wait(
          tester,
          () => controller.image != null || controller.error != null,
        );
        expect(controller.error, isNull, reason: format);
        expect(controller.frameCount, 2);
        expect(controller.frameIndex, 0);
        expect(await _pixel(tester, controller), [255, 0, 0, 255]);
        await tester.pump(const Duration(milliseconds: 100));
        await _wait(tester, () => controller.frameIndex == 1);
        expect(await _pixel(tester, controller), [0, 0, 255, 255]);
        await _native(tester, controller.close);
      }
    },
  );

  testWidgets(
    'UT-026 pause preserves displayed pixels and resumes the already decoded pending frame',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final asset = await fixture.import(tester, animated: true);
      late _ControlledCodec codec;
      final controller = fixture.controller(
        asset,
        codecFactory: (input) async {
          codec = _ControlledCodec(await _decode(input), gateCall: 2);
          fixture.releaseOnCleanup.add(codec.release);
          return codec;
        },
      );
      unawaited(controller.start());
      await _wait(tester, () => controller.image != null);
      final first = controller.image;
      await tester.pump(const Duration(milliseconds: 100));
      await _wait(tester, () => codec.entered.isCompleted);
      controller.pause();
      codec.release();
      await _wait(tester, () => codec.completedCalls == 2);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.image, same(first));
      expect(controller.frameIndex, 0);
      expect(await _pixel(tester, controller), [255, 0, 0, 255]);
      expect(codec.calls, 2);
      expect(first!.debugDisposed, false);
      controller.play();
      await tester.pump(const Duration(milliseconds: 100));
      await _wait(tester, () => controller.frameIndex == 1);
      expect(await _pixel(tester, controller), [0, 0, 255, 255]);
      expect(
        codec.calls,
        2,
        reason: 'Resume must consume pending frame before decoding another.',
      );
      expect(first.debugDisposed, true);
      await _native(tester, controller.close);
    },
  );

  testWidgets(
    'UT-026 foreground suspension preserves pending frame and does not override user pause',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final asset = await fixture.import(tester, animated: true);
      late _ControlledCodec codec;
      final controller = fixture.controller(
        asset,
        codecFactory: (input) async {
          codec = _ControlledCodec(await _decode(input), gateCall: 2);
          fixture.releaseOnCleanup.add(codec.release);
          return codec;
        },
      );
      unawaited(controller.start());
      await _wait(tester, () => controller.image != null);
      await tester.pump(const Duration(milliseconds: 100));
      await _wait(tester, () => codec.entered.isCompleted);
      controller.setForeground(false);
      codec.release();
      await _wait(tester, () => codec.completedCalls == 2);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.frameIndex, 0);
      expect(await _pixel(tester, controller), [255, 0, 0, 255]);
      controller.setForeground(true);
      await tester.pump(const Duration(milliseconds: 100));
      await _wait(tester, () => controller.frameIndex == 1);
      expect(codec.calls, 2);
      expect(await _pixel(tester, controller), [0, 0, 255, 255]);
      controller.pause();
      controller.setForeground(false);
      controller.setForeground(true);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.playing, false);
      expect(controller.frameIndex, 1);
      expect(codec.calls, 2);
      await _native(tester, controller.close);
    },
  );

  testWidgets(
    'UT-026 finite SDK repetition stops at final frame and explicit play restarts',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final asset = await fixture.import(tester, animated: true);
      for (final repeats in [0, 1]) {
        late _ControlledCodec codec;
        final controller = fixture.controller(
          asset,
          codecFactory: (input) async {
            codec = _ControlledCodec(
              await _decode(input),
              repetitions: repeats,
            );
            return codec;
          },
        );
        unawaited(controller.start());
        await _wait(tester, () => controller.image != null);
        final expectedFrames = 2 * (repeats + 1);
        for (var displayed = 1; displayed < expectedFrames; displayed++) {
          await tester.pump(const Duration(milliseconds: 100));
          await _wait(tester, () => codec.completedCalls == displayed + 1);
          expect(controller.frameIndex, displayed % 2);
        }
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.playing, false);
        expect(controller.frameIndex, 1);
        expect(await _pixel(tester, controller), [0, 0, 255, 255]);
        await tester.pump(const Duration(seconds: 10));
        expect(codec.calls, expectedFrames);
        controller.play();
        await tester.pump(const Duration(milliseconds: 100));
        await _wait(tester, () => controller.frameIndex == 0);
        expect(await _pixel(tester, controller), [255, 0, 0, 255]);
        await _native(tester, controller.close);
      }
    },
  );

  testWidgets(
    'UT-026/IT-002 close waits for actual codec future then disposes frames before budget release',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final asset = await fixture.import(tester, animated: true);
      late _ControlledCodec codec;
      final controller = fixture.controller(
        asset,
        codecFactory: (input) async {
          codec = _ControlledCodec(
            await _decode(input),
            gateCall: 2,
            onDispose: () {
              expect(fixture.repository.processingScheduler.activeCount, 1);
              expect(codec.frames.every((image) => image.debugDisposed), true);
            },
          );
          fixture.releaseOnCleanup.add(codec.release);
          return codec;
        },
      );
      unawaited(controller.start());
      await _wait(tester, () => controller.image != null);
      await tester.pump(const Duration(milliseconds: 100));
      await _wait(tester, () => codec.entered.isCompleted);
      var closed = false;
      final closeRequest = controller.close();
      final closing = closeRequest.then((_) => closed = true);
      expect(controller.close(), same(closeRequest));
      await _tick(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(closed, false);
      expect(codec.disposed, false);
      expect(codec.frames.every((image) => !image.debugDisposed), true);
      expect(fixture.repository.processingScheduler.activeCount, 1);
      codec.release();
      await _native(tester, () => closing);
      expect(closed, true);
      expect(codec.disposed, true);
      expect(codec.frames.every((image) => image.debugDisposed), true);
      expect(controller.image, isNull);
      expect(fixture.repository.processingScheduler.activeCount, 0);
    },
  );

  testWidgets(
    'UT-026/IT-002 close waits for late real reader input without starting a codec',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final asset = await fixture.import(tester);
      final entered = Completer<void>();
      final gate = Completer<void>();
      void release() {
        if (!gate.isCompleted) gate.complete();
      }

      fixture.releaseOnCleanup.add(release);
      var codecCalls = 0;
      final controller = fixture.controller(
        asset,
        loader: (_) async {
          final input = await OriginalPreviewReader(fixture.repository)
              .read(asset);
          entered.complete();
          await gate.future;
          return input;
        },
        codecFactory: (input) {
          codecCalls++;
          return _decode(input);
        },
      );
      unawaited(controller.start());
      await _wait(tester, () => entered.isCompleted);
      var closed = false;
      final closing = controller.close().then((_) => closed = true);
      await _tick(tester);
      expect(closed, false);
      expect(fixture.repository.processingScheduler.activeCount, 1);
      release();
      await _native(tester, () => closing);
      expect(codecCalls, 0);
      expect(controller.image, isNull);
      expect(fixture.repository.processingScheduler.activeCount, 0);
    },
  );

  testWidgets(
    'UT-026 initial codec failures use safe copy without stringifying unknown errors',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final asset = await fixture.import(tester);
      for (final failure in [
        _UnsafeError(),
        const ResourceFailure(FailureKind.resourceBudget),
      ]) {
        final controller = fixture.controller(
          asset,
          codecFactory: (_) async => throw failure,
        );
        unawaited(controller.start());
        await _wait(tester, () => controller.error != null);
        expect(
          controller.error,
          failure is ResourceFailure
              ? '图片超出当前预览内存预算；永久副本保持不变。'
              : '无法安全读取或解码本机副本，请检查副本后重试。',
        );
        expect(controller.error, isNot(contains('secret-path')));
        expect(controller.image, isNull);
        expect(controller.loading, false);
        expect(controller.playing, false);
        await _native(tester, controller.close);
        expect(fixture.repository.processingScheduler.activeCount, 0);
      }
    },
  );

  testWidgets(
    'UT-026 later SDK frame failure retains current pixels and drains ownership on close',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final asset = await fixture.import(tester, animated: true);
      late _ControlledCodec codec;
      final controller = fixture.controller(
        asset,
        codecFactory: (input) async {
          codec = _ControlledCodec(await _decode(input), failCall: 2);
          return codec;
        },
      );
      unawaited(controller.start());
      await _wait(tester, () => controller.image != null);
      final current = controller.image!;
      await tester.pump(const Duration(milliseconds: 100));
      await _wait(tester, () => controller.error != null);
      expect(controller.frameIndex, 0);
      expect(controller.image, same(current));
      expect(await _pixel(tester, controller), [255, 0, 0, 255]);
      expect(controller.playing, false);
      await tester.pump(const Duration(seconds: 1));
      expect(codec.calls, 2);
      expect(fixture.repository.processingScheduler.activeCount, 1);
      await _native(tester, controller.close);
      expect(current.debugDisposed, true);
      expect(codec.disposed, true);
      expect(fixture.repository.processingScheduler.activeCount, 0);
    },
  );

  testWidgets(
    'UT-026 zero-delay animation waits for candidate deadline without a busy decode loop',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final asset = await fixture.import(tester, animated: true);
      late _ControlledCodec codec;
      final controller = fixture.controller(
        asset,
        codecFactory: (input) async {
          codec = _ControlledCodec(
            await _decode(input),
            duration: Duration.zero,
          );
          return codec;
        },
      );
      unawaited(controller.start());
      await _wait(tester, () => controller.image != null);
      for (var i = 0; i < 3; i++) {
        await _tick(tester);
      }
      expect(
        codec.calls,
        1,
        reason: 'Draining IO without advancing fake time cannot decode another frame.',
      );
      await tester.pump(const Duration(milliseconds: 9));
      expect(codec.calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await _wait(tester, () => controller.frameIndex == 1);
      expect(codec.calls, 2);
      await tester.pump(const Duration(milliseconds: 9));
      expect(codec.calls, 2);
      controller.pause();
      await _native(tester, controller.close);
    },
  );
}

Future<ui.Codec> _decode(OriginalPreviewInput input) => decodeOriginalPreview(
  input.bytes,
  memoryBudgetBytes: input.memoryBudgetBytes,
);

Future<List<int>> _pixel(
  WidgetTester tester,
  OriginalPreviewController controller,
) async {
  final data = await _native(
    tester,
    () => controller.image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return data!.buffer.asUint8List(data.offsetInBytes, 4).toList();
}

// Real SQLite/isolate/SDK callbacks and fake-zone continuations must alternate.
// The helper does not advance fake time, so animation deadlines stay explicit.
Future<void> _tick(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump();
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250 && !ready(); i++) {
    await _tick(tester);
  }
  expect(
    ready(),
    true,
    reason: 'Actual IO and fake-zone continuations must both drain.',
  );
  await tester.pump();
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

// Test scheduling only: all returned image handles come from the real SDK.
class _ControlledCodec implements ui.Codec {
  _ControlledCodec(
    this.delegate, {
    this.gateCall,
    this.failCall,
    this.repetitions,
    this.duration,
    this.onDispose,
  });
  final ui.Codec delegate;
  final int? gateCall, failCall, repetitions;
  final Duration? duration;
  final void Function()? onDispose;
  final entered = Completer<void>();
  final _gate = Completer<void>();
  final frames = <ui.Image>[];
  int calls = 0, completedCalls = 0;
  bool disposed = false;
  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  int get frameCount => delegate.frameCount;
  @override
  int get repetitionCount => repetitions ?? delegate.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final call = ++calls;
    if (call == failCall) throw _UnsafeError();
    final frame = await delegate.getNextFrame();
    frames.add(frame.image);
    if (call == gateCall) {
      entered.complete();
      await _gate.future;
    }
    completedCalls++;
    return duration == null ? frame : _Frame(frame.image, duration!);
  }

  @override
  void dispose() {
    expect(disposed, false, reason: 'Codec must be disposed only once.');
    onDispose?.call();
    disposed = true;
    delegate.dispose();
  }
}

class _Frame implements ui.FrameInfo {
  _Frame(this.image, this.duration);
  @override
  final ui.Image image;
  @override
  final Duration duration;
}

class _UnsafeError {
  @override
  String toString() =>
      throw StateError('secret-path must never be stringified');
}

String _failureCategory(Object failure) => failure is ResourceFailure
    ? 'ResourceFailure.${failure.kind.name}'
    : '${failure.runtimeType}';

// Only a fixed kind or runtime type is reported; never exception contents.
class _DiagnosticDecoder extends OriginalPreviewDecoder {
  String? failureCategory;

  @override
  Future<Uint8List> read(
    File file, {
    required int memoryBudgetBytes,
    required String expectedSha256,
    required int expectedByteCount,
  }) async {
    try {
      return await super.read(
        file,
        memoryBudgetBytes: memoryBudgetBytes,
        expectedSha256: expectedSha256,
        expectedByteCount: expectedByteCount,
      );
    } catch (failure) {
      failureCategory = _failureCategory(failure);
      rethrow;
    }
  }
}

class _Fixture {
  _Fixture(this.root, this.repository);
  final Directory root;
  final LibraryRepository repository;
  final controllers = <OriginalPreviewController>[];
  final releaseOnCleanup = <void Function()>[];

  static Future<_Fixture> create(WidgetTester tester) async {
    final fixture = await _native(tester, () async {
      final root = await Directory.systemTemp.createTemp(
        'imagehost_original_playback_',
      );
      final repository = await LibraryRepository.open(
        Directory('${root.path}/library'),
      );
      return _Fixture(root, repository);
    });
    addTearDown(() async {
      for (final release in fixture.releaseOnCleanup) {
        release();
      }
      for (final controller in fixture.controllers) {
        await _native(tester, controller.close);
        controller.dispose();
      }
      await _native(tester, fixture.repository.close);
      await tester.runAsync(() => fixture.root.delete(recursive: true));
    });
    return fixture;
  }

  Future<ImageAsset> import(
    WidgetTester tester, {
    String format = 'gif',
    bool animated = false,
  }) => _native(tester, () async {
    final red = img.Image(
      width: 8,
      height: 6,
      numChannels: 4,
      frameDuration: 100,
    );
    img.fill(red, color: img.ColorRgba8(255, 0, 0, 255));
    if (animated) {
      final blue = img.Image(
        width: 8,
        height: 6,
        numChannels: 4,
        frameDuration: 100,
      );
      img.fill(blue, color: img.ColorRgba8(0, 0, 255, 255));
      red.addFrame(blue);
    }
    final bytes = switch (format) {
      'png' => img.encodePng(red),
      'jpg' => img.encodeJpg(red, quality: 100),
      'webp' => img.encodeWebP(red),
      'gif' => img.encodeGif(red),
      'bmp' => img.encodeBmp(red),
      _ => throw ArgumentError(format),
    };
    final imported = await repository.importResource(
      PlatformResource(
        displayName: 'preview.$format',
        openRead: () => Stream.value(bytes),
      ),
    );
    expect(imported.asset, isNotNull);
    return imported.asset!;
  });

  OriginalPreviewController controller(
    ImageAsset asset, {
    OriginalPreviewCodecFactory? codecFactory,
    OriginalPreviewLoader? loader,
  }) {
    final controller = OriginalPreviewController(
      loader:
          loader ??
          (token) =>
              OriginalPreviewReader(repository)
                  .read(asset, cancellation: token),
      codecFactory: codecFactory,
    );
    controllers.add(controller);
    return controller;
  }
}
