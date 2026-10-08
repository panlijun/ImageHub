import '../../accounts/domain/account_models.dart';
import '../../upload/domain/upload_queue_models.dart';
import 'backup_manifest.dart';

enum BackupResultConflictKind { resultIdentity, confirmationIdentity }

/// Only stable identities enter a conflict report, never URLs or exceptions.
final class BackupResultConflict {
  const BackupResultConflict({
    required this.resultId,
    required this.attemptId,
    required this.kind,
  });
  final String resultId, attemptId;
  final BackupResultConflictKind kind;
}

final class BackupResultMergePlan {
  BackupResultMergePlan._(
    Iterable<BackupRemoteResult> results,
    Map<String, String> resultIds,
    Iterable<BackupResultConflict> conflicts,
  ) : results = List.unmodifiable(results),
      resultIds = Map.unmodifiable(resultIds),
      conflicts = List.unmodifiable(conflicts);

  final List<BackupRemoteResult> results;

  /// Accepted incoming result -> preserved result. Rejected links have no map.
  final Map<String, String> resultIds;
  final List<BackupResultConflict> conflicts;
}

/// Pure merge of already validated, identity-remapped ordinary confirmations.
/// This does not persist, restore secrets, schedule a task or dedupe by URL.
abstract final class BackupResultMergePlanner {
  static BackupResultMergePlan plan({
    required Iterable<BackupRemoteResult> current,
    required Iterable<BackupRemoteResult> incoming,
  }) {
    final retained = current.toList();
    final candidates = incoming.toList()..sort((a, b) => a.id.compareTo(b.id));
    _unique(retained);
    _unique(candidates);
    final byId = {for (final result in retained) result.id: result};
    final byAttempt = {for (final result in retained) result.attemptId: result};
    final mappings = <String, String>{};
    final conflicts = <BackupResultConflict>[];
    for (final candidate in candidates) {
      final identity = byId[candidate.id];
      final confirmation = byAttempt[candidate.attemptId];
      if (identity != null) {
        if (!_sameConfirmation(identity, candidate) ||
            confirmation != null && confirmation.id != identity.id) {
          conflicts.add(
            BackupResultConflict(
              resultId: candidate.id,
              attemptId: candidate.attemptId,
              kind: BackupResultConflictKind.resultIdentity,
            ),
          );
          continue;
        }
        mappings[candidate.id] = identity.id;
      } else if (confirmation != null) {
        if (!_sameConfirmation(confirmation, candidate)) {
          conflicts.add(
            BackupResultConflict(
              resultId: candidate.id,
              attemptId: candidate.attemptId,
              kind: BackupResultConflictKind.confirmationIdentity,
            ),
          );
          continue;
        }
        mappings[candidate.id] = confirmation.id;
      } else {
        retained.add(candidate);
        byId[candidate.id] = candidate;
        byAttempt[candidate.attemptId] = candidate;
        mappings[candidate.id] = candidate.id;
      }
    }
    return BackupResultMergePlan._(retained, mappings, conflicts);
  }
}

void _unique(List<BackupRemoteResult> results) {
  final ids = <String>{}, attempts = <String>{};
  for (final result in results) {
    if (!ids.add(result.id) || !attempts.add(result.attemptId)) {
      throw const BackupFailure(BackupFailureKind.invalidManifest);
    }
  }
}

bool _sameInput(FrozenUploadInput a, FrozenUploadInput b) =>
    a.kind == b.kind &&
    a.referenceId == b.referenceId &&
    a.displayName == b.displayName &&
    a.version == b.version &&
    a.policyKey == b.policyKey &&
    a.processingSummary == b.processingSummary;

bool _sameTarget(TargetSnapshot a, TargetSnapshot b) =>
    a.id == b.id &&
    a.service == b.service &&
    a.alias == b.alias &&
    a.anonymous == b.anonymous;

bool _sameConfirmation(BackupRemoteResult a, BackupRemoteResult b) =>
    a.attemptId == b.attemptId &&
    _sameInput(a.input, b.input) &&
    _sameTarget(a.target, b.target) &&
    a.remoteId == b.remoteId &&
    a.directUrl == b.directUrl &&
    a.viewerUrl == b.viewerUrl &&
    a.confirmedUtc == b.confirmedUtc &&
    a.late == b.late;
