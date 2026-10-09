import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/generated/apple_files.g.dart',
    swiftOut: 'apple/generated/AppleFiles.g.swift',
  ),
)
enum AppleIoCode {
  ok,
  cancelled,
  permissionDenied,
  sourceMissing,
  cloudPending,
  unavailable,
  invalidInput,
  inputChanged,
  unsupported,
  storage,
  cleanupPending,
  unconfirmed,
}

class ApplePickedResource {
  ApplePickedResource({required this.handle, required this.displayName});
  String handle;
  String displayName;
}

class AppleSelection {
  AppleSelection({required this.cancelled, required this.resources});
  bool cancelled;
  List<ApplePickedResource> resources;
}

class AppleReadReply {
  AppleReadReply({required this.code, required this.bytes, required this.eof});
  AppleIoCode code;
  Uint8List bytes;
  bool eof;
}

class AppleDestination {
  AppleDestination({required this.cancelled, this.handle});
  bool cancelled;
  String? handle;
}

enum AppleDestinationKind { directory, photos }

class AppleExportRequest {
  AppleExportRequest({
    required this.operationId,
    required this.sourcePath,
    required this.displayName,
    required this.mimeType,
    required this.sha256,
    required this.byteCount,
    required this.kind,
    this.destinationHandle,
  });
  String operationId;
  String sourcePath;
  String displayName;
  String mimeType;
  String sha256;
  int byteCount;
  AppleDestinationKind kind;
  String? destinationHandle;
}

class AppleExportReply {
  AppleExportReply({
    required this.code,
    required this.cleanupPending,
    this.uri,
    this.displayName,
  });
  AppleIoCode code;
  bool cleanupPending;
  String? uri;
  String? displayName;
}

@HostApi()
abstract class AppleFileHost {
  @asyncCallback
  AppleSelection pickBackup(String selectionId);
  @asyncCallback
  AppleReadReply readResource(String handle);
  @asyncCallback
  void closeResource(String handle);
  @asyncCallback
  AppleDestination pickDirectory(String selectionId, List<String> operationIds);
  @asyncCallback
  void cancelSelection(String selectionId);
  @asyncCallback
  void closeDestination(String handle);
  @asyncCallback
  AppleExportReply exportFile(AppleExportRequest request);
  void cancelExport(String operationId);
}
