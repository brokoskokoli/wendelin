// A failed or impossible TEE check never leads silently to another provider.

import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';
import 'attestation_test.dart' show VerifyingFake;

const _gpuDown = AttestationFailedException(
  'GPU-Prüfung nicht bestanden (unreachable)',
  stage: 'gpu',
  unavailable: true,
);
const _locked = AttestationFailedException(
  'TEE-Anbieter nicht verifiziert (quote)',
  stage: 'quote',
);

void main() {
  group('Prüfung fehlgeschlagen: keine stille Übergabe', () {
    Future<(List<AgentEvent>, FakeLlmProvider)> runWith(
      List<ScriptedTurn> teeTurns, {
      List<Tool> tools = const [],
      Completer<AttestationReport?>? report,
    }) async {
      final (std, ps) = scripted('claude', [ScriptedTurn.text('Claude hier.')]);
      final tee = ProviderTarget(
        profileId: 'phala',
        modelId: 'phala-model',
        provider: VerifyingFake(
          FakeLlmProvider(teeTurns),
          report ?? (Completer<AttestationReport?>()..complete(null)),
        ),
        privacy: PrivacyLevel.tee,
      );
      final h = Harness(primary: tee, chain: [std], tools: tools);
      final events = await h.run(
        'Frage',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) e.respond(true);
        },
      );
      return (events, ps);
    }

    test('GPU nicht erreichbar (Vorher): kein Aufruf beim zweiten Anbieter, '
        'keine Frage, Fehler mit Ursache', () async {
      final (events, ps) = await runWith([
        ScriptedTurn.error(_gpuDown),
        ScriptedTurn.error(_gpuDown),
      ]);
      expect(ps.requests, isEmpty);
      expect(events.whereType<EscalationConfirmationRequired>(), isEmpty);
      expect(events.whereType<Escalated>(), isEmpty);
      final end = terminal(events) as AgentFailed;
      expect(end.cause, isA<AttestationFailedException>());
      expect((end.cause! as AttestationFailedException).stage, 'gpu');
    });

    test('Sitzung/Quittung gesperrt: keine Übergabe, keine Frage, auch nicht '
        'mit Bereitschaft zu „Ja“', () async {
      final (events, ps) = await runWith([ScriptedTurn.error(_locked)]);
      expect(ps.requests, isEmpty);
      expect(events.whereType<EscalationConfirmationRequired>(), isEmpty);
      expect(events.whereType<Escalated>(), isEmpty);
      expect(terminal(events), isA<AgentFailed>());
    });

    test('Nach roter Quittung mit Tool-Aufruf: die nächste Anfrage des '
        'gesperrten Anbieters endet, nichts geht an den zweiten', () async {
      final report = Completer<AttestationReport?>()
        ..complete(
          const AttestationReport(
            logId: 'att-1',
            status: AttestationStatus.red,
            reasonCode: 'upstream_session_mismatch',
          ),
        );
      final (events, ps) = await runWith(
        [
          ScriptedTurn.toolCalls([call('c1', 'web__search')]),
          ScriptedTurn.error(_locked),
        ],
        tools: [FakeTool(name: 'web__search')],
        report: report,
      );
      expect(ps.requests, isEmpty);
      expect(events.whereType<EscalationConfirmationRequired>(), isEmpty);
      expect(terminal(events), isA<AgentFailed>());
    });

    test(
      'Sitzung nicht erreichbar: nur ein Wiederholen, keine Übergabe',
      () async {
        const down = AttestationFailedException(
          'x',
          stage: 'quote',
          unavailable: true,
        );
        final (events, ps) = await runWith([
          ScriptedTurn.error(down),
          ScriptedTurn.error(down),
        ]);
        expect(ps.requests, isEmpty);
        expect(terminal(events), isA<AgentFailed>());
      },
    );
  });
}
