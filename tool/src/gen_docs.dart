// Erzeugt die aus Code ableitbaren Dokumentdateien (für `tool/gen_docs.dart`
// und `tool/check_docs.dart`). Jede erzeugte Datei trägt einen Kopf mit dem
// Hinweis, sie nicht von Hand zu ändern.
import 'dart:io';

const _head =
    '<!-- ERZEUGT von tool/gen_docs.dart (tool/regen_generated.sh). '
    'Nicht von Hand ändern. -->\n\n';

/// Alle erzeugten Dateien: Pfad (relativ zum Root) → Inhalt.
Map<String, String> generateDocs([String root = '.']) => {
  'docs/architecture/generated/packages.md': _packages(root),
  'docs/architecture/generated/integrations.md': _integrations(root),
  'docs/testing/m5/README.md': _m5Index(root),
};

String _read(String root, String path) => File('$root/$path').readAsStringSync();

String _packages(String root) {
  final names = [
    for (final d in Directory('$root/packages').listSync())
      if (d is Directory && File('${d.path}/pubspec.yaml').existsSync())
        d.path.split('/').last,
  ]..sort();
  final all = names.toSet();
  final b = StringBuffer(_head)
    ..writeln('# Pakete und ihre Abhängigkeiten (erzeugt)')
    ..writeln()
    ..writeln(
      'Aus `packages/*/pubspec.yaml`: Beschreibung und Abhängigkeiten auf '
      'andere Workspace-Pakete. Die Regeln prüft `tool/check_deps.dart`; '
      'wichtige Typen stehen in [packages.md](../packages.md).',
    )
    ..writeln()
    ..writeln('| Paket | Beschreibung | Hängt ab von |')
    ..writeln('| --- | --- | --- |');
  for (final n in names) {
    final y = _read(root, 'packages/$n/pubspec.yaml');
    final desc = RegExp(r'^description:\s*(.+)$', multiLine: true)
            .firstMatch(y)
            ?.group(1)
            ?.trim() ??
        '';
    final deps = <String>{};
    final sec = RegExp(
      r'^dependencies:\n((?:[ \t].*\n?|\n)*)',
      multiLine: true,
    ).firstMatch(y)?.group(1) ?? '';
    for (final m in RegExp(r'^  (\w+):', multiLine: true).allMatches(sec)) {
      if (all.contains(m.group(1)) && m.group(1) != n) deps.add(m.group(1)!);
    }
    final d = (deps.toList()..sort()).map((e) => '`$e`').join(', ');
    b.writeln('| `$n` | $desc | ${d.isEmpty ? '–' : d} |');
  }
  return b.toString();
}

String _integrations(String root) {
  final reg = _read(root, 'app/lib/di/integrations/registry.dart');
  final ids = <String>[];
  for (final m in RegExp(r'^  (\w+Spec),', multiLine: true).allMatches(reg)) {
    ids.add(m.group(1)!);
  }
  // Spec-Variable → Datei über den Import `<name>_spec.dart`.
  final files = {
    for (final m in RegExp(r"^import '(\w+)_spec\.dart';", multiLine: true)
        .allMatches(reg))
      m.group(1)!: '${m.group(1)}_spec.dart',
  };
  final b = StringBuffer(_head)
    ..writeln('# Eingebaute Integrationen (erzeugt)')
    ..writeln()
    ..writeln(
      'Aus `app/lib/di/integrations/registry.dart` (Reihenfolge der '
      'Anzeige). Nicht ableitbare Angaben stehen je Integration in '
      '`docs/architecture/integrations/<id>.md`.',
    )
    ..writeln()
    ..writeln('| Id | Spec | Paketordner | Integrationsdoku |')
    ..writeln('| --- | --- | --- | --- |');
  for (final v in ids) {
    final key = v.substring(0, v.length - 4); // ohne "Spec"
    final file = files[key];
    if (file == null) continue;
    final spec = _read(root, 'app/lib/di/integrations/$file');
    final id = RegExp("id:\\s*'([^']+)'").firstMatch(spec)?.group(1) ?? key;
    final pkg = Directory(
      '$root/packages/wendelin_integrations/lib/src/$key',
    ).existsSync()
        ? '`packages/wendelin_integrations/lib/src/$key/`'
        : '–';
    final doc = File('$root/docs/architecture/integrations/$id.md')
            .existsSync()
        ? '[$id.md](../integrations/$id.md)'
        : '–';
    b.writeln('| `$id` | `app/lib/di/integrations/$file` | $pkg | $doc |');
  }
  return b.toString();
}

String _m5Index(String root) {
  final dir = Directory('$root/docs/testing/m5');
  final files = [
    for (final f in dir.listSync())
      if (f is File &&
          f.path.endsWith('.md') &&
          !f.path.endsWith('/README.md'))
        f.path.split('/').last,
  ]..sort();
  final b = StringBuffer(_head)
    ..writeln('# M5 auf dem Telefon testen (Geräte-Prüfliste)')
    ..writeln()
    ..writeln(
      'Jedes M5-Arbeitspaket legt hier seine eigene Datei `<wp>.md` an '
      '(Überschrift `# WPnn Titel`); dieser Index wird erzeugt '
      '(`tool/regen_generated.sh`). Befehle am Telefon führt nur der '
      'Maintainer aus.',
    )
    ..writeln();
  for (final f in files) {
    final title = RegExp(r'^# (.+)$', multiLine: true)
            .firstMatch(_read(root, 'docs/testing/m5/$f'))
            ?.group(1) ??
        f;
    b.writeln('- [$title]($f)');
  }
  return b.toString();
}

/// Schreibt die erzeugten Dateien und gibt die geänderten Pfade zurück.
List<String> writeGenerated([String root = '.']) {
  final changed = <String>[];
  for (final e in generateDocs(root).entries) {
    final f = File('$root/${e.key}');
    if (!f.existsSync() || f.readAsStringSync() != e.value) {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(e.value);
      changed.add(e.key);
    }
  }
  return changed;
}

/// Pfade erzeugter Dateien, die fehlen oder veraltet sind.
List<String> staleGenerated([String root = '.']) => [
  for (final e in generateDocs(root).entries)
    if (!File('$root/${e.key}').existsSync() ||
        File('$root/${e.key}').readAsStringSync() != e.value)
      e.key,
];
