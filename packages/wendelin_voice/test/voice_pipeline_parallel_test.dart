import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_pipeline_test.dart' show GatedAgent, Harness, runFake, settle;

void main() {
  group('Parallele Runde, Ausgabe vor der Quittung (WP81c)', () {
    const red = AttestationStatusChanged(
      stepId: 's:1',
      status: AttestationStatus.red,
      logId: 'att-1',
    );

    test('Reset und rote Quittung: Ausgabe weg, Hinweis genau einmal', () {
      runFake((async) {
        final receipt = Completer<void>();
        final h = Harness(
          utteranceDuration: const Duration(seconds: 5),
          agent: GatedAgent(
            before: [const AgentTextDelta('Erster langer Satz. Zweiter Satz.')],
            gate: receipt.future,
            after: [
              const AgentTextReset('Vorherige Antwort nicht bestätigt'),
              red,
              const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
            ],
          ),
        );
        h.pipeline.start();
        async.elapse(const Duration(seconds: 3));
        expect(h.tts.spoken, ['Erster langer Satz.']);
        receipt.complete();
        settle(async);
        expect(h.tts.stops, greaterThan(0));
        expect(h.tts.spoken, ['Erster langer Satz.', VoiceTexts.de.unverified]);
        expect(
          h.tts.spoken.where((t) => t == VoiceTexts.de.unverified),
          hasLength(1),
        );
      });
    });

    test('Reset ohne Rot: Satzwarteschlange leer, nichts mehr gesprochen', () {
      runFake((async) {
        final receipt = Completer<void>();
        final h = Harness(
          utteranceDuration: const Duration(seconds: 5),
          agent: GatedAgent(
            before: [const AgentTextDelta('Erster langer Satz. Zweiter Satz.')],
            gate: receipt.future,
            after: [
              const AgentTextReset('Vorherige Antwort nicht bestätigt'),
              const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
            ],
          ),
        );
        h.pipeline.start();
        async.elapse(const Duration(seconds: 3));
        expect(h.tts.spoken, ['Erster langer Satz.']);
        receipt.complete();
        settle(async);
        async.elapse(const Duration(seconds: 30));
        settle(async);

        expect(h.tts.spoken, ['Erster langer Satz.']);
      });
    });

    test('Abbruch während der Ausgabe vor der Quittung stoppt alles', () {
      runFake((async) {
        final receipt = Completer<void>();
        final h = Harness(
          utteranceDuration: const Duration(seconds: 5),
          agent: GatedAgent(
            before: [const AgentTextDelta('Erster langer Satz. Zweiter Satz.')],
            gate: receipt.future,
            after: [
              const AgentDone(finalText: 'x', stopReason: StopReason.endTurn),
            ],
          ),
        );
        h.pipeline.start();
        async.elapse(const Duration(seconds: 3));
        expect(h.tts.spoken, ['Erster langer Satz.']);
        h.pipeline.cancel();
        settle(async);
        expect(h.tts.stops, greaterThan(0));
        expect(h.pipeline.state, VoiceState.idle);
        receipt.complete();
        settle(async);
        expect(h.tts.spoken, ['Erster langer Satz.']);
      });
    });
  });
}
