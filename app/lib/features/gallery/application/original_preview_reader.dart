import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashing;

import '../../../core/platform_resource.dart';
import '../../processing/application/processing_scheduler.dart';
import '../../processing/domain/processing_models.dart';
import '../data/library_repository.dart';
import '../domain/library_models.dart';
import '../domain/recycle_models.dart';

/// Reads the original encoding without decoding or replacing animated frames.
/// Production awaits the actual isolate, even when its caller is cancelled.
class OriginalPreviewDecoder {
  const OriginalPreviewDecoder();

  Future<Uint8List> read(
    File file, {
    required int memoryBudgetBytes,
    required String expectedSha256,
    required int expectedByteCount,
  }) => Isolate.run(
    () => _readOriginal(
      file.path,
      memoryBudgetBytes,
      expectedSha256,
      expectedByteCount,
    ),
  );
}

/// The file lease has drained before this input is returned. The shared pixel
/// budget remains reserved until the SDK codec and its current frame dispose.
final class OriginalPreviewInput {
  OriginalPreviewInput._(this.bytes, this.asset, this._permit);

  final Uint8List bytes;
  final ImageAsset asset;
  final ProcessingPermit _permit;
  int get memoryBudgetBytes => _permit.memoryBudgetBytes;

  /// Call after all real codec/frame work has ended. Repeated calls are safe.
  void release() => _permit.release();
}

class OriginalPreviewReader {
  const OriginalPreviewReader(
    this.repository, {
    this.decoder = const OriginalPreviewDecoder(),
  });

  final LibraryRepository repository;
  final OriginalPreviewDecoder decoder;

  Future<OriginalPreviewInput> read(
    ImageAsset asset, {
    CancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    LibraryFileLease? lease;
    ProcessingPermit? permit;
    try {
      lease = await repository.acquireAssetLease(
        [asset.id],
        purpose: 'original-preview',
        typedSourceFailures: true,
      );
      final fresh = lease.assets.single;
      if (fresh.id != asset.id || fresh.version != asset.version) {
        throw const ResourceFailure(FailureKind.unavailable);
      }
      permit = await repository.processingScheduler.acquire(
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      final bytes = await decoder.read(
        File(lease.pathsByVersion[fresh.version.id]!),
        memoryBudgetBytes: permit.memoryBudgetBytes,
        expectedSha256: fresh.version.sha256,
        expectedByteCount: fresh.version.byteCount,
      );
      cancellation?.throwIfCancelled();
      // Release can fail in SQL after IO has ended. Never return successful
      // input in that case, and do not retry cleanup as an implicit side effect.
      final completedLease = lease;
      lease = null;
      await completedLease.release();
      cancellation?.throwIfCancelled();
      final input = OriginalPreviewInput._(bytes, fresh, permit);
      permit = null;
      return input;
    } on ResourceFailure {
      rethrow;
    } on ProcessingFailure catch (failure) {
      throw ResourceFailure(
        failure.kind == ProcessingFailureKind.cancelled
            ? FailureKind.cancelled
            : failure.kind == ProcessingFailureKind.resourceBudget
            ? FailureKind.resourceBudget
            : FailureKind.storage,
      );
    } catch (_) {
      throw const ResourceFailure(FailureKind.storage);
    } finally {
      try {
        await _releaseLease(lease);
      } finally {
        // A failed SQL release keeps its protective row, but ended IO must
        // drain the in-process budget so close cannot wait forever.
        permit?.release();
      }
    }
  }
}

Future<void> _releaseLease(LibraryFileLease? lease) async {
  try {
    await lease?.release();
  } catch (_) {
    throw const ResourceFailure(FailureKind.storage);
  }
}

Future<Uint8List> _readOriginal(
  String path,
  int budget,
  String expectedSha256,
  int expectedByteCount,
) async {
  try {
    final limit = budget ~/ 4;
    if (expectedByteCount <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
      throw const ResourceFailure(FailureKind.invalidImage);
    }
    final file = File(path);
    final length = await file.length();
    if (length > limit || expectedByteCount > limit) {
      throw const ResourceFailure(FailureKind.resourceBudget);
    }
    if (length != expectedByteCount) {
      throw const ResourceFailure(FailureKind.invalidImage);
    }
    final bytes = Uint8List(expectedByteCount);
    final digest = _DigestSink();
    final hash = hashing.sha256.startChunkedConversion(digest);
    var offset = 0;
    try {
      await for (final chunk in file.openRead()) {
        if (offset + chunk.length > limit) {
          throw const ResourceFailure(FailureKind.resourceBudget);
        }
        if (offset + chunk.length > bytes.length) {
          throw const ResourceFailure(FailureKind.invalidImage);
        }
        bytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
        hash.add(chunk);
      }
    } finally {
      hash.close();
    }
    if (offset != expectedByteCount ||
        digest.value?.toString() != expectedSha256) {
      throw const ResourceFailure(FailureKind.invalidImage);
    }
    return bytes;
  } on ResourceFailure {
    rethrow;
  } on FileSystemException {
    throw const ResourceFailure(FailureKind.unavailable);
  } catch (_) {
    throw const ResourceFailure(FailureKind.storage);
  }
}

final class _DigestSink implements Sink<hashing.Digest> {
  hashing.Digest? value;
  @override
  void add(hashing.Digest data) => value = data;
  @override
  void close() {}
}
