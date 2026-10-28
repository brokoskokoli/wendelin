import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/attestation_log_detail.dart';
import 'package:wendelin/ui/settings/attestation_log_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_word_screen.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/tee_app_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';

/// Pumps until [cond] holds (the database runs on real time, the widgets on
/// fake time), then a few more frames for the receipt check and dialogs.
Future<void> _settle(WidgetTester tester, bool Function() cond) async {
  await pumpUntil(tester, cond);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late ScriptedVerifier verifier;
  late ScriptedGateway gateway;
  late FakeGpuAttestationVerifier gpu;
  late TestEnv env;

  Future<ProviderContainer> pumpTee(
    WidgetTester tester, {
    GpuCheckMode mode = GpuCheckMode.off,
    String? launchTarget,
  }) async {
    verifier = ScriptedVerifier();
    gateway = ScriptedGateway();
    gpu = FakeGpuAttestationVerifier();
    final provider = scriptedTee(
      verifier: verifier,
      gateway: gateway,
      gpu: gpu,
      gpuMode: mode,
    );
    env = TestEnv(
      providerConfig: ProviderConfig(
        primary: ProviderTarget(
          profileId: 'phala',
          modelId: 'z-ai/glm-5.3-flash',
          provider: provider,
          privacy: PrivacyLevel.tee,
        ),
        names: const {'phala': 'Phala · GLM klein'},
      ),
    );
    env.notifier.launchTarget = launchTarget;
    setView(tester, screenSize);
    await tester.pumpWidget(env.app());
    await tester.pump();
    final c = ProviderScope.containerOf(
      tester.element(find.byType(MainScreen, skipOffstage: false)),
    );
    c.read(attestationHubProvider).register('phala', provider);
    return c;
  }

  Future<void> sendText(
    WidgetTester tester,
    String text,
    bool Function() until,
  ) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _settle(tester, until);
  }

  testWidgets('Antwort mit grünem Schild; Tippen öffnet den Protokolleintrag', (
    tester,
  ) async {
    await pumpTee(tester);
    await sendText(
      tester,
      'Wie wird das Meer morgen?',
      () => find.text('geprüft').evaluate().isNotEmpty,
    );
    expect(find.text('Ruhig: 0,4 m Welle.'), findsOneWidget);
    expect(find.text('geprüft'), findsOneWidget);
    await tester.tap(find.byType(AttestationShield));
    await tester.pumpAndSettle();
    expect(find.byType(AttestationLogDetailScreen), findsOneWidget);
  });

  testWidgets('Rote Quittung: Warnkarte, „Neu prüfen“ hebt die Sperre auf', (
    tester,
  ) async {
    final c = await pumpTee(tester);
    verifier.receipts = [failedReceipt(AttestationStage.receiptSignature)];
    await sendText(
      tester,
      'Frage',
      () => c.read(attestationHubProvider).isLocked('phala'),
    );
    expect(find.text('Prüfung fehlgeschlagen'), findsNWidgets(2));
    expect(find.textContaining('Anbieter ist gesperrt'), findsOneWidget);
    expect(c.read(attestationHubProvider).isLocked('phala'), isTrue);
    verifier.receipts = [
      const ReceiptResult(stages: [], status: AttestationStatus.green),
    ];
    await tester.tap(find.text('Neu prüfen'));
    await _settle(
      tester,
      () => !c.read(attestationHubProvider).isLocked('phala'),
    );
    expect(c.read(attestationHubProvider).isLocked('phala'), isFalse);
    expect(find.textContaining('Sperre ist aufgehoben'), findsOneWidget);
  });

  testWidgets('Tippen auf die Benachrichtigung öffnet das Prüfprotokoll', (
    tester,
  ) async {
    await pumpTee(tester, launchTarget: 'attestation_log');
    await _settle(
      tester,
      () => find.byType(AttestationLogScreen).evaluate().isNotEmpty,
    );
    expect(find.byType(AttestationLogScreen), findsOneWidget);
  });

  testWidgets('Aktion der Weckwort-Benachrichtigung öffnet die '
      'Weckwort-Einstellungen (WP171)', (tester) async {
    await pumpTee(tester, launchTarget: 'wake_word_settings');
    await _settle(
      tester,
      () => find.byType(WakeWordScreen).evaluate().isNotEmpty,
    );
    expect(find.byType(WakeWordScreen), findsOneWidget);
    expect(find.byType(AttestationLogScreen), findsNothing);
  });

  testWidgets('Start ohne Benachrichtigung: kein Prüfprotokoll', (
    tester,
  ) async {
    await pumpTee(tester);
    // Absence cannot be awaited: the start is done once the main screen
    // stands; give the (empty) launch handling about 1 s real time.
    await _settle(tester, () => find.byType(MainScreen).evaluate().isNotEmpty);
    await pumpReal(tester, rounds: 100);
    expect(find.byType(AttestationLogScreen), findsNothing);
  });

  testWidgets('„Neu prüfen“ nutzt den Anbieter der roten Antwort, nicht den '
      'aktiven', (tester) async {
    final c = await pumpTee(tester);
    verifier.receipts = [failedReceipt(AttestationStage.receiptSignature)];
    await sendText(
      tester,
      'Frage',
      () => c.read(attestationHubProvider).isLocked('phala'),
    );
    expect(c.read(attestationHubProvider).isLocked('phala'), isTrue);
    final controller = c.read(agentControllerProvider.notifier);
    // ignore: invalid_use_of_protected_member
    controller.state = controller.state.copyWith(activeProfileId: 'anderer');
    await tester.pump();
    final logId = controller.state.entries
        .whereType<AssistantTextEntry>()
        .last
        .attestation!
        .logId;
    await tester.runAsync(
      () => env.storage.attestations.add(
        AttestationRecord(
          logId: logId,
          at: DateTime.utc(2026, 10, 13),
          profileId: 'phala',
          kind: AttestationRecordKind.receipt,
          status: AttestationStatus.red,
          stages: const [],
        ),
      ),
    );
    verifier.receipts = [
      const ReceiptResult(stages: [], status: AttestationStatus.green),
    ];
    await tester.tap(find.text('Neu prüfen'));
    await _settle(
      tester,
      () => !c.read(attestationHubProvider).isLocked('phala'),
    );
    expect(c.read(attestationHubProvider).isLocked('phala'), isFalse);
  });

  testWidgets('GPU „Vorher“ fehlgeschlagen: Dialog; „Ohne GPU-Prüfung senden“ '
      'sendet nur diese Anfrage', (tester) async {
    await pumpTee(tester, mode: GpuCheckMode.before);
    gpu.result = const GpuAttestationResult(GpuVerdict.failed, 'abgelehnt');
    await sendText(
      tester,
      'Vertrauliche Frage',
      () => find.text('GPU-Prüfung nicht bestanden').evaluate().isNotEmpty,
    );
    expect(find.text('GPU-Prüfung nicht bestanden'), findsOneWidget);
    expect(gateway.requests, 0);
    await tester.tap(find.text('Ohne GPU-Prüfung senden'));
    await _settle(
      tester,
      () =>
          find.text('Ruhig: 0,4 m Welle.').evaluate().isNotEmpty &&
          find.text('GPU-Prüfung nicht bestanden').evaluate().isEmpty,
    );
    expect(gateway.requests, 1);
    expect(find.text('Ruhig: 0,4 m Welle.'), findsOneWidget);
    expect(find.text('GPU-Prüfung nicht bestanden'), findsNothing);
  });

  testWidgets('GPU „Vorher“ fehlgeschlagen: Abbrechen sendet nichts', (
    tester,
  ) async {
    await pumpTee(tester, mode: GpuCheckMode.before);
    gpu.result = const GpuAttestationResult(GpuVerdict.unreachable);
    await sendText(
      tester,
      'Frage',
      () => find.text('GPU-Prüfung nicht bestanden').evaluate().isNotEmpty,
    );
    expect(find.text('GPU-Prüfung nicht bestanden'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await _settle(
      tester,
      () => find.text('GPU-Prüfung nicht bestanden').evaluate().isEmpty,
    );
    expect(gateway.requests, 0);
    expect(find.text('Ruhig: 0,4 m Welle.'), findsNothing);
  });

  testWidgets('GPU „Vorher“ ohne Nachweis (WP82): Grund „kein Nachweis“, '
      '„Ohne GPU-Prüfung senden“ nur für diese Anfrage', (tester) async {
    await pumpTee(tester, mode: GpuCheckMode.before);
    const none = GpuAttestationResult(
      GpuVerdict.failed,
      'Keine GPU-Evidenz im Bericht des Anbieters',
      GpuReason.noEvidence,
    );
    gpu
      ..result = none
      ..localResult = none;
    await sendText(
      tester,
      'Vertrauliche Frage',
      () => find.text('Kein GPU-Nachweis').evaluate().isNotEmpty,
    );
    expect(find.text('Kein GPU-Nachweis'), findsOneWidget);
    expect(
      find.text(AppLocalizationsDe().gpuNoEvidenceMessage('Phala · GLM klein')),
      findsWidgets,
    );
    expect(gateway.requests, 0);
    await tester.tap(find.text('Ohne GPU-Prüfung senden'));
    await _settle(tester, () => gateway.requests >= 1);
    expect(gateway.requests, 1);
    // Only this request: the next one is held back again.
    await sendText(
      tester,
      'Noch eine Frage',
      () => find.text('Kein GPU-Nachweis').evaluate().isNotEmpty,
    );
    expect(find.text('Kein GPU-Nachweis'), findsOneWidget);
    expect(gateway.requests, 1);
  });

  testWidgets('GPU „Nachher“ ohne Nachweis: nicht blockierend, kein Alarm', (
    tester,
  ) async {
    await pumpTee(tester, mode: GpuCheckMode.after);
    const none = GpuAttestationResult(
      GpuVerdict.failed,
      'Keine GPU-Evidenz im Bericht des Anbieters',
      GpuReason.noEvidence,
    );
    gpu
      ..result = none
      ..localResult = none;
    await sendText(tester, 'Frage', () => gateway.requests >= 1);
    await _settle(tester, () => gateway.requests >= 1);
    await pumpReal(tester, rounds: 100);
    expect(gateway.requests, 1);
    expect(find.text('Kein GPU-Nachweis'), findsNothing);
    expect(env.notifier.shown, isEmpty);
  });
}
