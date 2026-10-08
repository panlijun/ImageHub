import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/image_processor.dart';
import 'package:imagehost/features/processing/application/metadata_policy.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';

void main() {
  late Directory directory;
  var sequence = 0;
  const processor = ImageProcessor();
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'imagehost_processing_test_',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  ProcessingInput metadata(int width, int height, {int frames = 1}) =>
      ProcessingInput(
        file: File('${directory.path}/metadata-only'),
        assetId: 'asset',
        version: ImageVersion(
          id: 'version',
          sha256: '0' * 64,
          byteCount: 100,
          format: 'PNG',
          width: width,
          height: height,
          frameCount: frames,
          orientation: 1,
        ),
      );
  Future<ProcessingInput> input(
    Uint8List bytes,
    int width,
    int height, {
    String format = 'PNG',
    int frames = 1,
    int orientation = 1,
    int? selectedFrame,
  }) async {
    final id = '${sequence++}';
    final file = File('${directory.path}/input-$id');
    await file.writeAsBytes(bytes);
    return ProcessingInput(
      file: file,
      assetId: 'asset-$id',
      selectedFrame: selectedFrame,
      version: ImageVersion(
        id: 'version-$id',
        sha256: sha256.convert(bytes).toString(),
        byteCount: bytes.length,
        format: format,
        width: width,
        height: height,
        frameCount: frames,
        orientation: orientation,
      ),
    );
  }

  Future<ProcessingResult> process(ProcessingRequest request) =>
      processor.process(
        request,
        destination: File('${directory.path}/output-${sequence++}'),
      );
  Matcher failure(ProcessingFailureKind kind) =>
      isA<ProcessingFailure>().having((error) => error.kind, 'kind', kind);

  test(
    'UT-022 real compression/crop/stitch never change input bytes',
    () async {
      final a = await input(img.encodePng(_solid(3, 3, 255, 0, 0)), 3, 3);
      final b = await input(img.encodePng(_solid(2, 2, 0, 0, 255)), 2, 2);
      final original = await a.file.readAsBytes();
      for (final operation in ProcessingOperation.values) {
        final result = await process(
          ProcessingRequest(
            operation: operation,
            inputs: operation == ProcessingOperation.stitch ? [a, b] : [a],
            crop: operation == ProcessingOperation.crop
                ? const PixelCrop(1, 1, 1, 2)
                : null,
          ),
        );
        expect(result.file.existsSync(), isTrue);
        expect(
          result.version.sha256,
          sha256.convert(result.file.readAsBytesSync()).toString(),
        );
        expect(result.version.id, isNot(a.version.id));
        expect(await a.file.readAsBytes(), original);
      }
      await expectLater(
        processor.process(
          ProcessingRequest(
            operation: ProcessingOperation.compress,
            inputs: [a],
          ),
          destination: a.file,
        ),
        throwsA(failure(ProcessingFailureKind.storage)),
      );
      expect(await a.file.readAsBytes(), original);
    },
  );

  test('UT-022 failures, pre-cancel and worker cancellation leave no result or input mutation', () async {
    final bytes = img.encodePng(_solid(1600, 1200, 180, 10, 80));
    final a = await input(bytes, 1600, 1200);
    final destination = File('${directory.path}/cancel-output');
    final token = CancellationToken();
    final work = processor.process(
      ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: [a],
        outputFormat: ProcessingFormat.webp,
      ),
      cancellation: token,
      destination: destination,
    );
    final timer = Timer(const Duration(milliseconds: 30), token.cancel);
    try {
      await expectLater(
        work,
        throwsA(failure(ProcessingFailureKind.cancelled)),
      );
    } finally {
      timer.cancel();
    }
    expect(await destination.exists(), isFalse);
    expect(await a.file.readAsBytes(), bytes);
    final alreadyCancelled = CancellationToken()..cancel();
    await expectLater(
      processor.process(
        ProcessingRequest(operation: ProcessingOperation.compress, inputs: [a]),
        cancellation: alreadyCancelled,
        destination: destination,
      ),
      throwsA(failure(ProcessingFailureKind.cancelled)),
    );
    expect(await destination.exists(), isFalse);
    final bad = await input(Uint8List.fromList([1, 2, 3]), 1, 1);
    await expectLater(
      process(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [bad],
        ),
      ),
      throwsA(isA<ProcessingFailure>()),
    );
  });

  test('UT-023 fidelity preserves dimensions/alpha and cannot silently staticize animation', () async {
    final image = _solid(2, 2, 200, 0, 0)..setPixelRgba(0, 0, 0, 255, 0, 80);
    final a = await input(img.encodePng(image), 2, 2);
    final result = await process(
      ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: [a],
        longestSide: 1,
      ),
    );
    final decoded = img.decodePng(result.file.readAsBytesSync())!;
    expect([decoded.width, decoded.height], [2, 2]);
    expect(decoded.getPixel(0, 0).a, 80);
    expect(result.fidelityPreserved, isTrue);
    expect(
      () => processor.plan(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [metadata(2, 2, frames: 2)],
        ),
      ),
      throwsA(failure(ProcessingFailureKind.confirmationRequired)),
    );
  });

  test('UT-024 longest side bounds, rounding and no enlargement', () {
    expect(
      [
        fitLongestSide(const PixelSize(800, 600), 1600).width,
        fitLongestSide(const PixelSize(800, 600), 1600).height,
      ],
      [800, 600],
    );
    final scaled = fitLongestSide(const PixelSize(4000, 2001), 1600);
    expect([scaled.width, scaled.height], [1600, 800]);
    final thin = fitLongestSide(const PixelSize(16384, 1), 1);
    expect([thin.width, thin.height], [1, 1]);
    for (final value in [0, 16385]) {
      expect(
        () => fitLongestSide(const PixelSize(2, 2), value),
        throwsA(failure(ProcessingFailureKind.invalidParameters)),
      );
    }
    final request = ProcessingRequest(
      operation: ProcessingOperation.compress,
      inputs: [metadata(2, 2)],
    );
    for (final value in [1.5, double.infinity, double.nan]) {
      expect(
        () => ProcessingRequest.fromSnapshot({
          ...request.toSnapshot(),
          'longestSide': value,
        }),
        throwsA(failure(ProcessingFailureKind.invalidParameters)),
      );
    }
    expect(
      processor
          .plan(
            ProcessingRequest(
              operation: ProcessingOperation.compress,
              inputs: [metadata(2, 2)],
              longestSide: 16384,
            ),
          )
          .outputSize
          .width,
      2,
    );
  });

  test('UT-025 quality defaults/bounds match PNG JPEG WebP', () {
    for (final format in [ProcessingFormat.jpeg, ProcessingFormat.webp]) {
      expect(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [metadata(2, 2)],
          outputFormat: format,
        ).quality,
        85,
      );
      for (final quality in [1, 100]) {
        processor.plan(
          ProcessingRequest(
            operation: ProcessingOperation.compress,
            inputs: [metadata(2, 2)],
            outputFormat: format,
            quality: quality,
          ),
        );
      }
      for (final quality in [0, 101]) {
        expect(
          () => processor.plan(
            ProcessingRequest(
              operation: ProcessingOperation.compress,
              inputs: [metadata(2, 2)],
              outputFormat: format,
              quality: quality,
            ),
          ),
          throwsA(failure(ProcessingFailureKind.invalidParameters)),
        );
      }
    }
    expect(
      () => processor.plan(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [metadata(2, 2)],
          quality: 85,
        ),
      ),
      throwsA(failure(ProcessingFailureKind.invalidParameters)),
    );
    final request = ProcessingRequest(
      operation: ProcessingOperation.compress,
      inputs: [metadata(2, 2)],
      outputFormat: ProcessingFormat.jpeg,
    );
    for (final quality in [1.5, double.nan, double.infinity]) {
      expect(
        () => ProcessingRequest.fromSnapshot({
          ...request.toSnapshot(),
          'quality': quality,
        }),
        throwsA(failure(ProcessingFailureKind.invalidParameters)),
      );
    }
  });

  test('UT-024 real average downsampling includes palette GIF rather than nearest neighbour', () async {
    final image = _solid(4, 2, 0, 0, 255);
    for (var y = 0; y < 2; y++) {
      for (final x in [0, 2]) {
        image.setPixelRgb(x, y, 255, 0, 0);
      }
    }
    for (final format in ['PNG', 'GIF']) {
      final a = await input(
        format == 'GIF'
            ? img.encodeGif(_redBluePalette(4, 2, alternating: true))
            : img.encodePng(image),
        4,
        2,
        format: format,
      );
      final result = await process(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [a],
          mode: ProcessingMode.sizeFirst,
          longestSide: 2,
        ),
      );
      final decoded = img.decodePng(result.file.readAsBytesSync())!;
      expect([decoded.width, decoded.height], [2, 1]);
      expect(decoded.getPixel(0, 0).r, inInclusiveRange(120, 135));
      expect(decoded.getPixel(0, 0).b, inInclusiveRange(120, 135));
    }
  });

  test('UT-028 verified PNG cICP is retained and unsupported output colours are rejected', () async {
    const cicp = img.PngCicpData(
      colourPrimaries: 12,
      transferCharacteristics: 13,
      matrixCoefficients: 0,
      videoFullRangeFlag: 1,
    );
    final bytes = img.encodePng(_solid(2, 2, 40, 80, 160), cicpData: cicp);
    final a = await input(bytes, 2, 2);
    final result = await process(
      ProcessingRequest(operation: ProcessingOperation.compress, inputs: [a]),
    );
    expect(
      (img.PngDecoder().startDecode(result.file.readAsBytesSync())!
              as img.PngInfo)
          .cicpData,
      cicp,
    );
    await expectLater(
      process(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [a],
          outputFormat: ProcessingFormat.jpeg,
        ),
      ),
      throwsA(failure(ProcessingFailureKind.colorMetadataUnsupported)),
    );
  });

  test(
    'UT-026 real five static input formats and three actual output formats',
    () async {
      final image = _solid(3, 2, 220, 40, 70);
      final sources = <String, Uint8List>{
        'PNG': img.encodePng(image),
        'JPEG': img.encodeJpg(image),
        'WebP': img.encodeWebP(image),
        'GIF': img.encodeGif(image),
        'BMP': img.encodeBmp(image),
      };
      for (final source in sources.entries) {
        final a = await input(source.value, 3, 2, format: source.key);
        for (final format in ProcessingFormat.values) {
          final result = await process(
            ProcessingRequest(
              operation: ProcessingOperation.compress,
              inputs: [a],
              outputFormat: format,
              mode: ProcessingMode.sizeFirst,
            ),
          );
          expect(result.version.format, ['PNG', 'JPEG', 'WebP'][format.index]);
          expect(
            [
              result.version.width,
              result.version.height,
              result.version.frameCount,
            ],
            [3, 2, 1],
          );
        }
      }
    },
  );

  test('UT-026 animation requires selected frame AND explicit conversion, records feature loss', () async {
    for (final format in ['GIF', 'WebP']) {
      final animation = format == 'GIF'
          ? _redBluePalette(3, 2)
          : _solid(3, 2, 255, 0, 0);
      animation.addFrame(
        format == 'GIF'
            ? _redBluePalette(3, 2, blue: true)
            : _solid(3, 2, 0, 0, 255),
      );
      final bytes = format == 'GIF'
          ? img.encodeGif(animation)
          : img.encodeWebP(animation);
      final sourceAnimation = img.decodeImage(bytes)!;
      expect(
        sourceAnimation.numFrames,
        2,
        reason: '$format fixture frame count',
      );
      expect(
        sourceAnimation.getFrame(0).getPixel(1, 1).r,
        greaterThan(200),
        reason: '$format fixture red frame',
      );
      expect(
        sourceAnimation.getFrame(1).getPixel(1, 1).b,
        greaterThan(200),
        reason: '$format fixture blue frame',
      );
      final a = await input(
        bytes,
        3,
        2,
        format: format,
        frames: 2,
        selectedFrame: 1,
      );
      expect(
        () => processor.plan(
          ProcessingRequest(
            operation: ProcessingOperation.crop,
            inputs: [a],
            crop: const PixelCrop(0, 0, 3, 2),
          ),
        ),
        throwsA(failure(ProcessingFailureKind.confirmationRequired)),
      );
      final result = await process(
        ProcessingRequest(
          operation: ProcessingOperation.crop,
          inputs: [a],
          crop: const PixelCrop(0, 0, 3, 2),
          explicitStaticConversion: true,
        ),
      );
      expect(result.animationRemoved, isTrue);
      expect(result.fidelityPreserved, isFalse);
      expect(result.request.inputs.single.selectedFrame, 1);
      final pixel = img
          .decodePng(result.file.readAsBytesSync())!
          .getPixel(1, 1);
      expect(
        pixel.b,
        greaterThan(200),
        reason: '$format selected frame must be blue',
      );
      expect(
        pixel.r,
        lessThan(20),
        reason: '$format must not select red first frame',
      );
    }
  });

  test('UT-027 JPEG transparent backgrounds require confirmation and use chosen colour', () async {
    final a = await input(
      img.encodePng(_solid(3, 2, 255, 0, 0, alpha: 0)),
      3,
      2,
    );
    await expectLater(
      process(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [a],
          outputFormat: ProcessingFormat.jpeg,
        ),
      ),
      throwsA(failure(ProcessingFailureKind.confirmationRequired)),
    );
    final result = await process(
      ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: [a],
        outputFormat: ProcessingFormat.jpeg,
        backgroundConfirmed: true,
        backgroundArgb: 0xff00ff00,
        quality: 100,
      ),
    );
    final pixel = img.decodeJpg(result.file.readAsBytesSync())!.getPixel(1, 1);
    expect(pixel.g, greaterThan(240));
    expect(pixel.r, lessThan(15));
    expect(result.transparencyRemoved, isTrue);
    expect(result.lossy, isTrue);
    await expectLater(
      process(
        ProcessingRequest(
          operation: ProcessingOperation.stitch,
          inputs: [a, a],
        ),
      ),
      throwsA(failure(ProcessingFailureKind.confirmationRequired)),
    );
  });

  test('UT-028 real JPEG orientation6 crop rotates exactly once and drops EXIF/text', () async {
    final image = _solid(4, 2, 0, 0, 255);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 2; x++) {
        image.setPixelRgb(x, y, 255, 0, 0);
      }
    }
    image.exif.imageIfd
      ..orientation = 6
      ..make = 'private device location';
    final bytes = img.encodeJpg(
      image,
      quality: 100,
      chroma: img.JpegChroma.yuv444,
    );
    final a = await input(bytes, 2, 4, format: 'JPEG');
    final result = await process(
      ProcessingRequest(
        operation: ProcessingOperation.crop,
        inputs: [a],
        crop: const PixelCrop(0, 0, 2, 2),
      ),
    );
    final decoded = img.decodePng(result.file.readAsBytesSync())!;
    expect([decoded.width, decoded.height], [2, 2]);
    expect(decoded.getPixel(0, 0).r, greaterThan(240));
    expect(decoded.hasExif && !decoded.exif.isEmpty, isFalse);
    expect(decoded.textData, isNull);
    final png = _solid(2, 2, 80, 20, 40)
      ..textData = {'GPS': 'private location'};
    final p = await input(img.encodePng(png), 2, 2);
    final clean = await process(
      ProcessingRequest(operation: ProcessingOperation.compress, inputs: [p]),
    );
    expect(img.decodePng(clean.file.readAsBytesSync())!.textData, isNull);
  });

  test('UT-028 RGB ICC sanitization preserves colour tags and clears identifying bytes', () {
    final original = _rgbIcc();
    final clean = MetadataPolicy.sanitizeIcc(original);
    expect(String.fromCharCodes(clean), isNot(contains('private device')));
    expect(clean.sublist(48, 64), everyElement(0));
    expect(clean.sublist(80, 128), everyElement(0));
    expect(MetadataPolicy.sanitizeIcc(clean), clean);
    final count = ByteData.sublistView(clean).getUint32(128);
    final tags = List.generate(
      count,
      (i) => String.fromCharCodes(clean.sublist(132 + i * 12, 136 + i * 12)),
    );
    expect(
      tags,
      containsAll([
        'wtpt',
        'rXYZ',
        'gXYZ',
        'bXYZ',
        'rTRC',
        'gTRC',
        'bTRC',
        'chad',
      ]),
    );
    final cmyk = Uint8List.fromList(original)
      ..setRange(16, 20, 'CMYK'.codeUnits);
    expect(
      () => MetadataPolicy.sanitizeIcc(cmyk),
      throwsA(failure(ProcessingFailureKind.colorMetadataUnsupported)),
    );
    final malformed = Uint8List.fromList(original);
    ByteData.sublistView(malformed).setUint32(136, malformed.length + 4);
    expect(
      () => MetadataPolicy.sanitizeIcc(malformed),
      throwsA(failure(ProcessingFailureKind.colorMetadataUnsupported)),
    );
  });

  test('UT-028 RGB ICC survives actual PNG JPEG WebP output via standard containers', () async {
    final original = _rgbIcc();
    final image = _solid(3, 2, 200, 80, 30)
      ..iccProfile = img.IccProfile(
        'private device',
        img.IccProfileCompression.none,
        original,
      )
      ..textData = {'location': 'private device location'};
    final a = await input(img.encodePng(image), 3, 2);
    for (final format in ProcessingFormat.values) {
      final result = await process(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [a],
          outputFormat: format,
        ),
      );
      final bytes = result.file.readAsBytesSync();
      final color = MetadataPolicy.inspect(bytes, result.version.format);
      expect(color.icc, MetadataPolicy.sanitizeIcc(original));
      expect(String.fromCharCodes(bytes), isNot(contains('private device')));
      if (format == ProcessingFormat.jpeg) {
        final signature = 'ICC_PROFILE\u0000'.codeUnits;
        final offset = _indexOf(bytes, signature);
        expect(offset, greaterThan(0));
        expect(bytes.sublist(offset + 12, offset + 14), [1, 1]);
      }
    }
  });

  test(
    'UT-028 large RGB ICC uses ordered standard JPEG APP2 fragments',
    () async {
      final profile = _rgbIcc(large: true);
      final image = _solid(2, 2, 40, 80, 160)
        ..iccProfile = img.IccProfile(
          'colour',
          img.IccProfileCompression.none,
          profile,
        );
      final a = await input(img.encodePng(image), 2, 2);
      final result = await process(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [a],
          outputFormat: ProcessingFormat.jpeg,
        ),
      );
      final bytes = result.file.readAsBytesSync();
      final first = _indexOf(bytes, 'ICC_PROFILE\u0000'.codeUnits);
      expect(bytes[first + 12], 1);
      expect(bytes[first + 13], greaterThan(1));
      expect(
        MetadataPolicy.inspect(bytes, 'JPEG').icc,
        MetadataPolicy.sanitizeIcc(profile),
      );
      expect(img.decodeJpg(bytes)!.width, 2);
    },
  );

  test('UT-029 crop full/minimal/invalid integer pixel boundaries', () {
    for (final crop in [
      const PixelCrop(0, 0, 100, 80),
      const PixelCrop(99, 79, 1, 1),
    ]) {
      final plan = processor.plan(
        ProcessingRequest(
          operation: ProcessingOperation.crop,
          inputs: [metadata(100, 80)],
          crop: crop,
        ),
      );
      expect(
        [plan.outputSize.width, plan.outputSize.height],
        [crop.width, crop.height],
      );
    }
    for (final crop in [
      const PixelCrop(0, 0, 0, 1),
      const PixelCrop(-1, 0, 1, 1),
      const PixelCrop(99, 79, 2, 1),
    ]) {
      expect(
        () => processor.plan(
          ProcessingRequest(
            operation: ProcessingOperation.crop,
            inputs: [metadata(100, 80)],
            crop: crop,
          ),
        ),
        throwsA(failure(ProcessingFailureKind.invalidParameters)),
      );
    }
    for (final value in [1.5, double.infinity, double.nan]) {
      expect(
        () => PixelCrop.fromSnapshot({
          'x': value,
          'y': 0,
          'width': 1,
          'height': 1,
        }),
        throwsA(failure(ProcessingFailureKind.invalidParameters)),
      );
    }
  });

  test(
    'UT-030 horizontal/vertical dimensions and floor centering preserve order',
    () async {
      final a = await input(img.encodePng(_solid(3, 3, 255, 0, 0)), 3, 3);
      final b = await input(img.encodePng(_solid(2, 2, 0, 0, 255)), 2, 2);
      for (final layout in [StitchLayout.horizontal, StitchLayout.vertical]) {
        final request = ProcessingRequest(
          operation: ProcessingOperation.stitch,
          inputs: [a, b],
          layout: layout,
          gap: 1,
        );
        final plan = processor.plan(request);
        expect([
          plan.outputSize.width,
          plan.outputSize.height,
        ], layout == StitchLayout.horizontal ? [6, 3] : [3, 6]);
        expect(
          layout == StitchLayout.horizontal
              ? plan.placements[1].y
              : plan.placements[1].x,
          0,
        );
        final result = await process(request);
        final decoded = img.decodePng(result.file.readAsBytesSync())!;
        expect(
          decoded.getPixel(plan.placements[1].x, plan.placements[1].y).b,
          255,
        );
      }
      for (final gap in [-1, 1025]) {
        expect(
          () => processor.plan(
            ProcessingRequest(
              operation: ProcessingOperation.stitch,
              inputs: [a, b],
              gap: gap,
            ),
          ),
          throwsA(failure(ProcessingFailureKind.invalidParameters)),
        );
      }
      processor.plan(
        ProcessingRequest(
          operation: ProcessingOperation.stitch,
          inputs: [a, b],
          gap: 1024,
        ),
      );
      expect(
        () => processor.plan(
          ProcessingRequest(operation: ProcessingOperation.stitch, inputs: [a]),
        ),
        throwsA(failure(ProcessingFailureKind.invalidParameters)),
      );
    },
  );

  test('UT-031 3-image grid leaves empty background cell; swapped order and transparent canvas', () async {
    final a = await input(img.encodePng(_solid(3, 3, 255, 0, 0)), 3, 3);
    final b = await input(img.encodePng(_solid(2, 2, 0, 255, 0)), 2, 2);
    final c = await input(img.encodePng(_solid(1, 1, 0, 0, 255)), 1, 1);
    for (final order in [
      [a, b, c],
      [c, b, a],
    ]) {
      final result = await process(
        ProcessingRequest(
          operation: ProcessingOperation.stitch,
          inputs: order,
          gap: 1,
        ),
      );
      final decoded = img.decodePng(result.file.readAsBytesSync())!;
      expect([decoded.width, decoded.height], [7, 7]);
      expect(decoded.getPixel(6, 6).r, 255);
      expect(decoded.getPixel(1, 1).r, identical(order.first, a) ? 255 : 0);
    }
    final transparent = await process(
      ProcessingRequest(
        operation: ProcessingOperation.stitch,
        inputs: [a, b, c],
        gap: 1,
        backgroundArgb: 0,
      ),
    );
    expect(
      img.decodePng(transparent.file.readAsBytesSync())!.getPixel(6, 6).a,
      0,
    );
  });

  test('UT-032 resource plan rejects huge decoded pixels before file or canvas allocation', () {
    expect(
      () => processor.plan(
        ProcessingRequest(
          operation: ProcessingOperation.compress,
          inputs: [metadata(1000000000, 2)],
        ),
      ),
      throwsA(failure(ProcessingFailureKind.resourceBudget)),
    );
    expect(
      () => processor.plan(
        ProcessingRequest(
          operation: ProcessingOperation.stitch,
          inputs: [metadata(6000, 6000), metadata(6000, 6000)],
        ),
      ),
      throwsA(failure(ProcessingFailureKind.resourceBudget)),
    );
    final plan = processor.plan(
      ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: [metadata(100, 100)],
      ),
      memoryBudgetBytes: 2 * 1024 * 1024,
    );
    expect(plan.estimatedBytes, lessThanOrEqualTo(2 * 1024 * 1024));
    expect(
      () => processor.plan(
        ProcessingRequest(
          operation: ProcessingOperation.stitch,
          inputs: [metadata(9223372036854775807, 2), metadata(1, 1)],
        ),
      ),
      throwsA(failure(ProcessingFailureKind.resourceBudget)),
    );
  });

  test(
    'UT-033 snapshots freeze list/order/quality and separate item failure',
    () async {
      final a = await input(img.encodePng(_solid(2, 2, 255, 0, 0)), 2, 2);
      final b = await input(img.encodePng(_solid(2, 2, 0, 0, 255)), 2, 2);
      final mutable = [a, b];
      final request = ProcessingRequest(
        operation: ProcessingOperation.stitch,
        inputs: mutable,
        outputFormat: ProcessingFormat.jpeg,
      );
      mutable
        ..clear()
        ..add(b);
      expect(request.inputs.map((input) => input.assetId), [
        a.assetId,
        b.assetId,
      ]);
      final snapshot = request.toSnapshot();
      final restored = ProcessingRequest.fromSnapshot(snapshot);
      snapshot['quality'] = 50;
      expect(restored.quality, 85);
      expect(() => request.inputs.clear(), throwsUnsupportedError);
      final bad = await input(Uint8List.fromList([7, 7, 7]), 2, 2);
      await expectLater(
        process(
          ProcessingRequest(
            operation: ProcessingOperation.compress,
            inputs: [bad],
          ),
        ),
        throwsA(isA<ProcessingFailure>()),
      );
      expect(
        (await process(
          ProcessingRequest(
            operation: ProcessingOperation.compress,
            inputs: [b],
          ),
        )).version.width,
        2,
      );
    },
  );

  test('UT-022 altered content identity is rejected and existing destination is preserved', () async {
    final a = await input(img.encodePng(_solid(2, 2, 200, 0, 0)), 2, 2);
    await a.file.writeAsBytes(img.encodePng(_solid(2, 2, 0, 0, 200)));
    await expectLater(
      process(
        ProcessingRequest(operation: ProcessingOperation.compress, inputs: [a]),
      ),
      throwsA(failure(ProcessingFailureKind.inputChanged)),
    );
    final dest = File('${directory.path}/existing')
      ..writeAsStringSync('keep me');
    await expectLater(
      processor.process(
        ProcessingRequest(operation: ProcessingOperation.compress, inputs: [a]),
        destination: dest,
      ),
      throwsA(failure(ProcessingFailureKind.storage)),
    );
    expect(dest.readAsStringSync(), 'keep me');
  });
}

img.Image _solid(
  int width,
  int height,
  int r,
  int g,
  int b, {
  int alpha = 255,
}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  return img.fill(image, color: img.ColorRgba8(r, g, b, alpha));
}

/// Deterministic palette fixture avoids the upstream tiny-image quantizer's
/// zero training samples (6 pixels / default samplingFactor 10).
img.Image _redBluePalette(
  int width,
  int height, {
  bool blue = false,
  bool alternating = false,
}) {
  final palette = img.PaletteUint8(256, 3)
    ..setRgb(0, 255, 0, 0)
    ..setRgb(1, 0, 0, 255);
  final image = img.Image(
    width: width,
    height: height,
    numChannels: 1,
    palette: palette,
  );
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelIndex(
        x,
        y,
        alternating
            ? x % 2
            : blue
            ? 1
            : 0,
      );
    }
  }
  return image;
}

Uint8List _rgbIcc({bool large = false}) {
  Uint8List xyz(List<double> values) {
    final data = Uint8List(20)..setRange(0, 4, 'XYZ '.codeUnits);
    final view = ByteData.sublistView(data);
    for (var i = 0; i < 3; i++) {
      view.setInt32(8 + i * 4, (values[i] * 65536).round());
    }
    return data;
  }

  final trc = Uint8List(large ? 12 + 65536 * 2 : 14)
    ..setRange(0, 4, 'curv'.codeUnits);
  final trcView = ByteData.sublistView(trc);
  trcView.setUint32(8, large ? 65536 : 1);
  if (large) {
    for (var i = 0; i < 65536; i++) {
      trcView.setUint16(12 + i * 2, i);
    }
  } else {
    trcView.setUint16(12, 563);
  }
  final chad = Uint8List(44)..setRange(0, 4, 'sf32'.codeUnits);
  for (final index in [0, 4, 8]) {
    ByteData.sublistView(chad).setInt32(8 + index * 4, 65536);
  }
  final tags = <String, Uint8List>{
    'wtpt': xyz([0.9642, 1, 0.8249]),
    'rXYZ': xyz([0.436, 0.222, 0.014]),
    'gXYZ': xyz([0.385, 0.717, 0.097]),
    'bXYZ': xyz([0.143, 0.061, 0.714]),
    'rTRC': trc,
    'gTRC': trc,
    'bTRC': trc,
    'chad': chad,
    'desc': Uint8List.fromList([
      ...'text'.codeUnits,
      0,
      0,
      0,
      0,
      ...'private device location'.codeUnits,
      0,
    ]),
    'cprt': Uint8List.fromList([
      ...'text'.codeUnits,
      0,
      0,
      0,
      0,
      ...'private device'.codeUnits,
      0,
    ]),
  };
  var total = 132 + tags.length * 12;
  for (final data in tags.values) {
    total += (data.length + 3) & ~3;
  }
  final result = Uint8List(total);
  final view = ByteData.sublistView(result)
    ..setUint32(0, total)
    ..setUint32(8, 0x04300000)
    ..setUint32(128, tags.length);
  result.setRange(12, 24, 'mntrRGB XYZ '.codeUnits);
  result.setRange(36, 40, 'acsp'.codeUnits);
  result.setRange(48, 52, 'SECR'.codeUnits);
  view
    ..setUint32(68, 0x0000f6d6)
    ..setUint32(72, 0x00010000)
    ..setUint32(76, 0x0000d32d);
  var offset = 132 + tags.length * 12;
  var i = 0;
  for (final entry in tags.entries) {
    final record = 132 + i++ * 12;
    result.setRange(record, record + 4, entry.key.codeUnits);
    view
      ..setUint32(record + 4, offset)
      ..setUint32(record + 8, entry.value.length);
    result.setRange(offset, offset + entry.value.length, entry.value);
    offset += (entry.value.length + 3) & ~3;
  }
  return result;
}

int _indexOf(Uint8List bytes, List<int> pattern) {
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    if (List.generate(
      pattern.length,
      (j) => bytes[i + j] == pattern[j],
    ).every((value) => value)) {
      return i;
    }
  }
  return -1;
}
