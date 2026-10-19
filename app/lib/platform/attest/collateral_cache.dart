import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wendelin_providers/wendelin_providers.dart';

/// Dateicache für Quote-Kollateral, gültig bis `nextUpdate` (je FMSPC/CA/TEE eine Datei).
final class CollateralCache {
  /// Erstellt den Cache in [dir]; [now] liefert die Uhrzeit.
  CollateralCache({required this.dir, required this.now});

  /// Ordner (wird bei Bedarf angelegt).
  final Directory dir;

  /// Uhr.
  final DateTime Function() now;

  File _file(String key) => File(
    '${dir.path}/collateral-${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json',
  );

  /// Eintrag zu [key], oder null, wenn keiner da, unlesbar oder abgelaufen ist.
  QuoteCollateral? read(String key) {
    try {
      final f = _file(key);
      if (!f.existsSync()) return null;
      final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final next = DateTime.parse(m['nextUpdate'] as String);
      final json = m['collateral'] as String;
      if (!now().isBefore(next)) return null;
      return QuoteCollateral(
        Uint8List.fromList(utf8.encode(json)),
        validUntil: next,
      );
    } on Object {
      return null;
    }
  }

  /// Speichert [c] atomar unter [key].
  void write(String key, QuoteCollateral c) {
    dir.createSync(recursive: true);
    final f = _file(key);
    final tmp = File('${f.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({
        'nextUpdate': c.validUntil!.toUtc().toIso8601String(),
        'collateral': utf8.decode(c.json),
      }),
      flush: true,
    );
    tmp.renameSync(f.path);
  }

  /// Löscht den Eintrag zu [key] (kein Fehler, wenn keiner da ist).
  void delete(String key) {
    try {
      final f = _file(key);
      if (f.existsSync()) f.deleteSync();
    } on Object {
      // Nur ein Cache.
    }
  }
}
