import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:imagehost/core/image_inspector.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/data/backup_zip_writer.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:path/path.dart' as p;

import 'backup_interop_fixture.dart';
import '../integration_test/support/backup_interop_harness.dart';

const _imageCount = 172;
const _width = 4096;
const _height = 2048;
const _boundary = 0xffffffff;

Future<Map<String, Object?>> inspectActualZip64(File archive) async {
  final file = await archive.open();
  try {
    final length = await file.length();
    interopRequire(length > _boundary, 'actual-large-archive');
    Future<Uint8List> read(int offset, int size) async {
      interopRequire(
        offset >= 0 && size >= 0 && offset + size <= length,
        'zip-range',
      );
      await file.setPosition(offset);
      final bytes = await file.read(size);
      interopRequire(bytes.length == size, 'zip-short-read');
      return bytes;
    }

    int u16(Uint8List b, int offset) =>
        ByteData.sublistView(b).getUint16(offset, Endian.little);
    int u32(Uint8List b, int offset) =>
        ByteData.sublistView(b).getUint32(offset, Endian.little);
    int u64(Uint8List b, int offset) =>
        ByteData.sublistView(b).getUint64(offset, Endian.little);
    final end = await read(length - 22, 22);
    interopRequire(
      u32(end, 0) == 0x06054b50 &&
          u16(end, 20) == 0 &&
          u32(end, 16) == _boundary,
      'zip64-eocd-sentinel',
    );
    final locator = await read(length - 42, 20);
    interopRequire(
      u32(locator, 0) == 0x07064b50 &&
          u32(locator, 4) == 0 &&
          u32(locator, 16) == 1,
      'zip64-locator',
    );
    final extendedOffset = u64(locator, 8);
    interopRequire(extendedOffset + 56 == length - 42, 'zip64-location');
    final extended = await read(extendedOffset, 56);
    interopRequire(
      u32(extended, 0) == 0x06064b50 &&
          u64(extended, 4) == 44 &&
          u32(extended, 16) == 0 &&
          u32(extended, 20) == 0,
      'zip64-record',
    );
    final count = u64(extended, 32),
        centralSize = u64(extended, 40),
        centralOffset = u64(extended, 48);
    interopRequire(
      count == _imageCount + 1 &&
          u64(extended, 24) == count &&
          centralOffset > _boundary &&
          centralOffset + centralSize == extendedOffset,
      'zip64-central-range',
    );
    var position = centralOffset, lastLocalOffset = 0, expandedOffsets = 0;
    for (var index = 0; index < count; index++) {
      final header = await read(position, 46);
      interopRequire(
        u32(header, 0) == 0x02014b50 && u16(header, 10) == 0,
        'stored-central-header',
      );
      final nameLength = u16(header, 28),
          extraLength = u16(header, 30),
          commentLength = u16(header, 32);
      interopRequire(
        nameLength <= 128 && extraLength <= 1024 && commentLength == 0,
        'bounded-central',
      );
      final extra = await read(position + 46 + nameLength, extraLength);
      var localOffset = u32(header, 42);
      if (localOffset == _boundary) {
        var cursor = 0;
        var found = false;
        while (cursor < extra.length) {
          interopRequire(cursor + 4 <= extra.length, 'extra-header');
          final tag = u16(extra, cursor), size = u16(extra, cursor + 2);
          cursor += 4;
          interopRequire(cursor + size <= extra.length, 'extra-range');
          if (tag == 1) {
            interopRequire(!found, 'single-zip64-extra');
            var value = cursor;
            if (u32(header, 24) == _boundary) value += 8;
            if (u32(header, 20) == _boundary) value += 8;
            interopRequire(value + 8 <= cursor + size, 'zip64-offset-field');
            localOffset = u64(extra, value);
            found = true;
          }
          cursor += size;
        }
        interopRequire(
          found && localOffset > _boundary,
          'actual-expanded-offset',
        );
        expandedOffsets++;
      }
      final local = await read(localOffset, 30);
      interopRequire(
        u32(local, 0) == 0x04034b50 && localOffset < centralOffset,
        'actual-local-header',
      );
      if (localOffset > lastLocalOffset) lastLocalOffset = localOffset;
      position += 46 + nameLength + extraLength;
    }
    interopRequire(
      position == extendedOffset &&
          expandedOffsets > 0 &&
          lastLocalOffset > _boundary,
      'actual-large-local-offset',
    );
    return {
      'archiveBytes': length,
      'entries': count,
      'centralOffset': centralOffset,
      'centralBytes': centralSize,
      'lastLocalOffset': lastLocalOffset,
      'expandedOffsets': expandedOffsets,
    };
  } finally {
    await file.close();
  }
}

Future<void> main(List<String> args) async {
  if (!args.contains('--execute-large')) {
    stdout.writeln(
      'No large IO performed. From app: dart run tool/verify_large_backup.dart '
      '--execute-large --root NEW_WORKSPACE_CHILD [--cleanup-on-success]',
    );
    return;
  }
  final rootIndex = args.indexOf('--root');
  interopRequire(Platform.isWindows, 'windows-host-required');
  interopRequire(
    rootIndex >= 0 &&
        rootIndex + 1 < args.length &&
        !args[rootIndex + 1].startsWith('--') &&
        args.where((a) => a == '--execute-large').length == 1 &&
        args.where((a) => a == '--root').length == 1 &&
        args.every(
          (a) =>
              a == '--execute-large' ||
              a == '--root' ||
              a == '--cleanup-on-success' ||
              a == args[rootIndex + 1],
        ),
    'large-arguments',
  );
  final owned = await OwnedBackupWorkspace.create(args[rootIndex + 1]);
  LibraryRepository? source;
  LibraryRepository? restored;
  ValidatedBackup? validated;
  var completed = false;
  try {
    final capacity = WindowsStorageCapacity();
    final harness = BackupInteropHarness(
      availableBytes: capacity.availableBytes,
      publishExclusive: capacity.publishExclusive,
    );
    // Generated originals, source library, ZIP, owned ZIP copy, extraction,
    // and restored permanent copies can coexist until real cleanup finishes.
    final required =
        _imageCount * (_width * _height * 3 + 138) * 6 + 64 * 1024 * 1024;
    interopRequire(
      await capacity.availableBytes(owned.directory) > required,
      'large-capacity',
    );
    source = await harness.open(
      Directory(p.join(owned.directory.path, 'source-library')),
    );
    final sources = await Directory(p.join(owned.directory.path, 'generated'))
        .create();
    final assets = <ImageAsset>[];
    final hashes = <String>{};
    for (var index = 0; index < _imageCount; index++) {
      final image = img.Image(width: _width, height: _height, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(index, 80, 150));
      image.setPixelRgb(index % _width, index % _height, 255 - index, 33, 210);
      final file = File(p.join(sources.path, 'image-$index.bmp'));
      await file.create(exclusive: true);
      await file.writeAsBytes(img.encodeBmp(image), flush: true);
      final metadata = await const ImageInspector(256 * 1024 * 1024)
          .inspect(file);
      final hash = await interopSha(file);
      interopRequire(
        metadata.format == 'BMP' &&
            metadata.width == _width &&
            metadata.height == _height &&
            metadata.frameCount == 1 &&
            metadata.orientation == 1 &&
            hashes.add(hash),
        'real-distinct-bmp',
      );
      final imported = await source.importResource(
        PlatformResource(displayName: '大包-$index.bmp', openRead: file.openRead),
      );
      interopRequire(
        imported.status == ImportStatus.saved &&
            imported.asset!.version.sha256 == hash &&
            imported.asset!.version.byteCount == await file.length(),
        'real-library-import',
      );
      assets.add(imported.asset!);
      stdout.writeln(
        jsonEncode({
          'phase': 'import',
          'done': index + 1,
          'total': _imageCount,
        }),
      );
    }
    final unpublished = File(p.join(owned.directory.path, 'large.partial'));
    final package = File(p.join(owned.directory.path, 'large.zip'));
    final snapshot = await source.captureBackupSnapshot(mode: BackupMode.full);
    try {
      interopRequire(
        snapshot.manifest.versions.length == _imageCount,
        'snapshot-version-count',
      );
      await BackupZipWriter().write(snapshot, unpublished);
    } finally {
      await snapshot.release();
    }
    interopRequire(
      await capacity.publishExclusive(unpublished, package),
      'large-publication',
    );
    final zipEvidence = await inspectActualZip64(package);
    final packageSha = await interopSha(package);
    final stage = await Directory(p.join(owned.directory.path, 'preflight'))
        .create();
    validated = await const BackupZipReader().preflight(
      package,
      stage,
      availableBytes: capacity.availableBytes,
      onProgress: (done, total) => stdout.writeln(
        jsonEncode({'phase': 'preflight', 'done': done, 'total': total}),
      ),
    );
    interopRequire(
      validated.imageFiles.length == _imageCount,
      'large-preflight-count',
    );
    final restoredRoot = Directory(
      p.join(owned.directory.path, 'restored-library'),
    );
    restored = await harness.open(restoredRoot);
    final hold = await restored.acquireRestoreHold();
    try {
      final prepared = await restored.prepareMergeRestore(
        hold: hold,
        backup: validated,
      );
      interopRequire(prepared.plan.canCommit, 'large-merge-plan');
      final report = await restored.commitMergeRestore(
        preparation: prepared,
        availableBytes: capacity.availableBytes,
        publishExclusive: capacity.publishExclusive,
      );
      interopRequire(
        report.savedCopies == _imageCount &&
            report.addedAssets == _imageCount &&
            !report.cleanupPending,
        'large-merge-commit',
      );
    } finally {
      await hold.release();
    }
    await restored.close();
    restored = null;
    restored = await harness.open(restoredRoot);
    for (final expected in assets) {
      final actual = await restored.getAsset(expected.id);
      interopRequire(
        actual != null &&
            actual.version == expected.version &&
            actual.displayName == expected.displayName &&
            actual.deviceCopy.id != expected.deviceCopy.id,
        'large-reopened-asset',
      );
    }
    final verification = await restored.captureBackupSnapshot(
      mode: BackupMode.full,
    );
    try {
      interopRequire(
        verification.manifest.versions.length == _imageCount,
        'large-reopened-count',
      );
      for (final expected in assets) {
        final file = verification.permanentFiles[expected.version.id]!;
        interopRequire(
          await file.length() == expected.version.byteCount &&
              await interopSha(file) == expected.version.sha256,
          'large-reopened-bytes',
        );
      }
    } finally {
      await verification.release();
    }
    await restored.close();
    restored = null;
    await source.close();
    source = null;
    await validated.dispose();
    validated = null;
    final result = {
      'verificationVersion': 1,
      'platform': Platform.operatingSystem,
      'images': _imageCount,
      'width': _width,
      'height': _height,
      'sha256': packageSha,
      'imageBytes': assets.first.version.byteCount,
      'totalImageBytes': assets.fold<int>(
        0,
        (total, asset) => total + asset.version.byteCount,
      ),
      'zip64': zipEvidence,
      'stages': [
        'actual-bmp',
        'actual-import',
        'protected-snapshot',
        'store-writer',
        'exclusive-publication',
        'default-preflight',
        'merge-commit',
        'reopen-all-bytes',
      ],
    };
    await File(p.join(owned.directory.path, 'result.json'))
        .writeAsString(jsonEncode(result), flush: true);
    completed = true;
    stdout.writeln(jsonEncode(result));
  } catch (_) {
    stderr.writeln(
      'Large backup verification failed; owned workspace retained.',
    );
    exitCode = 1;
  } finally {
    try {
      await restored?.close();
      await source?.close();
    } catch (_) {
      completed = false;
      exitCode = 1;
      stderr.writeln(
        'Actual IO cleanup unconfirmed; owned workspace retained.',
      );
    }
  }
  if (completed && args.contains('--cleanup-on-success')) {
    await owned.removeAfterSuccess();
  }
}
