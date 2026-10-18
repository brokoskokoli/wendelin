// WP82: the overlay shows a card for a request stopped by the GPU check
// (no evidence) instead of the technical error; the block is cleared after
// use, dismissal and a new turn.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/conversation_state.dart'
    show gpuNoEvidenceSpoken;
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../screens/main_screen_test.dart' show pumpUntil;
import '../support/tee_app_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart' show pumpReal;
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

const _none = GpuAttestationResult(
  GpuVerdict.failed,
  'Keine GPU-Evidenz im Bericht des Anbieters',
  GpuReason.noEvidence,
);

Future<void> settle(WidgetTester tester) => pumpReal(tester, rounds: 10);

void main() {
  late ScriptedGateway gateway;
  late FakeAssistantPlatform platform;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final gpu = FakeGpuAttestationVerifier()
      ..result = _none
      ..localResult = _none;
    gateway = ScriptedGateway();
    final provider = scriptedTee(
      verifier: ScriptedVerifier(),
      gateway: gateway,
      gpu: gpu,
      gpuMode: GpuCheckMode.before,
    );
    final env = TestEnv(
      providerConfig: ProviderConfig(
        primary: ProviderTarget(
          profileId: 'phala',
          modelId: 'z-ai/glm-5.2',
          provider: provider,
          privacy: PrivacyLevel.tee,
        ),
        names: const {'phala': 'Phala'},
      ),
    );
    platform = FakeAssistantPlatform();
    final c = await pumpOverlay(tester, env, platform, autoStart: false);
    c.read(attestationHubProvider).register('phala', provider);
    return c;
  }

  testWidgets('Karte „Kein GPU-Nachweis“, einmal ohne Prüfung senden', (
    tester,
  ) async {
    final c = await pump(tester);
    final agent = c.read(agentControllerProvider.notifier);
    final events = <AgentEvent>[];
    agent.submit(UserInput(text: 'Vertrauliche Frage')).listen(events.add);
    await pumpUntil(tester, find.text('Kein GPU-Nachweis'));
    expect(gateway.requests, 0);
    // No technical error text, but the plain (and spoken) hint.
    expect(find.textContaining('Anfrage nicht gesendet'), findsNothing);
    expect(
      (events.last as AgentFailed).message,
      gpuNoEvidenceSpoken,
      reason: 'wird vom Sprachpfad vorgelesen',
    );
    await tester.tap(find.text('Ohne GPU-Prüfung senden'));
    await pumpUntil(tester, find.text('Ruhig: 0,4 m Welle.'));
    expect(gateway.requests, 1);
    expect(find.text('Kein GPU-Nachweis'), findsNothing);
    // Only this request: the next one is blocked again.
    await settle(tester);
    agent.submit(UserInput(text: 'Noch eine')).listen((_) {});
    await pumpUntil(tester, find.text('Kein GPU-Nachweis'));
    expect(gateway.requests, 1);
  });

  testWidgets('Abbrechen und neue Anfrage räumen den Block ab', (tester) async {
    final c = await pump(tester);
    final agent = c.read(agentControllerProvider.notifier);
    agent.submit(UserInput(text: 'Frage')).listen((_) {});
    await pumpUntil(tester, find.text('Kein GPU-Nachweis'));
    expect(c.read(agentControllerProvider).gpuBlock, isNotNull);
    await tester.tap(find.text('Abbrechen'));
    await tester.pump();
    expect(find.text('Kein GPU-Nachweis'), findsNothing);
    expect(c.read(agentControllerProvider).gpuBlock, isNull);
    expect(gateway.requests, 0);
    // A new turn drops a block that was left open.
    agent.submit(UserInput(text: 'Frage 2')).listen((_) {});
    await pumpUntil(tester, find.text('Kein GPU-Nachweis'));
    expect(c.read(agentControllerProvider).gpuBlock?.request, 'Frage 2');
    // The block is left open, the user changes the mode and asks again: the
    // old block is gone with the new turn.
    c.read(attestationHubProvider).provider('phala')!.gpuMode =
        GpuCheckMode.off;
    agent.submit(UserInput(text: 'Frage 3')).listen((_) {});
    await pumpUntil(tester, find.text('Ruhig: 0,4 m Welle.'));
    expect(c.read(agentControllerProvider).gpuBlock, isNull);
    expect(find.text('Kein GPU-Nachweis'), findsNothing);
    await settle(tester);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('Phone 411x914: Button der Karte erreichbar und tippbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 914 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.reset);
    final c = await pump(tester);
    final agent = c.read(agentControllerProvider.notifier);
    agent
        .submit(UserInput(text: 'Wie wird das Wetter morgen am Meer?'))
        .listen((_) {});
    await pumpUntil(tester, find.text('Kein GPU-Nachweis'));
    final button = find.text('Ohne GPU-Prüfung senden');
    final rect = tester.getRect(button);
    final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
    expect(
      viewport.contains(rect.center),
      isTrue,
      reason: 'Button liegt im sichtbaren Bereich ($rect in $viewport)',
    );
    await tester.tap(button);
    await pumpUntil(tester, find.text('Ruhig: 0,4 m Welle.'));
    expect(gateway.requests, 1);
    await settle(tester);
    await tester.pump(const Duration(seconds: 30));
  });
}
