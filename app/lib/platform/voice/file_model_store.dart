import 'dart:io';

import 'package:wendelin_voice/wendelin_voice.dart';

/// [ModelStore] on the file system: one directory per model id under
/// [root]; a download is written to `<name>.part` next to the final file
/// and [commit] renames it atomically (same directory).
///
/// Model ids and file names must be plain names (no path separators, no
/// leading dot), so nothing can be written outside [root].
final class FileModelStore implements ModelStore {
  /// Creates the store under [root] (created on demand).
  FileModelStore(this.root);

  /// Base directory (app support directory `/models` on the device).
  final Directory root;

  static final _plain = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*$');

  static String _check(String name, String what) {
    if (!_plain.hasMatch(name) || name.contains('..')) {
      throw ArgumentError.value(name, what, 'kein einfacher Name');
    }
    return name;
  }

  /// Directory of model [modelId].
  Directory modelDir(String modelId) =>
      Directory('${root.path}/${_check(modelId, 'modelId')}');

  /// Path of the final file [fileName] of [modelId].
  String pathOf(String modelId, String fileName) =>
      '${modelDir(modelId).path}/${_check(fileName, 'fileName')}';

  File _final(String m, String f) => File(pathOf(m, f));
  File _part(String m, String f) => File('${pathOf(m, f)}.part');

  @override
  Future<bool> exists(String modelId, String fileName) =>
      _final(modelId, fileName).exists();

  @override
  Future<int> partialLength(String modelId, String fileName) async {
    final part = _part(modelId, fileName);
    return await part.exists() ? part.length() : 0;
  }

  @override
  Stream<List<int>> readPartial(String modelId, String fileName) async* {
    final part = _part(modelId, fileName);
    if (await part.exists()) yield* part.openRead();
  }

  @override
  Future<void> append(String modelId, String fileName, List<int> bytes) async {
    final part = _part(modelId, fileName);
    await part.parent.create(recursive: true);
    await part.writeAsBytes(bytes, mode: FileMode.append, flush: false);
  }

  @override
  Future<void> truncate(String modelId, String fileName) async {
    final part = _part(modelId, fileName);
    if (await part.exists()) await part.writeAsBytes(const [], flush: true);
  }

  @override
  Future<void> commit(String modelId, String fileName) async {
    final part = _part(modelId, fileName);
    if (!await part.exists()) {
      throw StateError('Kein Teil-Download für $modelId/$fileName.');
    }
    // rename replaces an existing final file atomically (POSIX).
    await part.rename(_final(modelId, fileName).path);
  }

  @override
  Future<void> deletePartial(String modelId, String fileName) async {
    final part = _part(modelId, fileName);
    if (await part.exists()) await part.delete();
  }

  @override
  Future<void> deleteModel(String modelId) async {
    final dir = modelDir(modelId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Deletes the final file [fileName] of [modelId] (e.g. an archive after
  /// unpacking); no-op if missing.
  Future<void> deleteFile(String modelId, String fileName) async {
    final f = _final(modelId, fileName);
    if (await f.exists()) await f.delete();
  }

  /// Whether a partial download of any file of [model] exists.
  Future<bool> hasPartial(SpeechModel model) async {
    for (final f in model.files) {
      if (await partialLength(model.id, f.name) > 0) return true;
    }
    return false;
  }
}
