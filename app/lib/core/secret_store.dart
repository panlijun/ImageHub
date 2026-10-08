abstract interface class SecretStore {
  Future<void> write(String reference, String value);
  Future<String?> read(String reference);
  Future<void> delete(String reference);
}

/// Public errors deliberately retain no native exception, reference or value.
final class SecretStorageException implements Exception {
  const SecretStorageException();

  static const message = '系统安全存储暂不可用，请重试或选择仅本次会话使用。';

  @override
  String toString() => message;
}

/// Pure Dart callers can use the local library without a native secret backend.
/// This fails closed; it never persists or guesses credentials.
final class UnavailableSecretStore implements SecretStore {
  const UnavailableSecretStore();
  @override
  Future<void> write(String reference, String value) async =>
      throw const SecretStorageException();
  @override
  Future<String?> read(String reference) async =>
      throw const SecretStorageException();
  @override
  Future<void> delete(String reference) async =>
      throw const SecretStorageException();
}
