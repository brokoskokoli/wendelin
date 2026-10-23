import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_pipeline_test.dart' show Harness, runFake, settle;

Transcript _t(String text, double? conf) =>
    Transcript(text: text, language: 'de', confidence: conf);

void main() {
  group('SttConfidenceGate (WP140)', () {
    const gate = SttConfidenceGate();

    test('Schwellen sind benannte Konstanten', () {
      expect(SttConfidenceGate.defaultHandsFree, 0.5);
      expect(SttConfidenceGate.defaultDeliberate, 0.3);
    });

    test('ohne Urteil (null) wird nie verworfen', () {
      for (final f in [true, false]) {
        expect(gate.decide(null, followUp: f), SttGateAction.accept);
      }
    });

    test('Grenze: genau die Schwelle passt, knapp darunter nicht', () {
      expect(
        gate.decide(0.5, followUp: true, source: TriggerKind.pushToTalk),
        SttGateAction.accept,
      );
      expect(gate.decide(0.4999, followUp: true), SttGateAction.dropQuietly);
      expect(
        gate.decide(0.3, source: TriggerKind.pushToTalk, followUp: false),
        SttGateAction.accept,
      );
      expect(
        gate.decide(0.2999, source: TriggerKind.pushToTalk, followUp: false),
        SttGateAction.askAgain,
      );
    });

    test('Wake Word und Barge-in nutzen die strenge Schwelle', () {
      expect(
        gate.decide(0.4, source: TriggerKind.wakeWord, followUp: false),
        SttGateAction.askAgain,
      );
      expect(
        gate.decide(0.4, source: TriggerKind.pushToTalk, followUp: false),
        SttGateAction.accept,
      );
    });
  });

  group('Pipeline verwirft unsichere Erkennung (WP140)', () {
    test('Push-to-Talk unter 0,3: Nachfrage, kein Modellaufruf', () {
      runFake((async) {
        final h = Harness(transcripts: [_t('Wetter', 0.18)]);
        h.pipeline.start();
        settle(async);
        expect(h.recording.inputs, isEmpty);
        expect(h.eventsOf<VoiceNothingUnderstood>(), hasLength(1));
        expect(
          h.diagnostics,
          contains(startsWith('stt-reject reason=low-conf')),
        );
        expect(h.diagnostics.join(), isNot(contains('Wetter')));
      });
    });

    test('Push-to-Talk bei 0,45 geht durch (niedrigere Schwelle)', () {
      runFake((async) {
        final h = Harness(transcripts: [_t('Wetter', 0.45)]);
        h.pipeline.start();
        settle(async);
        expect(h.recording.inputs.map((i) => i.text), ['Wetter']);
      });
    });

    test('Wake Word bei niedriger Sicherheit (0,4): Nachfrage statt Modell', () {
      runFake((async) {
        final h = Harness(transcripts: [_t('Wetter', 0.4)]);
        h.pipeline.start(
          trigger: TriggerEvent(
            source: TriggerKind.wakeWord,
            at: DateTime.utc(2026),
          ),
        );
        settle(async);
        expect(h.recording.inputs, isEmpty);
        expect(h.eventsOf<VoiceNothingUnderstood>(), hasLength(1));
      });
    });

    test('hohe Sicherheit: normaler Ablauf', () {
      runFake((async) {
        final h = Harness(transcripts: [_t('Wetter', 0.9)]);
        h.pipeline.start();
        settle(async);
        expect(h.recording.inputs.map((i) => i.text), ['Wetter']);
        expect(h.diagnostics.where((d) => d.startsWith('stt-reject')), isEmpty);
      });
    });

    test('Stoppwort wird trotz niedriger Sicherheit befolgt', () {
      runFake((async) {
        final h = Harness(transcripts: [_t('Stopp', 0.1)]);
        h.pipeline.start();
        settle(async);
        expect(
          h.eventsOf<VoiceCancelled>().single.reason,
          VoiceCancelReason.stopWord,
        );
      });
    });

    test('Folgefrage unter 0,5: still verworfen, hört weiter', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 1),
          ),
          transcripts: [_t('Eins', 0.9), _t('Rauschen', 0.18), _t('Zwei', 0.9)],
          turns: [ScriptedTurn.text('Eins.'), ScriptedTurn.text('Zwei.')],
        );
        h.pipeline.start();
        settle(async);
        expect(h.recording.inputs.map((i) => i.text), ['Eins', 'Zwei']);
        // The rejected round says nothing.
        expect(h.eventsOf<VoiceNothingUnderstood>(), isEmpty);
        expect(
          h.diagnostics.where((d) => d.contains('mode=followup')),
          hasLength(1),
        );
      });
    });

    test('Folgefrage: nach zwei Verwürfen in Folge endet das Gespräch', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 1),
          ),
          transcripts: [
            _t('Eins', 0.9),
            _t('a', 0.1),
            _t('b', 0.1),
            _t('c', 0.1),
            _t('Nie', 0.9),
          ],
          turns: [ScriptedTurn.text('Eins.')],
        );
        h.pipeline.start();
        settle(async);
        expect(h.recording.inputs.map((i) => i.text), ['Eins']);
        expect(
          h.diagnostics.where((d) => d.startsWith('stt-reject')),
          hasLength(3),
        );
        expect(
          h.eventsOf<VoiceConversationEnded>().single.reason,
          ConversationEndReason.silence,
        );
        expect(h.pipeline.state, VoiceState.idle);
      });
    });
  });
}
