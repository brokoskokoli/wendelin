// WP41 (fail-closed): every shipped tool is classified on purpose. Only a
// tool whose successful result contains nothing but own data (a confirmation
// of what was just set or saved) is a TrustedContentSource; everything else
// switches the invisible `<spoken>` text off.
//
// The expectation lives in one file per integration, `test/trust/<id>.json`
// (tool name -> trusted). A new integration adds its own file; no existing
// file and no list in a test changes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/all_integrations.dart';

void main() {
  final dir = Directory('test/trust');
  final files = {
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.json'))
        f.uri.pathSegments.last.replaceAll('.json', ''): f,
  };
  Map<String, Integration>? cache;
  Map<String, Integration> all() => cache ??= allBuiltInIntegrations();

  for (final spec in builtInIntegrationSpecs) {
    test('${spec.id}: jedes Tool ist eingestuft und stimmt', () {
      final i = all()[spec.id]!;
      final file = files[i.id];
      expect(
        file,
        isNotNull,
        reason:
            'Keine Vertrauens-Einstufung: lege app/test/trust/${i.id}.json '
            'an (Tool-Name -> true/false, fail-closed: im Zweifel false).',
      );
      final trusted = (jsonDecode(file!.readAsStringSync()) as Map)
          .cast<String, bool>();
      expect(i.tools.map((t) => t.name).toSet(), trusted.keys.toSet());
      for (final t in i.tools) {
        expect(
          t is TrustedContentSource,
          trusted[t.name],
          reason: '${t.name}: Einstufung (vertrauenswürdig) weicht ab',
        );
      }
    });
  }

  test('keine Einstufungsdatei ohne Integration', () {
    expect(
      files.keys.toSet().difference({
        for (final s in builtInIntegrationSpecs) s.id,
      }),
      isEmpty,
      reason: 'Verwaiste Datei in app/test/trust/',
    );
  });
}
