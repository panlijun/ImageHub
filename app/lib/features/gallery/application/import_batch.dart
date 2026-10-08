import '../../../core/platform_resource.dart';
import '../data/library_repository.dart';
import '../domain/library_models.dart';

class BatchImportReport {
  BatchImportReport(Iterable<ImportResult> results)
    : results = List.unmodifiable(results);
  final List<ImportResult> results;
  int count(ImportStatus status) =>
      results.where((result) => result.status == status).length;
}

/// Independent results and a stop token retain committed items without acquiring later sources.
class ImportBatch {
  const ImportBatch(this.repository);
  final LibraryRepository repository;
  Future<BatchImportReport> run(
    List<PlatformResource> resources, {
    CancellationToken? cancellation,
    void Function(int index, ImportProgress progress)? onProgress,
    void Function(int index, ImportResult result)? onResult,
  }) async {
    final results = <ImportResult>[];
    for (var index = 0; index < resources.length; index++) {
      final result = cancellation?.isCancelled == true
          ? const ImportResult(
              ImportStatus.cancelled,
              failure: ResourceFailure(FailureKind.cancelled),
            )
          : await repository.importResource(
              resources[index],
              cancellation: cancellation,
              onProgress: (progress) => onProgress?.call(index, progress),
            );
      results.add(result);
      onResult?.call(index, result);
    }
    return BatchImportReport(results);
  }
}
