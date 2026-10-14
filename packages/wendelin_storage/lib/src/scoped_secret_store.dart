import 'secret_store.dart';

/// A view of a [SecretStore] below a fixed key [prefix]: the key `k` is
/// stored as `<prefix>k` in [inner]. It cannot read, write or list keys
/// outside the prefix, so a feature (HTTP tools, Bring!, MCP) never touches
/// the secrets of another one.
///
/// The stored key names are `prefix + key`, byte for byte; they are part of
/// the on-device data and must not change (existing secrets are found
/// without a migration). Passes `secretStoreContract` and the scope checks
/// of `scopedSecretStoreContract` (`package:wendelin_storage/testing.dart`).
final class ScopedSecretStore implements SecretStore {
  /// Creates the view of [inner] below [prefix].
  ScopedSecretStore(this.inner, this.prefix) {
    if (prefix.isEmpty) {
      throw ArgumentError.value(prefix, 'prefix', 'darf nicht leer sein');
    }
  }

  /// The store the keys live in.
  final SecretStore inner;

  /// Prefix of every key of this view in [inner].
  final String prefix;

  /// Key of [key] in [inner].
  String innerKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'darf nicht leer sein');
    }
    return '$prefix$key';
  }

  @override
  Future<String?> read(String key) => inner.read(innerKey(key));

  @override
  Future<void> write(String key, String value) =>
      inner.write(innerKey(key), value);

  @override
  Future<void> delete(String key) => inner.delete(innerKey(key));

  /// The keys of this view (without the prefix).
  @override
  Future<Set<String>> listKeys() async => {
    for (final key in await inner.listKeys())
      if (key.length > prefix.length && key.startsWith(prefix))
        key.substring(prefix.length),
  };

  /// Deletes every key of this view whose name (without the prefix) starts
  /// with [keyPrefix] and is not in [keep]; with the defaults all of them.
  /// Keys outside the view stay.
  Future<void> deleteAll({
    String keyPrefix = '',
    Set<String> keep = const {},
  }) async {
    for (final key in await listKeys()) {
      if (key.startsWith(keyPrefix) && !keep.contains(key)) {
        await delete(key);
      }
    }
  }

  @override
  String toString() => 'ScopedSecretStore($prefix<verborgen>)';
}
