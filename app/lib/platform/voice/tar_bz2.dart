import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart'
    show
        ArchiveException,
        BZip2Decoder,
        InputFileStream,
        InputMemoryStream,
        InputStream;
import 'package:meta/meta.dart';
import 'package:wendelin_voice/wendelin_voice.dart' show ArchiveRejected;

export 'package:wendelin_voice/wendelin_voice.dart' show ArchiveRejected;

/// One regular file or directory of a tar archive.
typedef TarEntry = ({String path, bool directory, Uint8List data});

/// Size of the pieces a file body is copied in (the only buffer that grows
/// with the entry, independent of its size).
const tarChunkBytes = 1 << 20;

/// Largest unpacked size accepted for an archive of [archiveBytes]: four
/// times the archive plus 16 MB (bzip2 on model files stays far below; this
/// is the same factor the free-space check uses, `requiredSpace`).
int unpackLimit(int archiveBytes) => archiveBytes * 4 + (16 << 20);

/// The body of the tar entry being read: [next] hands it out in pieces of
/// at most `chunkBytes`, so even a gigabyte file needs one small buffer.
final class TarBody {
  TarBody._(this._in, this.size, this._chunk) : remaining = size;
  final InputStream _in;
  final int _chunk;

  /// Size of the body in bytes.
  final int size;

  /// Bytes not yet handed out.
  int remaining;

  /// The next piece, or `null` when the body is used up. A truncated
  /// archive throws [ArchiveRejected].
  Uint8List? next() {
    if (remaining == 0) return null;
    final n = remaining < _chunk ? remaining : _chunk;
    final Uint8List piece;
    try {
      piece = _in.readBytes(n).toUint8List();
    } on ArchiveException {
      throw const ArchiveRejected(
        'Das Archiv ist beschädigt.',
        reason: 'corrupt',
      );
    }
    if (piece.length != n) {
      throw const ArchiveRejected(
        'Das Archiv ist beschädigt.',
        reason: 'corrupt',
      );
    }
    remaining -= n;
    return piece;
  }
}

/// Walks the tar stream [tar] (POSIX ustar and GNU) entry by entry and
/// rejects anything unsafe: absolute paths, `..` components, symbolic and
/// hard links, devices and FIFOs, and an unpacked size above [maxBytes]
/// (headers, bodies and padding count). Supports GNU long names (`L`) and
/// PAX `path` records; other PAX/GNU metadata is skipped.
///
/// [onEntry] must consume what it wants of the [TarBody]; the rest is
/// skipped. Memory stays at one header plus one chunk ([chunkBytes]).
///
/// Throws [ArchiveRejected].
void walkTar(
  InputStream tar, {
  required int maxBytes,
  required void Function(String path, bool directory, TarBody body) onEntry,
  int chunkBytes = tarChunkBytes,
}) {
  String? longName;
  var used = 0;
  Uint8List read(int n) {
    final Uint8List b;
    try {
      b = tar.readBytes(n).toUint8List();
    } on ArchiveException {
      throw const ArchiveRejected(
        'Das Archiv ist beschädigt.',
        reason: 'corrupt',
      );
    }
    return b;
  }

  while (!tar.isEOS) {
    final header = read(512);
    if (header.length < 512) break; // trailing garbage shorter than a block
    if (header.every((b) => b == 0)) break; // end of archive
    _checkChecksum(header);
    final size = _octal(header, 124, 12);
    final type = header[156];
    final padded = ((size + 511) ~/ 512) * 512;
    used += 512 + padded;
    if (size < 0) {
      throw const ArchiveRejected(
        'Das Archiv ist beschädigt.',
        reason: 'corrupt',
      );
    }
    if (used > maxBytes) {
      throw ArchiveRejected(
        'Das Archiv ist zu groß (mehr als ${maxBytes >> 20} MB entpackt).',
        reason: 'too-large',
      );
    }

    final body = TarBody._(tar, size, chunkBytes);
    switch (type) {
      case 0x4c || 0x78 || 0x67: // GNU long name, PAX header, global PAX
        final data = _readRecord(tar, size);
        _skipPadding(tar, padded - size);
        if (type == 0x4c) longName = _cString(data);
        if (type == 0x78) longName = _paxPath(data) ?? longName;
        continue;
    }

    final name = longName ?? _ustarName(header);
    longName = null;
    final directory = type == 0x35; // '5'
    if (type != 0 && type != 0x30 && !directory) {
      // '1' hard link, '2' symlink, '3'/'4' devices, '6' FIFO, …
      throw ArchiveRejected(
        'Das Archiv enthält einen nicht erlaubten Eintrag ($name).',
        reason: 'forbidden-entry',
      );
    }
    onEntry(safeRelativePath(name), directory, body);
    // Unread rest of the body and the padding.
    while (body.next() != null) {}
    _skipPadding(tar, padded - size);
  }
}

ArchiveRejected _corrupt() =>
    const ArchiveRejected('Das Archiv ist beschädigt.', reason: 'corrupt');

/// A small metadata record (long name, PAX): a huge one is not a name.
Uint8List _readRecord(InputStream tar, int size) {
  if (size > 1 << 20) throw _corrupt();
  final Uint8List data;
  try {
    data = tar.readBytes(size).toUint8List();
  } on ArchiveException {
    throw _corrupt();
  }
  if (data.length != size) throw _corrupt();
  return data;
}

void _skipPadding(InputStream tar, int n) {
  if (n <= 0) return;
  try {
    tar.skip(n);
  } on ArchiveException {
    throw const ArchiveRejected(
      'Das Archiv ist beschädigt.',
      reason: 'corrupt',
    );
  }
}

/// Reads the entries of a small tar archive in memory (see [walkTar] for
/// what is rejected); [unpackTarStream] is the way for model archives.
///
/// Throws [ArchiveRejected].
List<TarEntry> readTar(Uint8List tar) {
  final entries = <TarEntry>[];
  walkTar(
    InputMemoryStream(tar),
    maxBytes: 1 << 50, // a lying size fails on the truncated body
    onEntry: (path, directory, body) {
      final out = BytesBuilder(copy: false);
      for (var p = body.next(); p != null; p = body.next()) {
        out.add(p);
      }
      entries.add((path: path, directory: directory, data: out.takeBytes()));
    },
  );
  return entries;
}

/// [name] as a safe relative path (no leading `/`, no `..`, no empty or
/// `.` components after normalization). Throws [ArchiveRejected].
String safeRelativePath(String name) {
  if (name.startsWith('/') || name.contains('\\') || name.contains('\x00')) {
    throw ArchiveRejected(
      'Unsicherer Pfad im Archiv: $name',
      reason: 'unsafe-path',
    );
  }
  final parts = [
    for (final p in name.split('/'))
      if (p.isNotEmpty && p != '.') p,
  ];
  if (parts.isEmpty || parts.any((p) => p == '..')) {
    throw ArchiveRejected(
      'Unsicherer Pfad im Archiv: $name',
      reason: 'unsafe-path',
    );
  }
  return parts.join('/');
}

/// Unpacks the `.tar.bz2` [archive] into [target] safely and streaming
/// (file, bzip2, tar, files; memory independent of the archive size):
/// 1. the unpacked size is limited ([maxUnpackedBytes], default
///    [unpackLimit]) against bzip2 bombs,
/// 2. every entry is checked by [walkTar] before it is written,
/// 3. everything goes into a temporary sibling directory that is renamed to
///    [target] (an existing [target] is replaced only after success).
///
/// A file system error while writing (storage full, clashing entries)
/// becomes [ArchiveRejected] as well; nothing half-written stays.
///
/// The archive itself is left alone; the caller deletes it afterwards.
/// Runs in a background isolate. Returns the unpacked bytes (files).
/// Throws [ArchiveRejected] (its `reason` is a log code).
Future<int> extractTarBz2(
  File archive,
  Directory target, {
  int? maxUnpackedBytes,
}) {
  final archivePath = archive.path;
  final targetPath = target.path;
  return Isolate.run(
    () => unpackTarBz2(archivePath, targetPath, maxUnpackedBytes),
    debugName: 'untar',
  );
}

/// [extractTarBz2] in the calling isolate. [onChunk] sees the size of every
/// piece written (tests prove the bounded buffer with it).
@visibleForTesting
int unpackTarBz2(
  String archivePath,
  String targetPath,
  int? limit, {
  int chunkBytes = tarChunkBytes,
  void Function(int bytes)? onChunk,
}) {
  final input = InputFileStream(archivePath);
  try {
    final limitBytes = limit ?? unpackLimit(File(archivePath).lengthSync());
    final tar = BZip2Decoder().decodeLazy(input);
    return unpackTarStream(
      tar,
      targetPath,
      limitBytes,
      chunkBytes: chunkBytes,
      onChunk: onChunk,
    );
  } finally {
    input.closeSync();
  }
}

/// Unpacks the tar stream [tar] into [targetPath] via `<targetPath>.tmp`
/// (see [extractTarBz2]); returns the bytes of the files written.
@visibleForTesting
int unpackTarStream(
  InputStream tar,
  String targetPath,
  int limit, {
  int chunkBytes = tarChunkBytes,
  void Function(int bytes)? onChunk,
}) {
  final target = Directory(targetPath);
  final tmp = Directory('$targetPath.tmp');
  var written = 0;
  try {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    walkTar(
      tar,
      maxBytes: limit,
      chunkBytes: chunkBytes,
      onEntry: (path, directory, body) {
        final full = '${tmp.path}/$path';
        if (directory) {
          Directory(full).createSync(recursive: true);
          return;
        }
        final f = File(full)..parent.createSync(recursive: true);
        final sink = f.openSync(mode: FileMode.write);
        try {
          for (var p = body.next(); p != null; p = body.next()) {
            sink.writeFromSync(p);
            written += p.length;
            onChunk?.call(p.length);
          }
        } finally {
          sink.closeSync();
        }
      },
    );
    if (target.existsSync()) target.deleteSync(recursive: true);
    tmp.renameSync(targetPath);
    return written;
  } on FileSystemException catch (e) {
    // Full storage or entries that clash (a file where a folder must be):
    // nothing half-written stays, the caller discards the archive.
    _removeQuietly(tmp);
    throw ArchiveRejected(
      'Das Archiv ließ sich nicht entpacken (${e.osError?.message ?? e.message}).',
      reason: 'io',
    );
  } on ArchiveException {
    _removeQuietly(tmp);
    throw const ArchiveRejected(
      'Das Archiv ist beschädigt.',
      reason: 'corrupt',
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
    throw const ArchiveRejected(
      'Das Archiv ist beschädigt (Prüfsumme).',
      reason: 'corrupt',
    );
  }
}

int _octal(Uint8List h, int at, int len) {
  final s = String.fromCharCodes(
    h.sublist(at, at + len).takeWhile((b) => b != 0),
  ).trim();
  if (s.isEmpty) return 0;
  return int.tryParse(s, radix: 8) ??
      (throw const ArchiveRejected(
        'Das Archiv ist beschädigt.',
        reason: 'corrupt',
      ));
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
