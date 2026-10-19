import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dateien, deren deutsche Texte bewusst bleiben, mit Begründung. Neue
/// Einträge nur mit Begründung (sichtbare Texte gehören nach
/// `lib/l10n/app_*.arb`, siehe docs/ENGINEERING.md „Texte“).
const _allowed = <String, String>{
  // Beispieldaten der Entwurfsgalerie und der Golden-Kompositionen.
  'lib/ui/design/gallery.dart': 'Beispieldaten der Galerie',
  'lib/ui/design/compositions.dart': 'Beispieldaten der Goldens',
  // Erkennungsmuster für Stufen-Meldungen, kein Anzeigetext.
  'lib/ui/attestation/attestation_texts.dart': 'Regex auf Pakettexte',
  // Gesprochen (Sprech-Sprache, nicht UI-Sprache) oder an das LLM.
  'lib/voice/confirm_prompts.dart': 'gesprochen',
  'lib/voice/locked_agent_run.dart': 'gesprochen (Sperrbildschirm)',
  'lib/voice/voice_components.dart': 'Beispielsatz für Vokabular/STT',
  'lib/agent/conversation_state.dart': 'gesprochener GPU-Hinweis',
  'lib/agent/new_topic_command.dart': 'Sprachbefehle und Muster',
  'lib/di/demo_provider.dart': 'skriptierte Antworten des Demo-Modus',
  // Meldungen an Log/Registry/LLM oder Rückfall für Pakettexte; die UI
  // zeigt dafür eigene ARB-Texte (z. B. nach VoiceErrorKind).
  'lib/agent/agent_controller.dart': 'interne Fehler, Log',
  'lib/di/agent_providers.dart': 'Statusmeldungen, Log',
  'lib/di/voice_providers.dart': 'VoiceException-Rückfalltexte',
  'lib/voice/primed_audio_input.dart': 'VoiceException-Rückfalltext',
  'lib/di/wake_providers.dart': 'VoiceException-Rückfalltext',
  'lib/di/voice_settings_providers.dart': 'debugPrint',
  'lib/di/vocabulary_provider.dart': 'Log',
  'lib/di/list_access.dart': 'Registry-Fehler, UI zeigt listsAccessLost',
  'lib/di/app_requirements.dart': 'Schlüsselkonstante, UI mappt sie',
  'lib/di/home_assistant.dart': 'Meldungen der Ports (Pakettexte)',
  'lib/di/preference_models.dart': 'FormatException, Log',
  'lib/di/weather_config.dart': 'FormatException, Log',
  'lib/di/mcp/mcp_secrets.dart': 'Fehlertext an Log',
  'lib/di/integrations/ha_spec.dart': 'Registry-Meldung, Rückfall',
  'lib/di/integrations/spotify_spec.dart': 'Registry-Meldung, Rückfall',
  'lib/di/integrations/location_spec.dart': 'Registry-Meldung, Rückfall',
  'lib/di/integrations/bring_spec.dart': 'Registry-Meldung, Rückfall',
  'lib/di/integrations/obsidian_spec.dart': 'Rückfall, UI mappt per Paket',
  'lib/di/integrations/calendar_spec.dart': 'Rückfall, UI nutzt ARB',
  'lib/voice/wake/wake_enroller.dart': 'StateError/toString, Log',
  'lib/voice/wake/wake_tester.dart': 'StateError, Log',
  'lib/voice/wake/wake_calibrator.dart': 'StateError, Log',
};

/// Verzeichnisse, in denen deutsche Texte nur mit Eintrag oben bleiben.
const _dirs = ['lib/ui', 'lib/agent', 'lib/di', 'lib/voice'];

final _german = RegExp(
  '[äöüßÄÖÜ]|\\b(der|die|das|und|nicht|Bitte|für|mit|wird|ist|kein|keine|'
  'Die|Das|Es|Ein|Eine|Kein|Du|Dein|Deine|zu|von|Ja|Nein)\\b',
);

// Ein Textliteral mit mindestens einem Leerzeichen (kein Bezeichner).
final _literal = RegExp('\'([^\'\\n]{4,})\'|"([^"\\n]{4,})"');

bool _skip(String line) {
  final s = line.trimLeft();
  return s.startsWith('//') ||
      s.startsWith('import ') ||
      s.startsWith('export ');
}

List<String> scan(String dir, {Set<String> allowed = const {}}) {
  final found = <String>[];
  for (final f in Directory(dir).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (allowed.contains(f.path)) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (_skip(lines[i])) continue;
      for (final m in _literal.allMatches(lines[i])) {
        final t = m[1] ?? m[2]!;
        if ((t.contains(' ') && _german.hasMatch(t)) ||
            RegExp('[äöüßÄÖÜ]').hasMatch(t)) {
          found.add('${f.path}:${i + 1}: $t');
        }
      }
    }
  }
  return found;
}

void main() {
  test('Whitelist verweist nur auf vorhandene Dateien', () {
    for (final p in _allowed.keys) {
      expect(File(p).existsSync(), isTrue, reason: p);
    }
  });

  test('lib/ui, lib/agent, lib/di, lib/voice: keine neuen deutschen Texte', () {
    final found = [
      for (final d in _dirs) ...scan(d, allowed: _allowed.keys.toSet()),
    ];
    expect(found, isEmpty, reason: 'Texte gehören in lib/l10n/app_*.arb');
  });

  test('der Scan erkennt yes:/no:/showHint(/const-Strings', () {
    final dir = Directory.systemTemp.createTempSync('scan');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/a.dart').writeAsStringSync(
      "const a = 'Das ist ein Test';\n"
      "x(yes: 'Ja, löschen', no: 'Nein, behalten');\n"
      "showHint(context, 'Die Datei ist weg');\n"
      "final b = 'ok';\n",
    );
    expect(scan(dir.path), hasLength(4));
  });
}
