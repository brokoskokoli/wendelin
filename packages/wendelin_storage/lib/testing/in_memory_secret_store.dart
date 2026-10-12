import '../src/secret_store.dart';

/// A [SecretStore] held in memory (tests, demo mode). Never persists.
final class InMemorySecretStore implements SecretStore {
  /// Creates a store, optionally pre-filled with [initial].
  InMemorySecretStore([Map<String, String> initial = const {}])
    : _values = Map.of(initial);

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async {
    _checkKey(key);
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _checkKey(key);
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _checkKey(key);
    _values.remove(key);
  }

  @override
  Future<Set<String>> listKeys() async => Set.of(_values.keys);

  static void _checkKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'darf nicht leer sein');
    }
  }
}
