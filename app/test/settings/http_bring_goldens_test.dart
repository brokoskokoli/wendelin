import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/http_tool_editor_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/http_tools_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;

void main() {
  testWidgets('Golden HTTP-Tool-Editor', tags: ['golden'], (tester) async {
    final env = TestEnv();
    final tool = testHttpTool(risk: RiskLevel.write, autoRun: true);
    await storeHttpTools(env, [tool]);
    setView(tester, const Size(390, 2600));
    await tester.pumpWidget(
      env.app(
        home: RepaintBoundary(
          key: goldenKey,
          child: HttpToolEditorScreen(definition: tool),
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('$redactedSecret gespeichert'), findsOneWidget);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/http_tool_editor.png'),
    );
  });

  testWidgets('Golden Testergebnis', tags: ['golden'], (tester) async {
    final result = HttpToolTestResult(
      status: 200,
      duration: const Duration(milliseconds: 142),
      preview: '{"entity_id":"light.bad","state":"on"}',
      request: SentRequest(
        method: 'POST',
        url: Uri.parse('https://ha.example.org/api/services/light/turn_on'),
        headers: const {
          'Content-Type': 'application/json; charset=utf-8',
          'X-Api-Key': redactedSecret,
        },
        body: '{"entity_id":"light.bad"}',
      ),
    );
    const failed = HttpToolTestResult(
      duration: Duration(milliseconds: 3),
      preview: '',
      error: 'Ziel nicht erlaubt: lokales Ziel „127.0.0.1“',
    );
    await pumpComponent(tester, [
      SectionCard(children: [HttpTestResultView(result)]),
      const SectionCard(children: [HttpTestResultView(failed)]),
    ]);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/http_tool_testergebnis.png'),
    );
  });

  testWidgets(
    'Golden Bring!-Kachel: „Login fehlt“ und „Fehler“',
    tags: ['golden'],
    (tester) async {
      // Gegen docs/design/screens/integrationen@1x.png (Bring!-Zeile).
      await pumpComponent(tester, [
        SectionCard(
          children: [
            IntegrationTile(
              name: 'Bring! Einkaufsliste',
              icon: WIcons.cart,
              status: IntegrationStatus.setupRequired,
              detail: 'Login fehlt',
              onAction: () {},
            ),
            IntegrationTile(
              name: 'Bring! Einkaufsliste',
              icon: WIcons.cart,
              status: IntegrationStatus.error,
              detail: 'Schnittstelle nicht erreichbar · pausiert',
              actionLabel: 'Erneut versuchen',
              onAction: () {},
            ),
          ],
        ),
      ]);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/bring_kachel.png'),
      );
    },
  );
}
