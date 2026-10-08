import 'dart:collection';

final class StorageFailure implements Exception {
  const StorageFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

enum StorageCategory {
  permanent,
  recycled,
  retained,
  thumbnails,
  temporaryResults,
  staging,
  database,
  untracked,
}

/// Physical file bytes are disjoint; diagnostic JSON is logical SQL content.
final class StorageReport {
  StorageReport({
    required Map<StorageCategory, int> fileBytes,
    required this.diagnosticContentBytes,
    required this.cacheLimitBytes,
    required this.protectedThumbnailBytes,
    required this.untrackedThumbnailBytes,
    required this.observedAt,
    this.availableBytes,
    this.warning,
  }) : fileBytes = UnmodifiableMapView(Map.of(fileBytes));
  final Map<StorageCategory, int> fileBytes;
  final int diagnosticContentBytes, cacheLimitBytes;
  final int protectedThumbnailBytes, untrackedThumbnailBytes;
  final DateTime observedAt;
  final int? availableBytes;
  final String? warning;
  int get totalFileBytes => fileBytes.values.fold(0, (a, b) => a + b);
}

final class ThumbnailCleanupResult {
  const ThumbnailCleanupResult({
    required this.removed,
    required this.removedBytes,
    required this.protected,
    required this.failed,
  });
  final int removed, removedBytes, protected, failed;
}

/// Persisted use order is independent of a backwards wall clock.
final class CacheCandidate {
  const CacheCandidate(
    this.id,
    this.bytes,
    this.lastUseOrder, {
    this.protected = false,
  });
  final String id;
  final int bytes, lastUseOrder;
  final bool protected;
}

final class CacheAdmission {
  CacheAdmission(Iterable<String> evictIds, this.remainingBytes, this.canAdmit)
    : evictIds = List.unmodifiable(evictIds);
  final List<String> evictIds;
  final int remainingBytes;
  final bool canAdmit;
}

final class CachePolicy {
  const CachePolicy();
  CacheAdmission evaluate({
    required Iterable<CacheCandidate> entries,
    required int limitBytes,
    int incomingBytes = 0,
    int untrackedBytes = 0,
  }) {
    if (limitBytes < 1 || incomingBytes < 0 || untrackedBytes < 0) {
      throw const StorageFailure('缓存计量无效，未执行清理。');
    }
    final candidates = entries.toList();
    if (candidates.any((e) => e.bytes < 0 || e.lastUseOrder < 0) ||
        candidates.map((e) => e.id).toSet().length != candidates.length) {
      throw const StorageFailure('缓存记录无法安全识别，现场已保留。');
    }
    var remaining = candidates.fold(untrackedBytes, (n, e) => n + e.bytes);
    candidates.sort((a, b) {
      final time = a.lastUseOrder.compareTo(b.lastUseOrder);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
    final evict = <String>[];
    for (final candidate in candidates) {
      if (remaining + incomingBytes <= limitBytes) break;
      if (candidate.protected) continue;
      evict.add(candidate.id);
      remaining -= candidate.bytes;
    }
    return CacheAdmission(
      evict,
      remaining,
      remaining + incomingBytes <= limitBytes,
    );
  }
}

enum CacheBoundary {
  intent,
  stageOwned,
  prepared,
  published,
  ready,
  beforeDelete,
  reading,
}

typedef CacheFaultHook = Future<void> Function(CacheBoundary boundary);
