import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../common/port_exception.dart';
import 'ports.dart';
import 'vault_path.dart';

/// [VaultPort] on a local directory (`dart:io`): desktop, tests and
/// platforms with direct file access. Symbolic links are followed only
/// while they stay inside the vault; links leading outside are not listed
/// and rejected on access.
final class FileSystemVaultPort implements VaultPort {
  /// Creates the port on the existing directory [root].
  FileSystemVaultPort(Directory root)
    : _root = root.absolute.resolveSymbolicLinksSync();

  final String _root;
  final Random _random = Random();

  String _full(String path) {
    final p = VaultPath.normalize(path, allowRoot: true);
    return p.isEmpty ? _root : '$_root/$p';
  }

  bool _inside(String resolved) =>
      resolved == _root || resolved.startsWith('$_root/');

  /// [path] as absolute file system path, after checking that it and its
  /// deepest existing ancestor resolve inside the vault.
  String _checked(String path) {
    final full = _full(path);
    var probe = full;
    while (FileSystemEntity.typeSync(probe, followLinks: false) ==
        FileSystemEntityType.notFound) {
      if (probe == _root) break;
      probe = File(probe).parent.path;
    }
    final String resolved;
    try {
      resolved = File(probe).resolveSymbolicLinksSync();
    } on FileSystemException {
      throw PortException(
        PortErrorKind.rejected,
        'Pfad „$path“: Verknüpfung ohne Ziel',
      );
    }
    if (!_inside(resolved)) {
      throw PortException(
        PortErrorKind.rejected,
        'Pfad „$path“ führt aus dem Vault hinaus (Verknüpfung)',
      );
    }
    return full;
  }

  PortException _notFound(String path) =>
      PortException(PortErrorKind.notFound, '„$path“ gibt es nicht');

  File _file(String path) {
    final full = _checked(path);
    if (!FileSystemEntity.isFileSync(full)) throw _notFound(path);
    return File(full);
  }

  @override
  Future<List<VaultEntry>> list(String folder) async {
    final full = _checked(folder);
    if (!FileSystemEntity.isDirectorySync(full)) throw _notFound(folder);
    final base = VaultPath.normalize(folder, allowRoot: true);
    final result = <VaultEntry>[];
    for (final e in Directory(full).listSync(followLinks: false)) {
      final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final path = VaultPath.join(base, name);
      var type = FileSystemEntity.typeSync(e.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        try {
          if (!_inside(e.resolveSymbolicLinksSync())) continue;
        } on FileSystemException {
          continue;
        }
        type = FileSystemEntity.typeSync(e.path);
      }
      if (type == FileSystemEntityType.directory) {
        result.add(VaultEntry(path: path, isFolder: true));
      } else if (type == FileSystemEntityType.file) {
        final stat = File(e.path).statSync();
        result.add(
          VaultEntry(
            path: path,
            isFolder: false,
            modifiedAt: stat.modified,
            size: stat.size,
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<String> read(String path) async {
    final bytes = _file(path).readAsBytesSync();
    // utf8.decode verwirft eine BOM am Anfang; sie gehört zum Inhalt.
    final bom =
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    final text = utf8.decode(
      bom ? bytes.sublist(3) : bytes,
      allowMalformed: true,
    );
    return bom ? '\uFEFF$text' : text;
  }

  @override
  Future<void> write(String path, String content) async {
    final full = _checked(path);
    if (FileSystemEntity.isDirectorySync(full)) {
      throw PortException(PortErrorKind.rejected, '„$path“ ist ein Ordner');
    }
    final target = File(full);
    final before = target.existsSync() ? target.lastModifiedSync() : null;
    target.parent.createSync(recursive: true);
    final tmp = File(
      '${target.parent.path}/.${VaultPath.name(full)}.'
      'wendelin-${_random.nextInt(1 << 32)}.tmp',
    );
    try {
      tmp.writeAsBytesSync(utf8.encode(content), flush: true);
      tmp.renameSync(full);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
    // Grobe Zeitstempel (1 s auf manchen Dateisystemen): modifiedAt muss
    // sich trotzdem bei jedem Schreiben ändern.
    if (before != null && !target.lastModifiedSync().isAfter(before)) {
      target.setLastModifiedSync(before.add(const Duration(seconds: 1)));
    }
  }

  @override
  Future<void> create(String path, String content) async {
    final full = _checked(path);
    final file = File(full);
    file.parent.createSync(recursive: true);
    try {
      file.createSync(exclusive: true);
    } on FileSystemException {
      throw PortException(PortErrorKind.rejected, '„$path“ gibt es schon');
    }
    file.writeAsBytesSync(utf8.encode(content), flush: true);
  }

  @override
  Future<void> delete(String path) async => _file(path).deleteSync();

  @override
  Future<bool> exists(String path) async {
    final full = _checked(path);
    return FileSystemEntity.typeSync(full) != FileSystemEntityType.notFound;
  }

  @override
  Future<DateTime> modifiedAt(String path) async =>
      _file(path).lastModifiedSync();

  @override
  Future<int> size(String path) async => _file(path).lengthSync();
}
