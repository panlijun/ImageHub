import '../../../core/text_policy.dart';
import '../../accounts/domain/account_models.dart';
import '../../upload/domain/upload_queue_models.dart';
import 'link_availability.dart';

enum LinkResultSort { confirmed, name, target }

final class LinkResultQuery {
  const LinkResultQuery({
    this.keyword = '',
    this.targetId,
    this.service,
    this.inputKind,
    this.availability,
    this.sort = LinkResultSort.confirmed,
    this.ascending = false,
  });
  final String keyword;
  final String? targetId;
  final ImageHostService? service;
  final UploadInputKind? inputKind;
  final LinkAvailability? availability;
  final LinkResultSort sort;
  final bool ascending;
  String get normalizedKeyword => TextPolicy.key(keyword);
  bool get filtered =>
      normalizedKeyword.isNotEmpty ||
      targetId != null ||
      service != null ||
      inputKind != null ||
      availability != null;
  LinkResultQuery copyWith({
    String? keyword,
    Object? targetId = _unset,
    Object? service = _unset,
    Object? inputKind = _unset,
    Object? availability = _unset,
    LinkResultSort? sort,
    bool? ascending,
  }) => LinkResultQuery(
    keyword: keyword ?? this.keyword,
    targetId: identical(targetId, _unset) ? this.targetId : targetId as String?,
    service: identical(service, _unset)
        ? this.service
        : service as ImageHostService?,
    inputKind: identical(inputKind, _unset)
        ? this.inputKind
        : inputKind as UploadInputKind?,
    availability: identical(availability, _unset)
        ? this.availability
        : availability as LinkAvailability?,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
  );
  @override
  bool operator ==(Object other) =>
      other is LinkResultQuery &&
      keyword == other.keyword &&
      targetId == other.targetId &&
      service == other.service &&
      inputKind == other.inputKind &&
      availability == other.availability &&
      sort == other.sort &&
      ascending == other.ascending;
  @override
  int get hashCode => Object.hash(
    keyword,
    targetId,
    service,
    inputKind,
    availability,
    sort,
    ascending,
  );
}

const _unset = Object();

final class LinkResultPage {
  LinkResultPage(Iterable<RemoteUploadResult> items, this.total)
    : items = List.unmodifiable(items);
  final List<RemoteUploadResult> items;
  final int total;
}

enum LinkCopyScope { visibleResults, assetsAndTargets }

final class LocalResultRemovalReport {
  const LocalResultRemovalReport({
    required this.removed,
    required this.missing,
    required this.cleanupPending,
  });
  final int removed, missing, cleanupPending;
}
