import 'library_models.dart';

/// The caller releases this only after its actual file IO has safely ended.
/// Cancellation of a task does not release its lease.
class LibraryFileLease {
  factory LibraryFileLease({
    required Iterable<ImageAsset> assets,
    required Map<String, String> pathsByVersion,
    required Future<void> Function() onRelease,
  }) => LibraryFileLease._(
    List.unmodifiable(assets),
    Map.unmodifiable(pathsByVersion),
    onRelease,
  );

  LibraryFileLease._(this.assets, this.pathsByVersion, this._onRelease);

  final List<ImageAsset> assets;
  final Map<String, String> pathsByVersion;
  final Future<void> Function() _onRelease;
  Future<void>? _releasing;
  bool _released = false;
  bool get released => _released;

  Future<void> release() => _releasing ??= _release();
  Future<void> _release() async {
    try {
      await _onRelease();
      _released = true;
    } catch (_) {
      _releasing = null;
      rethrow;
    }
  }
}

class LibraryPurgeResult {
  const LibraryPurgeResult({
    required this.recordsRemoved,
    required this.copiesRemoved,
  });
  final int recordsRemoved;
  final int copiesRemoved;
}
