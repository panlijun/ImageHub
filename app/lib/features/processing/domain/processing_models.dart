import 'dart:io';

import '../../gallery/domain/library_models.dart';

enum ProcessingOperation { compress, crop, stitch }

enum ProcessingMode { fidelity, sizeFirst }

enum ProcessingFormat { png, jpeg, webp }

enum StitchLayout { horizontal, vertical, grid }

enum ProcessingFailureKind {
  invalidParameters,
  invalidImage,
  inputChanged,
  unsupported,
  confirmationRequired,
  colorMetadataUnsupported,
  resourceBudget,
  cancelled,
  storage,
}

class ProcessingFailure implements Exception {
  const ProcessingFailure(this.kind, this.message);
  final ProcessingFailureKind kind;
  final String message;
  @override
  String toString() => message;
}

int processingInteger(Object? value, String field) {
  if (value is! int) {
    throw ProcessingFailure(
      ProcessingFailureKind.invalidParameters,
      '$field 必须是有限整数。',
    );
  }
  return value;
}

Map<String, Object?> versionSnapshot(ImageVersion version) => {
  'id': version.id,
  'sha256': version.sha256,
  'byteCount': version.byteCount,
  'format': version.format,
  'width': version.width,
  'height': version.height,
  'frameCount': version.frameCount,
  'orientation': version.orientation,
};

ImageVersion versionFromSnapshot(Map<Object?, Object?> map) => ImageVersion(
  id: map['id'] as String,
  sha256: map['sha256'] as String,
  byteCount: processingInteger(map['byteCount'], 'byteCount'),
  format: map['format'] as String,
  width: processingInteger(map['width'], 'width'),
  height: processingInteger(map['height'], 'height'),
  frameCount: processingInteger(map['frameCount'], 'frameCount'),
  orientation: processingInteger(map['orientation'], 'orientation'),
);

/// References an immutable content version, never an output or a live setting.
class ProcessingInput {
  const ProcessingInput({
    required this.file,
    required this.assetId,
    required this.version,
    this.selectedFrame,
  });
  final File file;
  final String assetId;
  final ImageVersion version;
  final int? selectedFrame;
  Map<String, Object?> toSnapshot() => {
    'path': file.absolute.path,
    'assetId': assetId,
    'version': versionSnapshot(version),
    'selectedFrame': selectedFrame,
  };
  factory ProcessingInput.fromSnapshot(Map<Object?, Object?> map) =>
      ProcessingInput(
        file: File(map['path'] as String),
        assetId: map['assetId'] as String,
        version: versionFromSnapshot(map['version'] as Map<Object?, Object?>),
        selectedFrame: map['selectedFrame'] == null
            ? null
            : processingInteger(map['selectedFrame'], 'selectedFrame'),
      );
}

class PixelCrop {
  const PixelCrop(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;
  Map<String, Object?> toSnapshot() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
  factory PixelCrop.fromSnapshot(Map<Object?, Object?> map) => PixelCrop(
    processingInteger(map['x'], 'crop.x'),
    processingInteger(map['y'], 'crop.y'),
    processingInteger(map['width'], 'crop.width'),
    processingInteger(map['height'], 'crop.height'),
  );
}

/// Snapshot contains only values, immutable lists and stable content identities.
/// PNG has no lossy quality parameter. WebP quality is used only in sizeFirst.
class ProcessingRequest {
  ProcessingRequest({
    required this.operation,
    required Iterable<ProcessingInput> inputs,
    this.mode = ProcessingMode.fidelity,
    this.outputFormat = ProcessingFormat.png,
    this.longestSide = 1600,
    int? quality,
    this.crop,
    this.layout = StitchLayout.grid,
    this.gap = 0,
    this.backgroundArgb = 0xffffffff,
    this.backgroundConfirmed = false,
    this.explicitStaticConversion = false,
  }) : inputs = List.unmodifiable(inputs),
       quality = outputFormat == ProcessingFormat.png ? quality : quality ?? 85;
  final ProcessingOperation operation;
  final List<ProcessingInput> inputs;
  final ProcessingMode mode;
  final ProcessingFormat outputFormat;
  final int longestSide;
  final int? quality;
  final PixelCrop? crop;
  final StitchLayout layout;
  final int gap;
  final int backgroundArgb;
  final bool backgroundConfirmed;
  final bool explicitStaticConversion;
  Map<String, Object?> toSnapshot() => {
    'operation': operation.name,
    'inputs': inputs.map((input) => input.toSnapshot()).toList(growable: false),
    'mode': mode.name,
    'outputFormat': outputFormat.name,
    'longestSide': longestSide,
    'quality': quality,
    'crop': crop?.toSnapshot(),
    'layout': layout.name,
    'gap': gap,
    'backgroundArgb': backgroundArgb,
    'backgroundConfirmed': backgroundConfirmed,
    'explicitStaticConversion': explicitStaticConversion,
  };
  factory ProcessingRequest.fromSnapshot(Map<Object?, Object?> map) {
    try {
      return ProcessingRequest(
        operation: ProcessingOperation.values.byName(
          map['operation'] as String,
        ),
        inputs: (map['inputs'] as List<Object?>).map(
          (item) => ProcessingInput.fromSnapshot(item as Map<Object?, Object?>),
        ),
        mode: ProcessingMode.values.byName(map['mode'] as String),
        outputFormat: ProcessingFormat.values.byName(
          map['outputFormat'] as String,
        ),
        longestSide: processingInteger(map['longestSide'], 'longestSide'),
        quality: map['quality'] == null
            ? null
            : processingInteger(map['quality'], 'quality'),
        crop: map['crop'] == null
            ? null
            : PixelCrop.fromSnapshot(map['crop'] as Map<Object?, Object?>),
        layout: StitchLayout.values.byName(map['layout'] as String),
        gap: processingInteger(map['gap'], 'gap'),
        backgroundArgb: processingInteger(
          map['backgroundArgb'],
          'backgroundArgb',
        ),
        backgroundConfirmed: map['backgroundConfirmed'] as bool,
        explicitStaticConversion: map['explicitStaticConversion'] as bool,
      );
    } on ProcessingFailure {
      rethrow;
    } catch (_) {
      throw const ProcessingFailure(
        ProcessingFailureKind.invalidParameters,
        '处理快照含未知格式或无效参数。',
      );
    }
  }
}

class PixelSize {
  const PixelSize(this.width, this.height);
  final int width;
  final int height;
}

class ImagePlacement {
  const ImagePlacement(this.x, this.y);
  final int x;
  final int y;
}

class ProcessingPlan {
  ProcessingPlan(
    this.outputSize,
    Iterable<ImagePlacement> placements,
    this.estimatedBytes,
  ) : placements = List.unmodifiable(placements);
  final PixelSize outputSize;
  final List<ImagePlacement> placements;
  final int estimatedBytes;
}

/// A temporary processing result, not a permanent save or an export success.
class ProcessingResult {
  ProcessingResult({
    required this.file,
    required this.version,
    required this.request,
    required this.lossy,
    required this.transparencyRemoved,
    required this.animationRemoved,
    required Iterable<String> warnings,
    this.temporaryDirectory,
  }) : warnings = List.unmodifiable(warnings);
  final File file;
  final ImageVersion version;
  final ProcessingRequest request;
  final bool lossy;
  final bool transparencyRemoved;
  final bool animationRemoved;
  final List<String> warnings;
  final Directory? temporaryDirectory;
  List<ImageVersion> get before =>
      List.unmodifiable(request.inputs.map((input) => input.version));
  ImageVersion get after => version;
  int get beforeByteCount =>
      before.fold(0, (total, version) => total + version.byteCount);
  int get byteSavings => beforeByteCount - version.byteCount;
  bool get isSmaller => byteSavings > 0;
  bool get fidelityPreserved =>
      !lossy &&
      !transparencyRemoved &&
      !animationRemoved &&
      (request.operation != ProcessingOperation.compress ||
          (before.single.width == version.width &&
              before.single.height == version.height));
  Future<void> dispose() async {
    if (await file.exists()) await file.delete();
    final directory = temporaryDirectory;
    if (directory != null && await directory.exists()) {
      // Only remove the engine-owned empty directory; never recursive delete.
      await directory.delete();
    }
  }
}
