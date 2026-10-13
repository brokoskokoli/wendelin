import 'dart:convert';

import '../src/common/port_exception.dart';
import '../src/obsidian/ports.dart';
import '../src/obsidian/vault_path.dart';
import 'fake_failures.dart';

/// In-memory [VaultPort]: [files] maps vault paths to content, [folders]
/// holds empty folders (folders of files exist implicitly). Tests change
/// [files] directly to simulate an edit by Obsidian or Syncthing; use
/// [touch] to also move the modification time.
final class FakeVaultPort with FakeFailures implements VaultPort {
  /// Creates the fake with initial [files]. Modification times start at
  /// [epoch] and advance by one second per write.
  FakeVaultPort({Map<String, String>? files, DateTime? epoch})
    : files = files ?? {},
      _tick = epoch ?? DateTime.utc(2026, 10, 1) {
    for (final p in this.files.keys) {
      modified[p] = _next();
    }
  }

  /// Current file contents by path.
  final Map<String, String> files;

  /// Explicit (empty) folders.
  final Set<String> folders = {};

  /// Modification times by path.
  final Map<String, DateTime> modified = {};

  /// Number of [write] and [create] calls.
  int writes = 0;

  /// Simulated I/O time per call (lets parallel calls interleave).
  Duration delay = Duration.zero;

  DateTime _tick;

  DateTime _next() => _tick = _tick.add(const Duration(seconds: 1));

  /// Sets [path] to [content] as an external program would (new
  /// modification time).
  void touch(String path, String content) {
    files[path] = content;
    modified[path] = _next();
  }

  Future<void> _io() => delay == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(delay);

  String _norm(String path) => VaultPath.normalize(path, allowRoot: true);

  bool _isFolder(String p) =>
      p.isEmpty ||
      folders.contains(p) ||
      folders.any((f) => f.startsWith('$p/')) ||
      files.keys.any((f) => f.startsWith('$p/'));

  PortException _notFound(String path) =>
      PortException(PortErrorKind.notFound, '„$path“ gibt es nicht');

  String _existing(String path) {
    final p = _norm(path);
    if (!files.containsKey(p)) throw _notFound(path);
    return p;
  }

  @override
  Future<List<VaultEntry>> list(String folder) async {
    enter('list');
    final p = _norm(folder);
    await _io();
    if (!_isFolder(p)) throw _notFound(folder);
    final prefix = p.isEmpty ? '' : '$p/';
    final result = <String, VaultEntry>{};
    for (final f in [...files.keys, ...folders]) {
      if (!f.startsWith(prefix)) continue;
      final rest = f.substring(prefix.length);
      final slash = rest.indexOf('/');
      final child = '$prefix${slash < 0 ? rest : rest.substring(0, slash)}';
      if (slash < 0 && files.containsKey(f)) {
        result[child] = VaultEntry(
          path: child,
          isFolder: false,
          modifiedAt: modified[f],
          size: utf8.encode(files[f]!).length,
        );
      } else {
        result[child] = VaultEntry(path: child, isFolder: true);
      }
    }
    return result.values.toList();
  }

  @override
  Future<String> read(String path) async {
    enter('read');
    final p = _existing(path);
    await _io();
    return files[p] ?? (throw _notFound(path));
  }

  @override
  Future<void> write(String path, String content) async {
    enter('write');
    final p = _norm(path);
    if (_isFolder(p)) {
      throw PortException(PortErrorKind.rejected, '„$path“ ist ein Ordner');
    }
    await _io();
    writes++;
    files[p] = content;
    modified[p] = _next();
  }

  @override
  Future<void> create(String path, String content) async {
    enter('create');
    final p = _norm(path);
    if (files.containsKey(p) || _isFolder(p)) {
      throw PortException(PortErrorKind.rejected, '„$path“ gibt es schon');
    }
    await _io();
    if (files.containsKey(p)) {
      throw PortException(PortErrorKind.rejected, '„$path“ gibt es schon');
    }
    writes++;
    files[p] = content;
    modified[p] = _next();
  }

  @override
  Future<void> delete(String path) async {
    enter('delete');
    final p = _existing(path);
    await _io();
    files.remove(p);
    modified.remove(p);
  }

  @override
  Future<bool> exists(String path) async {
    enter('exists');
    final p = _norm(path);
    await _io();
    return files.containsKey(p) || _isFolder(p);
  }

  @override
  Future<DateTime> modifiedAt(String path) async {
    enter('modifiedAt');
    final p = _existing(path);
    await _io();
    return modified[p] ?? (modified[p] = _next());
  }

  @override
  Future<int> size(String path) async {
    enter('size');
    final p = _existing(path);
    await _io();
    return utf8.encode(files[p] ?? (throw _notFound(path))).length;
  }
}
