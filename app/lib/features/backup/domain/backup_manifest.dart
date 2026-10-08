import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/secret_redactor.dart';
import '../../../core/text_policy.dart';
import '../../accounts/domain/account_models.dart';
import '../../gallery/domain/library_models.dart';
import '../../gallery/domain/version_description_policy.dart';
import '../../processing/domain/processing_models.dart';
import '../../upload/domain/link_format.dart';
import '../../upload/domain/queue_policy.dart';
import '../../upload/domain/upload_queue_models.dart';
import 'backup_settings.dart';

enum BackupMode { metadata, full }

enum BackupFailureKind { invalidManifest, unsupportedFormat, resourceBudget }

/// Fixed, safe failures never stringify untrusted input or exceptions.
final class BackupFailure implements Exception {
  const BackupFailure(this.kind);
  final BackupFailureKind kind;
  String get message => switch (kind) {
    BackupFailureKind.invalidManifest => '备份清单无效或关联不完整。',
    BackupFailureKind.unsupportedFormat => '备份格式、版本或文本规则不受支持。',
    BackupFailureKind.resourceBudget => '备份清单超出允许的资源预算。',
  };
  @override
  String toString() => message;
}

/// Candidate defensive budgets; these are not measured device capabilities.
final class BackupBudgets {
  const BackupBudgets({
    this.maxManifestBytes = 16 * 1024 * 1024,
    this.maxRecords = 100000,
    this.maximumTotalImageBytes = 32 * 1024 * 1024 * 1024,
  });
  final int maxManifestBytes, maxRecords, maximumTotalImageBytes;
}

final class BackupName {
  const BackupName({required this.id, required this.name});
  final String id, name;
}

final class BackupAsset {
  BackupAsset({
    required this.id,
    required this.versionId,
    required this.displayName,
    required this.sourceType,
    required this.importedUtc,
    required this.updatedUtc,
    required this.favorite,
    required Iterable<String> tagIds,
    required this.recycled,
    this.categoryId,
    this.recycledUtc,
  }) : tagIds = List.unmodifiable(tagIds);
  final String id, versionId, displayName, sourceType;
  final int importedUtc, updatedUtc;
  final bool favorite, recycled;
  final String? categoryId;
  final int? recycledUtc;
  final List<String> tagIds;
}

/// Configuration identity only. Restoring it cannot configure a credential.
final class BackupAccount {
  const BackupAccount({
    required this.id,
    required this.service,
    required this.alias,
    required this.anonymous,
  });
  final String id, alias;
  final ImageHostService service;
  final bool anonymous;
}

final class BackupProcessingInput {
  const BackupProcessingInput({
    required this.assetId,
    required this.version,
    this.selectedFrame,
  });
  final String assetId;
  final ImageVersion version;
  final int? selectedFrame;
}

/// Audit values only: no File, resource path or executable reconstruction.
final class BackupProcessingSnapshot {
  BackupProcessingSnapshot({
    required this.operation,
    required Iterable<BackupProcessingInput> inputs,
    required this.mode,
    required this.outputFormat,
    required this.longestSide,
    required this.quality,
    required this.crop,
    required this.layout,
    required this.gap,
    required this.backgroundArgb,
    required this.backgroundConfirmed,
    required this.explicitStaticConversion,
  }) : inputs = List.unmodifiable(inputs);
  final ProcessingOperation operation;
  final List<BackupProcessingInput> inputs;
  final ProcessingMode mode;
  final ProcessingFormat outputFormat;
  final int longestSide;
  final int? quality;
  final PixelCrop? crop;
  final StitchLayout layout;
  final int gap, backgroundArgb;
  final bool backgroundConfirmed, explicitStaticConversion;

  factory BackupProcessingSnapshot.fromJson(Object? value) => _safe(() {
    _checkJsonBudget(value, const BackupBudgets());
    final snapshot = _readProcessing(value);
    _validateProcessing(snapshot);
    return snapshot;
  });

  Map<String, Object?> toJson() => _safe(() {
    _validateProcessing(this);
    return _processingJson(this);
  });

  factory BackupProcessingSnapshot.fromRequest(ProcessingRequest request) =>
      BackupProcessingSnapshot(
        operation: request.operation,
        inputs: request.inputs.map(
          (input) => BackupProcessingInput(
            assetId: input.assetId,
            version: input.version,
            selectedFrame: input.selectedFrame,
          ),
        ),
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
}

final class BackupOrigin {
  const BackupOrigin({
    required this.outputId,
    required this.versionId,
    required this.createdUtc,
    required this.processing,
  });
  final String outputId, versionId;
  final int createdUtc;
  final BackupProcessingSnapshot processing;
}

final class BackupRemoteResult {
  const BackupRemoteResult({
    required this.id,
    required this.attemptId,
    required this.input,
    required this.target,
    required this.remoteId,
    required this.directUrl,
    required this.confirmedUtc,
    required this.late,
    this.viewerUrl,
  });
  final String id, attemptId, remoteId;
  final FrozenUploadInput input;
  final TargetSnapshot target;
  final Uri directUrl;
  final Uri? viewerUrl;
  final int confirmedUtc;
  final bool late;

  factory BackupRemoteResult.fromResult(RemoteUploadResult result) =>
      BackupRemoteResult(
        id: result.id,
        attemptId: result.attemptId,
        input: result.input,
        target: result.target,
        remoteId: result.remoteId,
        directUrl: result.directUrl,
        viewerUrl: result.viewerUrl,
        confirmedUtc: result.confirmedAt.millisecondsSinceEpoch,
        late: result.late,
      );
}

final class BackupAttemptHistory {
  const BackupAttemptHistory({
    required this.id,
    required this.generation,
    required this.startedUtc,
    required this.endedUtc,
    this.outcome,
  });
  final String id;
  final int generation, startedUtc, endedUtc;
  final String? outcome;
}

/// Historical audit only. There are deliberately no scheduling methods.
final class BackupTaskHistory {
  BackupTaskHistory({
    required this.id,
    required this.batchId,
    required this.position,
    required this.input,
    required this.target,
    required this.state,
    required Iterable<BackupAttemptHistory> attempts,
    required this.createdUtc,
    required this.updatedUtc,
    this.message,
  }) : attempts = List.unmodifiable(attempts);
  final String id, batchId;
  final int position, createdUtc, updatedUtc;
  final FrozenUploadInput input;
  final TargetSnapshot target;
  final PublishState state;
  final List<BackupAttemptHistory> attempts;
  final String? message;
}

final class BackupImageEntry {
  const BackupImageEntry({
    required this.versionId,
    required this.name,
    required this.byteCount,
    required this.sha256,
  });
  final String versionId, name, sha256;
  final int byteCount;
}

/// Versioned, platform-independent whitelist. This describes an intended
/// package, not ZIP bytes, file availability, a database snapshot or restore.
final class BackupManifest {
  BackupManifest({
    required this.packageId,
    required this.createdUtc,
    required this.mode,
    required Iterable<ImageVersion> versions,
    required Iterable<BackupAsset> assets,
    required Iterable<BackupName> categories,
    required Iterable<BackupName> tags,
    required Iterable<BackupOrigin> origins,
    required Iterable<BackupAccount> accounts,
    required Iterable<BackupRemoteResult> results,
    required Iterable<BackupTaskHistory> history,
    required Iterable<BackupImageEntry> images,
    this.settings,
  }) : versions = List.unmodifiable(versions),
       assets = List.unmodifiable(assets),
       categories = List.unmodifiable(categories),
       tags = List.unmodifiable(tags),
       origins = List.unmodifiable(origins),
       accounts = List.unmodifiable(accounts),
       results = List.unmodifiable(results),
       history = List.unmodifiable(history),
       images = List.unmodifiable(images) {
    _validate();
  }
  static const format = 'imagehost-backup';
  static const formatVersion = 2;
  static const textPolicy = 'unicode-17-nfc-full-cf-v1';
  static const scope = 'all-permanent';
  final String packageId;
  final int createdUtc;
  final BackupMode mode;
  final List<ImageVersion> versions;
  final List<BackupAsset> assets;
  final List<BackupName> categories, tags;
  final List<BackupOrigin> origins;
  final List<BackupAccount> accounts;
  final List<BackupRemoteResult> results;
  final List<BackupTaskHistory> history;
  final List<BackupImageEntry> images;
  final BackupDeviceSettings? settings;

  /// The production snapshot layer must register actual credentials and
  /// management secrets before calling this boundary. A DTO cannot infer them.
  Map<String, Object?> toJson({
    required SecretRedactor redactor,
    BackupBudgets budgets = const BackupBudgets(),
  }) {
    _validate();
    final json = _json(redactor);
    // Redaction must not silently truncate names, merge identities, or produce
    // an invalid package. Validate the redacted view before emitting anything.
    BackupManifest.fromJson(json, budgets: budgets);
    _ensureSafeEncodedValues(json, redactor);
    return json;
  }

  Uint8List encode({
    required SecretRedactor redactor,
    BackupBudgets budgets = const BackupBudgets(),
  }) => Uint8List.fromList(
    utf8.encode(jsonEncode(toJson(redactor: redactor, budgets: budgets))),
  );

  factory BackupManifest.decode(
    List<int> bytes, {
    BackupBudgets budgets = const BackupBudgets(),
  }) => _safe(() {
    _budgetValid(budgets);
    if (bytes.length > budgets.maxManifestBytes) {
      _budgetFail();
    }
    return BackupManifest.fromJson(
      jsonDecode(utf8.decode(bytes)),
      budgets: budgets,
    );
  });

  factory BackupManifest.fromJson(
    Object? value, {
    BackupBudgets budgets = const BackupBudgets(),
  }) => _safe(() {
    _checkJsonBudget(value, budgets);
    if (value is! Map) _invalid();
    final version = value['formatVersion'];
    if (version is! int || (version != 1 && version != formatVersion)) {
      throw const BackupFailure(BackupFailureKind.unsupportedFormat);
    }
    if (version == formatVersion && !value.containsKey('settings')) _invalid();
    final map = _map(value, {
      'format',
      'formatVersion',
      'textPolicy',
      'packageId',
      'createdUtc',
      'mode',
      'scope',
      'versions',
      'assets',
      'categories',
      'tags',
      'origins',
      'accounts',
      'results',
      'history',
      'images',
      if (version == formatVersion) 'settings',
    });
    if (map['format'] != format ||
        map['textPolicy'] != textPolicy ||
        map['scope'] != scope ||
        !BackupMode.values.any((mode) => mode.name == map['mode'])) {
      throw const BackupFailure(BackupFailureKind.unsupportedFormat);
    }
    final manifest = BackupManifest(
      packageId: _string(map['packageId']),
      createdUtc: _integer(map['createdUtc']),
      mode: _enum(BackupMode.values, map['mode']),
      versions: _list(map['versions']).map(_readVersion),
      assets: _list(map['assets']).map(_readAsset),
      categories: _list(map['categories']).map(_readName),
      tags: _list(map['tags']).map(_readName),
      origins: _list(map['origins']).map(_readOrigin),
      accounts: _list(map['accounts']).map(_readAccount),
      results: _list(map['results']).map(_readResult),
      history: _list(map['history']).map(_readHistory),
      images: _list(map['images']).map(_readImage),
      settings: version == 1 || map['settings'] == null
          ? null
          : BackupDeviceSettings.fromJson(map['settings']),
    );
    var bytes = 0;
    for (final image in manifest.images) {
      if (image.byteCount > budgets.maximumTotalImageBytes - bytes) {
        _budgetFail();
      }
      bytes += image.byteCount;
    }
    return manifest;
  });

  void _validate() => _safe(() {
    _uuid(packageId);
    _utc(createdUtc);
    if (settings != null) BackupDeviceSettings.fromJson(settings!.toJson());
    final permanent = <String, ImageVersion>{};
    final descriptions = <String, ImageVersion>{};
    final content = <String>{};
    void permanentVersion(ImageVersion item) {
      _validateVersion(item);
      final prior = descriptions[item.id];
      if (prior != null && prior != item) {
        _invalid();
      }
      descriptions[item.id] = item;
    }

    for (final item in versions) {
      permanentVersion(item);
      if (permanent.containsKey(item.id) ||
          !content.add('${item.sha256}:${item.byteCount}')) {
        _invalid();
      }
      permanent[item.id] = item;
    }
    void auditVersion(ImageVersion item) {
      _validateVersion(item);
      final fixed = permanent[item.id];
      if (fixed != null) {
        if (!VersionDescriptionPolicy.same(item, fixed) &&
            !VersionDescriptionPolicy.isPngOrientationCorrection(item, fixed)) {
          _invalid();
        }
        return;
      }
      final prior = descriptions[item.id];
      if (prior != null &&
          !VersionDescriptionPolicy.auditCompatible(prior, item)) {
        _invalid();
      }
      descriptions[item.id] = prior == null
          ? item
          : VersionDescriptionPolicy.preferredAudit(prior, item);
    }

    Set<String> names(List<BackupName> items) {
      final ids = <String>{}, keys = <String>{};
      for (final item in items) {
        _uuid(item.id);
        if (!ids.add(item.id) ||
            TextPolicy.normalizeName(item.name) != item.name ||
            !keys.add(TextPolicy.key(item.name))) {
          _invalid();
        }
      }
      return ids;
    }

    final categoryIds = names(categories), tagIds = names(tags);
    final assetIds = <String>{};
    for (final item in assets) {
      _uuid(item.id);
      _uuid(item.versionId);
      _utc(item.importedUtc);
      _utc(item.updatedUtc);
      if (!assetIds.add(item.id) ||
          !permanent.containsKey(item.versionId) ||
          item.updatedUtc < item.importedUtc ||
          item.categoryId != null && !categoryIds.contains(item.categoryId) ||
          item.tagIds.length > TextPolicy.maxTags ||
          item.tagIds.toSet().length != item.tagIds.length ||
          item.tagIds.any((id) => !tagIds.contains(id)) ||
          item.recycled != (item.recycledUtc != null)) {
        _invalid();
      }
      if (item.recycledUtc != null) {
        _utc(item.recycledUtc!);
      }
    }
    final originIds = <String>{};
    for (final item in origins) {
      _uuid(item.outputId);
      _uuid(item.versionId);
      _utc(item.createdUtc);
      if (!originIds.add(item.outputId) ||
          !permanent.containsKey(item.versionId)) {
        _invalid();
      }
      final processing = item.processing;
      _validateProcessing(processing);
      for (final input in processing.inputs) {
        _uuid(input.assetId);
        auditVersion(input.version);
        if (input.selectedFrame != null) {
          _range(input.selectedFrame!, 0, input.version.frameCount - 1);
        }
      }
    }
    final accountIds = <String>{};
    for (final item in accounts) {
      _uuid(item.id);
      if (!accountIds.add(item.id)) {
        _invalid();
      }
    }
    void auditInput(FrozenUploadInput input) {
      _uuid(input.referenceId);
      auditVersion(input.version);
      if (input.policyKey.isEmpty) {
        _invalid();
      }
    }

    void auditTarget(TargetSnapshot target) => _uuid(target.id);
    final resultIds = <String>{}, resultAttempts = <String>{};
    for (final item in results) {
      _uuid(item.id);
      _uuid(item.attemptId);
      _utc(item.confirmedUtc);
      if (!resultIds.add(item.id) || !resultAttempts.add(item.attemptId)) {
        _invalid();
      }
      auditInput(item.input);
      auditTarget(item.target);
      if (item.remoteId.isEmpty) {
        _invalid();
      }
      _ordinary(item.directUrl.toString());
      if (item.viewerUrl != null) {
        _ordinary(item.viewerUrl.toString());
      }
    }
    final taskIds = <String>{}, attemptIds = <String>{}, positions = <String>{};
    for (final item in history) {
      _uuid(item.id);
      _uuid(item.batchId);
      _nonnegative(item.position);
      _utc(item.createdUtc);
      _utc(item.updatedUtc);
      if (!item.state.terminal ||
          !taskIds.add(item.id) ||
          !positions.add('${item.batchId}:${item.position}') ||
          item.updatedUtc < item.createdUtc) {
        _invalid();
      }
      auditInput(item.input);
      auditTarget(item.target);
      final generations = <int>{};
      for (final attempt in item.attempts) {
        _uuid(attempt.id);
        _positive(attempt.generation);
        _utc(attempt.startedUtc);
        _utc(attempt.endedUtc);
        if (!attemptIds.add(attempt.id) ||
            !generations.add(attempt.generation) ||
            attempt.endedUtc < attempt.startedUtc) {
          _invalid();
        }
      }
    }
    final imageIds = <String>{};
    for (final item in images) {
      final descriptor = permanent[item.versionId];
      if (descriptor == null ||
          !imageIds.add(item.versionId) ||
          item.name !=
              'images/${descriptor.id}.${descriptor.format.toLowerCase()}' ||
          item.byteCount != descriptor.byteCount ||
          item.sha256 != descriptor.sha256) {
        _invalid();
      }
    }
    if (mode == BackupMode.metadata && images.isNotEmpty ||
        mode == BackupMode.full && imageIds.length != permanent.length) {
      _invalid();
    }
  });

  Map<String, Object?> _json(SecretRedactor redactor) {
    String text(String value) => redactor.redactText(value);
    String stable(String value) {
      if (text(value) != value) {
        _invalid();
      }
      return value;
    }

    Map<String, Object?> input(FrozenUploadInput value) => {
      'kind': value.kind.name,
      'referenceId': value.referenceId,
      'displayName': text(value.displayName),
      'version': _versionJson(value.version),
      'policyKey': stable(value.policyKey),
      'processingSummary': value.processingSummary == null
          ? null
          : text(value.processingSummary!),
    };
    Map<String, Object?> target(TargetSnapshot value) => {
      'id': value.id,
      'service': value.service.name,
      'alias': text(value.alias),
      'anonymous': value.anonymous,
    };
    return {
      'format': format,
      'formatVersion': formatVersion,
      'textPolicy': textPolicy,
      'packageId': packageId,
      'createdUtc': createdUtc,
      'mode': mode.name,
      'scope': scope,
      'settings': settings?.toJson(),
      'versions': versions.map(_versionJson).toList(),
      'assets': assets
          .map(
            (a) => <String, Object?>{
              'id': a.id,
              'versionId': a.versionId,
              'displayName': text(a.displayName),
              'sourceType': text(a.sourceType),
              'importedUtc': a.importedUtc,
              'updatedUtc': a.updatedUtc,
              'favorite': a.favorite,
              'categoryId': a.categoryId,
              'tagIds': a.tagIds,
              'recycled': a.recycled,
              'recycledUtc': a.recycledUtc,
            },
          )
          .toList(),
      'categories': categories
          .map((n) => {'id': n.id, 'name': text(n.name)})
          .toList(),
      'tags': tags.map((n) => {'id': n.id, 'name': text(n.name)}).toList(),
      'origins': origins
          .map(
            (o) => <String, Object?>{
              'outputId': o.outputId,
              'versionId': o.versionId,
              'createdUtc': o.createdUtc,
              'processing': _processingJson(o.processing),
            },
          )
          .toList(),
      'accounts': accounts
          .map(
            (a) => <String, Object?>{
              'id': a.id,
              'service': a.service.name,
              'alias': text(a.alias),
              'anonymous': a.anonymous,
            },
          )
          .toList(),
      'results': results
          .map(
            (r) => <String, Object?>{
              'id': r.id,
              'attemptId': r.attemptId,
              'input': input(r.input),
              'target': target(r.target),
              'remoteId': text(r.remoteId),
              'directUrl': stable(r.directUrl.toString()),
              'viewerUrl': r.viewerUrl == null
                  ? null
                  : stable(r.viewerUrl.toString()),
              'confirmedUtc': r.confirmedUtc,
              'late': r.late,
            },
          )
          .toList(),
      'history': history
          .map(
            (h) => <String, Object?>{
              'id': h.id,
              'batchId': h.batchId,
              'position': h.position,
              'input': input(h.input),
              'target': target(h.target),
              'state': h.state.name,
              'createdUtc': h.createdUtc,
              'updatedUtc': h.updatedUtc,
              'message': h.message == null ? null : text(h.message!),
              'attempts': h.attempts
                  .map(
                    (a) => <String, Object?>{
                      'id': a.id,
                      'generation': a.generation,
                      'startedUtc': a.startedUtc,
                      'endedUtc': a.endedUtc,
                      'outcome': a.outcome == null ? null : text(a.outcome!),
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'images': images
          .map(
            (i) => <String, Object?>{
              'versionId': i.versionId,
              'name': i.name,
              'byteCount': i.byteCount,
              'sha256': i.sha256,
            },
          )
          .toList(),
    };
  }
}

/// Check the already validated whitelist without redacting the tree again.
/// Structural values cannot be rewritten: if a registered secret happens to
/// match an identity, digest, enum or parameter, the package must be refused.
/// This deliberately has no SecretRedactor.redact node limit or truncation.
void _ensureSafeEncodedValues(Object? value, SecretRedactor redactor) {
  if (value == null) {
    return;
  }
  String? representation;
  if (value is String) {
    representation = value;
  } else if (value is int || value is bool) {
    // Only built-in JSON primitives use their known safe representation.
    representation = value.toString();
  } else if (value is Map<String, Object?>) {
    for (final item in value.values) {
      _ensureSafeEncodedValues(item, redactor);
    }
    return;
  } else if (value is List<Object?>) {
    for (final item in value) {
      _ensureSafeEncodedValues(item, redactor);
    }
    return;
  } else {
    _invalid();
  }
  if (redactor.redactText(representation) != representation) {
    _invalid();
  }
}

Never _invalid() =>
    throw const BackupFailure(BackupFailureKind.invalidManifest);
Never _budgetFail() =>
    throw const BackupFailure(BackupFailureKind.resourceBudget);
T _safe<T>(T Function() callback) {
  try {
    return callback();
  } on BackupFailure {
    rethrow;
  } catch (_) {
    _invalid();
  }
}

const _maxInteger = 9007199254740991;
int _integer(Object? value) {
  if (value is! int || value < -_maxInteger || value > _maxInteger) {
    _invalid();
  }
  return value;
}

void _range(int value, int min, int max) {
  _integer(value);
  if (value < min || value > max) {
    _invalid();
  }
}

void _positive(int value) => _range(value, 1, _maxInteger);
void _nonnegative(int value) => _range(value, 0, _maxInteger);
void _utc(int value) => _range(value, -8640000000000000, 8640000000000000);
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
void _uuid(String value) {
  if (!_uuidPattern.hasMatch(value)) {
    _invalid();
  }
}

void _validateVersion(ImageVersion value) {
  _uuid(value.id);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value.sha256) ||
      !const {'PNG', 'JPEG', 'WebP', 'GIF', 'BMP'}.contains(value.format)) {
    _invalid();
  }
  _positive(value.byteCount);
  _positive(value.width);
  _positive(value.height);
  _positive(value.frameCount);
  _range(value.orientation, 1, 8);
}

void _validateProcessing(BackupProcessingSnapshot processing) {
  _positive(processing.longestSide);
  _nonnegative(processing.gap);
  _range(processing.backgroundArgb, 0, 0xffffffff);
  if (processing.quality != null) {
    _range(processing.quality!, 1, 100);
  }
  if (processing.inputs.isEmpty) {
    _invalid();
  }
  final versions = <String, ImageVersion>{};
  for (final input in processing.inputs) {
    _uuid(input.assetId);
    _validateVersion(input.version);
    if (versions.containsKey(input.version.id) &&
        versions[input.version.id] != input.version) {
      _invalid();
    }
    versions[input.version.id] = input.version;
    if (input.selectedFrame != null) {
      _range(input.selectedFrame!, 0, input.version.frameCount - 1);
    }
  }
  final crop = processing.crop;
  if (crop != null) {
    _nonnegative(crop.x);
    _nonnegative(crop.y);
    _positive(crop.width);
    _positive(crop.height);
  }
}

String _string(Object? value) {
  if (value is! String) {
    _invalid();
  }
  return value;
}

String? _nullableString(Object? value) => value == null ? null : _string(value);
int? _nullableInteger(Object? value) => value == null ? null : _integer(value);
bool _boolean(Object? value) {
  if (value is! bool) {
    _invalid();
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) {
    _invalid();
  }
  return value;
}

Map<String, Object?> _map(Object? value, Set<String> fields) {
  if (value is! Map) {
    _invalid();
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String || !fields.contains(entry.key)) {
      _invalid();
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

T _enum<T extends Enum>(List<T> values, Object? value) {
  for (final option in values) {
    if (option.name == value) {
      return option;
    }
  }
  _invalid();
}

String _ordinary(String value) => formatOrdinaryLink(
  ordinaryUrl: value,
  name: '',
  format: UploadLinkFormat.url,
);

void _budgetValid(BackupBudgets budgets) {
  _positive(budgets.maxManifestBytes);
  _positive(budgets.maxRecords);
  _nonnegative(budgets.maximumTotalImageBytes);
}

void _checkJsonBudget(Object? value, BackupBudgets budgets) {
  _budgetValid(budgets);
  final ancestors = HashSet<Object>.identity();
  var records = 0, nodes = 0;
  void visit(Object? current, int depth) {
    if (depth > 64 || ++nodes > budgets.maxManifestBytes) {
      _budgetFail();
    }
    if (current == null ||
        current is bool ||
        current is String ||
        current is int) {
      return;
    }
    if (current is! Map && current is! List) {
      _invalid();
    }
    if (!ancestors.add(current)) {
      _invalid();
    }
    try {
      if (current is Map) {
        for (final entry in current.entries) {
          if (entry.key is! String) {
            _invalid();
          }
          visit(entry.value, depth + 1);
        }
      } else {
        for (final entry in current as List) {
          if (++records > budgets.maxRecords) {
            _budgetFail();
          }
          visit(entry, depth + 1);
        }
      }
    } finally {
      ancestors.remove(current);
    }
  }

  visit(value, 0);
  if (utf8.encode(jsonEncode(value)).length > budgets.maxManifestBytes) {
    _budgetFail();
  }
}

Map<String, Object?> _versionJson(ImageVersion v) => {
  'id': v.id,
  'sha256': v.sha256,
  'byteCount': v.byteCount,
  'format': v.format,
  'width': v.width,
  'height': v.height,
  'frameCount': v.frameCount,
  'orientation': v.orientation,
};
ImageVersion _readVersion(Object? value) {
  final m = _map(value, {
    'id',
    'sha256',
    'byteCount',
    'format',
    'width',
    'height',
    'frameCount',
    'orientation',
  });
  return ImageVersion(
    id: _string(m['id']),
    sha256: _string(m['sha256']),
    byteCount: _integer(m['byteCount']),
    format: _string(m['format']),
    width: _integer(m['width']),
    height: _integer(m['height']),
    frameCount: _integer(m['frameCount']),
    orientation: _integer(m['orientation']),
  );
}

BackupName _readName(Object? value) {
  final m = _map(value, {'id', 'name'});
  return BackupName(id: _string(m['id']), name: _string(m['name']));
}

BackupAsset _readAsset(Object? value) {
  final m = _map(value, {
    'id',
    'versionId',
    'displayName',
    'sourceType',
    'importedUtc',
    'updatedUtc',
    'favorite',
    'categoryId',
    'tagIds',
    'recycled',
    'recycledUtc',
  });
  return BackupAsset(
    id: _string(m['id']),
    versionId: _string(m['versionId']),
    displayName: _string(m['displayName']),
    sourceType: _string(m['sourceType']),
    importedUtc: _integer(m['importedUtc']),
    updatedUtc: _integer(m['updatedUtc']),
    favorite: _boolean(m['favorite']),
    categoryId: _nullableString(m['categoryId']),
    tagIds: _list(m['tagIds']).map(_string),
    recycled: _boolean(m['recycled']),
    recycledUtc: _nullableInteger(m['recycledUtc']),
  );
}

BackupAccount _readAccount(Object? value) {
  final m = _map(value, {'id', 'service', 'alias', 'anonymous'});
  return BackupAccount(
    id: _string(m['id']),
    service: _enum(ImageHostService.values, m['service']),
    alias: _string(m['alias']),
    anonymous: _boolean(m['anonymous']),
  );
}

FrozenUploadInput _readInput(Object? value) {
  final m = _map(value, {
    'kind',
    'referenceId',
    'displayName',
    'version',
    'policyKey',
    'processingSummary',
  });
  return FrozenUploadInput(
    kind: _enum(UploadInputKind.values, m['kind']),
    referenceId: _string(m['referenceId']),
    displayName: _string(m['displayName']),
    version: _readVersion(m['version']),
    policyKey: _string(m['policyKey']),
    processingSummary: _nullableString(m['processingSummary']),
  );
}

TargetSnapshot _readTarget(Object? value) {
  final m = _map(value, {'id', 'service', 'alias', 'anonymous'});
  return TargetSnapshot(
    _string(m['id']),
    _enum(ImageHostService.values, m['service']),
    _string(m['alias']),
    _boolean(m['anonymous']),
  );
}

BackupRemoteResult _readResult(Object? value) {
  final m = _map(value, {
    'id',
    'attemptId',
    'input',
    'target',
    'remoteId',
    'directUrl',
    'viewerUrl',
    'confirmedUtc',
    'late',
  });
  return BackupRemoteResult(
    id: _string(m['id']),
    attemptId: _string(m['attemptId']),
    input: _readInput(m['input']),
    target: _readTarget(m['target']),
    remoteId: _string(m['remoteId']),
    directUrl: Uri.parse(_ordinary(_string(m['directUrl']))),
    viewerUrl: m['viewerUrl'] == null
        ? null
        : Uri.parse(_ordinary(_string(m['viewerUrl']))),
    confirmedUtc: _integer(m['confirmedUtc']),
    late: _boolean(m['late']),
  );
}

BackupAttemptHistory _readAttempt(Object? value) {
  final m = _map(value, {
    'id',
    'generation',
    'startedUtc',
    'endedUtc',
    'outcome',
  });
  return BackupAttemptHistory(
    id: _string(m['id']),
    generation: _integer(m['generation']),
    startedUtc: _integer(m['startedUtc']),
    endedUtc: _integer(m['endedUtc']),
    outcome: _nullableString(m['outcome']),
  );
}

BackupTaskHistory _readHistory(Object? value) {
  final m = _map(value, {
    'id',
    'batchId',
    'position',
    'input',
    'target',
    'state',
    'attempts',
    'createdUtc',
    'updatedUtc',
    'message',
  });
  return BackupTaskHistory(
    id: _string(m['id']),
    batchId: _string(m['batchId']),
    position: _integer(m['position']),
    input: _readInput(m['input']),
    target: _readTarget(m['target']),
    state: _enum(PublishState.values, m['state']),
    attempts: _list(m['attempts']).map(_readAttempt),
    createdUtc: _integer(m['createdUtc']),
    updatedUtc: _integer(m['updatedUtc']),
    message: _nullableString(m['message']),
  );
}

BackupImageEntry _readImage(Object? value) {
  final m = _map(value, {'versionId', 'name', 'byteCount', 'sha256'});
  return BackupImageEntry(
    versionId: _string(m['versionId']),
    name: _string(m['name']),
    byteCount: _integer(m['byteCount']),
    sha256: _string(m['sha256']),
  );
}

Map<String, Object?> _processingJson(BackupProcessingSnapshot p) => {
  'operation': p.operation.name,
  'inputs': p.inputs
      .map(
        (i) => <String, Object?>{
          'assetId': i.assetId,
          'version': _versionJson(i.version),
          'selectedFrame': i.selectedFrame,
        },
      )
      .toList(),
  'mode': p.mode.name,
  'outputFormat': p.outputFormat.name,
  'longestSide': p.longestSide,
  'quality': p.quality,
  'crop': p.crop == null
      ? null
      : <String, Object?>{
          'x': p.crop!.x,
          'y': p.crop!.y,
          'width': p.crop!.width,
          'height': p.crop!.height,
        },
  'layout': p.layout.name,
  'gap': p.gap,
  'backgroundArgb': p.backgroundArgb,
  'backgroundConfirmed': p.backgroundConfirmed,
  'explicitStaticConversion': p.explicitStaticConversion,
};
BackupOrigin _readOrigin(Object? value) {
  final m = _map(value, {'outputId', 'versionId', 'createdUtc', 'processing'});
  return BackupOrigin(
    outputId: _string(m['outputId']),
    versionId: _string(m['versionId']),
    createdUtc: _integer(m['createdUtc']),
    processing: _readProcessing(m['processing']),
  );
}

BackupProcessingSnapshot _readProcessing(Object? value) {
  final m = _map(value, {
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
  });
  PixelCrop? crop;
  if (m['crop'] != null) {
    final c = _map(m['crop'], {'x', 'y', 'width', 'height'});
    crop = PixelCrop(
      _integer(c['x']),
      _integer(c['y']),
      _integer(c['width']),
      _integer(c['height']),
    );
  }
  return BackupProcessingSnapshot(
    operation: _enum(ProcessingOperation.values, m['operation']),
    inputs: _list(m['inputs']).map((value) {
      final i = _map(value, {'assetId', 'version', 'selectedFrame'});
      return BackupProcessingInput(
        assetId: _string(i['assetId']),
        version: _readVersion(i['version']),
        selectedFrame: _nullableInteger(i['selectedFrame']),
      );
    }),
    mode: _enum(ProcessingMode.values, m['mode']),
    outputFormat: _enum(ProcessingFormat.values, m['outputFormat']),
    longestSide: _integer(m['longestSide']),
    quality: _nullableInteger(m['quality']),
    crop: crop,
    layout: _enum(StitchLayout.values, m['layout']),
    gap: _integer(m['gap']),
    backgroundArgb: _integer(m['backgroundArgb']),
    backgroundConfirmed: _boolean(m['backgroundConfirmed']),
    explicitStaticConversion: _boolean(m['explicitStaticConversion']),
  );
}
