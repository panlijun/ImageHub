import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/image_inspector.dart';
import '../../../core/platform_resource.dart';
import '../application/backup_snapshot.dart';
import '../domain/backup_manifest.dart';
import 'backup_temporary_workspace.dart';

/// Owns only a newly allocated preflight workspace, never a live library.
final class ValidatedBackup {
  ValidatedBackup._(
    this.manifest,
    Map<String, File> files,
    this.stagingDirectory,
    BackupTemporaryWorkspace workspace,
  ) : imageFiles = Map.unmodifiable(files),
      _workspace = workspace.copy();
  final BackupManifest manifest;

  /// Keys are stable version UUIDs, not untrusted ZIP paths.
  final Map<String, File> imageFiles;
  final Directory stagingDirectory;
  final BackupTemporaryWorkspace _workspace;
  Future<void>? _disposing;
  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    try {
      await _workspace.remove();
    } catch (_) {
      _disposing = null;
      throw BackupSnapshotFailure('备份临时文件无法安全清理，现场已保留，请核查后重试。');
    }
  }
}

/// Generation 1 deliberately accepts only contiguous, unencrypted store ZIPs.
/// Parsing raw records preserves duplicate names and never follows ZIP links.
final class BackupZipReader {
  const BackupZipReader({
    this.inspector = const ImageInspector(256 * 1024 * 1024),
  });
  final ImageInspector inspector;

  Future<ValidatedBackup> preflight(
    File source,
    Directory stagingParent, {
    BackupBudgets budgets = const BackupBudgets(),
    CancellationToken? cancellation,
    void Function(int verified, int total)? onProgress,
    required Future<int> Function(Directory) availableBytes,
  }) async {
    Directory? owned;
    BackupTemporaryWorkspace? workspace;
    RandomAccessFile? archive;
    var success = false;
    try {
      if (budgets.maxManifestBytes <= 0 ||
          budgets.maxRecords <= 0 ||
          budgets.maximumTotalImageBytes < 0 ||
          inspector.memoryBudgetBytes <= 0) {
        _budget();
      }
      _cancel(cancellation);
      await _noLinks(source.absolute.path, FileSystemEntityType.file);
      await _noLinks(
        stagingParent.absolute.path,
        FileSystemEntityType.directory,
      );
      final sourceSize = await source.length();
      final maximumArchive =
          budgets.maximumTotalImageBytes +
          budgets.maxManifestBytes +
          _centralLimit;
      if (sourceSize < 22) _invalid();
      if (sourceSize > maximumArchive) _budget();
      // The uncompressed store content cannot exceed source length. Reserve
      // both the immutable owned archive and all extracted bytes before copying.
      await _capacity(stagingParent, sourceSize * 2 + _margin, availableBytes);
      _cancel(cancellation);
      await _noLinks(
        stagingParent.absolute.path,
        FileSystemEntityType.directory,
      );
      owned = await stagingParent.createTemp('backup-preflight-');
      workspace = BackupTemporaryWorkspace(owned);
      final copied = File(p.join(owned.path, 'package.zip'));
      await _copySource(
        source,
        copied,
        sourceSize,
        maximumArchive,
        cancellation,
        () => _capacity(owned!, _margin, availableBytes),
        workspace,
      );
      await workspace.verifyAndRecordFile(copied);
      archive = await copied.open();
      final entries = await _readEntries(
        archive,
        sourceSize,
        budgets,
        cancellation,
      );
      final manifestEntry = entries['manifest.json'];
      if (manifestEntry == null) _invalid();
      final manifestBytes = BytesBuilder(copy: false);
      await _streamEntry(archive, manifestEntry, cancellation, (bytes) async {
        manifestBytes.add(bytes);
      });
      final manifest = BackupManifest.decode(
        manifestBytes.takeBytes(),
        budgets: budgets,
      );
      final expected = {'manifest.json', ...manifest.images.map((i) => i.name)};
      if (entries.length != expected.length ||
          !entries.keys.every(expected.contains)) {
        _invalid();
      }
      var total = 0;
      for (final image in manifest.images) {
        final entry = entries[image.name]!;
        if (entry.size != image.byteCount) _invalid();
        total += image.byteCount;
        if (total > budgets.maximumTotalImageBytes ||
            entry.size > inspector.memoryBudgetBytes ~/ 4) {
          _budget();
        }
      }
      await _capacity(owned, total + _margin, availableBytes);
      _cancel(cancellation);
      final imagesDirectory = await owned.createTemp('images-');
      workspace.registerDirectory(imagesDirectory);
      final versions = {
        for (final version in manifest.versions) version.id: version,
      };
      final files = <String, File>{};
      onProgress?.call(0, manifest.images.length);
      for (final image in manifest.images) {
        _cancel(cancellation);
        await _noLinks(imagesDirectory.path, FileSystemEntityType.directory);
        final entry = entries[image.name]!;
        // Name is constructed from validated manifest identity and format.
        final version = versions[image.versionId]!;
        final file = File(
          p.join(
            imagesDirectory.path,
            '${version.id}.${version.format.toLowerCase()}',
          ),
        );
        await file.create(exclusive: true);
        workspace.registerFile(file);
        final output = await file.open(mode: FileMode.write);
        final digest = _DigestSink();
        final hash = sha256.startChunkedConversion(digest);
        try {
          await _streamEntry(archive, entry, cancellation, (bytes) async {
            hash.add(bytes);
            await _capacity(owned!, _margin, availableBytes);
            try {
              await output.writeFrom(bytes);
            } catch (_) {
              workspace!.markIoUncertain();
              rethrow;
            }
          });
          hash.close();
          if (digest.value?.toString() != image.sha256) _invalid();
          try {
            await output.flush();
          } catch (_) {
            workspace.markIoUncertain();
            rethrow;
          }
        } finally {
          try {
            await output.close();
          } catch (_) {
            workspace.markIoUncertain();
            rethrow;
          }
        }
        _cancel(cancellation);
        // The isolate must actually finish before cleanup or cancellation.
        final metadata = await inspector.inspect(file);
        _cancel(cancellation);
        if (metadata.format != version.format ||
            metadata.width != version.width ||
            metadata.height != version.height ||
            metadata.frameCount != version.frameCount ||
            metadata.orientation != version.orientation) {
          _invalid();
        }
        files[version.id] = file;
        workspace.recordVerifiedFile(file, image.sha256, image.byteCount);
        onProgress?.call(files.length, manifest.images.length);
      }
      _cancel(cancellation);
      try {
        await archive.close();
      } catch (_) {
        workspace.markIoUncertain();
        rethrow;
      }
      archive = null;
      success = true;
      return ValidatedBackup._(manifest, files, owned, workspace);
    } on BackupFailure {
      rethrow;
    } on BackupSnapshotFailure {
      rethrow;
    } on ResourceFailure catch (failure) {
      if (failure.kind == FailureKind.cancelled) {
        throw BackupSnapshotFailure('已取消备份校验，当前资料库未改变。');
      }
      if (failure.kind == FailureKind.resourceBudget) _budget();
      _invalid();
    } catch (_) {
      throw BackupSnapshotFailure('备份读取或临时保存失败，当前资料库未改变。');
    } finally {
      try {
        try {
          await archive?.close();
        } catch (_) {
          workspace?.markIoUncertain();
          throw BackupSnapshotFailure('备份读取已结束，但临时文件关闭失败；请保留资料库并核查。');
        }
      } finally {
        if (!success) await workspace?.remove();
      }
    }
  }
}

const _centralLimit = 64 * 1024 * 1024;
const _margin = 1024 * 1024;
const _chunk = 64 * 1024;
const _safeInteger = 9007199254740991;
Never _invalid() => throw BackupSnapshotFailure('备份 ZIP 结构、图片或校验值无效。');
Never _budget() => throw const BackupFailure(BackupFailureKind.resourceBudget);
Never _unsupported() =>
    throw BackupSnapshotFailure('仅支持本应用第 1 版未压缩、未加密的备份 ZIP。');
void _cancel(CancellationToken? cancellation) =>
    cancellation?.throwIfCancelled();

Future<void> _capacity(
  Directory directory,
  int requiredBytes,
  Future<int> Function(Directory) availableBytes,
) async {
  final free = await availableBytes(directory);
  if (free < 0 || free < requiredBytes) {
    throw BackupSnapshotFailure('无法确认足够的可用空间，备份校验已停止。');
  }
}

Future<void> _noLinks(String path, FileSystemEntityType expected) async {
  var current = p.normalize(p.absolute(path));
  var wanted = expected;
  while (true) {
    if (await FileSystemEntity.type(current, followLinks: false) != wanted) {
      throw BackupSnapshotFailure('备份来源或临时目录不安全或不可用。');
    }
    final parent = p.dirname(current);
    if (parent == current) return;
    current = parent;
    wanted = FileSystemEntityType.directory;
  }
}

Future<void> _copySource(
  File source,
  File destination,
  int expectedSize,
  int maximumSize,
  CancellationToken? cancellation,
  Future<void> Function() checkSpace,
  BackupTemporaryWorkspace workspace,
) async {
  final input = await source.open();
  RandomAccessFile? output;
  try {
    await destination.create(exclusive: true);
    workspace.registerFile(destination);
    output = await destination.open(mode: FileMode.write);
    var count = 0;
    while (true) {
      _cancel(cancellation);
      final bytes = await input.read(_chunk);
      if (bytes.isEmpty) break;
      count += bytes.length;
      if (count > maximumSize) _budget();
      if (count > expectedSize) _invalid();
      await checkSpace();
      try {
        await output.writeFrom(bytes);
      } catch (_) {
        workspace.markIoUncertain();
        rethrow;
      }
    }
    if (count != expectedSize) _invalid();
    try {
      await output.flush();
    } catch (_) {
      workspace.markIoUncertain();
      rethrow;
    }
  } finally {
    try {
      try {
        await output?.close();
      } catch (_) {
        workspace.markIoUncertain();
        rethrow;
      }
    } finally {
      try {
        await input.close();
      } catch (_) {
        workspace.markIoUncertain();
        rethrow;
      }
    }
  }
}

final class _Entry {
  _Entry(this.name, this.flags, this.crc, this.size, this.offset);
  final String name;
  final int flags, crc, size, offset;
  int dataOffset = 0;
}

int _u16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint16(offset, Endian.little);
int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);
int _u64(Uint8List bytes, int offset) {
  final lo = _u32(bytes, offset), hi = _u32(bytes, offset + 4);
  if (hi > 0x1fffff) _budget();
  final result = hi * 4294967296 + lo;
  if (result > _safeInteger) _budget();
  return result;
}

Future<Uint8List> _read(
  RandomAccessFile file,
  int offset,
  int length,
  int end,
) async {
  if (offset < 0 || length < 0 || offset > end || length > end - offset) {
    _invalid();
  }
  await file.setPosition(offset);
  final bytes = await file.read(length);
  if (bytes.length != length) _invalid();
  return bytes;
}

Uint8List? _zip64(Uint8List extras) {
  Uint8List? value;
  var position = 0;
  while (position < extras.length) {
    if (extras.length - position < 4) _invalid();
    final tag = _u16(extras, position), length = _u16(extras, position + 2);
    position += 4;
    if (length > extras.length - position) _invalid();
    if (tag == 1) {
      if (value != null) _invalid();
      value = Uint8List.sublistView(extras, position, position + length);
    }
    position += length;
  }
  return value;
}

List<int> _sizes(Uint8List extras, int size, int compressed, [int? offset]) {
  final zip64 = _zip64(extras);
  var position = 0;
  int expand(int value) {
    if (value != 0xffffffff) return value;
    if (zip64 == null || zip64.length - position < 8) _invalid();
    final result = _u64(zip64, position);
    position += 8;
    return result;
  }

  final result = [expand(size), expand(compressed)];
  if (offset != null) result.add(expand(offset));
  // Reject unexplained/ambiguous ZIP64 values in this deliberately strict format.
  if (zip64 != null && position != zip64.length) _invalid();
  return result;
}

String _name(Uint8List bytes) {
  final name = utf8.decode(bytes, allowMalformed: false);
  if (name == 'manifest.json') return name;
  if (!RegExp(
    r'^images/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(png|jpeg|webp|gif|bmp)$',
  ).hasMatch(name)) {
    _invalid();
  }
  return name;
}

Future<Map<String, _Entry>> _readEntries(
  RandomAccessFile file,
  int length,
  BackupBudgets budgets,
  CancellationToken? cancellation,
) async {
  final eocdOffset = length - 22;
  final eocd = await _read(file, eocdOffset, 22, length);
  if (_u32(eocd, 0) != 0x06054b50 ||
      _u16(eocd, 20) != 0 ||
      _u16(eocd, 4) != 0 ||
      _u16(eocd, 8) != _u16(eocd, 10)) {
    _invalid();
  }
  var count = _u16(eocd, 10),
      centralSize = _u32(eocd, 12),
      centralOffset = _u32(eocd, 16);
  var centralEnd = eocdOffset;
  final locator = eocdOffset >= 20
      ? await _read(file, eocdOffset - 20, 20, length)
      : null;
  final hasZip64 = locator != null && _u32(locator, 0) == 0x07064b50;
  if (hasZip64) {
    // archive 4.3 writes the ZIP64 sentinel for the start-disk field too.
    // It is accepted only after the extended record proves both disks are 0.
    if (_u16(eocd, 6) != 0 && _u16(eocd, 6) != 0xffff) _invalid();
    if (_u32(locator, 4) != 0 || _u32(locator, 16) != 1) _invalid();
    final endOffset = _u64(locator, 8);
    final end = await _read(file, endOffset, 56, eocdOffset - 20);
    if (endOffset + 56 != eocdOffset - 20 ||
        _u32(end, 0) != 0x06064b50 ||
        _u64(end, 4) != 44 ||
        _u32(end, 16) != 0 ||
        _u32(end, 20) != 0 ||
        _u64(end, 24) != _u64(end, 32)) {
      _invalid();
    }
    final extendedCount = _u64(end, 32),
        extendedSize = _u64(end, 40),
        extendedOffset = _u64(end, 48);
    if ((count != 0xffff && count != extendedCount) ||
        (centralSize != 0xffffffff && centralSize != extendedSize) ||
        (centralOffset != 0xffffffff && centralOffset != extendedOffset)) {
      _invalid();
    }
    count = extendedCount;
    centralSize = extendedSize;
    centralOffset = extendedOffset;
    centralEnd = endOffset;
  } else if (_u16(eocd, 6) != 0 ||
      count == 0xffff ||
      centralSize == 0xffffffff ||
      centralOffset == 0xffffffff) {
    _invalid();
  }
  if (count < 1) _invalid();
  if (count > budgets.maxRecords + 1 || centralSize > _centralLimit) _budget();
  if (centralOffset + centralSize != centralEnd || centralSize < count * 46) {
    _invalid();
  }
  final entries = <String, _Entry>{};
  final foldedNames = <String>{};
  var position = centralOffset, total = 0;
  for (var i = 0; i < count; i++) {
    _cancel(cancellation);
    final h = await _read(file, position, 46, centralEnd);
    if (_u32(h, 0) != 0x02014b50) _invalid();
    final flags = _u16(h, 8), method = _u16(h, 10);
    if (method != 0 || (flags != 0 && flags != 0x800)) _unsupported();
    if (_u16(h, 6) > 45 || _u16(h, 34) != 0) _unsupported();
    final nameLength = _u16(h, 28), extraLength = _u16(h, 30);
    if (nameLength < 1 || nameLength > 128 || extraLength > 1024) _budget();
    if (_u16(h, 32) != 0) _invalid();
    final external = _u32(h, 38), unixType = (external >> 16) & 0xf000;
    if ((external & 0x10) != 0 || (unixType != 0 && unixType != 0x8000)) {
      _invalid();
    }
    final variable = await _read(
      file,
      position + 46,
      nameLength + extraLength,
      centralEnd,
    );
    final name = _name(Uint8List.sublistView(variable, 0, nameLength));
    if (!foldedNames.add(name.toLowerCase())) _invalid();
    final sizes = _sizes(
      Uint8List.sublistView(variable, nameLength),
      _u32(h, 24),
      _u32(h, 20),
      _u32(h, 42),
    );
    if (sizes[0] != sizes[1]) _invalid();
    if (name == 'manifest.json') {
      if (sizes[0] > budgets.maxManifestBytes) _budget();
    } else {
      total += sizes[0];
      if (sizes[0] < 1 || total > budgets.maximumTotalImageBytes) _budget();
    }
    entries[name] = _Entry(name, flags, _u32(h, 16), sizes[0], sizes[2]);
    position += 46 + nameLength + extraLength;
  }
  if (position != centralEnd) _invalid();
  final sorted = entries.values.toList()
    ..sort((a, b) => a.offset.compareTo(b.offset));
  position = 0;
  for (final entry in sorted) {
    _cancel(cancellation);
    if (entry.offset != position) _invalid();
    final h = await _read(file, position, 30, centralOffset);
    if (_u32(h, 0) != 0x04034b50 ||
        _u16(h, 4) > 45 ||
        _u16(h, 6) != entry.flags ||
        _u16(h, 8) != 0 ||
        _u32(h, 14) != entry.crc) {
      _invalid();
    }
    final nameLength = _u16(h, 26), extraLength = _u16(h, 28);
    if (nameLength < 1 || nameLength > 128 || extraLength > 1024) _budget();
    final variable = await _read(
      file,
      position + 30,
      nameLength + extraLength,
      centralOffset,
    );
    if (_name(Uint8List.sublistView(variable, 0, nameLength)) != entry.name) {
      _invalid();
    }
    final sizes = _sizes(
      Uint8List.sublistView(variable, nameLength),
      _u32(h, 22),
      _u32(h, 18),
    );
    if (sizes[0] != entry.size || sizes[1] != entry.size) _invalid();
    entry.dataOffset = position + 30 + nameLength + extraLength;
    if (entry.size > centralOffset - entry.dataOffset) _invalid();
    position = entry.dataOffset + entry.size;
  }
  if (position != centralOffset) _invalid();
  return entries;
}

final _crcTable = List<int>.generate(256, (value) {
  for (var i = 0; i < 8; i++) {
    value = (value & 1) != 0 ? 0xedb88320 ^ (value >> 1) : value >> 1;
  }
  return value;
}, growable: false);

Future<void> _streamEntry(
  RandomAccessFile file,
  _Entry entry,
  CancellationToken? cancellation,
  Future<void> Function(Uint8List) consume,
) async {
  var read = 0, crc = 0xffffffff;
  await file.setPosition(entry.dataOffset);
  while (read < entry.size) {
    _cancel(cancellation);
    final bytes = await file.read(math.min(_chunk, entry.size - read));
    if (bytes.isEmpty) _invalid();
    read += bytes.length;
    for (final value in bytes) {
      crc = _crcTable[(crc ^ value) & 0xff] ^ (crc >> 8);
    }
    await consume(bytes);
  }
  _cancel(cancellation);
  if (read != entry.size || (crc ^ 0xffffffff) != entry.crc) _invalid();
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
