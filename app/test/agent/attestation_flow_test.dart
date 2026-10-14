import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/attestation_log_writer.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/tee_app_support.dart';
import '../support/test_env.dart';

void main() {
  late TestEnv env;
  late ProviderContainer c;
  late ScriptedVerifier verifier;
  late ScriptedGateway gateway;
  late FakeGpuAttestationVerifier gpu;
  late AttestedProvider provider;
  late AttestationLogWriter writer;

  /// Starts the app logic with a Phala-like TEE provider as default target.
  void start({
    GpuCheckMode mode = GpuCheckMode.off,
    bool fallback = false,
    List<ProviderTarget> chain = const [],
  }) {
    verifier = ScriptedVerifier();
    gateway = ScriptedGateway();
    gpu = FakeGpuAttestationVerifier();
    final base = TestEnv();
    writer = AttestationLogWriter(base.storage.attestations);
    provider = scriptedTee(
      verifier: verifier,
      gateway: gateway,
      gpu: gpu,
      gpuMode: mode,
      logSink: writer,
      fallbackOnFailure: fallback,
    );
    env = TestEnv(
      providerConfig: ProviderConfig(
        primary: ProviderTarget(
          profileId: 'phala',
          modelId: 'z-ai/glm-5.3-flash',
          provider: provider,
          privacy: PrivacyLevel.tee,
        ),
        chain: chain,
        names: const {'phala': 'Phala · GLM klein'},
      ),
      storage: base.storage,
    );
    c = env.container();
    c.read(attestationHubProvider)
      ..gpuMode = mode
      ..register('phala', provider);
  }

  tearDown(() => c.dispose());

  Future<void> send(String text) async {
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send(text);
    await controller.idle;
    await c.read(auditRecorderProvider).flush();
  }

  AnswerAttestation? shield() => c
      .read(agentControllerProvider)
      .entries
      .whereType<AssistantTextEntry>()
      .lastOrNull
      ?.attestation;

  test(
    'Grün: Status an der Antwort, Protokolleintrag mit Gesprächsschritt',
    () async {
      start();
      await send('Wie wird das Meer morgen?');
      expect(shield()?.status, AttestationStatus.green);
      expect(shield()?.logId, isNotEmpty);
      expect(provider.locked, isFalse);
      await writer.flush();
      final entry = await env.storage.attestations.byLogId(shield()!.logId);
      expect(entry?.stepId, shield()!.stepId, reason: 'Eintrag am Schritt');
      expect(entry?.sessionId, isNotNull);
      expect(entry?.kind, AttestationRecordKind.receipt);
    },
  );

  test('Gelb („wird geprüft“) zuerst, dann Grün – im selben Eintrag', () async {
    start();
    verifier.receiptGate = Completer<void>();
    final events = <AttestationStatus>[];
    c.listen(agentControllerProvider, (_, next) {
      final s = next.entries
          .whereType<AssistantTextEntry>()
          .lastOrNull
          ?.attestation
          ?.status;
      if (s != null && (events.isEmpty || events.last != s)) events.add(s);
    });
    final done = send('Frage');
    await pumpEventQueue(times: 50);
    expect(shield()?.status, AttestationStatus.yellow);
    expect(shield()?.logId, isEmpty);
    verifier.receiptGate!.complete();
    await done;
    expect(events, [AttestationStatus.yellow, AttestationStatus.green]);
    expect(
      c.read(agentControllerProvider).entries.whereType<AssistantTextEntry>(),
      hasLength(1),
    );
  });

  test('Manipulierte Quittung: rot mit Grund, Anbieter gesperrt, Neu prüfen entsperrt', () async {
    start();
    verifier.receipts = [
      failedReceipt(AttestationStage.receiptSignature, code: null),
    ];
    await send('Frage');
    expect(shield()?.status, AttestationStatus.red);
    expect(shield()?.reasonCode, isNull, reason: 'Standardtext: Manipulation');
    expect(provider.locked, isTrue);
    final requestsBefore = gateway.requests;

    await send('Noch eine Frage');
    expect(
      gateway.requests,
      requestsBefore,
      reason: 'gesperrt: nichts gesendet',
    );
    expect(
      c.read(agentControllerProvider).entries.whereType<NoticeEntry>(),
      isNotEmpty,
    );

    verifier.receipts = [
      const ReceiptResult(stages: [], status: AttestationStatus.green),
    ];
    await c.read(agentControllerProvider.notifier).reattest('phala');
    expect(provider.locked, isFalse);
    await send('Dritte Frage');
    expect(gateway.requests, requestsBefore + 1);
    expect(shield()?.status, AttestationStatus.green);
  });

  test(
    'Sonderfall-Code erreicht die Antwort („Sicherheits-Update ausstehend“)',
    () async {
      start();
      verifier.receipts = [
        failedReceipt(
          AttestationStage.upstreamTcb,
          code: StageResult.upstreamTcbOutOfDate,
        ),
      ];
      await send('Frage');
      expect(shield()?.status, AttestationStatus.red);
      expect(shield()?.reasonCode, 'upstream_tcb_out_of_date');
    },
  );

  group('Ausweichen bei fehlgeschlagener Prüfung', () {
    final local = FakeLlmProvider([ScriptedTurn.text('Lokale Antwort.')]);
    ProviderTarget fallbackTarget() => ProviderTarget(
      profileId: 'lokal',
      modelId: 'llama',
      provider: local,
      privacy: PrivacyLevel.local,
    );

    test('Option an: der nächste Anbieter antwortet, nichts ging an den TEE-Anbieter', () async {
      start(fallback: true, chain: [fallbackTarget()]);
      verifier.sessionStages = const [
        StageResult.fail(AttestationStage.quote, 'ungültig'),
      ];
      await send('Frage');
      final s = c.read(agentControllerProvider);
      expect(gateway.requests, 0, reason: 'nichts an den TEE-Anbieter');
      expect(s.entries.whereType<EscalationEntry>(), isNotEmpty);
      expect(
        s.entries.whereType<AssistantTextEntry>().last.text,
        'Lokale Antwort.',
      );
    });

    test('Option aus: kein Ausweichen, die Anfrage endet mit Fehler', () async {
      start(chain: [fallbackTarget()]);
      verifier.sessionStages = const [
        StageResult.fail(AttestationStage.quote, 'ungültig'),
      ];
      await send('Frage');
      final s = c.read(agentControllerProvider);
      expect(s.pending, isNull);
      expect(s.entries.whereType<AssistantTextEntry>(), isEmpty);
      expect(s.entries.whereType<NoticeEntry>(), isNotEmpty);
    });
  });

  group('GPU-Prüfung', () {
    test('Vorher fehlgeschlagen: nichts gesendet, Dialog-Zustand, einmal ohne senden', () async {
      start(mode: GpuCheckMode.before);
      gpu.result = const GpuAttestationResult(GpuVerdict.failed, 'abgelehnt');
      await send('Vertrauliche Frage');
      var state = c.read(agentControllerProvider);
      expect(gateway.requests, 0);
      expect(state.gpuBlock?.profileId, 'phala');
      expect(state.gpuBlock?.request, 'Vertrauliche Frage');

      await c
          .read(agentControllerProvider.notifier)
          .resolveGpuBlock(sendWithout: true);
      await c.read(agentControllerProvider.notifier).idle;
      state = c.read(agentControllerProvider);
      expect(gateway.requests, 1, reason: 'nur diese Anfrage geht raus');
      expect(state.gpuBlock, isNull);
      expect(shield()?.status, AttestationStatus.green);

      // Die nächste Anfrage prüft wieder vorher.
      await send('Zweite Frage');
      expect(gateway.requests, 1);
      expect(c.read(agentControllerProvider).gpuBlock, isNotNull);
    });

    test('Vorher fehlgeschlagen und Abbrechen: nichts wird gesendet', () async {
      start(mode: GpuCheckMode.before);
      gpu.result = const GpuAttestationResult(GpuVerdict.unreachable);
      await send('Frage');
      expect(c.read(agentControllerProvider).gpuBlock, isNotNull);
      await c
          .read(agentControllerProvider.notifier)
          .resolveGpuBlock(sendWithout: false);
      expect(c.read(agentControllerProvider).gpuBlock, isNull);
      expect(gateway.requests, 0);
    });

    test('Nachher fehlgeschlagen: Antwort wird rot, Benachrichtigung, nächste Anfrage prüft vorher', () async {
      start(mode: GpuCheckMode.after);
      gpu.result = const GpuAttestationResult(GpuVerdict.failed, 'abgelehnt');
      await send('Frage');
      await pumpEventQueue(times: 50);
      expect(shield()?.status, AttestationStatus.red);
      expect(shield()?.reasonCode, 'gpu_failed');
      expect(env.notifier.shown, hasLength(1));
      expect(env.notifier.shown.single.$1, 'GPU-Prüfung fehlgeschlagen');
      expect(env.notifier.shown.single.$2, contains('Phala · GLM klein'));
      expect(
        env.notifier.shown.single.$2,
        isNot(contains('Frage')),
        reason: 'keine Inhalte in der Benachrichtigung',
      );

      // Folgeanfrage fragt vorher nach NVIDIA (und ist bei Fehler gestoppt).
      final callsBefore = gpu.calls.length;
      await send('Zweite Frage');
      expect(gpu.calls.length, callsBefore + 1);
      expect(gateway.requests, 1);
    });

    test('Aus: kein Aufruf an NVIDIA', () async {
      start();
      await send('Frage');
      expect(gpu.calls, isEmpty);
      expect(env.notifier.shown, isEmpty);
    });
  });
}
