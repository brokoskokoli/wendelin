import 'dart:typed_data';

import '../src/models/model_store.dart';

/// In-memory [ModelStore]. Passes `modelStoreContract`.
final class FakeModelStore implements ModelStore {
  final _final = <String, Uint8List>{};
  final _partial = <String, BytesBuilder>{};

  /// Fails the next [append] with this error (then cleared).
  Object? nextAppendError;

  /// Number of [append] calls.
  int appends = 0;

  /// Number of [commit] calls.
  int commits = 0;

  static String _key(String model, String file) => '$model/$file';

  /// Final file contents (for assertions).
  Uint8List? finalBytes(String model, String file) => _final[_key(model, file)];

  /// Partial file contents (for assertions).
  Uint8List? partialBytes(String model, String file) =>
      _partial[_key(model, file)]?.toBytes();

  /// Puts a partial file in place (simulates an aborted download).
  void seedPartial(String model, String file, List<int> bytes) =>
      _partial[_key(model, file)] = BytesBuilder()..add(bytes);

  /// Puts a final file in place.
  void seedFinal(String model, String file, List<int> bytes) =>
      _final[_key(model, file)] = Uint8List.fromList(bytes);

  @override
  Future<bool> exists(String modelId, String fileName) async =>
      _final.containsKey(_key(modelId, fileName));

  @override
  Future<int> partialLength(String modelId, String fileName) async =>
      _partial[_key(modelId, fileName)]?.length ?? 0;

  @override
  Stream<List<int>> readPartial(String modelId, String fileName) async* {
    final b = _partial[_key(modelId, fileName)];
    if (b != null) yield b.toBytes();
  }

  @override
  Future<void> append(String modelId, String fileName, List<int> bytes) async {
    appends++;
    final error = nextAppendError;
    if (error != null) {
      nextAppendError = null;
      throw error;
    }
    (_partial[_key(modelId, fileName)] ??= BytesBuilder()).add(bytes);
  }

  @override
  Future<void> truncate(String modelId, String fileName) async =>
      _partial[_key(modelId, fileName)] = BytesBuilder();

  @override
  Future<void> commit(String modelId, String fileName) async {
    final key = _key(modelId, fileName);
    final b = _partial.remove(key);
    if (b == null) throw StateError('Kein Teil-Download für $key');
    commits++;
    _final[key] = b.toBytes();
  }

  @override
  Future<void> deletePartial(String modelId, String fileName) async =>
      _partial.remove(_key(modelId, fileName));

  @override
  Future<void> deleteModel(String modelId) async {
    _final.removeWhere((k, _) => k.startsWith('$modelId/'));
    _partial.removeWhere((k, _) => k.startsWith('$modelId/'));
  }
}
