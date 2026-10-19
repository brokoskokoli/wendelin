import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/ui/settings/provider_setup/attestation_stages_card.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/tee_app_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';

const _key = 'testschluessel-tinfoil-0123456789-GEHEIM';

/// The stages of a green Tinfoil attestation (WP76d).
const _green = [
  StageResult.pass(AttestationStage.snpReport),
  StageResult.pass(AttestationStage.snpChain),
  StageResult.pass(AttestationStage.snpPolicy),
  StageResult.pass(AttestationStage.tlsSpki),
  StageResult.pass(AttestationStage.bindHpke),
  StageResult.pass(AttestationStage.sigstoreRelease),
  StageResult.pass(AttestationStage.measurement),
  StageResult.pass(AttestationStage.releaseFloor),
  StageResult.pass(AttestationStage.e2eeKey),
  StageResult(
    AttestationStage.noReceipt,
    StageOutcome.info,
    'Keine Quittung je Antwort',
  ),
];

Future<TestEnv> _open(WidgetTester tester, ScriptedVerifier verifier) async {
  final gateway = ScriptedGateway();
  final env = TestEnv(
    storedProfiles: true,
    llmFactory: (profile, _) =>
        scriptedTee(verifier: verifier, gateway: gateway),
  );
  setView(tester, const Size(390, 3000));
  await tester.pumpWidget(env.app(home: const ProviderSetupScreen()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tinfoil (TEE)'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('apiKey')), _key);
  await tester.tap(find.text('Verbindung testen'));
  await tester.pumpAndSettle();
  return env;
}

void main() {
  testWidgets('Tinfoil: Stufen je Prüfung, „keine Quittung“ als Information '
      'und Einschränkung, Stufe TEE nach dem Speichern', (tester) async {
    final env = await _open(tester, ScriptedVerifier()..sessionStages = _green);
    await tester.tap(find.text('Modell prüfen'));
    await tester.pumpAndSettle();

    expect(find.byType(AttestationStagesCard), findsOneWidget);
    // Eine Information ist kein Fehler: die Karte meldet nichts Rotes.
    expect(find.textContaining('nicht bestanden'), findsNothing);
    expect(find.byKey(const ValueKey('restrictionSetupNote')), findsOneWidget);

    await tester.tap(find.text('Prüfprotokoll ansehen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('AMD-Hardware-Nachweis · bestanden'), findsOne);
    expect(find.textContaining('Messwert = Release · bestanden'), findsOne);
    expect(find.textContaining('Kein Rückschritt · bestanden'), findsOne);
    // Die Information steht klar benannt in der Liste, mit Begründung.
    expect(
      find.textContaining('Quittung je Antwort · nur protokolliert'),
      findsOne,
    );
    expect(find.text('Keine Quittung je Antwort'), findsOne);
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
    expect(p.privacy, PrivacyLevel.tee);
    expect(p.options['attestation'], 'tinfoil');
    // Die Information ist als Einschränkung für dieses Modell akzeptiert.
    expect(
      (await env.storage.settings.get(
        AppSettings.teeAccepted(p.id, p.defaultModel),
      ))?['stages'],
      ['receipt.none'],
    );
  });

  testWidgets(
    'Rückschritt des Anbieters: Stufe fällt durch, nicht speicherbar',
    (tester) async {
      await _open(
        tester,
        ScriptedVerifier()
          ..sessionStages = [
            ..._green.take(7),
            const StageResult.fail(
              AttestationStage.releaseFloor,
              'Release v0.0.158 ist älter als das bereits gesehene v0.0.159 '
              '(Rückschritt abgelehnt)',
            ),
          ],
      );
      await tester.tap(find.text('Modell prüfen'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('setupFailure')), findsOneWidget);
      expect(
        find.textContaining('1 von 8 Stufen nicht bestanden: Kein Rückschritt'),
        findsOneWidget,
      );
      expect(find.text('Speichern'), findsNothing);
    },
  );
}
