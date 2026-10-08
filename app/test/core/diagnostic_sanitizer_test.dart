import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/secret_redactor.dart';
import 'package:imagehost/features/diagnostics/application/diagnostic_sanitizer.dart';
import 'package:imagehost/features/diagnostics/domain/diagnostic_models.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _batch = '22222222-2222-4222-8222-222222222222';

DiagnosticEvent _event({String? batchId, Object? details}) => DiagnosticEvent(
  id: _id,
  occurredAt: DateTime.utc(2026, 10, 7, 3, 4, 5, 6, 7),
  kind: DiagnosticKind.upload,
  level: DiagnosticLevel.error,
  code: 'upload.failed',
  summary: '上传失败，请检查目标。',
  recoveryAction: '确认目标配置后重试。',
  batchId: batchId,
  details: details,
);

final class _UnsafeObject {
  bool stringified = false;
  @override
  String toString() {
    stringified = true;
    throw StateError('private-value');
  }
}

final class _UnsafeMap extends MapBase<String, Object?> {
  @override
  Object? operator [](Object? key) => throw StateError('private-value');
  @override
  void operator []=(String key, Object? value) => throw UnimplementedError();
  @override
  void clear() => throw UnimplementedError();
  @override
  Iterable<String> get keys => throw StateError('private-value');
  @override
  Object? remove(Object? key) => throw UnimplementedError();
}

void main() {
  test(
    'UT-084 diagnostic identity, UTC milliseconds and strict JSON roundtrip',
    () {
      final event = _event(batchId: _batch, details: {'count': 2});
      final copy = DiagnosticEvent.fromJson(
        jsonDecode(jsonEncode(event.toJson())),
      );
      expect(copy.toJson(), event.toJson());
      expect(copy.occurredAt.isUtc, isTrue);
      expect(copy.occurredAt.microsecond, 0);
      expect(copy.batchId, _batch);
      expect(copy.code, 'upload.failed');
      expect(copy.recoveryAction, isNotEmpty);
      final query = DiagnosticQuery(
        kind: event.kind,
        level: event.level,
        batchId: _batch,
        attemptId: _id,
      );
      expect(query.batchId, _batch);
      expect(
        () => DiagnosticQuery(batchId: 'raw string'),
        throwsA(isA<DiagnosticFailure>()),
      );
    },
  );

  test(
    'UT-084 future, extra, missing and wrongly typed event fields fail closed',
    () {
      final valid = _event().toJson();
      for (final input in [
        {...valid, 'schemaVersion': 2},
        {...valid, 'schemaVersion': 1.0},
        {...valid, 'extra': 'value'},
        {...valid}..remove('details'),
        {...valid, 'id': 'invalid'},
        {...valid, 'entityId': 'invalid'},
        {...valid, 'occurredAt': 'today'},
        {...valid, 'occurredAt': 8640000000000001},
        {...valid, 'kind': 'future'},
        {...valid, 'level': 'fatal'},
        {...valid, 'code': 'Invalid Code'},
        {...valid, 'summary': 's' * 2049},
        {...valid, 'recoveryAction': '\ud800'},
        {...valid, 'recoveryAction': '   '},
        _UnsafeMap(),
      ]) {
        expect(
          () => DiagnosticEvent.fromJson(input),
          throwsA(isA<DiagnosticFailure>()),
        );
      }
    },
  );

  test(
    'UT-084 event and page snapshots do not retain mutable JSON aliases',
    () {
      final nested = <Object?>[
        {'safe': true},
      ];
      final details = {'nested': nested};
      final event = _event(details: details);
      nested.clear();
      details.clear();
      expect(event.details, {
        'nested': [
          {'safe': true},
        ],
      });
      expect(() => (event.details as Map)['extra'] = 1, throwsUnsupportedError);
      expect(
        () => ((event.details as Map)['nested'] as List).clear(),
        throwsUnsupportedError,
      );
      final items = [event];
      final page = DiagnosticPage(
        items,
        1,
        utf8.encode(jsonEncode(event.toJson())).length,
      );
      items.clear();
      expect(page.items, [event]);
      expect(() => page.items.clear(), throwsUnsupportedError);
      expect(
        () => DiagnosticPage([event], 0, 0),
        throwsA(isA<DiagnosticFailure>()),
      );
      expect(
        () => _event(details: double.nan),
        throwsA(isA<DiagnosticFailure>()),
      );
      final unknown = _UnsafeObject();
      expect(() => _event(details: unknown), throwsA(isA<DiagnosticFailure>()));
      expect(unknown.stringified, isFalse);
    },
  );

  test('UT-085 F-SECRET nested fields, opaque references, bodies and images excluded', () {
    final sanitizer = DiagnosticSanitizer(SecretRedactor());
    final output = jsonEncode(
      sanitizer.sanitize({
        'summary': 'safe summary',
        'nested': [
          for (final key in [
            'KEY',
            'userhash',
            'api_key',
            'deleteUrl',
            'authorization',
          ])
            {key: 'private-value'},
          {'credentialRef': _batch, 'managementSecretReference': _batch},
          {'rawBody': 'private-value', 'requestBody': 'private-value'},
          {
            'imageBytes': [1, 2, 3],
            'originalBytes': 'image-private',
          },
          {'path': r'C:\Users\alice\pictures\secret.png'},
        ],
      }),
    );
    for (final excluded in [
      'private-value',
      _batch,
      'image-private',
      'alice',
      'rawBody',
      'credentialRef',
      'imageBytes',
      'originalBytes',
    ]) {
      expect(output, isNot(contains(excluded)));
    }
    expect(output, contains('safe summary'));
    expect(output, contains(SecretRedactor.hidden));
    expect(
      sanitizer.text('data:image/png;base64,picture-private'),
      DiagnosticSanitizer.excluded,
    );
  });

  test(
    'UT-085 literal and encoded retired secrets masked before truncation',
    () {
      const value = 'secret+/中文?=';
      final redactor = SecretRedactor()..register(value);
      final sanitizer = DiagnosticSanitizer(redactor);
      for (final variant in [
        value,
        Uri.encodeComponent(value),
        Uri.encodeQueryComponent(value),
        Uri.encodeComponent(Uri.encodeComponent(value)),
      ]) {
        expect(
          sanitizer.text('before $variant after'),
          'before ${SecretRedactor.hidden} after',
        );
      }
      redactor.unregister(value);
      expect(sanitizer.text(value), SecretRedactor.hidden);
      const longSecret = 'a-very-long-private-key';
      redactor.register(longSecret);
      final output = sanitizer.text('${'x' * 4090}$longSecret trailing');
      expect(output.runes.length, lessThanOrEqualTo(4096));
      expect(output, isNot(contains('a-very')));
      expect(output, contains('[已隐藏]'));
      expect(sanitizer.text('😀' * 4100).runes.length, 4096);
      expect(sanitizer.text('\ud800'), SecretRedactor.unavailable);
    },
  );

  test('UT-085 malformed assignments, full external paths and URL credentials removed', () {
    final sanitizer = DiagnosticSanitizer(SecretRedactor());
    for (final input in [
      'failure: api_key=private-value',
      '{"password":"private-value',
      "failure token='private-value",
      'Authorization: Bearer private-value',
      'delete_url=https://delete.test/private-value',
      'credentialRef=$_batch',
      r'file:///C:/Users/alice/private.png',
      r'failure C:\Users\alice\private.png',
      r'failure \\server\alice\private.png',
      'failure /Users/alice/private.png',
      'failure /home/alice/private.png',
      'failure "/home/alice/private.png"',
      "failure '/Users/alice/private.png'",
      'failure C%3A%5CUsers%5Calice%5Cprivate.png',
      'failure %2Fhome%2Falice%2Fprivate.png',
    ]) {
      final output = sanitizer.text(input);
      for (final excluded in ['private-value', 'alice', _batch]) {
        expect(output, isNot(contains(excluded)));
      }
    }
    final url = sanitizer.text(
      'https://example.test/image.png?api_key=private-value&ok=other-private#private-fragment',
    );
    expect(url, 'https://example.test/image.png');
    expect(
      sanitizer.text('https://alice:private-value@example.test/image'),
      SecretRedactor.unavailable,
    );
    expect(
      sanitizer.text('https://[malformed/private-value'),
      SecretRedactor.unavailable,
    );
  });

  test('UT-085 unknown objects, hostile collections, cycles and budgets use safe markers', () {
    final sanitizer = DiagnosticSanitizer(SecretRedactor());
    final unknown = _UnsafeObject();
    expect(sanitizer.sanitize(unknown), SecretRedactor.unavailable);
    expect(sanitizer.sanitize(_UnsafeMap()), SecretRedactor.unavailable);
    expect(unknown.stringified, isFalse);
    final cycle = <Object?>[];
    cycle.add(cycle);
    expect(sanitizer.sanitize(cycle), [SecretRedactor.unavailable]);
    Object? deep = 'private-value';
    for (var index = 0; index < 40; index++) {
      deep = [deep];
    }
    expect(
      jsonEncode(sanitizer.sanitize(deep)),
      isNot(contains('private-value')),
    );
    expect(
      sanitizer.sanitize(List.filled(10001, 1)),
      SecretRedactor.unavailable,
    );
    expect(sanitizer.sanitize(double.infinity), SecretRedactor.unavailable);
  });

  test('UT-085 / UT-089 re-export redacts newly registered secrets and preserves identities', () {
    final redactor = SecretRedactor();
    final sanitizer = DiagnosticSanitizer(redactor);
    final original = _event(
      batchId: _batch,
      details: {'summary': 'new-secret'},
    );
    redactor.register('new-secret');
    final clean = sanitizer.event(original);
    expect(jsonEncode(clean.toJson()), isNot(contains('new-secret')));
    expect(clean.id, original.id);
    expect(original.details, {'summary': 'new-secret'});
    redactor.register(_batch);
    expect(sanitizer.event(original).batchId, isNull);
    redactor.register(_id);
    expect(() => sanitizer.event(original), throwsA(isA<DiagnosticFailure>()));
    expect(const DiagnosticFailure().message, isNot(contains('new-secret')));
    final codeRedactor = SecretRedactor()..register('upload.failed');
    expect(
      () => DiagnosticSanitizer(codeRedactor).event(original),
      throwsA(isA<DiagnosticFailure>()),
    );
  });
}
