import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'saf_list_file_port.dart';

/// Picks a text file once (Android Storage Access Framework, Kotlin
/// `FilesChannel`) and returns its content; the grant is released right
/// after reading. Used to import the routing rules (JSON).
final class DocumentTextImport {
  /// Creates the importer; `channel` is injectable for tests.
  const DocumentTextImport({
    this._channel = const MethodChannel(filesChannelName),
  });

  final MethodChannel _channel;

  /// MIME types offered for a JSON import (some file managers report JSON
  /// as plain text or binary).
  static const jsonTypes = [
    'application/json',
    'text/plain',
    'application/octet-stream',
  ];

  /// Lets the user pick a file of [mimeTypes]; its UTF-8 text, or `null`
  /// if the user cancelled. Throws [PortException] if the file cannot be
  /// read.
  Future<String?> pick({List<String> mimeTypes = jsonTypes}) async {
    try {
      final uri = await _channel.invokeMethod<String>('openDocument', {
        'mimeTypes': mimeTypes,
      });
      if (uri == null) return null;
      try {
        final bytes = await _channel.invokeMethod<Uint8List>('read', {
          'uri': uri,
        });
        if (bytes == null) {
          throw const PortException(
            PortErrorKind.notFound,
            'Die Datei gibt es nicht (mehr).',
          );
        }
        return utf8.decode(bytes);
      } finally {
        await _channel.invokeMethod<void>('release', {'uri': uri});
      }
    } on FormatException {
      throw const PortException(
        PortErrorKind.failed,
        'Die Datei ist kein UTF-8-Text.',
      );
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'unsupported' => const PortException(
          PortErrorKind.unsupported,
          'Auf diesem Gerät gibt es keine Dateiauswahl.',
        ),
        'tooLarge' => const PortException(
          PortErrorKind.rejected,
          'Die Datei ist größer als 5 MB.',
        ),
        _ => PortException(
          PortErrorKind.failed,
          'Die Datei konnte nicht gelesen werden (${e.code}).',
        ),
      };
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Dateiauswahl ist auf diesem Gerät nicht verfügbar.',
      );
    }
  }
}
