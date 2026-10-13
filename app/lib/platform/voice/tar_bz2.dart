import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart'
    show BZip2Decoder, InputMemoryStream, OutputMemoryStream;

/// Why unpacking failed.
final class ArchiveRejected implements Exception {
  /// Creates the error.
  const ArchiveRejected(this.message);

  /// German message for the user.
  final String message;

  @override
  String toString() => 'ArchiveRejected($message)';
}

/// One regular file or directory of a tar archive.
typedef TarEntry = ({String path, bool directory, Uint8List data});

/// Reads the entries of a tar archive (POSIX ustar and GNU) and rejects
/// anything unsafe: absolute paths, `..` components, symbolic and hard
/// links, devices and FIFOs. Supports GNU long names (`L`) and PAX `path`
/// records; other PAX/GNU metadata is skipped.
///
/// Throws [ArchiveRejected].
List<TarEntry> readTar(Uint8List tar) {
  final entries = <TarEntry>[];
  String? longName;
  var off = 0;
  while (off + 512 <= tar.length) {
    final header = Uint8List.sublistView(tar, off, off + 512);
    if (header.every((b) => b == 0)) break; // end of archive
    _checkChecksum(header);
    final size = _octal(header, 124, 12);
    final type = header[156];
    final body = off + 512;
    if (size < 0 || body + size > tar.length) {
      throw const ArchiveRejected('Das Archiv ist beschädigt.');
    }
    final data = Uint8List.sublistView(tar, body, body + size);
    off = body + ((size + 511) ~/ 512) * 512;

    switch (type) {
      case 0x4c: // 'L': GNU long name of the next entry
        longName = _cString(data);
        continue;
      case 0x78: // 'x': PAX header of the next entry
        longName = _paxPath(data) ?? longName;
        continue;
      case 0x67: // 'g': global PAX header
        continue;
    }

    final name = longName ?? _ustarName(header);
    longName = null;
    final directory = type == 0x35; // '5'
    if (type != 0 && type != 0x30 && !directory) {
      // '1' hard link, '2' symlink, '3'/'4' devices, '6' FIFO, …
      throw ArchiveRejected(
        'Das Archiv enthält einen nicht erlaubten Eintrag ($name).',
      );
    }
    entries.add((
      path: safeRelativePath(name),
      directory: directory,
      data: data,
    ));
  }
  return entries;
}

/// [name] as a safe relative path (no leading `/`, no `..`, no empty or
/// `.` components after normalization). Throws [ArchiveRejected].
String safeRelativePath(String name) {
  if (name.startsWith('/') || name.contains('\\') || name.contains('\x00')) {
    throw ArchiveRejected('Unsicherer Pfad im Archiv: $name');
  }
  final parts = [
    for (final p in name.split('/'))
      if (p.isNotEmpty && p != '.') p,
  ];
  if (parts.isEmpty || parts.any((p) => p == '..')) {
    throw ArchiveRejected('Unsicherer Pfad im Archiv: $name');
  }
  return parts.join('/');
}

/// Unpacks the `.tar.bz2` [archive] into [target] safely:
/// 1. decompress with a size limit ([maxUnpackedBytes], default four times
///    the archive plus 16 MB) against bzip2 bombs,
/// 2. check all entries with [readTar] before writing anything,
/// 3. write into a temporary sibling directory and rename it to [target]
///    (an existing [target] is replaced only after success).
///
/// A file system error while writing (storage full, clashing entries)
/// becomes [ArchiveRejected] as well; nothing half-written stays.
///
/// Memory: the whole archive and the unpacked tar are held in memory (a
/// Piper voice: 21 MB archive, 37 MB tar, so about 60 MB at peak).
///
/// The archive itself is left alone; the caller deletes it afterwards.
/// Runs in a background isolate. Throws [ArchiveRejected].
Future<void> extractTarBz2(
  File archive,
  Directory target, {
  int? maxUnpackedBytes,
}) {
  final archivePath = archive.path;
  final targetPath = target.path;
  return Isolate.run(
    () => _extract(archivePath, targetPath, maxUnpackedBytes),
    debugName: 'untar',
  );
}

void _extract(String archivePath, String targetPath, int? limit) {
  final compressed = File(archivePath).readAsBytesSync();
  final out = OutputMemoryStream();
  final bool ok;
  try {
    ok = BZip2Decoder().decodeStream(
      InputMemoryStream(compressed),
      out,
      maxOutputSize: limit ?? compressed.length * 4 + (16 << 20),
    );
  } on Object {
    throw const ArchiveRejected(
      'Das Archiv ist zu groß oder beschädigt und wurde nicht entpackt.',
    );
  }
  if (!ok) throw const ArchiveRejected('Das Archiv ist beschädigt.');
  final entries = readTar(out.getBytes());

  final target = Directory(targetPath);
  final tmp = Directory('$targetPath.tmp');
  try {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    for (final e in entries) {
      final path = '${tmp.path}/${e.path}';
      if (e.directory) {
        Directory(path).createSync(recursive: true);
      } else {
        final f = File(path)..parent.createSync(recursive: true);
        f.writeAsBytesSync(e.data, flush: false);
      }
    }
    if (target.existsSync()) target.deleteSync(recursive: true);
    tmp.renameSync(targetPath);
  } on FileSystemException catch (e) {
    // Full storage or entries that clash (a file where a folder must be):
    // nothing half-written stays, the caller discards the archive.
    _removeQuietly(tmp);
    throw ArchiveRejected(
      'Das Archiv ließ sich nicht entpacken (${e.osError?.message ?? e.message}).',
    );
  } on Object {
    _removeQuietly(tmp);
    rethrow;
  }
}

void _removeQuietly(Directory d) {
  try {
    if (d.existsSync()) d.deleteSync(recursive: true);
  } on FileSystemException {
    // Left for the next attempt, which deletes it first.
  }
}

void _checkChecksum(Uint8List h) {
  final stored = _octal(h, 148, 8);
  var sum = 0;
  for (var i = 0; i < 512; i++) {
    sum += (i >= 148 && i < 156) ? 0x20 : h[i];
  }
  if (stored != sum) {
    throw const ArchiveRejected('Das Archiv ist beschädigt (Prüfsumme).');
  }
}

int _octal(Uint8List h, int at, int len) {
  final s = String.fromCharCodes(
    h.sublist(at, at + len).takeWhile((b) => b != 0),
  ).trim();
  if (s.isEmpty) return 0;
  return int.tryParse(s, radix: 8) ??
      (throw const ArchiveRejected('Das Archiv ist beschädigt.'));
}

String _cString(Uint8List b) =>
    utf8.decode(b.takeWhile((c) => c != 0).toList(), allowMalformed: true);

String _ustarName(Uint8List h) {
  final name = _cString(Uint8List.sublistView(h, 0, 100));
  final magic = String.fromCharCodes(h.sublist(257, 262));
  if (magic == 'ustar' && h[262] == 0) {
    // POSIX ustar: prefix field.
    final prefix = _cString(Uint8List.sublistView(h, 345, 500));
    if (prefix.isNotEmpty) return '$prefix/$name';
  }
  return name;
}

String? _paxPath(Uint8List data) {
  // Records: "<len> <key>=<value>\n".
  final text = utf8.decode(data, allowMalformed: true);
  for (final line in const LineSplitter().convert(text)) {
    final m = RegExp(r'^\d+ path=(.*)$').firstMatch(line);
    if (m != null) return m[1];
  }
  return null;
}
