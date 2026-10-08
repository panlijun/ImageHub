import 'dart:io';
import 'dart:typed_data';

import '../../../core/image_inspector.dart';
import '../../../core/platform_resource.dart';
import '../../gallery/data/library_repository.dart';
import '../domain/output_models.dart';
import '../domain/processing_models.dart';
import 'processing_scheduler.dart';

/// A replaceable decoder boundary; production always awaits the actual isolate.
class OutputPreviewDecoder {
  const OutputPreviewDecoder();

  Future<Uint8List> read(
    File file, {
    required int memoryBudgetBytes,
    required String expectedSha256,
    required int expectedByteCount,
  }) => ImageInspector(memoryBudgetBytes).thumbnailBytes(
    file,
    expectedSha256: expectedSha256,
    expectedByteCount: expectedByteCount,
  );
}

/// Owns file use until the decoder really finishes, including after disposal.
class OutputPreviewReader {
  const OutputPreviewReader(
    this.repository, {
    this.decoder = const OutputPreviewDecoder(),
  });

  final LibraryRepository repository;
  final OutputPreviewDecoder decoder;

  Future<Uint8List> read(
    String outputId, {
    CancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    OutputFileLease? lease;
    ProcessingPermit? permit;
    try {
      lease = await repository.acquireOutputLease(outputId);
      permit = await repository.processingScheduler.acquire(
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      final output = lease.output;
      final bytes = await decoder.read(
        output.file!,
        memoryBudgetBytes: permit.memoryBudgetBytes,
        expectedSha256: output.version!.sha256,
        expectedByteCount: output.version!.byteCount,
      );
      cancellation?.throwIfCancelled();
      return bytes;
    } on ResourceFailure catch (failure) {
      throw ProcessingFailure(
        failure.kind == FailureKind.cancelled
            ? ProcessingFailureKind.cancelled
            : ProcessingFailureKind.storage,
        failure.kind == FailureKind.cancelled
            ? '结果预览已停止，实际读取结束后释放使用权。'
            : '结果预览无法安全读取，请重载检查；永久图片保留。',
      );
    } on ProcessingFailure {
      rethrow;
    } catch (_) {
      throw const ProcessingFailure(
        ProcessingFailureKind.storage,
        '结果预览无法安全读取，请重载检查；永久图片保留。',
      );
    } finally {
      try {
        await lease?.release();
      } finally {
        permit?.release();
      }
    }
  }
}
