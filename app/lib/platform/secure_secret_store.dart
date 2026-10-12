import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// [SecretStore] on `flutter_secure_storage` (Android Keystore, iOS
/// Keychain). Secrets never go into SQLite, logs or exports.
///
/// Passes `secretStoreContract` (test: `secure_secret_store_test.dart`, with
/// the plugin's in-memory test platform).
final class SecureSecretStore implements SecretStore {
  /// Creates the store; [storage] is injectable for tests.
  SecureSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) {
    _checkKey(key);
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) {
    _checkKey(key);
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) {
    _checkKey(key);
    return _storage.delete(key: key);
  }

  @override
  Future<Set<String>> listKeys() async =>
      (await _storage.readAll()).keys.toSet();

  static void _checkKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'darf nicht leer sein');
    }
  }
}
