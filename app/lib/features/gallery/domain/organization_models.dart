class LibraryTag {
  const LibraryTag({required this.id, required this.name});
  final String id;
  final String name;
  @override
  bool operator ==(Object other) =>
      other is LibraryTag && id == other.id && name == other.name;
  @override
  int get hashCode => Object.hash(id, name);
}

class LibraryCategory {
  const LibraryCategory({
    required this.id,
    required this.name,
    this.assetCount = 0,
  });
  final String id;
  final String name;
  final int assetCount;
}

class LibraryMutationException implements Exception {
  const LibraryMutationException(this.message);
  final String message;
  @override
  String toString() => message;
}
