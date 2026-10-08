import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/platform/image_preview_codec.dart';

import 'png_orientation_fixture.dart';

void main() {
  for (var orientation = 1; orientation <= 8; orientation++) {
    testWidgets(
      'UT-028/IT-002 actual SDK PNG eXIf orientation $orientation displays expected complete pixel matrix',
      (tester) async {
        final bytes = addPngExif(
          img.encodePng(orientationMatrix()),
          orientationTiff(orientation),
        );
        await _expectSdkOrientation(tester, bytes, orientation);
      },
    );
  }
  testWidgets(
    'UT-028/IT-002 actual SDK JPEG orientation 6 agrees with visual crop coordinates',
    (tester) async {
      final source = orientationMatrix(scale: 8);
      source.exif.imageIfd.orientation = 6;
      final bytes = img.encodeJpg(
        source,
        quality: 100,
        chroma: img.JpegChroma.yuv444,
      );
      await _expectSdkOrientation(tester, bytes, 6, scale: 8, tolerance: 3);
    },
  );
  testWidgets(
    'UT-028/IT-002 actual SDK WebP orientation 6 agrees with visual crop coordinates',
    (tester) async {
      final source = orientationMatrix(scale: 8);
      source.exif.imageIfd.orientation = 6;
      final bytes = img.encodeWebP(source, lossless: true);
      expect(
        img.decodeWebP(bytes)!.exif.imageIfd.orientation,
        6,
        reason: 'The fixture must really carry EXIF orientation.',
      );
      await _expectSdkOrientation(tester, bytes, 6, scale: 8);
    },
  );
  for (final orientation in [3, 6]) {
    testWidgets(
      'UT-028/IT-002 APNG orientation $orientation preserves every frame duration and finite repetition',
      (tester) async {
        final first = orientationMatrix()
          ..frameDuration = 70
          ..loopCount = 3;
        first.addFrame(orientationMatrix(reverse: true)..frameDuration = 130);
        final rawBytes = img.encodePng(first);
        final orientedBytes = addPngExif(
          rawBytes,
          orientationTiff(orientation),
        );
        ui.Codec? rawCodec;
        ui.Codec? orientedCodec;
        try {
          final raw = await _native(
            tester,
            () => decodeOriginalPreview(
              rawBytes,
              memoryBudgetBytes: 128 * 1024 * 1024,
            ),
          );
          rawCodec = raw;
          final oriented = await _native(
            tester,
            () => decodeOriginalPreview(
              orientedBytes,
              memoryBudgetBytes: 128 * 1024 * 1024,
            ),
          );
          orientedCodec = oriented;
          expect(oriented.frameCount, 2);
          expect(oriented.frameCount, raw.frameCount);
          expect(oriented.repetitionCount, 2);
          expect(oriented.repetitionCount, raw.repetitionCount);
          for (var index = 0; index < 3; index++) {
            final expectedFrame = await _native(tester, raw.getNextFrame);
            final actualFrame = await _native(tester, oriented.getNextFrame);
            try {
              expect(actualFrame.duration, expectedFrame.duration);
              expect(
                actualFrame.duration.inMilliseconds,
                index == 1 ? 130 : 70,
              );
              final width = orientation >= 5 ? 3 : 2;
              final height = orientation >= 5 ? 2 : 3;
              expect(
                [actualFrame.image.width, actualFrame.image.height],
                [width, height],
              );
              final data = (await _native(
                tester,
                () => actualFrame.image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ),
              ))!;
              final indices = orientedPixelIndices[orientation]!;
              for (var pixel = 0; pixel < indices.length; pixel++) {
                final expected = matrixPixel(
                  index == 1 ? 5 - indices[pixel] : indices[pixel],
                );
                expect(
                  [
                    for (var channel = 0; channel < 4; channel++)
                      data.getUint8(pixel * 4 + channel),
                  ],
                  expected,
                  reason: 'frame $index pixel $pixel',
                );
              }
            } finally {
              expectedFrame.image.dispose();
              actualFrame.image.dispose();
            }
          }
        } finally {
          rawCodec?.dispose();
          orientedCodec?.dispose();
        }
      },
    );
  }
  testWidgets(
    'UT-028/UT-032 PNG direction transform requires its additional canvas budget before creating codec',
    (tester) async {
      final base = img.encodePng(orientationMatrix());
      final plain = addPngExif(base, orientationTiff(1));
      final transformed = addPngExif(base, orientationTiff(6));
      final ordinaryBudget = plain.length * 2 + 2 * 3 * 4 * 2 + 2 * 3 * 4 * 3;
      final codec = await _native(
        tester,
        () => decodeOriginalPreview(plain, memoryBudgetBytes: ordinaryBudget),
      );
      codec.dispose();
      final budgetFailure = isA<ResourceFailure>().having(
        (failure) => failure.kind,
        'kind',
        FailureKind.resourceBudget,
      );
      await _native(
        tester,
        () => expectLater(
          decodeOriginalPreview(transformed, memoryBudgetBytes: ordinaryBudget),
          throwsA(budgetFailure),
        ),
      );
      await _native(
        tester,
        () => expectLater(
          decodeOriginalPreview(
            transformed,
            memoryBudgetBytes: transformed.length * 2 - 1,
          ),
          throwsA(budgetFailure),
        ),
      );
    },
  );
  testWidgets(
    'UT-028 PNG malformed CRC rejects safely before SDK work and frame disposal drains actual transform',
    (tester) async {
      final bytes = addPngExif(
        img.encodePng(orientationMatrix()),
        orientationTiff(6),
      );
      final malformed = Uint8List.fromList(bytes)..[45] ^= 1;
      final invalid = isA<ResourceFailure>().having(
        (failure) => failure.kind,
        'kind',
        FailureKind.invalidImage,
      );
      await _native(
        tester,
        () => expectLater(
          decodeOriginalPreview(
            malformed,
            memoryBudgetBytes: 128 * 1024 * 1024,
          ),
          throwsA(invalid),
        ),
      );
      final codec = await _native(
        tester,
        () =>
            decodeOriginalPreview(bytes, memoryBudgetBytes: 128 * 1024 * 1024),
      );
      await _native(tester, () async {
        final pending = codec.getNextFrame();
        codec.dispose();
        await expectLater(pending, throwsA(invalid));
        await expectLater(codec.getNextFrame(), throwsA(invalid));
      });
    },
  );
}

Future<void> _expectSdkOrientation(
  WidgetTester tester,
  Uint8List bytes,
  int orientation, {
  int scale = 1,
  int tolerance = 0,
}) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    final openedCodec = await _native(
      tester,
      () => decodeOriginalPreview(bytes, memoryBudgetBytes: 128 * 1024 * 1024),
    );
    codec = openedCodec;
    final frame = await _native(tester, openedCodec.getNextFrame);
    image = frame.image;
    final width = orientation >= 5 ? 3 : 2;
    final height = orientation >= 5 ? 2 : 3;
    expect([image.width, image.height], [width * scale, height * scale]);
    final data = (await _native(
      tester,
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    final expected = orientedPixelIndices[orientation]!;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset =
            (((y * scale + scale ~/ 2) * image.width) +
                x * scale +
                scale ~/ 2) *
            4;
        final color = matrixPixel(expected[y * width + x]);
        for (var channel = 0; channel < 4; channel++) {
          expect(
            data.getUint8(offset + channel),
            inInclusiveRange(
              color[channel] - tolerance,
              color[channel] + tolerance,
            ),
            reason: 'orientation $orientation pixel ($x,$y) channel $channel',
          );
        }
      }
    }
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

// Native codec completions and fake-zone continuations must both drain.
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
  for (var i = 0; i < 250 && !finished; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(finished, true, reason: 'Actual native codec work must finish.');
  if (failure != null) throw failure!;
  return result as T;
}
