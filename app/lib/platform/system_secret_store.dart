import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/secret_store.dart';

/// Only this app's UUID references are addressed. No bulk read/delete API and
/// no plaintext fallback are exposed. Account/session orchestration is separate.
final class SystemSecretStore implements SecretStore {
  SystemSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const namespace = 'imagehost.credentials.v1';
  static const _prefix = '$namespace.';
  static const iosOptions = IOSOptions(
    accountName: namespace,
    synchronizable: false,
    accessibility: KeychainAccessibility.unlocked_this_device,
  );
  static const macosOptions = MacOsOptions(
    accountName: namespace,
    synchronizable: false,
    accessibility: KeychainAccessibility.unlocked_this_device,
    usesDataProtectionKeychain: false,
  );
  static const androidOptions = AndroidOptions(
    storageNamespace: namespace,
    migrateOnAlgorithmChange: false,
    resetOnError: false,
  );
  static const windowsOptions = WindowsOptions();
  static final _uuidV4 = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  final FlutterSecureStorage _storage;
  Future<void> _pending = Future<void>.value();

  String _key(String reference) {
    if (reference.length != 36 || !_uuidV4.hasMatch(reference)) {
      // Never include the caller's supplied reference in public error text.
      throw const SecretStorageException();
    }
    return '$_prefix${reference.toLowerCase()}';
  }

  Future<String?> _readKey(String key) => _storage.read(
    key: key,
    iOptions: iosOptions,
    mOptions: macosOptions,
    aOptions: androidOptions,
    wOptions: windowsOptions,
  );

  // Serializing this instance also protects write/delete read-back verification
  // against another call changing the same reference before verification.
  Future<T> _perform<T>(Future<T> Function() operation) {
    final result = _pending.then((_) async {
      try {
        return await operation();
      } catch (_) {
        throw const SecretStorageException();
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<void> write(String reference, String value) => _perform(() async {
    final key = _key(reference);
    await _storage.write(
      key: key,
      value: value,
      iOptions: iosOptions,
      mOptions: macosOptions,
      aOptions: androidOptions,
      wOptions: windowsOptions,
    );
    if (await _readKey(key) != value) {
      throw const SecretStorageException();
    }
  });

  @override
  Future<String?> read(String reference) =>
      _perform(() => _readKey(_key(reference)));

  @override
  Future<void> delete(String reference) => _perform(() async {
    final key = _key(reference);
    await _storage.delete(
      key: key,
      iOptions: iosOptions,
      mOptions: macosOptions,
      aOptions: androidOptions,
      wOptions: windowsOptions,
    );
    if (await _readKey(key) != null) {
      throw const SecretStorageException();
    }
  });
}
