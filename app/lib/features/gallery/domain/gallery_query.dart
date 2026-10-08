import '../../../core/text_policy.dart';
import '../../accounts/domain/account_models.dart';
import '../../upload/domain/upload_queue_models.dart';
import 'library_models.dart';

enum GallerySort { imported, uploaded, name, size }

/// Matching publications need not form a single overall status for an asset.
enum GalleryUploadFilter {
  confirmed,
  failed,
  unknown,
  active,
  cancelled,
  withoutLinks,
}

/// The same immutable query controls counts, pages and matching identities.
class GalleryQuery {
  const GalleryQuery({
    this.keyword = '',
    this.favoritesOnly = false,
    this.categoryId,
    this.uncategorized = false,
    this.format,
    this.sourceType,
    this.availability,
    this.remoteTargetId,
    this.remoteService,
    this.remoteInputKind,
    this.uploadFilter,
    this.recycledOnly = false,
    this.sort = GallerySort.imported,
    this.ascending = false,
  }) : tagIds = const [];

  GalleryQuery.filtered({
    this.keyword = '',
    this.favoritesOnly = false,
    this.categoryId,
    this.uncategorized = false,
    this.format,
    this.sourceType,
    this.availability,
    this.remoteTargetId,
    this.remoteService,
    this.remoteInputKind,
    this.uploadFilter,
    this.recycledOnly = false,
    this.sort = GallerySort.imported,
    this.ascending = false,
    Iterable<String> tagIds = const [],
  }) : tagIds = List.unmodifiable(tagIds.toSet().toList()..sort());

  final String keyword;
  final bool favoritesOnly;
  final String? categoryId;
  final bool uncategorized;
  final String? format;
  final String? sourceType;
  final CopyAvailability? availability;
  final String? remoteTargetId;
  final ImageHostService? remoteService;
  final UploadInputKind? remoteInputKind;
  final GalleryUploadFilter? uploadFilter;
  final bool recycledOnly;
  final GallerySort sort;
  final bool ascending;
  final List<String> tagIds;

  String get normalizedKeyword => TextPolicy.key(keyword);
  bool get isUnfiltered =>
      normalizedKeyword.isEmpty &&
      !favoritesOnly &&
      categoryId == null &&
      !uncategorized &&
      format == null &&
      sourceType == null &&
      availability == null &&
      remoteTargetId == null &&
      remoteService == null &&
      remoteInputKind == null &&
      uploadFilter == null &&
      tagIds.isEmpty;

  GalleryQuery copyWith({
    String? keyword,
    bool? favoritesOnly,
    Object? categoryId = _unset,
    bool? uncategorized,
    Object? format = _unset,
    Object? sourceType = _unset,
    Object? availability = _unset,
    Object? remoteTargetId = _unset,
    Object? remoteService = _unset,
    Object? remoteInputKind = _unset,
    Object? uploadFilter = _unset,
    bool? recycledOnly,
    GallerySort? sort,
    bool? ascending,
    Iterable<String>? tagIds,
  }) => GalleryQuery.filtered(
    keyword: keyword ?? this.keyword,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    categoryId: identical(categoryId, _unset)
        ? this.categoryId
        : categoryId as String?,
    uncategorized: uncategorized ?? this.uncategorized,
    format: identical(format, _unset) ? this.format : format as String?,
    sourceType: identical(sourceType, _unset)
        ? this.sourceType
        : sourceType as String?,
    availability: identical(availability, _unset)
        ? this.availability
        : availability as CopyAvailability?,
    remoteTargetId: identical(remoteTargetId, _unset)
        ? this.remoteTargetId
        : remoteTargetId as String?,
    remoteService: identical(remoteService, _unset)
        ? this.remoteService
        : remoteService as ImageHostService?,
    remoteInputKind: identical(remoteInputKind, _unset)
        ? this.remoteInputKind
        : remoteInputKind as UploadInputKind?,
    uploadFilter: identical(uploadFilter, _unset)
        ? this.uploadFilter
        : uploadFilter as GalleryUploadFilter?,
    recycledOnly: recycledOnly ?? this.recycledOnly,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    tagIds: tagIds ?? this.tagIds,
  );

  @override
  bool operator ==(Object other) =>
      other is GalleryQuery &&
      keyword == other.keyword &&
      favoritesOnly == other.favoritesOnly &&
      categoryId == other.categoryId &&
      uncategorized == other.uncategorized &&
      format == other.format &&
      sourceType == other.sourceType &&
      availability == other.availability &&
      remoteTargetId == other.remoteTargetId &&
      remoteService == other.remoteService &&
      remoteInputKind == other.remoteInputKind &&
      uploadFilter == other.uploadFilter &&
      recycledOnly == other.recycledOnly &&
      sort == other.sort &&
      ascending == other.ascending &&
      tagIds.length == other.tagIds.length &&
      List.generate(
        tagIds.length,
        (i) => tagIds[i] == other.tagIds[i],
      ).every((same) => same);

  @override
  int get hashCode => Object.hash(
    keyword,
    favoritesOnly,
    categoryId,
    uncategorized,
    format,
    sourceType,
    availability,
    remoteTargetId,
    remoteService,
    remoteInputKind,
    uploadFilter,
    recycledOnly,
    sort,
    ascending,
    Object.hashAll(tagIds),
  );
}

const _unset = Object();
