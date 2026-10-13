/// Storage for downloaded model files (implemented by the app on the file
/// system, `FakeModelStore` in memory).
///
/// Files are addressed by model id and file name. A download writes into a
/// *partial* file that only becomes visible under its final name through
/// [commit] (atomic rename), so an aborted download never looks complete.
///
/// Contract (`modelStoreContract`):
/// - [partialLength] is 0 when no partial file exists.
/// - [append] creates the partial file if needed and appends bytes;
///   [truncate] empties it.
/// - [readPartial] streams the partial bytes in order.
/// - [commit] replaces a final file atomically and removes the partial one;
///   afterwards [exists] is true and [partialLength] is 0. Without a
///   partial file it throws `StateError`.
/// - [deletePartial] and [deleteModel] are no-ops for missing files.
abstract interface class ModelStore {
  /// Whether the final file exists.
  Future<bool> exists(String modelId, String fileName);

  /// Length of the partial download in bytes (0 if none).
  Future<int> partialLength(String modelId, String fileName);

  /// Contents of the partial download.
  Stream<List<int>> readPartial(String modelId, String fileName);

  /// Appends [bytes] to the partial download.
  Future<void> append(String modelId, String fileName, List<int> bytes);

  /// Empties the partial download (server ignored the range request).
  Future<void> truncate(String modelId, String fileName);

  /// Moves the partial download to its final name atomically.
  Future<void> commit(String modelId, String fileName);

  /// Removes the partial download.
  Future<void> deletePartial(String modelId, String fileName);

  /// Removes all files of a model (final and partial).
  Future<void> deleteModel(String modelId);
}
