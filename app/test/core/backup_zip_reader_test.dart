import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/backup/application/backup_snapshot.dart';
import 'package:imagehost/features/backup/data/backup_zip_reader.dart';
import 'package:imagehost/features/backup/domain/backup_manifest.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';

const versionId = '00000000-0000-4000-8000-000000000001';
const assetId = '00000000-0000-4000-8000-000000000002';
const packageId = '00000000-0000-4000-8000-000000000003';
const imageName = 'images/$versionId.png';
final pixels = Uint8List.fromList(
  img.encodePng(img.Image(width: 2, height: 3)),
);

BackupManifest manifest({
  BackupMode mode = BackupMode.full,
  int width = 2,
  String? digest,
}) {
  final version = ImageVersion(
    id: versionId,
    sha256: digest ?? sha256.convert(pixels).toString(),
    byteCount: pixels.length,
    format: 'PNG',
    width: width,
    height: 3,
    frameCount: 1,
    orientation: 1,
  );
  return BackupManifest(
    packageId: packageId,
    createdUtc: 0,
    mode: mode,
    versions: [version],
    assets: [
      BackupAsset(
        id: assetId,
        versionId: versionId,
        displayName: '图片',
        sourceType: 'file',
        importedUtc: 0,
        updatedUtc: 0,
        favorite: false,
        tagIds: [],
        recycled: false,
      ),
    ],
    categories: [],
    tags: [],
    origins: [],
    accounts: [],
    results: [],
    history: [],
    images: mode == BackupMode.metadata
        ? []
        : [
            BackupImageEntry(
              versionId: versionId,
              name: imageName,
              byteCount: pixels.length,
              sha256: version.sha256,
            ),
          ],
  );
}

// Raw fixture builder intentionally preserves duplicates and invalid names.
// No upstream ZIP decoder transforms/deduplicates these attack fixtures.
final class RawEntry {
  RawEntry(this.name, this.bytes);
  final String name;
  final List<int> bytes;
}

Uint8List zip(
  List<RawEntry> entries, {
  bool zip64 = false,
  bool writerZip64 = false,
}) {
  final extended = zip64 || writerZip64;
  final body = BytesBuilder(), central = BytesBuilder();
  var offset = 0;
  for (final entry in entries) {
    final name = utf8.encode(entry.name), crc = crc32(entry.bytes);
    final extra = zip64 ? Uint8List(20) : Uint8List(0);
    if (zip64) {
      final d = ByteData.sublistView(extra);
      d.setUint16(0, 1, Endian.little);
      d.setUint16(2, 16, Endian.little);
      d.setUint64(4, entry.bytes.length, Endian.little);
      d.setUint64(12, entry.bytes.length, Endian.little);
    }
    final local = Uint8List(30), l = ByteData.sublistView(local);
    l.setUint32(0, 0x04034b50, Endian.little);
    l.setUint16(4, zip64 ? 45 : 20, Endian.little);
    l.setUint16(6, 0x800, Endian.little);
    l.setUint32(14, crc, Endian.little);
    l.setUint32(18, zip64 ? 0xffffffff : entry.bytes.length, Endian.little);
    l.setUint32(22, zip64 ? 0xffffffff : entry.bytes.length, Endian.little);
    l.setUint16(26, name.length, Endian.little);
    l.setUint16(28, extra.length, Endian.little);
    body
      ..add(local)
      ..add(name)
      ..add(extra)
      ..add(entry.bytes);
    final centralExtra = writerZip64 ? Uint8List(28) : extra;
    if (writerZip64) {
      final ex = ByteData.sublistView(centralExtra);
      ex.setUint16(0, 1, Endian.little);
      ex.setUint16(2, 24, Endian.little);
      ex.setUint64(4, entry.bytes.length, Endian.little);
      ex.setUint64(12, entry.bytes.length, Endian.little);
      ex.setUint64(20, offset, Endian.little);
    }
    final c = Uint8List(46), d = ByteData.sublistView(c);
    d.setUint32(0, 0x02014b50, Endian.little);
    d.setUint16(4, 20, Endian.little);
    d.setUint16(6, extended ? 45 : 20, Endian.little);
    d.setUint16(8, 0x800, Endian.little);
    d.setUint32(16, crc, Endian.little);
    d.setUint32(20, extended ? 0xffffffff : entry.bytes.length, Endian.little);
    d.setUint32(24, extended ? 0xffffffff : entry.bytes.length, Endian.little);
    d.setUint16(28, name.length, Endian.little);
    d.setUint16(30, centralExtra.length, Endian.little);
    d.setUint32(42, writerZip64 ? 0xffffffff : offset, Endian.little);
    central
      ..add(c)
      ..add(name)
      ..add(centralExtra);
    offset += 30 + name.length + extra.length + entry.bytes.length;
  }
  final directory = central.takeBytes();
  body.add(directory);
  if (extended) {
    final end = Uint8List(56), d = ByteData.sublistView(end);
    d.setUint32(0, 0x06064b50, Endian.little);
    d.setUint64(4, 44, Endian.little);
    d.setUint16(12, 45, Endian.little);
    d.setUint16(14, 45, Endian.little);
    d.setUint64(24, entries.length, Endian.little);
    d.setUint64(32, entries.length, Endian.little);
    d.setUint64(40, directory.length, Endian.little);
    d.setUint64(48, offset, Endian.little);
    final locator = Uint8List(20), loc = ByteData.sublistView(locator);
    loc.setUint32(0, 0x07064b50, Endian.little);
    loc.setUint64(8, offset + directory.length, Endian.little);
    loc.setUint32(16, 1, Endian.little);
    body
      ..add(end)
      ..add(locator);
  }
  final eocd = Uint8List(22), e = ByteData.sublistView(eocd);
  e.setUint32(0, 0x06054b50, Endian.little);
  e.setUint16(6, writerZip64 ? 0xffff : 0, Endian.little);
  e.setUint16(8, extended ? 0xffff : entries.length, Endian.little);
  e.setUint16(10, extended ? 0xffff : entries.length, Endian.little);
  e.setUint32(12, extended ? 0xffffffff : directory.length, Endian.little);
  e.setUint32(16, extended ? 0xffffffff : offset, Endian.little);
  body.add(eocd);
  return body.takeBytes();
}

int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}

List<RawEntry> records({BackupManifest? value}) {
  final m = value ?? manifest();
  return [
    RawEntry('manifest.json', m.encode(redactor: SecretRedactor())),
    if (m.mode == BackupMode.full) RawEntry(imageName, pixels),
  ];
}

void main() {
  late Directory root, staging;
  late File source, current;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('imagehost-preflight-test-');
    staging = await Directory('${root.path}/staging').create();
    source = File('${root.path}/selected.zip');
    current = await File('${root.path}/current.sqlite')
        .writeAsString('current library sentinel');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<ValidatedBackup> read({
    BackupBudgets budgets = const BackupBudgets(),
    CancellationToken? cancellation,
    Future<int> Function(Directory)? capacity,
    void Function(int, int)? progress,
  }) => const BackupZipReader().preflight(
    source,
    staging,
    budgets: budgets,
    cancellation: cancellation,
    onProgress: progress,
    availableBytes: capacity ?? (_) async => 1 << 40,
  );
  Future<void> untouched() async {
    expect(await current.readAsString(), 'current library sentinel');
    expect(await staging.list().toList(), isEmpty);
  }

  Future<void> reject(
    Uint8List bytes, {
    BackupBudgets budgets = const BackupBudgets(),
    Matcher? failure,
  }) async {
    await source.writeAsBytes(bytes);
    await expectLater(
      read(budgets: budgets),
      throwsA(
        failure ?? anyOf(isA<BackupSnapshotFailure>(), isA<BackupFailure>()),
      ),
    );
    await untouched();
  }

  test(
    'UT-075 partial: store ZIP and ZIP64 actual pixels and metadata validate',
    () async {
      for (final extended in [false, true]) {
        await source.writeAsBytes(zip(records(), zip64: extended));
        final progress = <int>[];
        final result = await read(
          progress: (verified, total) {
            progress.add(verified);
            expect(total, 1);
          },
        );
        expect(result.manifest.packageId, packageId);
        expect(await result.imageFiles[versionId]!.readAsBytes(), pixels);
        expect(progress, [0, 1]);
        expect(await current.readAsString(), 'current library sentinel');
        await Future.wait([result.dispose(), result.dispose()]);
        await result.dispose();
        await untouched();
      }
    },
  );
  test(
    'UT-075 partial: metadata preflight owns no permanent image files',
    () async {
      await source.writeAsBytes(
        zip(records(value: manifest(mode: BackupMode.metadata))),
      );
      final result = await read();
      expect(result.imageFiles, isEmpty);
      expect(result.manifest.assets, hasLength(1));
      await result.dispose();
      await untouched();
    },
  );
  test('UT-075 partial: archive 4.3 ZIP64 sentinels and full central extra validate', () async {
    await source.writeAsBytes(zip(records(), writerZip64: true));
    final result = await read();
    expect(await result.imageFiles[versionId]!.readAsBytes(), pixels);
    await result.dispose();
    await untouched();
    final multiDisk = zip(records(), writerZip64: true);
    final d = ByteData.sublistView(multiDisk);
    final endOffset = d.getUint64(multiDisk.length - 34, Endian.little);
    d.setUint32(endOffset + 20, 1, Endian.little);
    await reject(multiDisk);
    final noExtended = zip(records());
    ByteData.sublistView(noExtended)
        .setUint16(noExtended.length - 16, 0xffff, Endian.little);
    await reject(noExtended);
  });
  test('UT-077 partial: duplicates, traversal, directories and wrong entry set reject', () async {
    final valid = records();
    for (final attack in [
      [...valid, valid.first],
      [
        ...valid,
        RawEntry('../outside', [1]),
      ],
      [...valid, RawEntry('images/', [])],
      [
        ...valid,
        RawEntry('images/00000000-0000-4000-8000-000000000004.png', pixels),
      ],
      [RawEntry('MANIFEST.JSON', valid.first.bytes), valid.last],
      [RawEntry('/manifest.json', valid.first.bytes), valid.last],
      [RawEntry('images\\$versionId.png', pixels), valid.first],
    ]) {
      await reject(zip(attack));
    }
  });
  test('UT-077 partial: CRC, SHA256, actual dimensions and manifest version reject', () async {
    final corrupt = zip(records());
    corrupt[30 + utf8.encode('manifest.json').length] ^= 1;
    await reject(corrupt);
    await reject(zip(records(value: manifest(digest: 'a' * 64))));
    await reject(zip(records(value: manifest(width: 20))));
    final raw =
        jsonDecode(utf8.decode(records().first.bytes)) as Map<String, dynamic>;
    raw['formatVersion'] = 999;
    await reject(
      zip([
        RawEntry('manifest.json', utf8.encode(jsonEncode(raw))),
        records().last,
      ]),
      failure: isA<BackupFailure>().having(
        (f) => f.kind,
        'kind',
        BackupFailureKind.unsupportedFormat,
      ),
    );
  });
  test(
    'UT-077 partial: compression, encryption, links and local mismatch reject',
    () async {
      for (final mutate in <void Function(Uint8List)>[
        (b) {
          final d = ByteData.sublistView(b);
          d.setUint16(
            d.getUint32(b.length - 6, Endian.little) + 10,
            8,
            Endian.little,
          );
        },
        (b) {
          final d = ByteData.sublistView(b);
          d.setUint16(
            d.getUint32(b.length - 6, Endian.little) + 8,
            1,
            Endian.little,
          );
        },
        (b) {
          final d = ByteData.sublistView(b);
          d.setUint32(
            d.getUint32(b.length - 6, Endian.little) + 38,
            0xa0000000,
            Endian.little,
          );
        },
        (b) {
          b[14] ^= 1;
        },
        (b) {
          b[30] ^= 1;
        },
        (b) {
          final d = ByteData.sublistView(b);
          d.setUint32(
            d.getUint32(b.length - 6, Endian.little) + 42,
            1,
            Endian.little,
          );
        },
      ]) {
        final bytes = zip(records());
        mutate(bytes);
        await reject(bytes);
      }
    },
  );
  test('UT-077 partial: truncation, EOCD trailing bytes, central junk and orphan prefix reject', () async {
    final bytes = zip(records());
    await reject(Uint8List.sublistView(bytes, 0, bytes.length - 1));
    await reject(Uint8List.fromList([...bytes, 0]));
    await reject(Uint8List.fromList([0, ...bytes]));
    final junk = Uint8List.fromList(bytes);
    final d = ByteData.sublistView(junk);
    d.setUint32(
      junk.length - 10,
      d.getUint32(junk.length - 10, Endian.little) - 1,
      Endian.little,
    );
    await reject(junk);
  });
  test('UT-077 partial: early count, declared expansion and aggregate budgets reject', () async {
    final count = zip(records()), d = ByteData.sublistView(count);
    d.setUint16(count.length - 14, 65534, Endian.little);
    d.setUint16(count.length - 12, 65534, Endian.little);
    await reject(count, budgets: const BackupBudgets(maxRecords: 10));
    final expanded = zip(records()), e = ByteData.sublistView(expanded);
    final start = e.getUint32(expanded.length - 6, Endian.little);
    e.setUint32(start + 20, 20 * 1024 * 1024, Endian.little);
    e.setUint32(start + 24, 20 * 1024 * 1024, Endian.little);
    await reject(expanded);
    await reject(
      zip(records()),
      budgets: BackupBudgets(maximumTotalImageBytes: pixels.length - 1),
    );
    await reject(
      zip(records()),
      budgets: const BackupBudgets(maxManifestBytes: 1),
    );
  });
  test('UT-082 partial: unknown/insufficient injected capacity and cancellation leave current untouched', () async {
    await source.writeAsBytes(zip(records()));
    for (final free in [-1, 0]) {
      await expectLater(
        read(capacity: (_) async => free),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      await untouched();
    }
    final cancellation = CancellationToken();
    var checks = 0;
    await expectLater(
      read(
        cancellation: cancellation,
        capacity: (_) async {
          if (++checks == 2) cancellation.cancel();
          return 1 << 40;
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    await untouched();
    final decodingCancel = CancellationToken();
    await expectLater(
      read(
        cancellation: decodingCancel,
        progress: (verified, total) {
          decodingCancel.cancel();
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    await untouched();
  });
  test(
    'UT-077 partial: ZIP64 inconsistent pointer and unsafe integer reject',
    () async {
      final bad = zip(records(), zip64: true), d = ByteData.sublistView(bad);
      d.setUint64(bad.length - 34, 1, Endian.little);
      await reject(bad);
      final huge = zip(records(), zip64: true), h = ByteData.sublistView(huge);
      h.setUint64(huge.length - 34, 0x20000000000000, Endian.little);
      await reject(huge);
    },
  );

  for (final mode in [BackupMode.full, BackupMode.metadata]) {
    test(
      'UT-075/082 ${mode.name} cleanup preserves complete workspace with unknown file and retries after removal',
      () async {
        final original = zip(records(value: manifest(mode: mode)));
        await source.writeAsBytes(original);
        final result = await read();
        final package = File('${result.stagingDirectory.path}/package.zip');
        final unknown = await File(
          '${result.stagingDirectory.path}/foreign.bin',
        ).writeAsBytes([7, 8], flush: true);
        await expectLater(
          result.dispose(),
          throwsA(isA<BackupSnapshotFailure>()),
        );
        expect(await unknown.readAsBytes(), [7, 8]);
        expect(await package.readAsBytes(), original);
        expect(await source.readAsBytes(), original);
        expect(await current.readAsString(), 'current library sentinel');
        if (mode == BackupMode.full) {
          expect(await result.imageFiles[versionId]!.readAsBytes(), pixels);
        }
        await unknown.delete();
        await result.dispose();
        await untouched();
      },
    );
  }

  test('UT-075/082 unknown directory is never traversed or partly cleaned and disposal can retry', () async {
    final original = zip(records());
    await source.writeAsBytes(original);
    final result = await read();
    final unknown = await Directory('${result.stagingDirectory.path}/foreign')
        .create();
    final sentinel = await File('${unknown.path}/keep.bin')
        .writeAsString('external owner');
    await expectLater(result.dispose(), throwsA(isA<BackupSnapshotFailure>()));
    expect(await sentinel.readAsString(), 'external owner');
    expect(
      await File('${result.stagingDirectory.path}/package.zip').readAsBytes(),
      original,
    );
    expect(await result.imageFiles[versionId]!.readAsBytes(), pixels);
    await sentinel.delete();
    await unknown.delete();
    await result.dispose();
    await untouched();
  });

  test('UT-075/082 changed verified image digest preserves every known file before cleanup and allows restored bytes retry', () async {
    final original = zip(records());
    await source.writeAsBytes(original);
    final result = await read();
    final image = result.imageFiles[versionId]!;
    final changed = Uint8List.fromList(pixels)..[pixels.length - 1] ^= 1;
    await image.writeAsBytes(changed, flush: true);
    await expectLater(result.dispose(), throwsA(isA<BackupSnapshotFailure>()));
    expect(await image.readAsBytes(), changed);
    expect(
      await File('${result.stagingDirectory.path}/package.zip').readAsBytes(),
      original,
    );
    expect(await source.readAsBytes(), original);
    expect(await current.readAsString(), 'current library sentinel');
    await image.writeAsBytes(pixels, flush: true);
    await result.dispose();
    await untouched();
  });

  test('UT-075/082 replacing owned image file with directory never grants deletion of the replacement', () async {
    final original = zip(records());
    await source.writeAsBytes(original);
    final result = await read();
    final image = result.imageFiles[versionId]!;
    await image.delete();
    final replacement = await Directory(image.path).create();
    await expectLater(result.dispose(), throwsA(isA<BackupSnapshotFailure>()));
    expect(await replacement.exists(), true);
    expect(
      await File('${result.stagingDirectory.path}/package.zip').readAsBytes(),
      original,
    );
    await replacement.delete();
    await image.writeAsBytes(pixels, flush: true);
    await result.dispose();
    await untouched();
  });

  test('UT-075/082 linked descendant and external source are preserved without partial cleanup', () async {
    final original = zip(records());
    await source.writeAsBytes(original);
    final result = await read();
    final link = Link('${result.stagingDirectory.path}/foreign-link');
    var created = false;
    try {
      try {
        await link.create(current.path);
        created = true;
      } on FileSystemException {
        markTestSkipped('当前测试进程无符号链接创建权限，真实链接分支未执行。');
        return;
      }
      await expectLater(
        result.dispose(),
        throwsA(isA<BackupSnapshotFailure>()),
      );
      expect(
        await FileSystemEntity.type(link.path, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(await current.readAsString(), 'current library sentinel');
      expect(await source.readAsBytes(), original);
      expect(
        await File('${result.stagingDirectory.path}/package.zip').readAsBytes(),
        original,
      );
      expect(await result.imageFiles[versionId]!.readAsBytes(), pixels);
    } finally {
      if (created) await link.delete();
      await result.dispose();
    }
    await untouched();
  });

  test('UT-075/082 failed preflight does not recursively erase foreign child inserted during actual source copy', () async {
    final original = zip(records());
    await source.writeAsBytes(original);
    final token = CancellationToken();
    File? unknown;
    Directory? workspace;
    await expectLater(
      read(
        cancellation: token,
        capacity: (directory) async {
          if (directory.path != staging.path && unknown == null) {
            workspace = directory;
            unknown = await File('${directory.path}/foreign.bin')
                .writeAsString('keep');
            token.cancel();
          }
          return 1 << 40;
        },
      ),
      throwsA(isA<BackupSnapshotFailure>()),
    );
    expect(await unknown!.readAsString(), 'keep');
    expect(await workspace!.exists(), true);
    expect(await File('${workspace!.path}/package.zip').exists(), true);
    expect(await source.readAsBytes(), original);
    expect(await current.readAsString(), 'current library sentinel');
  });
}
