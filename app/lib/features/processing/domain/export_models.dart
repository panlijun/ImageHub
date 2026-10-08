import 'dart:io';

/// A caller-owned file reference. Its lease must outlive all export IO.
class ExportInput {
  const ExportInput({
    required this.id,
    required this.source,
    required this.displayName,
    required this.expectedSha256,
    required this.expectedByteCount,
  });

  final String id;
  final File source;
  final String displayName;
  final String expectedSha256;
  final int expectedByteCount;
}

enum ExportStatus { saved, failed, cancelled }

enum ExportFailureKind {
  invalidInput,
  sourceMissing,
  inputChanged,
  permissionDenied,
  unsafePath,
  unsupported,
  storage,
}

class ExportFailure implements Exception {
  const ExportFailure(this.kind, this.message);
  final ExportFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Actual per-input evidence, including the selected collision-free name.
class ExportItemResult {
  const ExportItemResult({
    required this.id,
    required this.status,
    this.fileName,
    this.destinationPath,
    this.failureKind,
    this.reason,
  });

  final String id;
  final ExportStatus status;
  final String? fileName;
  final String? destinationPath;
  final ExportFailureKind? failureKind;
  final String? reason;
}
