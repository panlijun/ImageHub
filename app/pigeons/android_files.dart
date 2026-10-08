import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/generated/android_files.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/io/imagehost/imagehost/AndroidFiles.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.imagehost.imagehost'),
  ),
)
enum AndroidIoCode {
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

class AndroidPickedResource {
  AndroidPickedResource({
    required this.handle,
    required this.displayName,
    required this.sourceType,
  });
  String handle;
  String displayName;
  String sourceType;
}

class AndroidSelection {
  AndroidSelection({required this.cancelled, required this.resources});
  bool cancelled;
  List<AndroidPickedResource> resources;
}

class AndroidReadReply {
  AndroidReadReply({
    required this.code,
    required this.bytes,
    required this.eof,
  });
  AndroidIoCode code;
  Uint8List bytes;
  bool eof;
}

class AndroidDestination {
  AndroidDestination({required this.cancelled, this.handle});
  bool cancelled;
  String? handle;
}

enum AndroidDestinationKind { document, tree, photos }

class AndroidExportRequest {
  AndroidExportRequest({
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
  AndroidDestinationKind kind;
  String? destinationHandle;
}

class AndroidExportReply {
  AndroidExportReply({required this.code, this.uri, this.displayName});
  AndroidIoCode code;
  String? uri;
  String? displayName;
}

@HostApi()
abstract class AndroidResourceHost {
  @asyncCallback
  AndroidSelection pickResources(bool photos, bool backup);
  @asyncCallback
  AndroidSelection recoverSelection();
  @asyncCallback
  AndroidReadReply readResource(String handle);
  @asyncCallback
  void closeResource(String handle);
}

@HostApi()
abstract class AndroidExportHost {
  @asyncCallback
  AndroidDestination createDocument(String displayName, String mimeType);
  @asyncCallback
  AndroidDestination pickDirectory(List<String> operationIds);
  @asyncCallback
  void closeDestination(String handle);
  @asyncCallback
  AndroidExportReply exportFile(AndroidExportRequest request);
  void cancelExport(String operationId);
}
