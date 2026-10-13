import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Free space on the volume of a path (for the check before a model
/// download).
abstract interface class DiskSpace {
  /// Bytes available to the app at [path], or `null` if unknown.
  Future<int?> freeBytes(String path);
}

/// [DiskSpace] via libc `statvfs` (no plugin, no platform channel).
///
/// Only ABIs with a known `struct statvfs` layout are supported: 64-bit
/// Android/Linux and macOS. Elsewhere (32-bit Android) [freeBytes] returns
/// `null` and the download starts without the check.
final class StatvfsDiskSpace implements DiskSpace {
  /// Creates the probe.
  const StatvfsDiskSpace();

  @override
  Future<int?> freeBytes(String path) async {
    final layout = _layouts[Abi.current()];
    if (layout == null) return null;
    final int Function(Pointer<Utf8>, Pointer<Uint8>) statvfs;
    try {
      statvfs = DynamicLibrary.process()
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Uint8>),
            int Function(Pointer<Utf8>, Pointer<Uint8>)
          >('statvfs');
    } on ArgumentError {
      return null;
    }
    final cPath = path.toNativeUtf8();
    final buf = calloc<Uint8>(512);
    try {
      if (statvfs(cPath, buf) != 0) return null;
      final view = buf.asTypedList(512);
      final bytes = view.buffer.asByteData(view.offsetInBytes, 512);
      final frsize = bytes.getUint64(8, Endian.host);
      final avail = layout.wideBlocks
          ? bytes.getUint64(layout.bavailOffset, Endian.host)
          : bytes.getUint32(layout.bavailOffset, Endian.host);
      return frsize * avail;
    } finally {
      calloc
        ..free(cPath)
        ..free(buf);
    }
  }

  static const _lp64 = (bavailOffset: 32, wideBlocks: true);
  static const _darwin = (bavailOffset: 24, wideBlocks: false);
  static const _layouts = {
    Abi.androidArm64: _lp64,
    Abi.androidX64: _lp64,
    Abi.linuxArm64: _lp64,
    Abi.linuxX64: _lp64,
    Abi.macosArm64: _darwin,
    Abi.macosX64: _darwin,
  };
}

/// Space a download of [downloadBytes] needs: the files themselves, three
/// times an archive for unpacking (concept hand-over WP15) and a buffer of
/// 50 MB.
int requiredSpace(int downloadBytes, {required bool archive}) =>
    downloadBytes * (archive ? 4 : 1) + (50 << 20);
