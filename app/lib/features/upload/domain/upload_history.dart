import '../../accounts/domain/account_models.dart';
import 'queue_policy.dart';

enum UploadHistoryKind { publication, imported }

/// Restored audit identities never designate executable publications.
final class UploadHistoryRef {
  const UploadHistoryRef(this.kind, this.id);
  final UploadHistoryKind kind;
  final String id;
  @override
  bool operator ==(Object other) =>
      other is UploadHistoryRef && kind == other.kind && id == other.id;
  @override
  int get hashCode => Object.hash(kind, id);
}

final class UploadHistoryClearEntry {
  const UploadHistoryClearEntry({
    required this.reference,
    required this.displayName,
    required this.target,
    required this.state,
    required this.updatedAt,
  });
  final UploadHistoryRef reference;
  final String displayName;
  final TargetSnapshot target;
  final PublishState state;
  final DateTime updatedAt;
}

enum UploadHistoryProtection {
  active,
  inputInUse,
  pendingResult,
  retainedDependency,
  missing,
}

final class UploadHistoryPreserved {
  const UploadHistoryPreserved(this.reference, this.reason);
  final UploadHistoryRef reference;
  final UploadHistoryProtection reason;
}

final class UploadHistoryClearResult {
  const UploadHistoryClearResult({
    required this.publicationRemoved,
    required this.importedRemoved,
    required this.preservedCount,
  });
  final int publicationRemoved;
  final int importedRemoved;
  final int preservedCount;
  int get removedCount => publicationRemoved + importedRemoved;
}

enum UploadHistoryClearBoundary { recordsDeleted }

typedef UploadHistoryClearFaultHook = Future<void> Function(
  UploadHistoryClearBoundary boundary,
);
