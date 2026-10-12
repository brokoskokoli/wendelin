/// Storage for secrets (API keys, OAuth tokens, logins), referenced from
/// `AuthMethod.secretRefs`. The app implements it with
/// `flutter_secure_storage` (Android Keystore / iOS Keychain); secrets never
/// go into SQLite, logs or exports.
///
/// Contract (checked by `secretStoreContract` in
/// `package:wendelin_storage/testing.dart`):
/// - [read] returns the last value written for a key, or `null`.
/// - [write] overwrites; values are stored exactly (empty string and
///   Unicode included).
/// - [delete] removes the key; deleting a missing key is no error.
/// - [listKeys] returns exactly the keys currently stored.
/// - Keys are independent; an empty key throws [ArgumentError].
abstract interface class SecretStore {
  /// The secret stored under [key], or `null`.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any previous value.
  Future<void> write(String key, String value);

  /// Removes [key] (no error if it does not exist).
  Future<void> delete(String key);

  /// All keys currently stored.
  Future<Set<String>> listKeys();
}
