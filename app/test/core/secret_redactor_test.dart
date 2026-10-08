import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/secret_redactor.dart';

final class _UnsafeObject {
  var stringified = false;
  @override
  String toString() {
    stringified = true;
    throw StateError('a secret must not reach a fallback');
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
  test('UT-097 / SEC-004 primitive type conversion cannot reveal registered values', () {
    final redactor = SecretRedactor()
      ..register('123')
      ..register('true');
    expect(
      redactor.redact({
        'integer': 123,
        'decimal': 123.0,
        'flag': true,
        'nested': [123, true, 456, 4.5, false, null],
      }),
      {
        'integer': SecretRedactor.hidden,
        'decimal': SecretRedactor.hidden,
        'flag': SecretRedactor.hidden,
        'nested': [
          SecretRedactor.hidden,
          SecretRedactor.hidden,
          456,
          4.5,
          false,
          null,
        ],
      },
    );
    expect(SecretRedactor().redact([123, 123.0, true, false]), [
      123,
      123.0,
      true,
      false,
    ]);
  });

  test(
    'UT-097 / SEC-004 nested sensitive fields ignore spelling and casing',
    () {
      final redactor = SecretRedactor();
      final result = redactor.redact({
        'name': 'safe',
        'nested': [
          for (final key in [
            'KEY',
            'api_key',
            'ApiKey',
            'userhash',
            'TOKEN',
            'secret',
            'password',
            'Authorization',
            'delete_url',
            'refresh-token',
            'clientSecret',
          ])
            {key: 'private-value'},
          {'count': 3, 'ok': true, 'empty': null},
        ],
      });
      final output = jsonEncode(result);
      expect(output, isNot(contains('private-value')));
      expect(output, contains('safe'));
      expect(output, contains('"count":3'));
      expect(output, contains(SecretRedactor.hidden));
    },
  );

  test(
    'UT-097 / SEC-004 registered values, URL encodings and retired history',
    () {
      const value = 'fake secret+/中文?=';
      final redactor = SecretRedactor()..register(value);
      final variants = [
        value,
        Uri.encodeComponent(value),
        Uri.encodeQueryComponent(value),
        Uri.encodeComponent(Uri.encodeComponent(value)),
        Uri.encodeComponent(value).toLowerCase(),
      ];
      for (final variant in variants) {
        expect(
          redactor.redactText('before $variant after'),
          'before ${SecretRedactor.hidden} after',
        );
      }
      redactor.unregister(value);
      expect(redactor.redactText(value), SecretRedactor.hidden);
    },
  );

  test('UT-097 / SEC-004 short secrets and overlapping values are masked', () {
    final redactor = SecretRedactor()
      ..register('x')
      ..register('xy')
      ..register('');
    expect(
      redactor.redactText('xy x'),
      '${SecretRedactor.hidden} ${SecretRedactor.hidden}',
    );
    expect(SecretRedactor().redactText('safe'), 'safe');
  });

  test('UT-097 / SEC-004 URL query values and user info are masked', () {
    final redactor = SecretRedactor();
    final output = redactor.redactText(
      'https://name:private-password@example.test/image?api%5fkey=unregistered-secret&ok=one&ToKeN=unknown-token&delete_url=https%3A%2F%2Fdelete.test#fragment',
    );
    expect(output, isNot(contains('private-password')));
    expect(output, isNot(contains('unregistered-secret')));
    expect(output, isNot(contains('unknown-token')));
    expect(output, isNot(contains('delete.test')));
    expect(output, contains('ok=one'));
    expect(output, contains('#fragment'));
  });

  test(
    'UT-097 / SEC-004 assignments, headers and truncated quoted exceptions',
    () {
      final redactor = SecretRedactor();
      for (final text in [
        'failure: api_key=truncated-secret',
        '{"password":"truncated-secret',
        "failure token='truncated-secret",
        'Authorization: Bearer truncated-secret',
        'header: bEaReR truncated-secret',
        'delete_url=https://delete.test/truncated-secret',
        'error: {"Token": "truncated-secret", "message": "safe"}',
      ]) {
        expect(
          redactor.redactText(text),
          isNot(contains('truncated-secret')),
          reason: text,
        );
      }
    },
  );

  test(
    'UT-097 / SEC-004 unknown objects and collection failures never stringify',
    () {
      final redactor = SecretRedactor();
      final object = _UnsafeObject();
      expect(redactor.redact(object), SecretRedactor.unavailable);
      expect(
        redactor.redact(StateError('private-value')),
        SecretRedactor.unavailable,
      );
      expect(redactor.redact(_UnsafeMap()), SecretRedactor.unavailable);
      expect(
        redactor.redact({object: 'private-value'}),
        SecretRedactor.unavailable,
      );
      expect(object.stringified, isFalse);
    },
  );

  test('UT-097 / SEC-004 cycles and depth/node budgets are safe', () {
    final redactor = SecretRedactor();
    final cycle = <Object?>[];
    cycle.add(cycle);
    expect(redactor.redact(cycle), [SecretRedactor.unavailable]);
    final mapCycle = <String, Object?>{};
    mapCycle['nested'] = mapCycle;
    expect(redactor.redact(mapCycle), {'nested': SecretRedactor.unavailable});
    Object? deep = 'private-value';
    for (var index = 0; index < 40; index++) {
      deep = [deep];
    }
    expect(jsonEncode(redactor.redact(deep)), isNot(contains('private-value')));
    expect(redactor.redact(List.filled(10001, 1)), SecretRedactor.unavailable);
    final shared = ['safe'];
    expect(redactor.redact([shared, shared]), [shared, shared]);
  });
}
