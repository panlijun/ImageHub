import 'dart:io';

import '../../gallery/domain/library_models.dart';
import 'processing_models.dart';

enum OutputState { writing, prepared, ready, failed, cancelled, deleting }

enum OutputRetention {
  hour(Duration(hours: 1)),
  day(Duration(hours: 24)),
  week(Duration(days: 7));

  const OutputRetention(this.duration);
  final Duration duration;
}

/// Only ready + verified results expose a file to preview/save/export callers.
class ProcessedOutput {
  ProcessedOutput({
    required this.id,
    required this.displayName,
    required this.state,
    required this.request,
    required this.createdAt,
    required this.expiresAt,
    required this.availability,
    this.version,
    this.file,
    this.savedVersionId,
    this.failureMessage,
    this.lossy = false,
    this.transparencyRemoved = false,
    this.animationRemoved = false,
    Iterable<String> warnings = const [],
  }) : warnings = List.unmodifiable(warnings);
  final String id;
  final String displayName;
  final OutputState state;
  final ProcessingRequest request;
  final DateTime createdAt;
  final DateTime expiresAt;
  final CopyAvailability availability;
  final ImageVersion? version;
  final File? file;
  final String? savedVersionId;
  final String? failureMessage;
  final bool lossy;
  final bool transparencyRemoved;
  final bool animationRemoved;
  final List<String> warnings;
  bool get usable =>
      state == OutputState.ready && file != null && version != null;
  int get beforeByteCount =>
      request.inputs.fold(0, (sum, i) => sum + i.version.byteCount);
  int? get byteSavings =>
      version == null ? null : beforeByteCount - version!.byteCount;
}

class OutputWriteIntent {
  const OutputWriteIntent(this.id, this.destination);
  final String id;
  final File destination;
}

/// Cancellation does not release this; the actual reader must have stopped.
class OutputFileLease {
  OutputFileLease(this.output, this._release);
  final ProcessedOutput output;
  final Future<void> Function() _release;
  Future<void>? _releasing;
  Future<void> release() =>
      _releasing ??= _release().catchError((Object error) {
        _releasing = null;
        throw error;
      });
}

class OutputCleanupResult {
  OutputCleanupResult(this.removed, this.protected, Iterable<String> failedIds)
    : failedIds = List.unmodifiable(failedIds);
  final int removed;
  final int protected;
  final List<String> failedIds;
}

enum OutputBoundary { intent, prepared, published, committed, beforeDelete }

typedef OutputFaultHook = Future<void> Function(OutputBoundary boundary);
