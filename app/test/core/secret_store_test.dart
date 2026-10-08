import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/secret_store.dart';
import 'package:imagehost/platform/system_secret_store.dart';

const _reference = 'a84757f1-69ce-4c6e-8a38-2aac7a062bdc';
const _otherReference = '9858db8f-e847-4d0c-b067-bbc723724f22';
const _secret = 'fake-credential-for-unit-test';

final class _UnsafeFailure implements Exception {
  @override
  String toString() => throw StateError('must not stringify native errors');
}

final class _FakeSecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  final calls = <String>[];
  final optionMaps = <Map<String, String>>[];
  String? failingOperation;
  bool ignoreWrite = false;
  bool ignoreDelete = false;
  Completer<void>? writeGate;

  void _record(
    String operation,
    String key,
    AppleOptions? ios,
    AndroidOptions? android,
    AppleOptions? macos,
    WindowsOptions? windows,
  ) {
    calls.add('$operation:$key');
    optionMaps.addAll([
      ios!.toMap(),
      android!.toMap(),
      macos!.toMap(),
      windows!.toMap(),
    ]);
    if (operation == failingOperation) throw _UnsafeFailure();
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _record('write', key, iOptions, aOptions, mOptions, wOptions);
    final gate = writeGate;
    if (gate != null) await gate.future;
    if (!ignoreWrite) values[key] = value!;
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _record('read', key, iOptions, aOptions, mOptions, wOptions);
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _record('delete', key, iOptions, aOptions, mOptions, wOptions);
    if (!ignoreDelete) values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected secure storage call');
}

// A test fixture only: never an automatic production plaintext fallback.
final class MemorySecretStore implements SecretStore {
  final _values = <String, String>{};
  @override
  Future<void> write(String reference, String value) async {
    _values[reference] = value;
  }

  @override
  Future<String?> read(String reference) async => _values[reference];
  @override
  Future<void> delete(String reference) async => _values.remove(reference);
}

Matcher get _safeFailure => isA<SecretStorageException>().having(
  (error) => error.toString(),
  'public message',
  SecretStorageException.message,
);

void main() {
  test(
    'UT-095 / SEC-002 scoped UUID read/write/delete and platform policy',
    () async {
      final native = _FakeSecureStorage();
      final store = SystemSecretStore(storage: native);
      native.values['unrelated.application.key'] = 'unrelated';
      await store.write(_reference.toUpperCase(), _secret);
      await store.write(_otherReference, 'another fake secret');
      expect(await store.read(_reference), _secret);
      await store.delete(_reference);
      expect(await store.read(_reference), isNull);
      expect(await store.read(_otherReference), 'another fake secret');
      expect(native.values['unrelated.application.key'], 'unrelated');
      expect(
        native.calls.every(
          (call) => call.contains('imagehost.credentials.v1.'),
        ),
        isTrue,
      );
      final options = native.optionMaps;
      expect(options[0]['accountName'], SystemSecretStore.namespace);
      expect(options[0]['synchronizable'], 'false');
      expect(options[0]['accessibility'], 'unlocked_this_device');
      expect(options[1]['storageNamespace'], SystemSecretStore.namespace);
      expect(options[1]['resetOnError'], 'false');
      expect(options[1]['migrateOnAlgorithmChange'], 'false');
      expect(options[2]['usesDataProtectionKeychain'], 'false');
      expect(options[2]['accountName'], SystemSecretStore.namespace);
      expect(options[2]['synchronizable'], 'false');
      expect(options[2]['accessibility'], 'unlocked_this_device');
      expect(options[3]['useBackwardCompatibility'], 'false');
    },
  );

  test(
    'UT-095 / SEC-002 invalid references never address the backend',
    () async {
      final native = _FakeSecureStorage();
      final store = SystemSecretStore(storage: native);
      for (final value in [
        '',
        '../outside',
        'plain-api-key',
        '$_reference\n',
        _reference.replaceFirst('-4', '-1'),
      ]) {
        await expectLater(store.write(value, _secret), throwsA(_safeFailure));
        await expectLater(store.read(value), throwsA(_safeFailure));
        await expectLater(store.delete(value), throwsA(_safeFailure));
      }
      expect(native.calls, isEmpty);
    },
  );

  for (final operation in ['write', 'read', 'delete']) {
    test(
      'UT-095 / SEC-002 $operation failure has no raw error or fallback',
      () async {
        final native = _FakeSecureStorage()..failingOperation = operation;
        final store = SystemSecretStore(storage: native);
        final future = switch (operation) {
          'write' => store.write(_reference, _secret),
          'read' => store.read(_reference),
          _ => store.delete(_reference),
        };
        await expectLater(future, throwsA(_safeFailure));
        native.failingOperation = null;
        expect(await store.read(_reference), isNull);
        // A failure does not poison the instance's serialized operation queue.
        await store.write(_reference, _secret);
        expect(await store.read(_reference), _secret);
      },
    );
  }

  test(
    'UT-095 / SEC-002 successful native return requires exact read-back',
    () async {
      final native = _FakeSecureStorage()..ignoreWrite = true;
      final store = SystemSecretStore(storage: native);
      await expectLater(
        store.write(_reference, _secret),
        throwsA(_safeFailure),
      );
      native.ignoreWrite = false;
      await store.write(_reference, _secret);
      native.ignoreDelete = true;
      await expectLater(store.delete(_reference), throwsA(_safeFailure));
      native.ignoreDelete = false;
      await store.delete(_reference);
      native.failingOperation = 'read';
      await expectLater(
        store.write(_reference, _secret),
        throwsA(_safeFailure),
      );
      await expectLater(store.delete(_reference), throwsA(_safeFailure));
    },
  );

  test('UT-095 / SEC-002 pending native IO cannot report success or race verification', () async {
    final native = _FakeSecureStorage()..writeGate = Completer<void>();
    final store = SystemSecretStore(storage: native);
    var completed = false;
    final writing = store
        .write(_reference, _secret)
        .then((_) => completed = true);
    final deleting = store.delete(_reference);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(native.calls.map((value) => value.split(':').first), ['write']);
    native.writeGate!.complete();
    await writing;
    await deleting;
    expect(native.calls.map((value) => value.split(':').first), [
      'write',
      'read',
      'delete',
      'read',
    ]);
    expect(await store.read(_reference), isNull);
  });

  test(
    'UT-095 test-only memory fixture can be injected and explicitly deleted',
    () async {
      final SecretStore store = MemorySecretStore();
      await store.write(_reference, _secret);
      expect(await store.read(_reference), _secret);
      await store.delete(_reference);
      expect(await store.read(_reference), isNull);
    },
  );
}
