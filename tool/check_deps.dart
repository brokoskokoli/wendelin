// Prüft die Abhängigkeitsregeln aus docs/ENGINEERING.md.
//
// - pubspec-Abhängigkeiten zwischen den Workspace-Paketen
// - keine Flutter-Imports in packages/
// - keine Provider-spezifischen Imports außerhalb der Adapter
import 'dart:io';

const allowed = <String, Set<String>>{
  'wendelin_core': {},
  'wendelin_providers': {'wendelin_core'},
  'wendelin_tools': {'wendelin_core'},
  'wendelin_agent': {'wendelin_core'},
  'wendelin_storage': {'wendelin_core'},
  'wendelin_integrations': {'wendelin_core'},
  'wendelin_voice': {'wendelin_core', 'wendelin_agent'},
  'wendelin_mcp': {'wendelin_core', 'wendelin_integrations'},
  'wendelin_evals': {
    'wendelin_core',
    'wendelin_providers',
    'wendelin_tools',
    'wendelin_agent',
    'wendelin_integrations',
  },
};

const forbiddenInPackages = [
  'package:flutter/',
  'package:flutter_test/',
  'dart:ui',
  'package:riverpod',
  'package:flutter_riverpod',
];

void main() {
  final errors = <String>[];
  final root = Directory.current;

  for (final entry in allowed.entries) {
    final dir = entry.key == 'wendelin_evals'
        ? Directory('${root.path}/evals')
        : Directory('${root.path}/packages/${entry.key}');
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final deps = _workspaceDeps(pubspec.readAsStringSync());
    for (final dep in deps) {
      if (!entry.value.contains(dep)) {
        errors.add('${entry.key}: Abhängigkeit auf $dep nicht erlaubt');
      }
    }
    if (entry.key == 'wendelin_evals') continue;
    for (final file in _dartFiles(dir)) {
      final text = file.readAsStringSync();
      for (final f in forbiddenInPackages) {
        if (text.contains("'$f") || text.contains('"$f')) {
          errors.add('${file.path}: Import "$f" in reinem Dart-Paket');
        }
      }
      for (final dep in allowed.keys) {
        if (dep == entry.key || entry.value.contains(dep)) continue;
        if (text.contains("'package:$dep/")) {
          errors.add('${file.path}: Import von $dep nicht erlaubt');
        }
      }
    }
  }

  // Provider-JSON nur innerhalb der Adapter: einfache Heuristik auf
  // typische Wire-Format-Schlüssel außerhalb von wendelin_providers/lib/src/{anthropic,openai}.
  final wireMarkers = [
    "'input_json_delta'",
    "'content_block_delta'",
    "'tool_calls'",
    "'finish_reason'",
  ];
  for (final file in _dartFiles(
    Directory('${root.path}/packages'),
  ).followedBy(_dartFiles(Directory('${root.path}/app/lib')))) {
    final p = file.path;
    if (p.contains('/wendelin_providers/lib/src/anthropic/') ||
        p.contains('/wendelin_providers/lib/src/openai/') ||
        p.contains('/test/')) {
      continue;
    }
    final text = file.readAsStringSync();
    for (final m in wireMarkers) {
      if (text.contains(m)) {
        errors.add('$p: Provider-Wire-Format $m außerhalb der Adapter');
      }
    }
  }

  // K7: keine Google Play Services / Firebase.
  final appPubspec = File('${root.path}/app/pubspec.yaml');
  final gradle = File('${root.path}/app/android/app/build.gradle.kts');
  for (final f in [appPubspec, gradle]) {
    if (!f.existsSync()) continue;
    final t = f.readAsStringSync();
    for (final m in [
      'firebase',
      'com.google.android.gms',
      'google_mobile_ads',
      'play-services',
    ]) {
      if (t.contains(m)) {
        errors.add('${f.path}: "$m" verletzt K7 (ohne Google-Dienste)');
      }
    }
  }

  if (errors.isEmpty) {
    stdout.writeln('check_deps: ok');
  } else {
    errors.forEach(stderr.writeln);
    exitCode = 1;
  }
}

Set<String> _workspaceDeps(String pubspec) {
  final result = <String>{};
  var inDeps = false;
  for (final line in pubspec.split('\n')) {
    if (RegExp(r'^dependencies:\s*$').hasMatch(line)) {
      inDeps = true;
      continue;
    }
    if (RegExp(r'^\S').hasMatch(line)) inDeps = false;
    if (!inDeps) continue;
    final m = RegExp(r'^\s{2}(wendelin_\w+)\s*:').firstMatch(line);
    if (m != null) result.add(m.group(1)!);
  }
  return result;
}

Iterable<File> _dartFiles(Directory dir) sync* {
  if (!dir.existsSync()) return;
  for (final e in dir.listSync(recursive: true)) {
    if (e is File &&
        e.path.endsWith('.dart') &&
        !e.path.contains('/.dart_tool/') &&
        !e.path.contains('/build/')) {
      yield e;
    }
  }
}
