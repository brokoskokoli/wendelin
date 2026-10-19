// WP41 (fail-closed): every shipped tool is classified on purpose. Only a
// tool whose successful result contains nothing but own data (a confirmation
// of what was just set or saved) is a TrustedContentSource; everything else
// switches the invisible `<spoken>` text off. A new tool that is not in the
// table (`builtInIntegrationsWithFakes`, next to its integration) turns
// this test red.
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'http_tools/support.dart' as http_support;

void main() {
  final fixtures = builtInIntegrationsWithFakes();

  for (final f in fixtures) {
    test('${f.integration.id}: jedes Tool ist eingestuft und stimmt', () {
      final tools = f.integration.tools;
      expect(tools.map((t) => t.name).toSet(), f.trusted.keys.toSet());
      for (final t in tools) {
        expect(
          t is TrustedContentSource,
          f.trusted[t.name],
          reason: '${t.name}: Einstufung (vertrauenswürdig) weicht ab',
        );
      }
    });
  }

  test('HTTP-Tools sind nie vertrauenswürdig', () {
    final h = http_support.mockRunner((_) async => http.Response('', 200));
    final tool = HttpTool(http_support.def(), h.runner);
    expect(tool, isNot(isA<TrustedContentSource>()));
  });
}
