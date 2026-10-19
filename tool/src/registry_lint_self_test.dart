// Selbsttests von src/registry_lint.dart.
import 'registry_lint.dart';
import 'self_check.dart';

const _reg = '''
import 'a_spec.dart';
import 'b_spec.dart';
import 'integration_spec.dart';

/// doc
final builtInIntegrationSpecs = <IntegrationSpec>[
  bSpec,
  aSpec,
];
''';

void registryLintChecks(SelfCheck t) {
  t.group('registry_lint');
  t.eq(lintRegistry(_reg, specFiles: {'a', 'b'}), <String>[], 'gültig');

  t.isTrue(
    lintRegistry(_reg.replaceFirst("import 'a_spec.dart';\n", ''))
        .any((p) => p.contains('aSpec ohne Import')),
    'Eintrag ohne Import',
  );
  t.isTrue(
    lintRegistry(_reg.replaceFirst('  aSpec,\n', ''))
        .any((p) => p.contains('a_spec.dart ohne Eintrag')),
    'Import ohne Eintrag',
  );
  t.isTrue(
    lintRegistry(_reg.replaceFirst('  aSpec,\n', '  foo(),\n'))
        .contains('Registry-Zeile nicht "  xSpec,": "  foo(),"'),
    'falsch geformte Registry-Zeile wird gemeldet',
  );
  final unsorted = _reg.replaceFirst(
    "import 'a_spec.dart';\nimport 'b_spec.dart';",
    "import 'b_spec.dart';\nimport 'a_spec.dart';",
  );
  t.isTrue(
    lintRegistry(unsorted).any((p) => p.contains('nicht sortiert')),
    'unsortierte Imports',
  );
  t.eq(lintRegistry(fixLists(unsorted)), <String>[], 'fix sortiert Imports');
  final dupImport = _reg.replaceFirst(
    "import 'b_spec.dart';",
    "import 'b_spec.dart';\nimport 'b_spec.dart';",
  );
  t.isTrue(
    lintRegistry(dupImport).any((p) => p.contains('doppelt')),
    'doppelter Import',
  );
  t.eq(lintRegistry(fixLists(dupImport)), <String>[], 'fix entfernt Doppelte');
  final dupEntry = _reg.replaceFirst('  aSpec,\n', '  aSpec,\n  aSpec,\n');
  t.isTrue(
    lintRegistry(dupEntry).any((p) => p.contains('Integration doppelt')),
    'doppelter Eintrag',
  );
  t.eq(lintRegistry(dedupeEntries(dupEntry)), <String>[], 'dedupe');
  t.isTrue(
    lintRegistry(
      _reg,
      specFiles: {'a', 'b', 'c'},
    ).any((p) => p.contains('c_spec.dart ist nicht importiert')),
    'Spec-Datei nicht importiert',
  );
  t.isTrue(
    lintRegistry(
      _reg,
      specFiles: {'a'},
    ).any((p) => p.contains('b_spec.dart existiert nicht')),
    'Import ohne Datei',
  );

  const barrel = "library;\n\nexport 'a.dart';\nexport 'b.dart';\n";
  t.eq(lintBarrel(barrel, exists: (_) => true), <String>[], 'Barrel gültig');
  t.isTrue(
    lintBarrel("export 'b.dart';\nexport 'a.dart';\n").isNotEmpty,
    'Barrel unsortiert',
  );
  t.isTrue(
    lintBarrel("export 'a.dart';\nexport 'a.dart';\n").isNotEmpty,
    'Barrel doppelt',
  );
  t.isTrue(
    lintBarrel(barrel, exists: (e) => e == 'a.dart').isNotEmpty,
    'Barrel Export ohne Datei',
  );
}
