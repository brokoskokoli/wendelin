// WP157 / ADR 0023: every shipped tool is classified on purpose as having a
// network target or not. Only web search, web fetch and the user-defined HTTP
// and MCP tools carry call arguments to a free network target; everything
// else is NoNetworkTarget. A new tool without the marker counts as network
// (fail-closed) and fails here until it is classified.
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/all_integrations.dart';

void main() {
  const networkTools = {'web__search', 'web__fetch'};

  test(
    'Katalog: NoNetworkTarget genau für alle außer Websuche/-abruf/HTTP',
    () {
      final all = allBuiltInIntegrations().values
          .expand((i) => i.tools)
          .toList();
      expect(all, isNotEmpty);
      expect(
        all.map((t) => t.name),
        containsAll(networkTools),
        reason: 'die Netz-Liste muss im Katalog vorkommen',
      );
      final wrong = <String>[];
      for (final t in all) {
        final expectNoNet = !(networkTools.contains(t.name) || t is HttpTool);
        if ((t is NoNetworkTarget) != expectNoNet) {
          wrong.add(
            '${t.name}: ${t is NoNetworkTarget ? 'ohne' : 'mit'} Netzziel',
          );
        }
      }
      expect(wrong, isEmpty, reason: 'Falsche Netzziel-Einstufung: $wrong');
    },
  );

  test('Websuche und -abruf sind nie vertraut (fest, nicht abschaltbar)', () {
    final all = allBuiltInIntegrations().values.expand((i) => i.tools);
    for (final t in all.where((t) => networkTools.contains(t.name))) {
      expect(t, isNot(isA<TrustedContentSource>()), reason: t.name);
      expect(t, isNot(isA<ContentTrustAware>()), reason: t.name);
    }
  });

  test('Zwischenablage lesen: kein Netzziel, aber fremder Inhalt', () {
    final t = allBuiltInIntegrations().values
        .expand((i) => i.tools)
        .firstWhere((t) => t.name == 'clipboard__read');
    expect(t, isA<NoNetworkTarget>());
    expect(t, isNot(isA<TrustedContentSource>()));
  });
}
