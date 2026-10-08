import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/bake_image_orientation.dart';
import 'package:imagehost/core/image_inspector.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/png_orientation.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/image_processor.dart';
import 'package:imagehost/features/processing/application/metadata_policy.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';

import 'png_orientation_fixture.dart';

const _budget = 128 * 1024 * 1024;

void main() {
  for (final size in [(2, 3), (3, 2), (3, 3), (3, 5), (5, 3), (1, 3), (3, 1)]) {
    test(
      'UT-028 orientation 3 preserves every pixel across odd ${size.$1}x${size.$2} geometry',
      () {
        final source = img.Image(
          width: size.$1,
          height: size.$2,
          numChannels: 4,
        );
        for (final pixel in source) {
          final index = pixel.y * source.width + pixel.x;
          pixel.setRgba(5 + index * 10, 240 - index * 10, 70 + index * 5, 255);
        }
        source.exif.imageIfd
          ..orientation = 3
          ..make = 'test device';
        source.textData = {'colour-test': 'unchanged'};
        final transformed = bakeImageOrientation(source);
        expect(
          [transformed.width, transformed.height, transformed.numFrames],
          [source.width, source.height, 1],
        );
        for (var y = 0; y < source.height; y++) {
          for (var x = 0; x < source.width; x++) {
            final expected = source.getPixel(
              source.width - 1 - x,
              source.height - 1 - y,
            );
            final actual = transformed.getPixel(x, y);
            expect(
              [actual.r, actual.g, actual.b, actual.a],
              [expected.r, expected.g, expected.b, expected.a],
              reason: 'pixel ($x,$y)',
            );
          }
        }
        expect(transformed.exif.imageIfd.orientation, isNull);
        expect(transformed.exif.imageIfd.make, 'test device');
        expect(transformed.textData, source.textData);
        expect(source.exif.imageIfd.orientation, 3);
        expect(source.getPixel(0, 0).r, 5);
      },
    );
  }
  final base = img.encodePng(orientationMatrix());
  final invalid = isA<ResourceFailure>().having(
    (failure) => failure.kind,
    'kind',
    FailureKind.invalidImage,
  );
  test('UT-028 PNG absent orientation and valid empty TIFF default to 1', () {
    expect(readPngOrientation(base), 1);
    final tiff = Uint8List(14);
    ByteData.sublistView(tiff)
      ..setUint16(0, 0x4949)
      ..setUint16(2, 42, Endian.little)
      ..setUint32(4, 8, Endian.little);
    expect(readPngOrientation(addPngExif(base, tiff)), 1);
  });
  for (final endian in [Endian.little, Endian.big]) {
    for (var orientation = 1; orientation <= 8; orientation++) {
      test('UT-028 PNG TIFF $endian reads orientation $orientation', () {
        expect(
          readPngOrientation(
            addPngExif(base, orientationTiff(orientation, endian: endian)),
          ),
          orientation,
        );
      });
    }
  }
  final malformed = <String, Uint8List>{
    'out of range zero': orientationTiff(0),
    'out of range nine': orientationTiff(9),
    'wrong type': orientationTiff(6, type: 4),
    'wrong count zero': orientationTiff(6, count: 0),
    'wrong count two': orientationTiff(6, count: 2),
    'duplicate field': orientationTiff(6, duplicate: true),
    'truncated TIFF': Uint8List.fromList([0x49, 0x49, 42]),
    'invalid IFD pointer': Uint8List.fromList(orientationTiff(6))..[4] = 255,
    'invalid byte order': Uint8List.fromList(orientationTiff(6))..[0] = 0,
    'invalid TIFF magic': Uint8List.fromList(orientationTiff(6))..[2] = 43,
    'truncated entries': Uint8List.fromList(orientationTiff(6))..[8] = 2,
    'invalid next IFD': Uint8List.fromList(orientationTiff(6))..[22] = 255,
    'self-referencing next IFD': Uint8List.fromList(orientationTiff(6))
      ..[22] = 8,
  };
  for (final entry in malformed.entries) {
    test(
      'UT-028 malformed PNG ${entry.key} rejects with fixed classification',
      () {
        final bytes = addPngExif(base, entry.value);
        expect(() => readPngOrientation(bytes), throwsA(invalid));
        expect(
          () => MetadataPolicy.inspect(bytes, 'PNG'),
          throwsA(
            isA<ProcessingFailure>().having(
              (failure) => failure.kind,
              'kind',
              ProcessingFailureKind.invalidImage,
            ),
          ),
        );
      },
    );
  }
  test(
    'UT-028 PNG duplicate eXIf, chunk CRC, boundary and trailing bytes reject',
    () {
      final bytes = addPngExif(base, orientationTiff(6));
      final crc = Uint8List.fromList(bytes)..[45] ^= 1;
      final huge = Uint8List.fromList(bytes);
      ByteData.sublistView(huge).setUint32(33, 0xffffffff);
      for (final invalidBytes in [
        addPngExif(base, orientationTiff(6), duplicate: true),
        crc,
        huge,
        Uint8List.fromList(bytes.sublist(0, bytes.length - 1)),
        Uint8List.fromList([...bytes, 0]),
      ]) {
        expect(() => readPngOrientation(invalidBytes), throwsA(invalid));
      }
    },
  );
  for (var orientation = 1; orientation <= 8; orientation++) {
    test(
      'UT-028/IT-002 actual PNG $orientation import, thumbnail, compression, crop and stitch agree exactly',
      () async {
        final sandbox = await Directory.systemTemp.createTemp(
          'imagehost_png_orientation_',
        );
        final repository = await LibraryRepository.open(
          Directory('${sandbox.path}/library'),
        );
        final results = <ProcessingResult>[];
        try {
          final bytes = addPngExif(base, orientationTiff(orientation));
          final imported = await repository.importResource(
            PlatformResource(
              displayName: 'oriented.png',
              openRead: () => Stream.value(bytes),
            ),
          );
          expect(imported.status, ImportStatus.saved);
          final asset = imported.asset!;
          final width = orientation >= 5 ? 3 : 2;
          final height = orientation >= 5 ? 2 : 3;
          expect(
            [
              asset.version.width,
              asset.version.height,
              asset.version.orientation,
            ],
            [width, height, orientation],
          );
          final original = await repository.originalFor(asset);
          expect(await original.readAsBytes(), bytes);
          final thumbnail = await const ImageInspector(_budget).thumbnailBytes(
            original,
            expectedSha256: asset.version.sha256,
            expectedByteCount: bytes.length,
          );
          final pixels = orientedPixelIndices[orientation]!;
          _expectPixels(img.decodePng(thumbnail)!, width, height, pixels);
          expect(img.decodePng(thumbnail)!.numFrames, 1);
          final input = ProcessingInput(
            file: original,
            assetId: asset.id,
            version: asset.version,
          );
          final compressed = await const ImageProcessor().process(
            ProcessingRequest(
              operation: ProcessingOperation.compress,
              inputs: [input],
            ),
          );
          results.add(compressed);
          _expectPixels(
            img.decodePng(await compressed.file.readAsBytes())!,
            width,
            height,
            pixels,
          );
          expect(compressed.version.orientation, 1);
          expect(compressed.fidelityPreserved, true);
          expect(
            MetadataPolicy.inspect(
              await compressed.file.readAsBytes(),
              'PNG',
            ).orientation,
            1,
          );
          final roundTrip = await const ImageProcessor().process(
            ProcessingRequest(
              operation: ProcessingOperation.compress,
              inputs: [
                ProcessingInput(
                  file: compressed.file,
                  assetId: asset.id,
                  version: compressed.version,
                ),
              ],
            ),
          );
          results.add(roundTrip);
          _expectPixels(
            img.decodePng(await roundTrip.file.readAsBytes())!,
            width,
            height,
            pixels,
          );
          final crop = await const ImageProcessor().process(
            ProcessingRequest(
              operation: ProcessingOperation.crop,
              inputs: [input],
              crop: const PixelCrop(1, 0, 1, 1),
            ),
          );
          results.add(crop);
          _expectPixels(img.decodePng(await crop.file.readAsBytes())!, 1, 1, [
            pixels[1],
          ]);
          final stitch = await const ImageProcessor().process(
            ProcessingRequest(
              operation: ProcessingOperation.stitch,
              inputs: [input, input],
              layout: StitchLayout.horizontal,
            ),
          );
          results.add(stitch);
          _expectPixels(
            img.decodePng(await stitch.file.readAsBytes())!,
            width * 2,
            height,
            [
              for (var y = 0; y < height; y++) ...[
                ...pixels.sublist(y * width, (y + 1) * width),
                ...pixels.sublist(y * width, (y + 1) * width),
              ],
            ],
          );
          expect(await original.readAsBytes(), bytes);
        } finally {
          for (final result in results) {
            await result.dispose();
          }
          await repository.close();
          await sandbox.delete(recursive: true);
        }
      },
    );
  }
  test('UT-002/UT-028 malformed or ambiguous PNG eXIf creates no usable asset and preserves existing original', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'imagehost_png_invalid_',
    );
    final repository = await LibraryRepository.open(
      Directory('${sandbox.path}/library'),
    );
    try {
      final saved = (await repository.importResource(
        PlatformResource(
          displayName: 'original.png',
          openRead: () => Stream.value(base),
        ),
      )).asset!;
      for (final bytes in [
        addPngExif(base, orientationTiff(0)),
        addPngExif(base, orientationTiff(6), duplicate: true),
      ]) {
        final rejected = await repository.importResource(
          PlatformResource(
            displayName: 'invalid.png',
            openRead: () => Stream.value(bytes),
          ),
        );
        expect(rejected.status, ImportStatus.failed);
        expect(rejected.failure?.kind, FailureKind.invalidImage);
        expect((await repository.listAssets()).total, 1);
      }
      expect(await (await repository.originalFor(saved)).readAsBytes(), base);
    } finally {
      await repository.close();
      await sandbox.delete(recursive: true);
    }
  });
  test('UT-028 frozen legacy PNG version with incorrect orientation refuses inputChanged without mutation', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'imagehost_png_legacy_',
    );
    try {
      final bytes = addPngExif(base, orientationTiff(6));
      final file = await File('${sandbox.path}/input.png').writeAsBytes(bytes);
      final metadata = await const ImageInspector(_budget).inspect(file);
      expect(
        [metadata.width, metadata.height, metadata.orientation],
        [3, 2, 6],
      );
      final old = ImageVersion(
        id: 'legacy',
        sha256: _digest(bytes),
        byteCount: bytes.length,
        format: 'PNG',
        width: 2,
        height: 3,
        frameCount: 1,
        orientation: 1,
      );
      final destination = File('${sandbox.path}/result.png');
      await expectLater(
        const ImageProcessor().process(
          ProcessingRequest(
            operation: ProcessingOperation.compress,
            inputs: [
              ProcessingInput(file: file, assetId: 'asset', version: old),
            ],
          ),
          destination: destination,
        ),
        throwsA(
          isA<ProcessingFailure>().having(
            (failure) => failure.kind,
            'kind',
            ProcessingFailureKind.inputChanged,
          ),
        ),
      );
      expect(await file.readAsBytes(), bytes);
      expect(await destination.exists(), false);
      expect(old.orientation, 1);
    } finally {
      await sandbox.delete(recursive: true);
    }
  });
  test('UT-028 animated PNG orientation thumbnail detaches the explicitly selected frame', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'imagehost_png_frame_',
    );
    try {
      final animation = orientationMatrix()
        ..addFrame(orientationMatrix(reverse: true));
      final bytes = addPngExif(img.encodePng(animation), orientationTiff(6));
      final file = await File('${sandbox.path}/animation.png')
          .writeAsBytes(bytes);
      final metadata = await const ImageInspector(_budget).inspect(file);
      expect(
        [
          metadata.width,
          metadata.height,
          metadata.frameCount,
          metadata.orientation,
        ],
        [3, 2, 2, 6],
      );
      for (var frame = 0; frame < 2; frame++) {
        final result = img.decodePng(
          await const ImageInspector(_budget).thumbnailBytes(
            file,
            expectedSha256: _digest(bytes),
            expectedByteCount: bytes.length,
            frame: frame,
          ),
        )!;
        expect(result.numFrames, 1);
        _expectPixels(result, 3, 2, [
          for (final index in orientedPixelIndices[6]!)
            frame == 0 ? index : 5 - index,
        ]);
      }
      final version = ImageVersion(
        id: 'animated',
        sha256: _digest(bytes),
        byteCount: bytes.length,
        format: 'PNG',
        width: 3,
        height: 2,
        frameCount: 2,
        orientation: 6,
      );
      final output = await const ImageProcessor().process(
        ProcessingRequest(
          operation: ProcessingOperation.crop,
          inputs: [
            ProcessingInput(
              file: file,
              assetId: 'animation',
              version: version,
              selectedFrame: 1,
            ),
          ],
          crop: const PixelCrop(1, 0, 1, 1),
          explicitStaticConversion: true,
        ),
      );
      try {
        _expectPixels(img.decodePng(await output.file.readAsBytes())!, 1, 1, [
          5 - orientedPixelIndices[6]![1],
        ]);
        expect(output.animationRemoved, true);
      } finally {
        await output.dispose();
      }
      expect(await file.readAsBytes(), bytes);
    } finally {
      await sandbox.delete(recursive: true);
    }
  });
}

void _expectPixels(img.Image image, int width, int height, List<int> indices) {
  expect([image.width, image.height], [width, height]);
  for (var i = 0; i < indices.length; i++) {
    final pixel = image.getPixel(i % width, i ~/ width);
    expect(
      [pixel.r, pixel.g, pixel.b, pixel.a],
      matrixPixel(indices[i]),
      reason: 'pixel $i',
    );
  }
  expect(image.exif.imageIfd.orientation ?? 1, 1);
}

String _digest(Uint8List bytes) => sha256.convert(bytes).toString();
