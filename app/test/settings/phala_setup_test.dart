import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/ui/design/design.dart' show WSwitch;
import 'package:wendelin/ui/settings/attestation_explain_screen.dart';
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
  testWidgets('WP78: Einschränkung beim Einrichten gezeigt, mit Speichern '
      'akzeptiert; Details-Seite erklärt die Stufen', (tester) async {
    final env = await _openPhala(
      tester,
      ScriptedVerifier()
        ..sessionStages = const [
          StageResult.pass(AttestationStage.quote),
          StageResult(
            AttestationStage.provenance,
            StageOutcome.info,
            'keine Liste hinterlegt',
          ),
        ],
    );
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('restrictionSetupNote')), findsOneWidget);
    expect(find.textContaining('Herkunft (Commit)'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Details'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byType(AttestationExplainScreen), findsOneWidget);
    expect(find.textContaining('Geprüft wird:'), findsNWidgets(2));
    expect(find.textContaining('Bedeutung:'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Speichern'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final p = (await env.storage.providerProfiles.list()).single;
    expect(
      (await env.storage.settings.get(
        AppSettings.teeAccepted(p.id, p.defaultModel),
      ))?['stages'],
      ['provenance'],
    );
  });

  testWidgets('nur TEE-Modelle wählbar; erste Attestierung mit Ergebnis je '
      'Stufe; „ausweichen“ standardmäßig aus', (tester) async {
    final env = await _openPhala(tester, ScriptedVerifier());
    expect(find.text('z-ai/glm-5.3-flash'), findsWidgets);
    expect(find.text('openai/gpt-nicht-tee'), findsNothing);
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();

    expect(find.byType(AttestationStagesCard), findsOneWidget);
    expect(find.text('Erste Attestierung'), findsOneWidget);
    // WP65: only a summary here, the stages on their own page.
    expect(find.textContaining('TDX-Quote (DCAP)'), findsNothing);
    await tester.tap(find.text('Prüfprotokoll ansehen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TDX-Quote (DCAP) · bestanden'), findsOneWidget);
    expect(find.textContaining('Nonce gebunden · bestanden'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
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
    expect(p.options.containsKey('noTools'), isFalse, reason: 'Standard aus');
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
      find.text('1 von 2 Stufen nicht bestanden: Schlüsselsatz-Signatur'),
      findsOneWidget,
    );
    await tester.tap(find.text('Prüfprotokoll ansehen'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Schlüsselsatz-Signatur · fehlgeschlagen'),
      findsOneWidget,
    );
    expect(find.text('Signatur ungültig'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern'), findsNothing, reason: 'bleibt bei der Wahl');
  });

  testWidgets('kein Schalter „Ohne Tools“ mehr (WP71)', (tester) async {
    await _openPhala(tester, ScriptedVerifier());
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Speichern'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ohne Tools (alles verschlüsselt)'), findsNothing);
    expect(find.byType(WSwitch), findsNothing);
  });

  testWidgets('Migration: ein Profil mit altem noTools lädt ohne Fehler, die '
      'Option fällt beim Speichern weg', (tester) async {
    final gateway = ScriptedGateway();
    final env = TestEnv(
      storedProfiles: true,
      llmFactory: (profile, _) =>
          scriptedTee(verifier: ScriptedVerifier(), gateway: gateway),
    );
    final profile = ProviderProfile(
      id: 'phala',
      name: 'Phala (RedPill)',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://api.redpill.ai/v1',
      defaultModel: 'z-ai/glm-5.3-flash',
      privacy: PrivacyLevel.tee,
      authMethod: const NoAuth(),
      options: {'attestation': 'phala', 'noTools': true},
    );
    await env.storage.providerProfiles.save(profile);
    setView(tester, const Size(390, 1800));
    await tester.pumpWidget(
      env.app(home: ProviderSetupScreen(existing: profile)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('apiKey')), _key);
    await tester.tap(find.text('Verbindung testen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Speichern'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final saved = (await env.storage.providerProfiles.list()).single;
    expect(saved.options.containsKey('noTools'), isFalse);
    expect(saved.options['attestation'], 'phala');
  });
}
