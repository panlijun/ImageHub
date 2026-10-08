import '../../../core/platform_resource.dart';
import 'organization_models.dart';

class ImageVersion {
  const ImageVersion({
    required this.id,
    required this.sha256,
    required this.byteCount,
    required this.format,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.orientation,
  });
  final String id;
  final String sha256;
  final int byteCount;
  final String format;
  final int width;
  final int height;
  final int frameCount;
  final int orientation;
  bool get isAnimated => frameCount > 1;
  @override
  bool operator ==(Object other) =>
      other is ImageVersion &&
      id == other.id &&
      sha256 == other.sha256 &&
      byteCount == other.byteCount &&
      format == other.format &&
      width == other.width &&
      height == other.height &&
      frameCount == other.frameCount &&
      orientation == other.orientation;
  @override
  int get hashCode => Object.hash(
    id,
    sha256,
    byteCount,
    format,
    width,
    height,
    frameCount,
    orientation,
  );
}

class DeviceCopy {
  const DeviceCopy({
    required this.id,
    required this.versionId,
    required this.relativePath,
  });
  final String id;
  final String versionId;
  final String relativePath;
  @override
  bool operator ==(Object other) =>
      other is DeviceCopy &&
      id == other.id &&
      versionId == other.versionId &&
      relativePath == other.relativePath;
  @override
  int get hashCode => Object.hash(id, versionId, relativePath);
}

class ImageAsset {
  ImageAsset({
    required this.id,
    required this.displayName,
    required this.version,
    required this.deviceCopy,
    required this.importedAt,
    required this.updatedAt,
    required this.sourceType,
    this.favorite = false,
    this.category,
    this.recycled = false,
    this.categoryId,
    List<LibraryTag> tags = const [],
    this.recycledAt,
    this.lastConfirmedUploadAt,
    this.confirmedRemoteResultCount = 0,
  }) : tags = List.unmodifiable(tags);
  final String id;
  final String displayName;
  final ImageVersion version;
  final DeviceCopy deviceCopy;
  final DateTime importedAt;
  final DateTime updatedAt;
  final String sourceType;
  final bool favorite;
  final String? category;
  final bool recycled;
  final String? categoryId;
  final List<LibraryTag> tags;
  final DateTime? recycledAt;
  final DateTime? lastConfirmedUploadAt;
  final int confirmedRemoteResultCount;
  @override
  bool operator ==(Object other) =>
      other is ImageAsset &&
      id == other.id &&
      displayName == other.displayName &&
      version == other.version &&
      deviceCopy == other.deviceCopy &&
      importedAt == other.importedAt &&
      updatedAt == other.updatedAt &&
      sourceType == other.sourceType &&
      favorite == other.favorite &&
      category == other.category &&
      recycled == other.recycled &&
      categoryId == other.categoryId &&
      recycledAt == other.recycledAt &&
      lastConfirmedUploadAt == other.lastConfirmedUploadAt &&
      confirmedRemoteResultCount == other.confirmedRemoteResultCount &&
      tags.length == other.tags.length &&
      List.generate(
        tags.length,
        (i) => tags[i] == other.tags[i],
      ).every((match) => match);
  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    version,
    deviceCopy,
    importedAt,
    updatedAt,
    sourceType,
    favorite,
    category,
    recycled,
    categoryId,
    recycledAt,
    lastConfirmedUploadAt,
    confirmedRemoteResultCount,
    Object.hashAll(tags),
  );
}

class GalleryPage {
  GalleryPage(Iterable<ImageAsset> items, this.total)
    : items = List.unmodifiable(items);
  final List<ImageAsset> items;
  final int total;
}

enum ImportStatus {
  saved,
  duplicate,
  repaired,
  needsRestore,
  failed,
  cancelled,
}

class ImportResult {
  const ImportResult(this.status, {this.asset, this.failure});
  final ImportStatus status;
  final ImageAsset? asset;
  final ResourceFailure? failure;
  bool get persisted =>
      status == ImportStatus.saved ||
      status == ImportStatus.repaired ||
      status == ImportStatus.duplicate;
}

enum CopyAvailability { available, missing, damaged, inaccessible }

class ImportProgress {
  const ImportProgress(this.phase, this.bytesCopied);
  final String phase;
  final int bytesCopied;
}

class RecoveryIssue {
  const RecoveryIssue(this.operationId, this.message);
  final String operationId;
  final String message;
}

enum ImportBoundary {
  copy,
  verified,
  ready,
  published,
  beforeDbCommit,
  afterDbCommit,
}

typedef ImportFaultHook = Future<void> Function(ImportBoundary boundary);
