import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/attestation_log_detail.dart';
import 'package:wendelin/ui/settings/attestation_log_screen.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/tee_app_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';

/// Pumps until the run ended (the send button is back), then a little more
/// for the receipt check and dialogs.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    // The database runs on real time, the widgets on fake time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
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

  Future<void> sendText(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _settle(tester);
  }

  testWidgets('Antwort mit grünem Schild; Tippen öffnet den Protokolleintrag', (
    tester,
  ) async {
    await pumpTee(tester);
    await sendText(tester, 'Wie wird das Meer morgen?');
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
    await sendText(tester, 'Frage');
    expect(find.text('Prüfung fehlgeschlagen'), findsNWidgets(2));
    expect(find.textContaining('Anbieter ist gesperrt'), findsOneWidget);
    expect(c.read(attestationHubProvider).isLocked('phala'), isTrue);
    verifier.receipts = [
      const ReceiptResult(stages: [], status: AttestationStatus.green),
    ];
    await tester.tap(find.text('Neu prüfen'));
    await _settle(tester);
    expect(c.read(attestationHubProvider).isLocked('phala'), isFalse);
    expect(find.textContaining('Sperre ist aufgehoben'), findsOneWidget);
  });

  testWidgets('Tippen auf die Benachrichtigung öffnet das Prüfprotokoll', (
    tester,
  ) async {
    await pumpTee(tester, launchTarget: 'attestation_log');
    await _settle(tester);
    expect(find.byType(AttestationLogScreen), findsOneWidget);
  });

  testWidgets('Start ohne Benachrichtigung: kein Prüfprotokoll', (
    tester,
  ) async {
    await pumpTee(tester);
    await _settle(tester);
    expect(find.byType(AttestationLogScreen), findsNothing);
  });

  testWidgets('„Neu prüfen“ nutzt den Anbieter der roten Antwort, nicht den '
      'aktiven', (tester) async {
    final c = await pumpTee(tester);
    verifier.receipts = [failedReceipt(AttestationStage.receiptSignature)];
    await sendText(tester, 'Frage');
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
    await _settle(tester);
    expect(c.read(attestationHubProvider).isLocked('phala'), isFalse);
  });

  testWidgets('GPU „Vorher“ fehlgeschlagen: Dialog; „Ohne GPU-Prüfung senden“ '
      'sendet nur diese Anfrage', (tester) async {
    await pumpTee(tester, mode: GpuCheckMode.before);
    gpu.result = const GpuAttestationResult(GpuVerdict.failed, 'abgelehnt');
    await sendText(tester, 'Vertrauliche Frage');
    expect(find.text('GPU-Prüfung nicht bestanden'), findsOneWidget);
    expect(gateway.requests, 0);
    await tester.tap(find.text('Ohne GPU-Prüfung senden'));
    await _settle(tester);
    expect(gateway.requests, 1);
    expect(find.text('Ruhig: 0,4 m Welle.'), findsOneWidget);
    expect(find.text('GPU-Prüfung nicht bestanden'), findsNothing);
  });

  testWidgets('GPU „Vorher“ fehlgeschlagen: Abbrechen sendet nichts', (
    tester,
  ) async {
    await pumpTee(tester, mode: GpuCheckMode.before);
    gpu.result = const GpuAttestationResult(GpuVerdict.unreachable);
    await sendText(tester, 'Frage');
    expect(find.text('GPU-Prüfung nicht bestanden'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await _settle(tester);
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
    await sendText(tester, 'Vertrauliche Frage');
    expect(find.text('Kein GPU-Nachweis'), findsOneWidget);
    expect(find.textContaining('keinen GPU-Nachweis'), findsWidgets);
    expect(gateway.requests, 0);
    await tester.tap(find.text('Ohne GPU-Prüfung senden'));
    await _settle(tester);
    expect(gateway.requests, 1);
    // Only this request: the next one is held back again.
    await sendText(tester, 'Noch eine Frage');
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
    await sendText(tester, 'Frage');
    await _settle(tester);
    expect(gateway.requests, 1);
    expect(find.text('Kein GPU-Nachweis'), findsNothing);
    expect(env.notifier.shown, isEmpty);
  });
}
