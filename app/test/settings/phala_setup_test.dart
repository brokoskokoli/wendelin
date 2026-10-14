import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/settings/provider_setup/attestation_stages_card.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/tee_app_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';

const _key = 'testschluessel-phala-0123456789-GEHEIM';

Future<TestEnv> _openPhala(
  WidgetTester tester,
  ScriptedVerifier verifier,
) async {
  final gateway = ScriptedGateway();
  final env = TestEnv(
    storedProfiles: true,
    llmFactory: (profile, _) =>
        scriptedTee(verifier: verifier, gateway: gateway),
  );
  setView(tester, const Size(390, 1800));
  await tester.pumpWidget(env.app(home: const ProviderSetupScreen()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Phala (RedPill)'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('apiKey')), _key);
  await tester.tap(find.text('Verbindung testen'));
  await tester.pumpAndSettle();
  return env;
}

void main() {
  testWidgets('nur TEE-Modelle wählbar; erste Attestierung mit Ergebnis je '
      'Stufe; „ausweichen“ standardmäßig aus', (tester) async {
    final env = await _openPhala(tester, ScriptedVerifier());
    expect(find.text('z-ai/glm-5.3-flash'), findsWidgets);
    expect(find.text('openai/gpt-nicht-tee'), findsNothing);
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();

    expect(find.byType(AttestationStagesCard), findsOneWidget);
    expect(find.text('Erste Attestierung'), findsOneWidget);
    expect(find.textContaining('TDX-Quote (DCAP) · bestanden'), findsOneWidget);
    expect(find.textContaining('Nonce gebunden · bestanden'), findsOneWidget);
    expect(find.textContaining('ausweichen'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Speichern'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final p = (await env.storage.providerProfiles.list()).single;
    expect(p.privacy, PrivacyLevel.tee);
    expect(p.options.containsKey('attestationFallback'), isFalse);
    expect(p.options['attestation'], 'phala');
  });

  testWidgets('fehlgeschlagene Attestierung: Quadrat und die Stufe, die '
      'durchfiel', (tester) async {
    final verifier = ScriptedVerifier()
      ..sessionStages = const [
        StageResult.pass(AttestationStage.quote),
        StageResult.fail(
          AttestationStage.keysetEndorsement,
          'Signatur ungültig',
        ),
      ];
    await _openPhala(tester, verifier);
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('setupFailure')), findsOneWidget);
    expect(find.text('Erste Attestierung'), findsOneWidget);
    expect(
      find.textContaining('Schlüsselsatz-Signatur · fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.text('Signatur ungültig'), findsOneWidget);
    expect(find.text('Speichern'), findsNothing, reason: 'bleibt bei der Wahl');
  });
}
