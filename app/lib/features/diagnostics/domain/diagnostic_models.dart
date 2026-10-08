import 'dart:collection';

enum DiagnosticKind {
  importImage,
  processing,
  upload,
  account,
  settings,
  cleanup,
  backup,
  restore,
  system,
}

enum DiagnosticLevel { info, warning, error }

/// Never derives its message from an exception or untrusted response.
final class DiagnosticFailure implements Exception {
  const DiagnosticFailure();
  String get message => '诊断信息无法安全读取或保存，请重试。';
  @override
  String toString() => message;
}

final class DiagnosticEvent {
  DiagnosticEvent({
    required this.id,
    required DateTime occurredAt,
    required this.kind,
    required this.level,
    required this.code,
    required this.summary,
    required this.recoveryAction,
    this.entityId,
    this.batchId,
    this.attemptId,
    Object? details,
  }) : occurredAt = _utcMillis(occurredAt),
       details = _freezeJson(details) {
    _checkId(id);
    for (final value in [entityId, batchId, attemptId]) {
      if (value != null) _checkId(value);
    }
    if (!RegExp(r'^[a-z0-9_.]{1,64}$').hasMatch(code)) {
      throw const DiagnosticFailure();
    }
    _checkString(summary, 2048);
    _checkString(recoveryAction, 2048);
    if (level == DiagnosticLevel.error && recoveryAction.trim().isEmpty) {
      throw const DiagnosticFailure();
    }
  }

  static const schemaVersion = 1;
  final String id;
  final DateTime occurredAt;
  final DiagnosticKind kind;
  final DiagnosticLevel level;
  final String code;
  final String summary;
  final String recoveryAction;
  final String? entityId;
  final String? batchId;
  final String? attemptId;
  final Object? details;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'occurredAt': occurredAt.millisecondsSinceEpoch,
    'kind': kind.name,
    'level': level.name,
    'code': code,
    'summary': summary,
    'recoveryAction': recoveryAction,
    'entityId': entityId,
    'batchId': batchId,
    'attemptId': attemptId,
    'details': details,
  };

  factory DiagnosticEvent.fromJson(Object? input) {
    try {
      const keys = {
        'schemaVersion',
        'id',
        'occurredAt',
        'kind',
        'level',
        'code',
        'summary',
        'recoveryAction',
        'entityId',
        'batchId',
        'attemptId',
        'details',
      };
      if (input is! Map ||
          input.length != keys.length ||
          input.keys.any((key) => key is! String || !keys.contains(key)) ||
          input['schemaVersion'] is! int ||
          input['schemaVersion'] != schemaVersion ||
          input['occurredAt'] is! int) {
        throw const DiagnosticFailure();
      }
      return DiagnosticEvent(
        id: input['id'] as String,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          input['occurredAt'] as int,
          isUtc: true,
        ),
        kind: DiagnosticKind.values.byName(input['kind'] as String),
        level: DiagnosticLevel.values.byName(input['level'] as String),
        code: input['code'] as String,
        summary: input['summary'] as String,
        recoveryAction: input['recoveryAction'] as String,
        entityId: input['entityId'] as String?,
        batchId: input['batchId'] as String?,
        attemptId: input['attemptId'] as String?,
        details: input['details'],
      );
    } catch (_) {
      throw const DiagnosticFailure();
    }
  }
}

final class DiagnosticQuery {
  DiagnosticQuery({this.kind, this.level, this.batchId, this.attemptId}) {
    if (batchId != null) _checkId(batchId!);
    if (attemptId != null) _checkId(attemptId!);
  }
  final DiagnosticKind? kind;
  final DiagnosticLevel? level;
  final String? batchId;
  final String? attemptId;
}

final class DiagnosticPage {
  DiagnosticPage(List<DiagnosticEvent> items, this.total, this.contentBytes)
    : items = List.unmodifiable(items) {
    if (total < items.length || contentBytes < 0) {
      throw const DiagnosticFailure();
    }
  }
  final List<DiagnosticEvent> items;
  final int total;
  final int contentBytes;
}

void _checkId(String value) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw const DiagnosticFailure();
  }
}

void _checkString(String value, int max) {
  // Reject malformed UTF-16 rather than allowing a serializer to change it.
  var count = 0;
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= value.length) throw const DiagnosticFailure();
      final low = value.codeUnitAt(index);
      if (low < 0xdc00 || low > 0xdfff) throw const DiagnosticFailure();
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const DiagnosticFailure();
    }
    if (++count > max) throw const DiagnosticFailure();
  }
}

DateTime _utcMillis(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
  value.millisecondsSinceEpoch,
  isUtc: true,
);

Object? _freezeJson(Object? input) {
  final ancestors = HashSet<Object>.identity();
  var nodes = 0;
  Object? visit(Object? value, int depth) {
    if (++nodes > 10000 || depth > 32) throw const DiagnosticFailure();
    if (value == null || value is bool || value is int) return value;
    if (value is double && value.isFinite) return value;
    if (value is String) {
      _checkString(value, 4096);
      return value;
    }
    if (value is! Map && value is! List) throw const DiagnosticFailure();
    if (!ancestors.add(value)) throw const DiagnosticFailure();
    try {
      if (value is Map) {
        final result = <String, Object?>{};
        for (final entry in value.entries) {
          if (++nodes > 10000 || entry.key is! String) {
            throw const DiagnosticFailure();
          }
          final key = entry.key as String;
          _checkString(key, 4096);
          result[key] = visit(entry.value, depth + 1);
        }
        return Map<String, Object?>.unmodifiable(result);
      }
      final result = <Object?>[];
      for (final entry in value as List) {
        result.add(visit(entry, depth + 1));
      }
      return List<Object?>.unmodifiable(result);
    } finally {
      ancestors.remove(value);
    }
  }

  try {
    return visit(input, 0);
  } catch (_) {
    throw const DiagnosticFailure();
  }
}
