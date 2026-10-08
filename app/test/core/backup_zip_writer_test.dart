import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:path/path.dart' as p;

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aGxQAAAAASUVORK5CYII=',
);

List<int> _imageBytes(int index) => index == 1
    ? _png
    : img.encodePng(
        img.Image(width: 1, height: 1)..setPixelRgba(0, 0, index, 20, 30, 255),
      );

Future<BackupSnapshotLease> _snapshot(
  Directory directory, {
  BackupMode mode = BackupMode.full,
  int count = 1,
}) async {
  final versions = <ImageVersion>[];
  final assets = <BackupAsset>[];
  final images = <BackupImageEntry>[];
  final files = <String, File>{};
  for (var i = 1; i <= count; i++) {
    final bytes = _imageBytes(i);
    final version = ImageVersion(
      id: _id(i),
      sha256: sha256.convert(bytes).toString(),
      byteCount: bytes.length,
      format: 'PNG',
      width: 1,
      height: 1,
      frameCount: 1,
      orientation: 1,
    );
    versions.add(version);
    assets.add(
      BackupAsset(
        id: _id(100 + i),
        versionId: version.id,
        displayName: '图片 $i',
        sourceType: 'selected',
        importedUtc: 1700000000000,
        updatedUtc: 1700000000000,
        favorite: false,
        tagIds: const [],
        recycled: false,
      ),
    );
    if (mode == BackupMode.full) {
      final file = File(p.join(directory.path, 'source-$i.png'));
      await file.writeAsBytes(bytes, flush: true);
      files[version.id] = file;
      images.add(
        BackupImageEntry(
          versionId: version.id,
          name: 'images/${version.id}.png',
          byteCount: version.byteCount,
          sha256: version.sha256,
        ),
      );
    }
  }
  final manifest = BackupManifest(
    packageId: _id(999),
    createdUtc: 1700000000000,
    mode: mode,
    versions: versions,
    assets: assets,
    categories: const [],
    tags: const [],
    origins: const [],
    accounts: const [],
    results: const [],
    history: const [],
    images: images,
  );
  return BackupSnapshotLease(
    manifest: manifest,
    manifestBytes: manifest.encode(redactor: SecretRedactor()),
    permanentFiles: files,
    onRelease: () async {},
  );
}

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('backup-zip-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test(
    'UT-074 partial: ZIP preserves exact manifest, canonical stored PNGs',
    () async {
      final snapshot = await _snapshot(directory, count: 2);
      final destination = File(p.join(directory.path, 'unpublished.zip'));
      final progress = <int>[];
      var total = 0;
      await BackupZipWriter().write(
        snapshot,
        destination,
        onProgress: (written, max) {
          progress.add(written);
          total = max;
        },
      );
      final input = InputFileStream(destination.path);
      try {
        final archive = ZipDecoder().decodeStream(input, verify: true);
        expect(archive.files.map((file) => file.name), [
          'manifest.json',
          ...snapshot.manifest.images.map((entry) => entry.name),
        ]);
        expect(archive.files.first.readBytes(), snapshot.manifestBytes);
        for (var i = 1; i < archive.files.length; i++) {
          final file = archive.files[i];
          expect(file.readBytes(), _imageBytes(i));
          expect(getCrc32(file.readBytes()!), file.crc32);
          expect(file.compression, CompressionType.none);
        }
      } finally {
        await input.close();
      }
      expect(snapshot.released, isFalse);
      expect(progress, isNotEmpty);
      expect(progress.last, total);
      expect(
        total,
        snapshot.manifestBytes.length +
            snapshot.manifest.images.fold<int>(
              0,
              (sum, entry) => sum + entry.byteCount,
            ),
      );
      expect(progress, orderedEquals(progress.toList()..sort()));
      await snapshot.release();
    },
  );

  test('UT-074 partial: metadata ZIP contains only manifest', () async {
    final snapshot = await _snapshot(directory, mode: BackupMode.metadata);
    final destination = File(p.join(directory.path, 'metadata.zip'));
    await BackupZipWriter().write(snapshot, destination);
    final archive = ZipDecoder().decodeBytes(
      await destination.readAsBytes(),
      verify: true,
    );
    expect(archive.files.map((file) => file.name), ['manifest.json']);
    expect(archive.files.single.readBytes(), snapshot.manifestBytes);
    await snapshot.release();
  });

  test(
    'UT-082 partial: existing destination is never overwritten or deleted',
    () async {
      final snapshot = await _snapshot(directory);
      final destination = File(p.join(directory.path, 'existing.zip'));
      await destination.writeAsString('existing private file');
      await expectLater(
        BackupZipWriter().write(snapshot, destination),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      expect(await destination.readAsString(), 'existing private file');
      await snapshot.release();
    },
  );

  test(
    'UT-082 partial: cancellation joins worker and removes owned stage',
    () async {
      final snapshot = await _snapshot(directory, count: 2);
      final destination = File(p.join(directory.path, 'cancelled.zip'));
      final cancellation = CancellationToken();
      await expectLater(
        BackupZipWriter().write(
          snapshot,
          destination,
          cancellation: cancellation,
          onProgress: (_, _) => cancellation.cancel(),
        ),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      expect(await destination.exists(), isFalse);
      expect(snapshot.released, isFalse);
      for (final file in snapshot.permanentFiles.values) {
        final bytes = await file.readAsBytes();
        final id = snapshot.permanentFiles.entries
            .firstWhere((entry) => entry.value == file)
            .key;
        expect(
          sha256.convert(bytes).toString(),
          snapshot.manifest.images
              .firstWhere((entry) => entry.versionId == id)
              .sha256,
        );
      }
      await snapshot.release();
      // Worker has exited; there can be no delayed writes recreating this path.
      expect(await destination.exists(), isFalse);
    },
  );

  test(
    'UT-082 partial: changed source fails digest and cleans only stage',
    () async {
      final snapshot = await _snapshot(directory);
      final source = snapshot.permanentFiles.values.single;
      final changed = List<int>.from(_png)..[20] ^= 1;
      await source.writeAsBytes(changed, flush: true);
      final destination = File(p.join(directory.path, 'invalid.zip'));
      await expectLater(
        BackupZipWriter().write(snapshot, destination),
        throwsA(
          isA<BackupSnapshotFailure>().having(
            (error) => error.affectedVersions,
            'stable version identity',
            [_id(1)],
          ),
        ),
      );
      expect(await destination.exists(), isFalse);
      expect(await source.readAsBytes(), changed);
      await snapshot.release();
    },
  );

  test(
    'UT-082 partial: released snapshot and precancellation create nothing',
    () async {
      final snapshot = await _snapshot(directory);
      final destination = File(p.join(directory.path, 'released.zip'));
      await snapshot.release();
      await expectLater(
        BackupZipWriter().write(snapshot, destination),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      expect(await destination.exists(), isFalse);
      final protected = await _snapshot(directory);
      final cancellation = CancellationToken()..cancel();
      await expectLater(
        BackupZipWriter().write(
          protected,
          destination,
          cancellation: cancellation,
        ),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      expect(await destination.exists(), isFalse);
      await protected.release();
    },
  );
}
