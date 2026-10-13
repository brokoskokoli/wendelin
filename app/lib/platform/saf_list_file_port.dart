import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Name of the platform channel for files picked through the Android
/// Storage Access Framework (Kotlin side: `FilesChannel.kt`).
const filesChannelName = 'app.wendelin/files';

/// [ListFilePort] on SAF documents: the handle is the document URI with a
/// persisted read/write grant (taken by [DocumentPicker]).
///
/// Content travels as bytes and is decoded/encoded here as UTF-8, so line
/// endings, BOM and a missing final newline stay exactly as they are.
/// Writes use mode `wt` (truncate). Every call has a [timeout]; a hanging
/// provider becomes `PortException(unavailable)` instead of blocking the
/// list's write queue.
final class SafListFilePort implements ListFilePort {
  /// Creates the port; `channel` is injectable for tests.
  SafListFilePort({
    this._channel = const MethodChannel(filesChannelName),
    this.timeout = const Duration(seconds: 5),
  });

  final MethodChannel _channel;

  /// Limit per platform call.
  final Duration timeout;

  @override
  Future<String> read(String handle) async {
    final bytes = await _call<Uint8List>('read', {'uri': handle});
    if (bytes == null) throw _missing;
    try {
      return decodeUtf8KeepingBom(bytes);
    } on FormatException {
      throw const PortException(
        PortErrorKind.failed,
        'Die Listendatei ist kein UTF-8-Text.',
      );
    }
  }

  @override
  Future<void> write(String handle, String content) => _call<void>('write', {
    'uri': handle,
    'bytes': Uint8List.fromList(utf8.encode(content)),
  });

  @override
  Future<bool> exists(String handle) async =>
      await _call<bool>('exists', {'uri': handle}) ?? false;

  static const _missing = PortException(
    PortErrorKind.notFound,
    'Die Listendatei gibt es nicht (mehr).',
  );

  Future<T?> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args).timeout(timeout);
    } on TimeoutException {
      throw const PortException(
        PortErrorKind.unavailable,
        'Die Listendatei antwortet nicht.',
      );
    } on PlatformException catch (e) {
      throw portExceptionForFileError(e.code);
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Dateizugriff ist auf diesem Gerät nicht verfügbar.',
      );
    }
  }
}

/// UTF-8 text of [bytes]. Unlike `utf8.decode`, a leading byte order mark
/// is kept as U+FEFF, so writing the text back restores the file exactly.
String decodeUtf8KeepingBom(List<int> bytes) {
  final bom =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  return bom ? '\uFEFF${utf8.decode(bytes.sublist(3))}' : utf8.decode(bytes);
}

/// German [PortException] for a native file error [code].
PortException portExceptionForFileError(String code) => switch (code) {
  'notFound' => SafListFilePort._missing,
  'tooLarge' => const PortException(
    PortErrorKind.rejected,
    'Die Listendatei ist größer als 5 MB.',
  ),
  'unsupported' => const PortException(
    PortErrorKind.unsupported,
    'Auf diesem Gerät gibt es keine Dateiauswahl.',
  ),
  'permissionDenied' => const PortException(
    PortErrorKind.permissionDenied,
    'Kein Zugriff mehr auf die Listendatei. Bitte in den Einstellungen '
    'neu auswählen.',
  ),
  _ => const PortException(
    PortErrorKind.failed,
    'Die Listendatei konnte nicht gelesen oder geschrieben werden.',
  ),
};

/// Android file picker (SAF) for list files: open an existing document or
/// create a new one; both keep a persisted read/write grant.
final class DocumentPicker {
  /// Creates the picker; `channel` is injectable for tests.
  const DocumentPicker({this._channel = const MethodChannel(filesChannelName)});

  final MethodChannel _channel;

  /// Lets the user pick a Markdown or text file; `null` if cancelled.
  Future<String?> open() => _call('openDocument', const {});

  /// Lets the user create a file named [fileName]; `null` if cancelled.
  Future<String?> create(String fileName) =>
      _call('createDocument', {'name': fileName});

  /// Display name of [uri] (e.g. `Einkaufen.md`), or `null` if unknown.
  Future<String?> displayName(String uri) => _call('displayName', {'uri': uri});

  /// Whether a persisted read/write grant for [uri] is still held (it can
  /// be lost, e.g. after the file was moved or the app data restored).
  Future<bool> hasAccess(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('hasAccess', {'uri': uri}) ??
          false;
    } on PlatformException catch (e) {
      throw portExceptionForFileError(e.code);
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Dateiauswahl ist auf diesem Gerät nicht verfügbar.',
      );
    }
  }

  /// Gives up the persisted grant of [uri] (list deleted).
  Future<void> release(String uri) => _call('release', {'uri': uri});

  Future<String?> _call(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<String>(method, args);
    } on PlatformException catch (e) {
      throw portExceptionForFileError(e.code);
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Dateiauswahl ist auf diesem Gerät nicht verfügbar.',
      );
    }
  }
}
