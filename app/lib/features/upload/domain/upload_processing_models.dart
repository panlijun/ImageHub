import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../gallery/domain/library_models.dart';
import '../../processing/domain/output_models.dart';
import '../../processing/domain/processing_models.dart';
import 'upload_queue_models.dart';

enum UploadProcessingState {
  queued,
  running,
  ready,
  failed,
  cancelled,
  waiting,
}

/// Pixel parameters only. Defaults are captured here, never read from settings.
final class ProcessingRecipe {
  ProcessingRecipe({
    required this.operation,
    this.mode = ProcessingMode.fidelity,
    this.outputFormat = ProcessingFormat.png,
    this.longestSide = 1600,
    int? quality,
    PixelCrop? crop,
    this.layout = StitchLayout.grid,
    this.gap = 0,
    this.backgroundArgb = 0xffffffff,
    this.backgroundConfirmed = false,
    this.explicitStaticConversion = false,
  }) : quality = outputFormat == ProcessingFormat.png ? quality : quality ?? 85,
       crop = crop == null
           ? null
           : PixelCrop(crop.x, crop.y, crop.width, crop.height);

  factory ProcessingRecipe.fromRequest(ProcessingRequest request) =>
      ProcessingRecipe(
        operation: request.operation,
        mode: request.mode,
        outputFormat: request.outputFormat,
        longestSide: request.longestSide,
        quality: request.quality,
        crop: request.crop,
        layout: request.layout,
        gap: request.gap,
        backgroundArgb: request.backgroundArgb,
        backgroundConfirmed: request.backgroundConfirmed,
        explicitStaticConversion: request.explicitStaticConversion,
      );

  final ProcessingOperation operation;
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

  ProcessingRequest bind(Iterable<ProcessingInput> inputs) => ProcessingRequest(
    operation: operation,
    inputs: inputs,
    mode: mode,
    outputFormat: outputFormat,
    longestSide: longestSide,
    quality: quality,
    crop: crop,
    layout: layout,
    gap: gap,
    backgroundArgb: backgroundArgb,
    backgroundConfirmed: backgroundConfirmed,
    explicitStaticConversion: explicitStaticConversion,
  );
}

/// Ordered source identities plus the user's confirmed pixel parameters.
final class UploadProcessingSelection {
  UploadProcessingSelection({
    required Iterable<String> assetIds,
    required this.recipe,
    Map<String, int> selectedFrames = const {},
    this.displayName,
  }) : assetIds = List.unmodifiable(assetIds),
       selectedFrames = Map.unmodifiable(selectedFrames) {
    _validateSources(this.assetIds, recipe.operation);
    for (final entry in this.selectedFrames.entries) {
      if (!this.assetIds.contains(entry.key) || entry.value < 0) _invalidPlan();
    }
  }

  final List<String> assetIds;
  final ProcessingRecipe recipe;
  final Map<String, int> selectedFrames;
  final String? displayName;
}

/// Persisted execution intent. Only runtime binding introduces local paths.
final class FrozenProcessingPlan {
  FrozenProcessingPlan._(
    Map<String, Object?> snapshot,
    ProcessingRequest parsed,
  ) : _snapshot = snapshot,
      canonical = _canonicalJson(snapshot),
      assetIds = List.unmodifiable(parsed.inputs.map((input) => input.assetId)),
      versions = List.unmodifiable(parsed.inputs.map((input) => input.version)),
      _frames = List.unmodifiable(
        parsed.inputs.map((input) => input.selectedFrame),
      ),
      recipe = ProcessingRecipe.fromRequest(parsed);

  factory FrozenProcessingPlan.capture(ProcessingRequest request) {
    final snapshot = request.toSnapshot();
    snapshot['inputs'] = request.inputs
        .map((input) {
          final source = input.toSnapshot()..remove('path');
          return source;
        })
        .toList(growable: false);
    return FrozenProcessingPlan.fromJson({
      'formatVersion': 1,
      'request': snapshot,
    });
  }

  factory FrozenProcessingPlan.fromJson(Map<String, Object?> json) {
    try {
      _exactKeys(json, const {'formatVersion', 'request'});
      if (json['formatVersion'] is! int || json['formatVersion'] != 1) {
        _invalidPlan();
      }
      final snapshot = _stringMap(json['request']);
      _exactKeys(snapshot, _requestKeys);
      final sources = snapshot['inputs'];
      if (sources is! List<Object?>) _invalidPlan();
      final runtimeSources = <Map<String, Object?>>[];
      for (final value in sources) {
        final source = _stringMap(value);
        _exactKeys(source, const {'assetId', 'version', 'selectedFrame'});
        final version = _stringMap(source['version']);
        _exactKeys(version, _versionKeys);
        runtimeSources.add({...source, 'path': File('').path});
      }
      if (snapshot['crop'] != null) {
        _exactKeys(_stringMap(snapshot['crop']), const {
          'x',
          'y',
          'width',
          'height',
        });
      }
      final parsed = ProcessingRequest.fromSnapshot({
        ...snapshot,
        'inputs': runtimeSources,
      });
      _validateSources(
        parsed.inputs.map((input) => input.assetId).toList(growable: false),
        parsed.operation,
      );
      for (final input in parsed.inputs) {
        if (!_uuidPattern.hasMatch(input.version.id) ||
            !_shaPattern.hasMatch(input.version.sha256) ||
            !_formats.contains(input.version.format) ||
            (input.selectedFrame != null && input.selectedFrame! < 0)) {
          _invalidPlan();
        }
      }
      // The shared parser may fill defaults. Persisted intents must already
      // contain the exact frozen values, so normalization is never implicit.
      final normalized = parsed.toSnapshot();
      normalized['inputs'] = parsed.inputs
          .map((input) {
            return input.toSnapshot()..remove('path');
          })
          .toList(growable: false);
      if (_canonicalJson(snapshot) != _canonicalJson(normalized)) {
        _invalidPlan();
      }
      return FrozenProcessingPlan._(_freezeMap(normalized), parsed);
    } catch (_) {
      _invalidPlan();
    }
  }

  final Map<String, Object?> _snapshot;
  final List<int?> _frames;
  final String canonical;
  final List<String> assetIds;
  final List<ImageVersion> versions;
  final ProcessingRecipe recipe;

  String get policyKey =>
      'processed-confirmed-v1:${sha256.convert(utf8.encode(canonical))}';

  /// Local sharing depends on ordered content versions and pixel policy;
  /// aliases of the same version do not require duplicate pixel work.
  String get batchReuseKey {
    final normalized = <String, Object?>{
      ..._snapshot,
      'inputs': [
        for (final value in _snapshot['inputs']! as List)
          Map<String, Object?>.from(value as Map)..remove('assetId'),
      ],
    };
    return _canonicalJson(normalized);
  }

  Map<String, Object?> toJson() =>
      Map.unmodifiable({'formatVersion': 1, 'request': _snapshot});

  ProcessingRequest bind(List<ProcessingInput> actual) {
    if (actual.length != assetIds.length) _changedInputs();
    for (var i = 0; i < actual.length; i++) {
      if (actual[i].assetId != assetIds[i] ||
          actual[i].version != versions[i]) {
        _changedInputs();
      }
    }
    return recipe.bind([
      for (var i = 0; i < actual.length; i++)
        ProcessingInput(
          file: actual[i].file,
          assetId: assetIds[i],
          version: versions[i],
          selectedFrame: _frames[i],
        ),
    ]);
  }
}

final class UploadProcessingJob {
  const UploadProcessingJob({
    required this.id,
    required this.batchId,
    required this.plan,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.retention,
    this.outputId,
    this.message,
  });

  final String id, batchId;
  final FrozenProcessingPlan plan;
  final UploadProcessingState state;
  final DateTime createdAt, updatedAt;
  final OutputRetention retention;
  final String? outputId, message;
}

const _requestKeys = {
  'operation',
  'inputs',
  'mode',
  'outputFormat',
  'longestSide',
  'quality',
  'crop',
  'layout',
  'gap',
  'backgroundArgb',
  'backgroundConfirmed',
  'explicitStaticConversion',
};
const _versionKeys = {
  'id',
  'sha256',
  'byteCount',
  'format',
  'width',
  'height',
  'frameCount',
  'orientation',
};
const _formats = {'PNG', 'JPEG', 'WebP', 'GIF', 'BMP'};
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _shaPattern = RegExp(r'^[0-9a-f]{64}$');

void _validateSources(List<String> ids, ProcessingOperation operation) {
  if (ids.isEmpty ||
      ids.toSet().length != ids.length ||
      ids.any((id) => !_uuidPattern.hasMatch(id)) ||
      (operation == ProcessingOperation.stitch
          ? ids.length < 2
          : ids.length != 1)) {
    _invalidPlan();
  }
}

Map<String, Object?> _stringMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) _invalidPlan();
  return value.cast<String, Object?>();
}

void _exactKeys(Map<String, Object?> map, Set<String> keys) {
  if (map.length != keys.length || !map.keys.every(keys.contains)) {
    _invalidPlan();
  }
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) => Map.unmodifiable(
  {for (final entry in value.entries) entry.key: _freeze(entry.value)},
);

Object? _freeze(Object? value) {
  if (value is Map<String, Object?>) return _freezeMap(value);
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freeze));
  }
  return value;
}

String _canonicalJson(Object? value) {
  Object? sorted(Object? current) {
    if (current is Map<String, Object?>) {
      final keys = current.keys.toList()..sort();
      return {for (final key in keys) key: sorted(current[key])};
    }
    if (current is List<Object?>) {
      return current.map(sorted).toList(growable: false);
    }
    return current;
  }

  return jsonEncode(sorted(value));
}

Never _invalidPlan() => throw const UploadQueueFailure('上传处理计划含未知格式或无效参数。');
Never _changedInputs() => throw const UploadQueueFailure('上传处理来源已变化，请重新确认。');
