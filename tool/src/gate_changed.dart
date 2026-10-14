// Paketauswahl für `dart run tool/gate.dart --changed`.
//
// Aus den geänderten Pfaden (relativ zum Repo-Root) wird abgeleitet,
// welche Pakete das Gate prüft: die geänderten selbst und alle, die
// transitiv von ihnen abhängen. Die Abhängigkeiten sind die Vereinigung
// der Erlaubnisliste in `tool/check_deps.dart` und der echten Kanten aus
// den pubspecs (inklusive `dev_dependencies`), also eher zu viel als zu
// wenig geprüft.
import 'dart:io';

import '../check_deps.dart' show allowed, pubspecWorkspaceDeps;

/// Name der Flutter-App in der Auswahl.
const appTarget = 'app';

/// Name des Eval-Pakets in der Auswahl (Ordner `evals/`).
const evalsTarget = 'evals';

/// Dateien, deren Änderung das ganze Gate auslöst.
const _fullGatePaths = {
  'pubspec.yaml',
  'pubspec.lock',
  'analysis_options.yaml',
  'tool/gate.dart',
  'tool/check_deps.dart',
};

/// Abhängigkeiten je Prüfziel (Ordnername unter `packages/`, `evals`,
/// `app`): [allowed] vereinigt mit den Workspace-Kanten der pubspecs
/// ([pubspecs]: Paketname → Inhalt, Standard: von der Platte gelesen).
/// Die App hängt von allen Paketen ab.
Map<String, Set<String>> workspaceDeps({Map<String, String>? pubspecs}) {
  String target(String name) => name == 'wendelin_evals' ? evalsTarget : name;
  final texts = pubspecs ?? _readPubspecs();
  final deps = <String, Set<String>>{};
  for (final name in {...allowed.keys, ...texts.keys}) {
    deps[target(name)] = {
      ...?allowed[name],
      ...pubspecWorkspaceDeps(texts[name] ?? ''),
    }.map(target).toSet();
  }
  deps[appTarget] = {
    for (final k in deps.keys)
      if (k != evalsTarget) k,
  };
  return deps;
}

Map<String, String> _readPubspecs() => {
  for (final name in allowed.keys)
    if (File(_pubspecPath(name)) case final f when f.existsSync())
      name: f.readAsStringSync(),
};

String _pubspecPath(String name) => name == 'wendelin_evals'
    ? 'evals/pubspec.yaml'
    : 'packages/$name/pubspec.yaml';

/// Geänderte Pfade seit dem Merge-Base mit [base], inklusive nicht
/// committeter und neuer (nicht ignorierter) Dateien. [git] liefert die
/// Ausgabe eines Git-Befehls (austauschbar für die Selbsttests) und wirft
/// bei einem Fehler.
List<String> changedPaths(String base, String Function(List<String>) git) {
  final mergeBase = git(['merge-base', base, 'HEAD']).trim();
  return {
    ...git(['diff', '--name-only', '--no-renames', '-z', mergeBase])
        .split('\x00'),
    ...git(['ls-files', '--others', '--exclude-standard', '-z']).split('\x00'),
  }.where((p) => p.isNotEmpty).toList()..sort();
}

/// Ergebnis der Auswahl.
final class Selection {
  /// Erstellt eine Auswahl.
  const Selection({
    this.fullReason,
    this.targets = const {},
    this.tooling = false,
  });

  /// Gesetzt, wenn das ganze Gate laufen muss (Grund).
  final String? fullReason;

  /// Prüfziele mit Grund, z. B. `wendelin_voice: hängt von wendelin_agent ab`.
  final Map<String, String> targets;

  /// `tool/` wurde geändert: Format, Analyse und Selbsttests der Werkzeuge.
  final bool tooling;

  /// Nur die globalen Prüfungen (Secrets, Abhängigkeiten, Größen, Doku).
  bool get globalOnly => fullReason == null && targets.isEmpty && !tooling;
}

/// Ordnet einen geänderten Pfad ein: `*` (alles), `doc`, `tool`, `global`
/// oder ein Prüfziel (Paketname, `evals`, `app`).
String classifyPath(String path, Set<String> knownTargets) {
  final p = path.startsWith('./') ? path.substring(2) : path;
  if (_fullGatePaths.contains(p) || p.startsWith('tool/src/gate_')) return '*';
  // Rust-Crate (WP47): Cargo, Quellen und Tests laufen nur im vollen Gate.
  if (p.startsWith('native/')) return '*';
  final segs = p.split('/');
  // Unter docs/ ist nur Markdown reine Doku. Andere Dateien lesen Tests
  // (z. B. docs/design/tokens.json in app/test/ui/tokens_test.dart).
  if (p.startsWith('docs/') && !p.endsWith('.md')) {
    return p.startsWith('docs/design/') ? appTarget : '*';
  }
  final isDoc =
      (p.endsWith('.md') &&
      !segs.contains('test') &&
      !segs.contains('lib') &&
      !segs.contains('integration_test'));
  if (isDoc) return 'doc';
  if (segs.length > 2 && segs.first == 'packages') {
    return knownTargets.contains(segs[1]) ? segs[1] : '*';
  }
  if (segs.first == 'evals' && segs.length > 1) return evalsTarget;
  if (segs.first == 'app' && segs.length > 1) return appTarget;
  if (segs.first == 'tool' && segs.length > 1) return 'tool';
  return 'global';
}

/// Wählt aus [changed] die Prüfziele samt aller transitiv abhängigen.
Selection selectChanged(
  Iterable<String> changed,
  Map<String, Set<String>> deps,
) {
  final direct = <String>{};
  var tooling = false;
  for (final path in changed) {
    final c = classifyPath(path, deps.keys.toSet());
    switch (c) {
      case '*':
        return Selection(fullReason: '$path geändert', tooling: true);
      case 'doc' || 'global':
        break;
      case 'tool':
        tooling = true;
      default:
        direct.add(c);
    }
  }
  final targets = <String, String>{
    for (final d in direct.toList()..sort()) d: 'geändert',
  };
  // Transitiv abhängige Ziele, Grund ist das erste (sortiert) geänderte
  // Paket, von dem sie abhängen.
  final names = deps.keys.toList()..sort();
  for (final name in names) {
    if (targets.containsKey(name)) continue;
    final closure = _closure(name, deps);
    final via = (direct.toList()..sort()).where(closure.contains);
    if (via.isNotEmpty) targets[name] = 'hängt von ${via.first} ab';
  }
  return Selection(targets: targets, tooling: tooling);
}

Set<String> _closure(String name, Map<String, Set<String>> deps) {
  final seen = <String>{};
  final todo = [...?deps[name]];
  while (todo.isNotEmpty) {
    final d = todo.removeLast();
    if (seen.add(d)) todo.addAll(deps[d] ?? const {});
  }
  return seen;
}
