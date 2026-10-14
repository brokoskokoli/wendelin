import '../src/http_tools/http_tool_repository.dart';

/// In-memory [HttpToolStore].
final class FakeHttpToolStore implements HttpToolStore {
  /// Creates the store with [initial] definitions.
  FakeHttpToolStore([List<Map<String, Object?>> initial = const []])
    : stored = [...initial];

  /// What is stored (JSON of each definition).
  List<Map<String, Object?>> stored;

  @override
  Future<List<Map<String, Object?>>> read() async => [...stored];

  @override
  Future<void> write(List<Map<String, Object?>> definitions) async =>
      stored = [...definitions];
}

/// In-memory [HttpToolSecretVault].
final class FakeHttpToolSecretVault implements HttpToolSecretVault {
  /// Creates the vault with [initial] secrets by reference.
  FakeHttpToolSecretVault([Map<String, String> initial = const {}])
    : values = {...initial};

  /// The secrets by reference.
  final Map<String, String> values;

  @override
  Future<String?> read(String ref) async => values[ref];

  @override
  Future<void> write(String ref, String value) async => values[ref] = value;

  @override
  Future<void> delete(String ref) async => values.remove(ref);

  @override
  Future<Set<String>> refs() async => values.keys.toSet();
}
