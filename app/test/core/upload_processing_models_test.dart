import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/processing/domain/output_models.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';
import 'package:imagehost/features/upload/domain/upload_processing_models.dart';
import 'package:imagehost/features/upload/domain/upload_queue_models.dart';

const _assetA = '00000000-0000-4000-8000-000000000001';
const _assetB = '00000000-0000-4000-8000-000000000002';
const _versionId = '00000000-0000-4000-8000-000000000003';
const _version = ImageVersion(
  id: _versionId,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  byteCount: 500,
  format: 'GIF',
  width: 40,
  height: 30,
  frameCount: 3,
  orientation: 1,
);

ProcessingInput _input(
  String assetId, {
  String path = 'private-source-path',
  ImageVersion version = _version,
  int? selectedFrame = 1,
}) => ProcessingInput(
  file: File(path),
  assetId: assetId,
  version: version,
  selectedFrame: selectedFrame,
);

ProcessingRequest _request({String path = 'private-source-path'}) =>
    ProcessingRequest(
      operation: ProcessingOperation.stitch,
      inputs: [
        _input(_assetA, path: path),
        _input(_assetB, path: path),
      ],
      mode: ProcessingMode.sizeFirst,
      outputFormat: ProcessingFormat.jpeg,
      longestSide: 901,
      quality: 67,
      layout: StitchLayout.vertical,
      gap: 9,
      backgroundArgb: 0xff112233,
      backgroundConfirmed: true,
      explicitStaticConversion: true,
    );

Map<String, Object?> _mutableJson(FrozenProcessingPlan plan) =>
    (jsonDecode(jsonEncode(plan.toJson())) as Map).cast<String, Object?>();

Map<String, Object?> _requestMap(Map<String, Object?> json) =>
    (json['request'] as Map).cast<String, Object?>();

List<Object?> _sources(Map<String, Object?> json) =>
    _requestMap(json)['inputs'] as List<Object?>;

void main() {
  test(
    'UT-033/046 processing recipe matches request defaults without inputs',
    () {
      final recipe = ProcessingRecipe(operation: ProcessingOperation.compress);
      final actual = recipe.bind([_input(_assetA)]);
      final expected = ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: [_input(_assetA)],
      );
      expect(actual.toSnapshot(), expected.toSnapshot());
      expect(recipe.quality, isNull);
      final jpeg = ProcessingRecipe(
        operation: ProcessingOperation.compress,
        outputFormat: ProcessingFormat.jpeg,
      );
      expect(jpeg.quality, 85);
      expect(ProcessingRecipe.fromRequest(_request()).bind([]).quality, 67);
    },
  );

  test('UT-033/046 selection freezes identity order and frame map', () {
    final ids = [_assetB, _assetA];
    final frames = {_assetA: 2, _assetB: 1};
    final selection = UploadProcessingSelection(
      assetIds: ids,
      selectedFrames: frames,
      recipe: ProcessingRecipe(operation: ProcessingOperation.stitch),
      displayName: '拼接',
    );
    ids.clear();
    frames.clear();
    expect(selection.assetIds, [_assetB, _assetA]);
    expect(selection.selectedFrames, {_assetA: 2, _assetB: 1});
    expect(() => selection.assetIds.add(_assetA), throwsUnsupportedError);
    expect(() => selection.selectedFrames[_assetA] = 0, throwsUnsupportedError);
  });

  test(
    'UT-033/046 selection rejects empty duplicate invalid and wrong counts',
    () {
      for (final ids in <List<String>>[
        [],
        [_assetA, _assetA],
        ['private-source-path'],
        [_assetA, _assetB],
      ]) {
        expect(
          () => UploadProcessingSelection(
            assetIds: ids,
            recipe: ProcessingRecipe(operation: ProcessingOperation.compress),
          ),
          throwsA(isA<UploadQueueFailure>()),
        );
      }
      expect(
        () => UploadProcessingSelection(
          assetIds: [_assetA],
          recipe: ProcessingRecipe(operation: ProcessingOperation.stitch),
        ),
        throwsA(isA<UploadQueueFailure>()),
      );
      for (final frames in [
        {_assetB: 0},
        {_assetA: -1},
      ]) {
        expect(
          () => UploadProcessingSelection(
            assetIds: [_assetA],
            selectedFrames: frames,
            recipe: ProcessingRecipe(operation: ProcessingOperation.crop),
          ),
          throwsA(isA<UploadQueueFailure>()),
        );
      }
    },
  );

  test(
    'UT-033/046 canonical excludes runtime paths and matches legacy policy',
    () {
      final request = _request();
      final plan = FrozenProcessingPlan.capture(request);
      Object? legacyCanonical(Object? value) {
        if (value is Map) {
          final keys =
              value.keys.cast<String>().where((key) => key != 'path').toList()
                ..sort();
          return {for (final key in keys) key: legacyCanonical(value[key])};
        }
        if (value is List) return value.map(legacyCanonical).toList();
        return value;
      }

      final canonical = jsonEncode(legacyCanonical(request.toSnapshot()));
      expect(plan.canonical, canonical);
      expect(plan.canonical, isNot(contains('private-source-path')));
      expect(plan.canonical, isNot(contains('"path"')));
      expect(
        plan.policyKey,
        'processed-confirmed-v1:${sha256.convert(utf8.encode(canonical))}',
      );
      expect(
        FrozenProcessingPlan.capture(_request(path: 'other')).policyKey,
        plan.policyKey,
      );
      final decoded = FrozenProcessingPlan.fromJson(_mutableJson(plan));
      expect(decoded.canonical, plan.canonical);
      expect(decoded.versions, [_version, _version]);
      expect(decoded.assetIds, [_assetA, _assetB]);
    },
  );

  test('UT-033/046 frozen plan and returned JSON are deeply immutable', () {
    final plan = FrozenProcessingPlan.capture(_request());
    final json = _mutableJson(plan);
    final restored = FrozenProcessingPlan.fromJson(json);
    _requestMap(json)['quality'] = 2;
    _sources(json).clear();
    expect(restored.canonical, plan.canonical);
    final exported = restored.toJson();
    final request = exported['request'] as Map<String, Object?>;
    final sources = request['inputs'] as List<Object?>;
    final source = sources.first as Map<String, Object?>;
    final version = source['version'] as Map<String, Object?>;
    expect(() => exported['formatVersion'] = 2, throwsUnsupportedError);
    expect(() => request['quality'] = 2, throwsUnsupportedError);
    expect(() => sources.clear(), throwsUnsupportedError);
    expect(() => source['assetId'] = _assetB, throwsUnsupportedError);
    expect(() => version['width'] = 2, throwsUnsupportedError);
    expect(() => restored.assetIds.clear(), throwsUnsupportedError);
    expect(() => restored.versions.clear(), throwsUnsupportedError);
  });

  test('UT-033/046 batch sharing ignores source asset alias but retains frames versions and pixel parameters', () {
    FrozenProcessingPlan plan(
      String assetId, {
      ImageVersion version = _version,
      int selectedFrame = 1,
      int longestSide = 901,
      int quality = 67,
    }) => FrozenProcessingPlan.capture(
      ProcessingRequest(
        operation: ProcessingOperation.compress,
        inputs: [
          _input(assetId, version: version, selectedFrame: selectedFrame),
        ],
        mode: ProcessingMode.sizeFirst,
        outputFormat: ProcessingFormat.jpeg,
        longestSide: longestSide,
        quality: quality,
        explicitStaticConversion: true,
      ),
    );

    final original = plan(_assetA);
    final alias = plan(_assetB);
    expect(alias.batchReuseKey, original.batchReuseKey);
    expect(alias.policyKey, isNot(original.policyKey));
    expect(alias.assetIds, [_assetB]);
    expect(original.assetIds, [_assetA]);
    for (final changed in [
      plan(_assetA, selectedFrame: 2),
      plan(_assetA, longestSide: 902),
      plan(_assetA, quality: 68),
    ]) {
      expect(changed.batchReuseKey, isNot(original.batchReuseKey));
    }
    final versionChanges = <String, Object?>{
      'id': _assetB,
      'sha256':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'byteCount': 501,
      'format': 'PNG',
      'width': 41,
      'height': 31,
      'frameCount': 4,
      'orientation': 2,
    };
    for (final entry in versionChanges.entries) {
      final changed = versionFromSnapshot({
        ...versionSnapshot(_version),
        entry.key: entry.value,
      });
      expect(
        plan(_assetA, version: changed).batchReuseKey,
        isNot(original.batchReuseKey),
        reason: entry.key,
      );
    }
  });

  test('UT-033/046 batch sharing retains ordered version and selected frame tuples', () {
    final other = versionFromSnapshot({
      ...versionSnapshot(_version),
      'id': _assetB,
      'sha256':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    });
    final recipe = ProcessingRecipe.fromRequest(_request());
    final inputs = [
      _input(_assetA),
      _input(_assetB, version: other, selectedFrame: 2),
    ];
    final forward = FrozenProcessingPlan.capture(recipe.bind(inputs));
    final reversed = FrozenProcessingPlan.capture(recipe.bind(inputs.reversed));
    final framesChanged = FrozenProcessingPlan.capture(
      recipe.bind([
        _input(_assetA, selectedFrame: 2),
        _input(_assetB, version: other),
      ]),
    );
    expect(reversed.batchReuseKey, isNot(forward.batchReuseKey));
    expect(framesChanged.batchReuseKey, isNot(forward.batchReuseKey));
  });

  test('UT-033/046 bind uses actual paths and frozen frames and parameters', () {
    final plan = FrozenProcessingPlan.capture(_request());
    final actual = [
      _input(_assetA, path: 'current-a', selectedFrame: 2),
      _input(_assetB, path: 'current-b', selectedFrame: 0),
    ];
    final bound = plan.bind(actual);
    expect(bound.inputs.map((input) => input.file.path), [
      'current-a',
      'current-b',
    ]);
    expect(bound.inputs.map((input) => input.selectedFrame), [1, 1]);
    expect(bound.quality, 67);
    expect(bound.longestSide, 901);
    expect(bound.mode, ProcessingMode.sizeFirst);
    expect(bound.layout, StitchLayout.vertical);
    expect(bound.gap, 9);
    expect(bound.backgroundArgb, 0xff112233);
    expect(bound.backgroundConfirmed, isTrue);
    expect(bound.explicitStaticConversion, isTrue);
    // A later settings-derived recipe cannot modify an existing frozen intent.
    final later = ProcessingRecipe(
      operation: ProcessingOperation.compress,
      outputFormat: ProcessingFormat.jpeg,
      quality: 20,
      longestSide: 100,
    );
    expect(later.quality, 20);
    expect(plan.bind(actual).quality, 67);
    expect(plan.bind(actual).longestSide, 901);
  });

  test(
    'UT-033/046 bind rejects count order and every version field change',
    () {
      final plan = FrozenProcessingPlan.capture(_request());
      for (final actual in <List<ProcessingInput>>[
        [],
        [_input(_assetA)],
        [_input(_assetB), _input(_assetA)],
      ]) {
        expect(() => plan.bind(actual), throwsA(isA<UploadQueueFailure>()));
      }
      final changes = <String, Object?>{
        'id': _assetB,
        'sha256':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'byteCount': 501,
        'format': 'PNG',
        'width': 41,
        'height': 31,
        'frameCount': 4,
        'orientation': 2,
      };
      for (final entry in changes.entries) {
        final changed = versionFromSnapshot({
          ...versionSnapshot(_version),
          entry.key: entry.value,
        });
        expect(
          () => plan.bind([_input(_assetA, version: changed), _input(_assetB)]),
          throwsA(isA<UploadQueueFailure>()),
          reason: entry.key,
        );
      }
    },
  );

  test(
    'UT-033/046 malformed plans reject unknown fields and invalid types safely',
    () {
      final plan = FrozenProcessingPlan.capture(_request());
      final mutations = <void Function(Map<String, Object?>)>[
        (json) => json['formatVersion'] = 2,
        (json) => json['extra'] = 'secret-error-value',
        (json) => json.remove('request'),
        (json) => _requestMap(json)['path'] = 'secret-error-value',
        (json) => _requestMap(json)['operation'] = 'secret-error-value',
        (json) => _requestMap(json)['quality'] = 1.5,
        (json) => _requestMap(json)['quality'] = null,
        (json) => _requestMap(json)['backgroundConfirmed'] = 1,
        (json) => (_sources(json).first as Map)['path'] = 'secret-error-value',
        (json) => (_sources(json).first as Map)['selectedFrame'] = -1,
        (json) =>
            (_sources(json).first as Map)['assetId'] = 'secret-error-value',
        (json) =>
            ((_sources(json).first as Map)['version'] as Map)['width'] = 1.5,
        (json) => ((_sources(json).first as Map)['version'] as Map)['path'] =
            'secret-error-value',
        (json) => ((_sources(json).first as Map)['version'] as Map).remove(
          'orientation',
        ),
        (json) => _requestMap(json)['crop'] = {
          'x': 0,
          'y': 0,
          'width': 10,
          'height': 10,
          'path': 'secret-error-value',
        },
      ];
      for (final mutate in mutations) {
        final json = _mutableJson(plan);
        mutate(json);
        expect(
          () => FrozenProcessingPlan.fromJson(json),
          throwsA(
            isA<UploadQueueFailure>().having(
              (failure) => failure.message,
              'fixed safe message',
              '上传处理计划含未知格式或无效参数。',
            ),
          ),
        );
      }
    },
  );

  test('UT-033/046 crop parameters and output retention remain frozen', () {
    final plan = FrozenProcessingPlan.capture(
      ProcessingRequest(
        operation: ProcessingOperation.crop,
        inputs: [_input(_assetA)],
        crop: const PixelCrop(1, 2, 20, 10),
        explicitStaticConversion: true,
      ),
    );
    final bound = plan.bind([_input(_assetA)]);
    expect(bound.crop!.toSnapshot(), {
      'x': 1,
      'y': 2,
      'width': 20,
      'height': 10,
    });
    final job = UploadProcessingJob(
      id: _assetA,
      batchId: _assetB,
      plan: plan,
      state: UploadProcessingState.queued,
      createdAt: DateTime.utc(2026, 10, 7),
      updatedAt: DateTime.utc(2026, 10, 7),
      retention: OutputRetention.hour,
    );
    expect(job.retention.duration, const Duration(hours: 1));
    expect(job.outputId, isNull);
  });

  test(
    'UT-046 pending publication marks frozen source until confirmed output',
    () {
      UploadPublication publication(UploadInputKind kind, {String? jobId}) =>
          UploadPublication(
            id: _assetA,
            batchId: _assetB,
            position: 0,
            input: FrozenUploadInput(
              kind: kind,
              referenceId: _assetA,
              displayName: '来源',
              version: _version,
              policyKey: 'frozen',
            ),
            target: const TargetSnapshot(
              _assetB,
              ImageHostService.catbox,
              '目标',
              true,
            ),
            state: PublishState.queued,
            attemptCount: 0,
            generation: 0,
            accumulatedRunning: Duration.zero,
            createdAt: DateTime.utc(2026, 10, 7),
            updatedAt: DateTime.utc(2026, 10, 7),
            processingJobId: jobId,
          );
      expect(publication(UploadInputKind.original).processingPending, isFalse);
      expect(
        publication(UploadInputKind.original, jobId: _assetA).processingPending,
        isTrue,
      );
      expect(
        publication(
          UploadInputKind.processed,
          jobId: _assetA,
        ).processingPending,
        isFalse,
      );
    },
  );
}
