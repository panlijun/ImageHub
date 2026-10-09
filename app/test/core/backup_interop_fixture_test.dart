import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../integration_test/support/backup_interop_harness.dart';

void main() {
  late Directory sandbox;
  late BackupInteropHarness harness;
  late Map<String, Object?> expected;
  late InteropOwnedScene scene;
  var success = false;
  setUp(() async {
    final temporary = Directory(
      await Directory.systemTemp.resolveSymbolicLinks(),
    );
    scene = await InteropOwnedScene.create(temporary);
    sandbox = scene.directory;
    success = false;
    // Controlled test callbacks only; native capacity/publication is separately
    // required by the CLI and integration entry points.
    harness = BackupInteropHarness(
      availableBytes: (_) async => 1 << 40,
      publishExclusive: (source, target) async {
        if (await target.exists()) return false;
        await source.rename(target.path);
        return true;
      },
    );
    expected = await harness.exportFixtures(sandbox, scene: scene);
  });
  tearDown(() async {
    if (success) {
      await scene.removeAfterSuccess();
    }
  });

  for (final mode in ['full', 'metadata']) {
    test(
      'CT-006 fixture $mode includes four formats recycled and independent bytes and reopens',
      () async {
        final packages = expected['packages'] as Map<String, Object?>;
        final row = packages[mode] as Map<String, Object?>;
        final manifest = row['manifest'] as Map<String, Object?>;
        final versions = manifest['versions'] as List;
        expect(versions.length, 5);
        expect(versions.map((v) => (v as Map)['format']).toSet(), {
          'PNG',
          'JPEG',
          'GIF',
          'BMP',
        });
        expect((manifest['assets'] as List).length, 4);
        expect(
          (manifest['assets'] as List).where(
            (a) => (a as Map)['recycled'] == true,
          ),
          hasLength(1),
        );
        final root = await Directory(p.join(sandbox.path, 'consume-$mode'))
            .create();
        await scene.recordDirectory(root);
        final result = await harness.verifyPackage(
          File(p.join(sandbox.path, 'exports', row['fileName'] as String)),
          row,
          root,
          originPlatform: expected['originPlatform'] as String,
          scene: scene,
        );
        expect(result['closedAndReopened'], true);
        expect(result['restoredSettings'], hasLength(8));
        expect(result['skippedSettings'], isEmpty);
        success = true;
      },
    );
  }

  test(
    'CT-006 fixture transport mismatch rejects before restore creation',
    () async {
      final row = Map<String, Object?>.from(
        (expected['packages'] as Map)['full'] as Map,
      );
      row['sha256'] = List.filled(64, '0').join();
      final root = await Directory(p.join(sandbox.path, 'rejected')).create();
      await scene.recordDirectory(root);
      await expectLater(
        harness.verifyPackage(
          File(p.join(sandbox.path, 'exports', row['fileName'] as String)),
          row,
          root,
          originPlatform: expected['originPlatform'] as String,
        ),
        throwsStateError,
      );
      expect(await root.list().toList(), isEmpty);
      success = true;
    },
  );

  Future<String> payload() => encodeInteropPayload(
    expected,
    Directory(p.join(sandbox.path, 'exports')),
  );

  test('CT-006 payload rejects a changed archive hash', () async {
    final encoded = await payload();
    final decoded = jsonDecode(utf8.decode(base64Decode(encoded))) as Map;
    ((decoded['expectation'] as Map)['packages'] as Map)['full']['sha256'] =
        List.filled(64, '0').join();
    final changed = base64Encode(utf8.encode(jsonEncode(decoded)));
    expect(() => BackupInteropPayload.decode(changed), throwsStateError);
    success = true;
  });

  test('CT-006 matrix rejects duplicate actual origins', () async {
    final encoded = await payload();
    expect(() => validateInteropMatrix([encoded, encoded]), throwsStateError);
    success = true;
  });

  test('CT-006 capture accepts exactly one prefixed validated payload and rejects two', () async {
    final encoded = await payload();
    expect(
      captureInteropPayload([
        'ordinary log',
        'timestamp $interopExportPrefix$encoded',
      ]).originPlatform,
      expected['originPlatform'],
    );
    expect(
      () => captureInteropPayload([
        '$interopExportPrefix$encoded',
        '$interopExportPrefix$encoded',
      ]),
      throwsStateError,
    );
    expect(() => captureInteropPayload(['ordinary log']), throwsStateError);
    success = true;
  });

  test(
    'CT-006 cleanup retains an unknown ordinary file and all registered bytes',
    () async {
      final unknown = await File(p.join(sandbox.path, 'unknown.txt'))
          .writeAsString('unknown', flush: true);
      await expectLater(scene.removeAfterSuccess(), throwsStateError);
      expect(await unknown.readAsString(), 'unknown');
      expect(await File(p.join(sandbox.path, '.interop-owner')).exists(), true);
      await unknown.delete();
      success = true;
    },
  );
}
