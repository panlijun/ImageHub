import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';

List<int> fixture() {
  final image = img.Image(width: 9, height: 7);
  img.fill(image, color: img.ColorRgb8(54, 113, 196));
  return img.encodePng(image);
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    final mode = args[0];
    final root = Directory(args[1]);
    final boundary = args.length > 2 ? args[2] : '';
    var fixtureImported = false;
    final repository = await LibraryRepository.open(
      root,
      outputFaultHook: mode == 'interrupt'
          ? (b) async {
              if (b.name == boundary) {
                if (b == OutputBoundary.intent) {
                  final file = Directory('${root.path}/cache/outputs');
                  // Leave an actual partial managed file to test startup disposal.
                  final output = (await repositoryForPartial(root)).single;
                  await File('${file.path}/$output.png.part')
                      .writeAsBytes([1, 2, 3], flush: true);
                }
                exit(73);
              }
            }
          : null,
      faultHook: mode == 'save-interrupt'
          ? (b) async {
              if (fixtureImported && b == ImportBoundary.beforeDbCommit) {
                exit(73);
              }
            }
          : null,
    );
    if (mode != 'verify') {
      final imported = await repository.importResource(
        PlatformResource(
          displayName: 'source.png',
          openRead: () => Stream.value(fixture()),
        ),
      );
      if (!imported.persisted) throw StateError('Fixture import failed');
      fixtureImported = true;
      final epoch = mode == 'interrupt' && boundary == 'beforeDelete'
          ? DateTime.now().toUtc().subtract(const Duration(hours: 25))
          : DateTime.now().toUtc();
      final output = await withClock(
        Clock.fixed(epoch),
        () => ProcessingCoordinator(repository).process(
          [imported.asset!.id],
          (inputs) => ProcessingRequest(
            operation: ProcessingOperation.crop,
            inputs: inputs,
            crop: const PixelCrop(1, 1, 3, 2),
          ),
          displayName: 'crop.png',
        ),
      );
      if (mode == 'save-interrupt') await repository.saveOutput(output.id);
      if (boundary == 'beforeDelete') await repository.cleanupOutputs();
    }
    final outputs = await repository.listOutputs();
    final assets = await repository.listAssets();
    for (final asset in assets.items) {
      if (await repository.verifyCopy(asset) != CopyAvailability.available) {
        throw StateError('Permanent bytes unavailable');
      }
    }
    for (final output in outputs.where((o) => o.usable)) {
      final decoded = img.decodeImage(await output.file!.readAsBytes());
      if (decoded == null || decoded.width != 3 || decoded.height != 2) {
        throw StateError('Output pixels invalid');
      }
    }
    var originCount = 0;
    for (final asset in assets.items) {
      originCount += (await repository.savedOutputOrigins(asset.version.id))
          .length;
    }
    stdout.writeln(
      jsonEncode({
        'outputIds': outputs.map((o) => o.id).toList(),
        'states': outputs.map((o) => o.state.name).toList(),
        'usable': outputs.where((o) => o.usable).length,
        'assetIds': assets.items.map((a) => a.id).toList(),
        'assets': assets.total,
        'origins': originCount,
        'issues': repository.recoveryIssues.length,
        'parts': (await Directory(
          '${root.path}/cache/outputs',
        ).list().toList()).where((f) => f.path.endsWith('.part')).length,
      }),
    );
    await repository.close();
    return;
  }
  final sandbox = await Directory.systemTemp.createTemp(
    'imagehost_output_process_',
  );
  final script = Platform.script.toFilePath();
  Future<ProcessResult> child(List<String> values) => Process.run(
    Platform.resolvedExecutable,
    ['run', script, ...values],
    workingDirectory: Directory.current.path,
  );
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  try {
    for (final boundary in OutputBoundary.values) {
      final root = '${sandbox.path}/${boundary.name}';
      final interrupted = await child(['interrupt', root, boundary.name]);
      require(
        interrupted.exitCode == 73,
        'Boundary did not terminate: ${boundary.name}: ${interrupted.stderr}',
      );
      final verified = await child(['verify', root]);
      require(verified.exitCode == 0, 'Recovery failed: ${verified.stderr}');
      final result = jsonDecode(verified.stdout.toString().trim()) as Map;
      final expected =
          boundary == OutputBoundary.intent ||
              boundary == OutputBoundary.beforeDelete
          ? 0
          : 1;
      require(
        result['usable'] == expected &&
            result['assets'] == 1 &&
            result['parts'] == 0 &&
            result['issues'] == 0,
        'Unexpected recovery: $result',
      );
      if (boundary == OutputBoundary.intent) {
        require(
          (result['states'] as List).single == 'failed',
          'Partial reported ready',
        );
      }
      if (boundary == OutputBoundary.beforeDelete) {
        require(
          (result['outputIds'] as List).isEmpty,
          'Delete intent incomplete',
        );
      }
      final repeated = await child(['verify', root]);
      require(
        repeated.exitCode == 0 &&
            repeated.stdout.toString().trim() ==
                verified.stdout.toString().trim(),
        'Repeated recovery changed identity/state',
      );
      stdout.writeln(
        'PASS abrupt output ${boundary.name}: $expected usable, permanent input verified, stable identity, no partial',
      );
    }
    final root = '${sandbox.path}/save';
    final interrupted = await child(['save-interrupt', root]);
    require(interrupted.exitCode == 73, 'Permanent save did not terminate');
    final verified = await child(['verify', root]);
    require(
      verified.exitCode == 0,
      'Permanent save recovery failed: ${verified.stderr}',
    );
    final result = jsonDecode(verified.stdout.toString()) as Map;
    require(
      result['assets'] == 2 &&
          result['origins'] == 1 &&
          result['usable'] == 1 &&
          result['issues'] == 0,
      'Provenance or permanent save missing: $result',
    );
    stdout.writeln(
      'PASS abrupt permanent save before DB commit: independent bytes and source relationship recovered',
    );
  } finally {
    await sandbox.delete(recursive: true);
  }
}

// Separate read-only connection observes the committed intent without opening a
// second repository (the first owns the root lock). It reads only this new fixture.
Future<List<String>> repositoryForPartial(Directory root) async {
  final db = sqlite3.open(
    '${root.path}/library.sqlite',
    mode: OpenMode.readOnly,
  );
  try {
    return db
        .select("SELECT id FROM processed_outputs WHERE state='writing'")
        .map((row) => row['id'] as String)
        .toList();
  } finally {
    db.close();
  }
}
