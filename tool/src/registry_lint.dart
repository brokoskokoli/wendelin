// Listendisziplin für die Dateien, die je Integration wachsen (konfliktfreies
// Mergen per `merge=union`, siehe .gitattributes): Registry-Imports und
// Barrel-Exports stehen einzeln pro Zeile, sortiert und ohne Doppelte; jede
// Registry-Zeile hat ihren Import und umgekehrt.
import 'dart:io';

const registryPath = 'app/lib/di/integrations/registry.dart';
const barrelPath =
    'packages/wendelin_integrations/lib/wendelin_integrations.dart';

final _import = RegExp(r"^import '([a-z0-9_]+)_spec\.dart';$");
final _export = RegExp(r"^export '([^']+)';$");
final _entry = RegExp(r'^  ([a-z][A-Za-z0-9]*)Spec,$');

String _snake(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

/// Befunde der Registry-Datei. [specFiles]: vorhandene `*_spec.dart` im
/// Ordner (ohne `integration_spec`), `null` überspringt die Dateiprüfung.
List<String> lintRegistry(String text, {Set<String>? specFiles}) {
  final lines = text.split('\n');
  final imports = [
    for (final l in lines)
      if (_import.firstMatch(l) case final m?) m[1]!,
  ];
  final problems = <String>[];
  _sortedUnique(imports, 'Import in registry.dart', problems);
  final start = lines.indexWhere((l) => l.contains('builtInIntegrationSpecs'));
  final entries = <String>[];
  for (final l in start < 0 ? <String>[] : lines.sublist(start + 1)) {
    if (l.trim() == '];') break;
    final m = _entry.firstMatch(l);
    if (m == null) {
      problems.add('Registry-Zeile nicht "  xSpec,": "$l"');
    } else {
      entries.add(_snake(m[1]!));
    }
  }
  if (start < 0) problems.add('builtInIntegrationSpecs nicht gefunden');
  final dup = {
    for (final e in entries)
      if (entries.where((x) => x == e).length > 1) e,
  };
  for (final d in dup) {
    problems.add('Integration doppelt in der Liste: ${d}Spec');
  }
  final imp = imports.toSet()..remove('integration');
  for (final e in entries.toSet().difference(imp)) {
    problems.add('${e}Spec ohne Import');
  }
  for (final i in imp.difference(entries.toSet())) {
    problems.add('Import ${i}_spec.dart ohne Eintrag in der Liste');
  }
  if (specFiles != null) {
    for (final i in imp.difference(specFiles)) {
      problems.add('${i}_spec.dart existiert nicht');
    }
    for (final f in specFiles.difference(imp)) {
      problems.add('${f}_spec.dart ist nicht importiert');
    }
  }
  return problems;
}

/// Befunde des Barrels: Export-Zeilen sortiert, ohne Doppelte.
List<String> lintBarrel(String text, {bool Function(String)? exists}) {
  final exports = [
    for (final l in text.split('\n'))
      if (_export.firstMatch(l) case final m?) m[1]!,
  ];
  final problems = <String>[];
  _sortedUnique(exports, 'Export im Barrel', problems);
  if (exists != null) {
    for (final e in exports.where((e) => !exists(e))) {
      problems.add('Export $e zeigt auf keine Datei');
    }
  }
  return problems;
}

void _sortedUnique(List<String> items, String what, List<String> out) {
  for (var i = 1; i < items.length; i++) {
    if (items[i] == items[i - 1]) {
      out.add('$what doppelt: ${items[i]}');
    } else if (items[i].compareTo(items[i - 1]) < 0) {
      out.add('$what nicht sortiert: ${items[i]} steht hinter ${items[i - 1]}');
    }
  }
  final seen = <String>{};
  for (final i in items) {
    if (!seen.add(i) && !out.any((p) => p.endsWith(': $i'))) {
      out.add('$what doppelt: $i');
    }
  }
}

/// Sortiert zusammenhängende Import- bzw. Export-Blöcke und entfernt Doppelte
/// (Reparatur nach einem `merge=union`, der beide Seiten hintereinanderlegt).
String fixLists(String text) {
  final lines = text.split('\n');
  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    final isItem = _import.hasMatch(lines[i]) || _export.hasMatch(lines[i]);
    if (!isItem) {
      out.add(lines[i++]);
      continue;
    }
    final block = <String>[];
    while (i < lines.length &&
        (_import.hasMatch(lines[i]) || _export.hasMatch(lines[i]))) {
      block.add(lines[i++]);
    }
    out.addAll(block.toSet().toList()..sort());
  }
  return out.join('\n');
}

/// Gleiche Registry-Zeilen nur einmal (Reihenfolge = Anzeigereihenfolge bleibt).
String dedupeEntries(String text) {
  final seen = <String>{};
  var inList = false;
  final out = <String>[];
  for (final l in text.split('\n')) {
    if (l.contains('builtInIntegrationSpecs')) inList = true;
    if (inList && _entry.hasMatch(l) && !seen.add(l)) continue;
    if (inList && l.trim() == '];') inList = false;
    out.add(l);
  }
  return out.join('\n');
}

/// CLI: `dart run tool/check_registry.dart [--fix]` aus der Repo-Wurzel.
int runRegistryCheck({bool fix = false}) {
  final reg = File(registryPath), bar = File(barrelPath);
  if (fix) {
    reg.writeAsStringSync(dedupeEntries(fixLists(reg.readAsStringSync())));
    bar.writeAsStringSync(fixLists(bar.readAsStringSync()));
  }
  final dir = reg.parent;
  final files = {
    for (final f in dir.listSync().whereType<File>())
      if (f.uri.pathSegments.last.endsWith('_spec.dart') &&
          f.uri.pathSegments.last != 'integration_spec.dart')
        f.uri.pathSegments.last.replaceFirst('_spec.dart', ''),
  };
  final p = [
    for (final s in lintRegistry(reg.readAsStringSync(), specFiles: files))
      '$registryPath: $s',
    for (final s in lintBarrel(
      bar.readAsStringSync(),
      exists: (e) => File('${bar.parent.path}/$e').existsSync(),
    ))
      '$barrelPath: $s',
  ];
  if (p.isEmpty) {
    stdout.writeln('check_registry: ok');
    return 0;
  }
  p.forEach(stderr.writeln);
  stderr.writeln(
    'check_registry: ${p.length} Befund(e); `dart run tool/check_registry.dart --fix` sortiert Imports/Exports.',
  );
  return 1;
}
