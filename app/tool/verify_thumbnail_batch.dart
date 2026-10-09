import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../integration_test/support/backup_interop_harness.dart';
import 'backup_interop_fixture.dart';

// Test-host verification of a real cold batch, independent of widget fake time.
// Owns only a newly allocated workspace; retains its evidence after completion.
Future<void> main(List<String> args) async {
  try {
    interopRequire(args.length == 1, 'new-workspace-argument');
    final workspace = await OwnedBackupWorkspace.create(args.single);
    final capacity = WindowsStorageCapacity();
    final root = Directory(p.join(workspace.directory.path, 'library'));
    final repository = await LibraryRepository.open(
      root,
      availableStorageBytes: capacity.availableBytes,
      publishCacheExclusive: capacity.publishExclusive,
    );
    final thumbnails = <Map<String, Object?>>[];
    final elapsed = Stopwatch();
    try {
      final assets = <ImageAsset>[];
      for (var index = 0; index < 62; index++) {
        final image = img.Image(width: 13, height: 9, numChannels: 3);
        img.fill(image, color: img.ColorRgb8(index * 3, 83, 149));
        final bytes = img.encodePng(image);
        final result = await repository.importResource(
          PlatformResource(
            displayName: 'cold-batch-$index.png',
            openRead: () => Stream.value(bytes),
          ),
        );
        interopRequire(result.status == ImportStatus.saved, 'actual-import');
        assets.add(result.asset!);
      }
      elapsed.start();
      // As in the workbench, accept the whole batch, and wait for every actual
      // read/finalizer even if another item fails. No cancellation shortcuts.
      thumbnails.addAll(
        await Future.wait(
          assets.map((asset) async {
            interopRequire(
              await repository.verifyCopy(asset) == CopyAvailability.available,
              'permanent-copy',
            );
            final lease = await repository.acquireThumbnailLease(asset);
            interopRequire(lease != null, 'actual-thumbnail');
            try {
              final bytes = await lease!.readBytes();
              interopRequire(
                bytes.length == await lease.file.length() &&
                    img.decodePng(bytes) != null,
                'actual-closed-thumbnail-bytes',
              );
              return <String, Object?>{
                'assetId': asset.id,
                'bytes': bytes.length,
                'sha256': sha256.convert(bytes).toString(),
              };
            } finally {
              await lease?.release();
            }
          }),
        ),
      );
      elapsed.stop();
    } finally {
      await repository.close();
    }
    final database = sqlite3.open(
      p.join(root.path, 'library.sqlite'),
      mode: OpenMode.readOnly,
    );
    try {
      interopRequire(
        database.select('SELECT id FROM file_leases').isEmpty,
        'all-real-file-leases-drained',
      );
    } finally {
      database.close();
    }
    interopRequire(thumbnails.length == 62, 'complete-cold-batch');
    final result = {
      'verificationVersion': 1,
      'platform': 'windows',
      'coldThumbnails': thumbnails,
      'allActualReadsFinished': true,
      'closedLibrary': true,
      'fileLeases': 0,
      'elapsedMilliseconds': elapsed.elapsedMilliseconds,
      'hardwarePerformanceAcceptance': false,
    };
    await File(p.join(workspace.directory.path, 'result.json'))
        .writeAsString(jsonEncode(result), flush: true);
    stdout.writeln(
      jsonEncode({
        'coldThumbnails': thumbnails.length,
        'allActualReadsFinished': true,
        'closedLibrary': true,
        'fileLeases': 0,
        'elapsedMilliseconds': elapsed.elapsedMilliseconds,
        'hardwarePerformanceAcceptance': false,
      }),
    );
  } catch (_) {
    stderr.writeln('Cold thumbnail verification failed; workspace retained.');
    exitCode = 1;
  }
}
