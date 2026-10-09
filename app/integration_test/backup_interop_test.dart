import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'support/apple_xctest_startup.dart';
import 'support/backup_interop_harness.dart';

void main() {
  if (const bool.fromEnvironment('IMAGEHUB_BACKUP_EXPORT')) {
    runBackupInteropExport();
  } else {
    runEmbeddedBackupInterop(
      const String.fromEnvironment('IMAGEHUB_BACKUP_INTEROP'),
    );
  }
}

/// Preserves the single external-origin contract; self-origin always rejects.
void runEmbeddedBackupInterop(String payload) {
  final decoded = BackupInteropPayload.decode(payload);
  interopRequire(
    decoded.originPlatform != Platform.operatingSystem,
    'external-platform-required',
  );
  _initializeBinding();
  _registerConsumer(decoded);
}

/// Each distinct external origin receives its own full+metadata native test.
/// A self-origin fixture is explicitly skipped and never counts as a success.
void runBackupInteropMatrix(
  List<String> payloads, {
  bool exportCurrent = false,
}) {
  final decoded = validateInteropMatrix(payloads);
  interopRequire(
    decoded.any((p) => p.originPlatform != Platform.operatingSystem),
    'matrix-external-origin-required',
  );
  _initializeBinding();
  if (exportCurrent) {
    runBackupInteropExport();
  }
  for (final payload in decoded) {
    if (payload.originPlatform == Platform.operatingSystem) {
      testWidgets(
        'CT-006 ${payload.originPlatform} self-origin explicitly skipped',
        (tester) async {},
        skip: true,
      );
    } else {
      _registerConsumer(payload);
    }
  }
}

void runBackupInteropExport() {
  final binding = _initializeBinding();
  testWidgets(
    'CT-006 ${Platform.operatingSystem} actual closed full and metadata exports',
    (tester) async {
      final scene = await InteropOwnedScene.create(
        await getTemporaryDirectory(),
      );
      const capacity = StorageCapacity();
      final harness = BackupInteropHarness(
        availableBytes: capacity.availableBytes,
        publishExclusive: capacity.publishExclusive,
      );
      final expectation = await harness.exportFixtures(
        scene.directory,
        scene: scene,
      );
      final encoded = await encodeInteropPayload(
        expectation,
        Directory(p.join(scene.directory.path, 'exports')),
      );
      await scene.removeAfterSuccess();
      await _writeIosXctestEvidence('export.json', {
        'fixtureVersion': 1,
        'encoded': encoded,
      }, createRoot: true);
      binding.reportData ??= <String, dynamic>{};
      (binding.reportData!.putIfAbsent(
        'imageHubBackupExports',
        () => <String>[],
      ) as List<String>).add(encoded);
      // Only this validated synthetic payload is emitted; no host paths or secrets.
      // ignore: avoid_print
      print('$interopExportPrefix$encoded');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

void _registerConsumer(BackupInteropPayload payload) {
  final binding = _initializeBinding();
  testWidgets(
    'CT-006/IT-005/BAK-005 ${payload.originPlatform} to ${Platform.operatingSystem} actual full metadata restore reopen',
    (tester) async {
      final scene = await InteropOwnedScene.create(
        await getTemporaryDirectory(),
      );
      const capacity = StorageCapacity();
      final harness = BackupInteropHarness(
        availableBytes: capacity.availableBytes,
        publishExclusive: capacity.publishExclusive,
      );
      final results = <Object?>[];
      final packages = payload.expectation['packages'] as Map;
      for (final mode in ['full', 'metadata']) {
        final file = File(p.join(scene.directory.path, '$mode.zip'));
        await file.create(exclusive: true);
        await file.writeAsBytes(payload.bytes[mode]!, flush: true);
        await scene.recordFile(file);
        final root = await Directory(p.join(scene.directory.path, mode))
            .create();
        await scene.recordDirectory(root);
        results.add(
          await harness.verifyPackage(
            file,
            Map<String, Object?>.from(packages[mode] as Map),
            root,
            originPlatform: payload.originPlatform,
            scene: scene,
          ),
        );
      }
      await scene.removeAfterSuccess();
      await _writeIosXctestEvidence('${payload.originPlatform}.json', {
        'fixtureVersion': 1,
        'results': results,
      });
      binding.reportData ??= <String, dynamic>{};
      (binding.reportData!.putIfAbsent(
        'imageHubBackupInteropResults',
        () => <Object?>[],
      ) as List<Object?>).add(results);
      // ignore: avoid_print
      print(jsonEncode({'backupInteropResults': results}));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

IntegrationTestWidgetsFlutterBinding _initializeBinding() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerAppleXctestStartup(binding);
  return binding;
}

/// Closed synthetic evidence for the dedicated native XCTest CI entry only.
/// A fresh owned simulator is required; existing/unknown files are preserved.
Future<void> _writeIosXctestEvidence(
  String name,
  Map<String, Object?> value, {
  bool createRoot = false,
}) async {
  if (!const bool.fromEnvironment('IMAGEHUB_XCTEST_EVIDENCE')) return;
  interopRequire(Platform.isIOS, 'xctest-ios-only');
  interopRequire(
    {
      'export.json',
      'windows.json',
      'android.json',
      'macos.json',
    }.contains(name),
    'xctest-evidence-name',
  );
  final parent = Directory(
    await (await getTemporaryDirectory()).resolveSymbolicLinks(),
  );
  final root = Directory(
    p.join(parent.path, 'imagehub-ios-xctest-evidence-v1'),
  );
  final type = await FileSystemEntity.type(root.path, followLinks: false);
  if (createRoot) {
    interopRequire(type == FileSystemEntityType.notFound, 'xctest-fresh-root');
    await root.create();
  } else {
    interopRequire(type == FileSystemEntityType.directory, 'xctest-owned-root');
  }
  interopRequire(
    await root.resolveSymbolicLinks() == root.path &&
        p.dirname(root.path) == parent.path,
    'xctest-root-containment',
  );
  final bytes = utf8.encode(jsonEncode(value));
  interopRequire(bytes.length <= 256 * 1024, 'xctest-evidence-budget');
  final file = File(p.join(root.path, name));
  await file.create(exclusive: true);
  await file.writeAsBytes(bytes, flush: true);
}
