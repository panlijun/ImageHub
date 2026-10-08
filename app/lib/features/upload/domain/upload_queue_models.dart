import 'dart:io';

import '../../accounts/domain/account_models.dart';
import '../../gallery/domain/library_models.dart';
import '../../links/domain/link_availability.dart';
import 'queue_policy.dart';

enum UploadInputKind { original, processed }

enum QueueWaitReason {
  network,
  authorization,
  inputUnavailable,
  capabilityUnknown,
  retry,
  system,
  processing,
}

/// Immutable, non-secret input and policy captured by the repository, rather
/// than supplied by a mutable UI or reconstructed from later defaults.
/// A publication with processingJobId and an original input references its
/// frozen processing source. It must not dispatch to the network until a
/// confirmed processing output replaces that input.
final class FrozenUploadInput {
  FrozenUploadInput({
    required this.kind,
    required this.referenceId,
    required this.displayName,
    required this.version,
    required this.policyKey,
    this.processingSummary,
  });
  final UploadInputKind kind;
  final String referenceId;
  final String displayName;
  final ImageVersion version;
  final String policyKey;

  /// Frozen, redacted audit text; it is never reparsed to execute processing.
  /// policyKey is a digest of the exact canonical, non-runtime parameters.
  final String? processingSummary;
}

final class UploadPublication {
  const UploadPublication({
    required this.id,
    required this.batchId,
    required this.position,
    required this.input,
    required this.target,
    required this.state,
    required this.attemptCount,
    required this.generation,
    required this.accumulatedRunning,
    required this.createdAt,
    required this.updatedAt,
    this.userPaused = false,
    this.waitReason,
    this.retryDelay,
    this.currentAttemptId,
    this.message,
    this.resultId,
    this.processingJobId,
  });
  final String id, batchId;
  final int position;
  final FrozenUploadInput input;
  final TargetSnapshot target;
  final PublishState state;
  final int attemptCount, generation;
  final Duration accumulatedRunning;
  final DateTime createdAt, updatedAt;

  /// Independent user intent; batch resume must not clear this pause.
  final bool userPaused;
  final QueueWaitReason? waitReason;

  /// On reopening, wait this entire saved duration conservatively. A process
  /// monotonic origin never survives a restart and UTC is not a retry clock.
  final Duration? retryDelay;
  final String? currentAttemptId, message, resultId;
  final String? processingJobId;
  bool get processingPending =>
      processingJobId != null && input.kind == UploadInputKind.original;
}

final class UploadBatch {
  UploadBatch({
    required this.id,
    required this.intentId,
    required this.createdAt,
    required this.paused,
    required Iterable<UploadPublication> items,
  }) : items = List.unmodifiable(items);
  final String id, intentId;
  final DateTime createdAt;
  final bool paused;
  final List<UploadPublication> items;
  BatchSummary get summary => BatchSummary(items.map((item) => item.state));
}

final class UploadAttemptRecord {
  const UploadAttemptRecord({
    required this.id,
    required this.itemId,
    required this.generation,
    required this.startedAt,
    required this.requestMayHaveStarted,
    this.endedAt,
    this.outcome,
  });
  final String id, itemId;
  final int generation;
  final DateTime startedAt;
  final bool requestMayHaveStarted;
  final DateTime? endedAt;
  final String? outcome;
}

/// Runtime only. Release AFTER the adapter's actual IO has settled, not when
/// CancelToken is signalled. Neither the credential nor file is serialized.
final class UploadExecution {
  factory UploadExecution({
    required UploadPublication item,
    required String attemptId,
    required int generation,
    required ResolvedTarget target,
    required File file,
    required Future<void> Function() release,
    String? libraryEpoch,
  }) => UploadExecution._(
    item,
    attemptId,
    generation,
    target,
    file,
    release,
    libraryEpoch,
  );
  UploadExecution._(
    this.item,
    this.attemptId,
    this.generation,
    this.target,
    this.file,
    this._release,
    this.libraryEpoch,
  );
  final UploadPublication item;
  final String attemptId;
  final int generation;
  final String? libraryEpoch;
  final ResolvedTarget target;
  final File file;
  final Future<void> Function() _release;
  Future<void>? _releasing;
  Future<void> release() =>
      _releasing ??= _release().catchError((Object error) {
        _releasing = null;
        throw error;
      });
  @override
  String toString() => 'UploadExecution([运行中])';
}

/// Safe ordinary history; the protected management reference is not exposed.
final class RemoteUploadResult {
  const RemoteUploadResult({
    required this.id,
    required this.attemptId,
    required this.input,
    required this.target,
    required this.remoteId,
    required this.directUrl,
    required this.confirmedAt,
    required this.late,
    required this.managementAvailable,
    this.viewerUrl,
    this.availability = const LinkAvailabilityRecord(),
  });
  final String id, attemptId, remoteId;
  final FrozenUploadInput input;
  final TargetSnapshot target;
  final Uri directUrl;
  final Uri? viewerUrl;
  final DateTime confirmedAt;
  final bool late, managementAvailable;
  final LinkAvailabilityRecord availability;
  bool get usesInsecureHttp => directUrl.scheme == 'http';
}

final class UploadQueueFailure implements Exception {
  const UploadQueueFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
