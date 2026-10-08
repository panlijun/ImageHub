import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/processing/domain/export_models.dart';
import 'package:imagehost/platform/android_export_gateway.dart';
import 'package:imagehost/platform/android_resource_gateway.dart';
import 'package:imagehost/platform/generated/android_files.g.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// Run on an Android emulator with a real DocumentsUI driver. This test opens
// native selectors, performs actual byte IO, and never invokes an image host.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'IT partial Android emulator native SAF MediaStore streaming and owned source fd regression',
    (tester) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'Actual Android native file bridges are required.',
      );
      final support = await getApplicationSupportDirectory();
      final canonical = await support.resolveSymbolicLinks();
      final root = Directory(canonical);
      final runId = const Uuid().v4();
      expect(
        await FileSystemEntity.type(canonical, followLinks: false),
        FileSystemEntityType.directory,
      );
      final fixture = File(p.join(root.path, 'android_bridge_fixture.png'));
      final secondFixture = File(
        p.join(root.path, 'android_bridge_fixture_copy.png'),
      );
      final state = File(p.join(root.path, 'android_bridge_state.json'));
      final invalidPhoto = File(
        p.join(root.path, 'android_bridge_not_image.json'),
      );
      final fixtureBytes = _noisePng();
      final fixtureSha = sha256.convert(fixtureBytes).toString();
      final fixtureLength = fixtureBytes.length;
      expect(fixtureLength, greaterThan(64 * 1024));
      // Completion includes flush and actual handle closure; the driver copies
      // only this test-owned file after it sees the first published phase.
      await fixture.writeAsBytes(fixtureBytes, flush: true);
      await secondFixture.writeAsBytes(fixtureBytes, flush: true);
      await invalidPhoto.writeAsString(
        '{"androidBridgeTest":true}',
        flush: true,
      );
      await _assertPrivateSource(fixture, root, fixtureSha, fixtureLength);
      await _assertPrivateSource(
        secondFixture,
        root,
        fixtureSha,
        fixtureLength,
      );

      final outcomes = <String, Object?>{};
      String? finalUri;
      String? finalName;
      Future<void> phase(String value) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: Text('Android file bridge: $value')),
            ),
          ),
        );
        await tester.pump();
        // writeAsString closes the actual file before any native operation below.
        await state.writeAsString(
          jsonEncode({
            'phase': value,
            'runId': runId,
            'fixtureSha': fixtureSha,
            'byteCount': fixtureLength,
            'uri': finalUri,
            'name': finalName,
            'results': outcomes,
          }),
          flush: true,
        );
      }

      final resources = AndroidResourceGateway();
      final native = _ObservedExportHost();
      final exporter = AndroidExportGateway(host: native);
      ExportInput input(File source, String name) => ExportInput(
        id: const Uuid().v4(),
        source: source,
        displayName: name,
        expectedSha256: fixtureSha,
        expectedByteCount: fixtureLength,
      );

      await phase('exportPhotos');
      final photosResults = await exporter.export([
        input(fixture, 'BridgePhoto.png'),
      ], photos: true);
      expect(photosResults, hasLength(1));
      outcomes['exportPhotos'] = photosResults.map(_evidence).toList();
      outcomes['nativeExportCodes'] = native.codes
          .map((code) => code.name)
          .toList();
      await phase('exportPhotos');
      _assertSaved(photosResults.single, nativeCode: native.codes.last);
      finalUri = photosResults.single.destinationUri;
      finalName = photosResults.single.fileName;
      await _assertPrivateSource(fixture, root, fixtureSha, fixtureLength);
      final duplicatePhotos = await exporter.export([
        input(secondFixture, 'BridgePhoto.png'),
      ], photos: true);
      expect(duplicatePhotos, hasLength(1));
      _assertSaved(duplicatePhotos.single, nativeCode: native.codes.last);
      expect(
        duplicatePhotos.single.destinationUri,
        isNot(photosResults.single.destinationUri),
        reason: 'A same-name photo must create a new media identity.',
      );
      outcomes['exportPhotosDuplicate'] = duplicatePhotos
          .map(_evidence)
          .toList();

      await phase('importFile');
      final fileSelection = await resources.pick();
      outcomes['importFile'] = await _readSelection(
        fileSelection,
        'file',
        fixtureSha,
        fixtureLength,
      );

      await phase('importPhoto');
      final photoSelection = await resources.pick(photos: true);
      outcomes['importPhoto'] = await _readSelection(
        photoSelection,
        'photo',
        fixtureSha,
        fixtureLength,
      );

      await phase('cancelledImport');
      final cancelledSelection = await resources.pick();
      try {
        expect(cancelledSelection, isEmpty);
        outcomes['cancelledImport'] = <Object?>[];
      } finally {
        await _releaseAll(cancelledSelection);
      }

      await phase('exportDocument');
      final documentResults = await exporter.export([
        input(fixture, 'BridgeDocument.png'),
      ]);
      expect(documentResults, hasLength(1));
      _assertSaved(documentResults.single);
      outcomes['exportDocument'] = documentResults.map(_evidence).toList();
      await _assertPrivateSource(fixture, root, fixtureSha, fixtureLength);

      await phase('exportTree');
      final treeInputs = [
        input(fixture, 'BridgeExport.png'),
        input(secondFixture, 'BridgeExport.png'),
      ];
      expect(treeInputs.map((item) => item.id).toSet(), hasLength(2));
      final treeResults = await exporter.export(treeInputs);
      expect(treeResults, hasLength(2));
      for (final result in treeResults) {
        _assertSaved(result);
      }
      expect(
        treeResults.map((item) => item.fileName).toSet(),
        hasLength(2),
        reason:
            'Same-name files must create distinct names without overwriting.',
      );
      expect(
        treeResults.map((item) => item.destinationUri).toSet(),
        hasLength(2),
      );
      outcomes['exportTree'] = treeResults.map(_evidence).toList();
      await _assertPrivateSource(fixture, root, fixtureSha, fixtureLength);
      await _assertPrivateSource(
        secondFixture,
        root,
        fixtureSha,
        fixtureLength,
      );

      await phase('sourceFdRegression');
      AndroidExportRequest rejectedRequest({
        required String sourcePath,
        required String expectedSha,
        required int length,
      }) => AndroidExportRequest(
        operationId: const Uuid().v4(),
        sourcePath: sourcePath,
        displayName: 'BridgeRejected.png',
        mimeType: 'image/png',
        sha256: expectedSha,
        byteCount: length,
        kind: AndroidDestinationKind.photos,
      );
      Future<AndroidExportReply> wrongSha() => native.exportFile(
        rejectedRequest(
          sourcePath: fixture.path,
          expectedSha: '0' * 64,
          length: fixtureLength,
        ),
      );
      // Warm native execution and channel allocations before measuring handles.
      _assertRejected(await wrongSha());
      final before = await _descriptorCount();
      final rejected = <String>[];
      for (var index = 0; index < 32; index++) {
        final reply = await wrongSha();
        _assertRejected(reply);
        expect(reply.code, AndroidIoCode.inputChanged);
        rejected.add(reply.code.name);
      }
      final after = await _descriptorCount();
      expect(
        after - before,
        lessThanOrEqualTo(4),
        reason: 'Failed pre-insert source validation must close each owned OS descriptor.',
      );

      final external = await native.exportFile(
        rejectedRequest(
          sourcePath: '/storage/emulated/0/Download/ImageHostBridgeFixture/BridgeFixture.png',
          expectedSha: fixtureSha,
          length: fixtureLength,
        ),
      );
      _assertRejected(external);
      expect(external.code, AndroidIoCode.invalidInput);
      final invalidBytes = await invalidPhoto.readAsBytes();
      final nonImage = await native.exportFile(
        rejectedRequest(
          sourcePath: invalidPhoto.path,
          expectedSha: sha256.convert(invalidBytes).toString(),
          length: invalidBytes.length,
        ),
      );
      _assertRejected(nonImage);
      expect(nonImage.code, AndroidIoCode.invalidInput);
      outcomes['sourceFdRegression'] = {
        'before': before,
        'after': after,
        'wrongSha': rejected,
        'externalSource': external.code.name,
        'nonImage': nonImage.code.name,
      };
      await _assertPrivateSource(fixture, root, fixtureSha, fixtureLength);
      await _assertPrivateSource(
        secondFixture,
        root,
        fixtureSha,
        fixtureLength,
      );
      await phase('complete');
      final acknowledgement = File(
        p.join(root.path, 'android_bridge_ack-$runId'),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!await acknowledgement.exists() &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        await acknowledgement.exists(),
        isTrue,
        reason: 'The owned driver must preserve final evidence before test-tool uninstall.',
      );
      // Keep all test-owned evidence for independent ADB inspection. There is
      // no recursive deletion, fixture-source mutation, or server request.
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Uint8List _noisePng() {
  final image = img.Image(width: 320, height: 256, numChannels: 4);
  var value = 0x13579bdf;
  int next() {
    value ^= (value << 13) & 0xffffffff;
    value ^= value >> 17;
    value ^= (value << 5) & 0xffffffff;
    value &= 0xffffffff;
    return value & 255;
  }

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, next(), next(), next(), 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Future<List<Map<String, Object?>>> _readSelection(
  List<PlatformResource> resources,
  String sourceType,
  String expectedSha,
  int expectedLength,
) async {
  final evidence = <Map<String, Object?>>[];
  try {
    expect(resources, hasLength(1));
    for (final resource in resources) {
      expect(resource.sourceType, sourceType);
      // No size is assumed from metadata. Count the actual selected source bytes.
      final chunks = await resource.read().toList();
      expect(chunks, isNotEmpty);
      for (final chunk in chunks) {
        expect(chunk.length, inInclusiveRange(1, 64 * 1024));
      }
      expect(chunks.length, greaterThan(1));
      final bytes = BytesBuilder(copy: false);
      for (final chunk in chunks) {
        bytes.add(chunk);
      }
      final selectedBytes = bytes.takeBytes();
      final digest = sha256.convert(selectedBytes).toString();
      expect(selectedBytes.length, expectedLength);
      expect(digest, expectedSha);
      evidence.add({
        'sourceType': sourceType,
        'byteCount': selectedBytes.length,
        'sha256': digest,
        'chunks': chunks.length,
      });
    }
  } finally {
    await _releaseAll(resources);
  }
  return evidence;
}

Future<void> _releaseAll(List<PlatformResource> resources) async {
  var failed = false;
  for (final resource in resources) {
    try {
      await resource.release!();
    } catch (_) {
      failed = true;
    }
  }
  if (failed) throw const ResourceFailure(FailureKind.storage);
}

Future<void> _assertPrivateSource(
  File file,
  Directory root,
  String digest,
  int count,
) async {
  expect(
    await FileSystemEntity.type(file.path, followLinks: false),
    FileSystemEntityType.file,
  );
  expect(p.dirname(await file.resolveSymbolicLinks()), root.path);
  final bytes = await file.readAsBytes();
  expect(bytes.length, count);
  expect(sha256.convert(bytes).toString(), digest);
}

void _assertSaved(ExportItemResult result, {AndroidIoCode? nativeCode}) {
  expect(
    result.status,
    ExportStatus.saved,
    reason: 'Native code: ${nativeCode?.name}; safe feedback: ${result.reason}',
  );
  final uri = Uri.tryParse(result.destinationUri ?? '');
  expect(uri?.scheme, 'content');
  expect(uri?.authority.isNotEmpty, isTrue);
  expect(result.fileName?.isNotEmpty, isTrue);
  expect(result.destinationPath, isNull);
  expect(
    result.reason,
    isNull,
    reason: 'A confirmed save with unconfirmed cleanup requires separate investigation.',
  );
}

Map<String, Object?> _evidence(ExportItemResult result) => {
  'status': result.status.name,
  'uri': result.destinationUri,
  'name': result.fileName,
};

void _assertRejected(AndroidExportReply reply) {
  expect(reply.code, isNot(AndroidIoCode.ok));
  expect(reply.uri, isNull);
  expect(reply.displayName, isNull);
}

Future<int> _descriptorCount() async {
  final entries = await Directory('/proc/self/fd')
      .list(followLinks: false)
      .toList();
  expect(
    entries,
    isNotEmpty,
    reason: 'Descriptor accounting is mandatory for this regression; unavailable accounting is a failure.',
  );
  return entries.length;
}

// Observes the actual generated platform channel; it never substitutes replies.
final class _ObservedExportHost extends AndroidExportHost {
  final codes = <AndroidIoCode>[];

  @override
  Future<AndroidExportReply> exportFile(AndroidExportRequest request) async {
    final reply = await super.exportFile(request);
    codes.add(reply.code);
    return reply;
  }
}
