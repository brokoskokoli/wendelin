import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_pipeline_test.dart' show Harness, frame, runFake, settle;

// WP68: „Wendelin, mach …“ in one breath. 30 ms frames = 480 samples.
Int16List cat(List<Int16List> parts) {
  final out = Int16List(parts.fold(0, (n, p) => n + p.length));
  var at = 0;
  for (final p in parts) {
    out.setAll(at, p);
    at += p.length;
  }
  return out;
}

Int16List speech(int ms) => AudioFrames.speech(Duration(milliseconds: ms));
Int16List quiet(int ms) => AudioFrames.silence(Duration(milliseconds: ms));

TriggerEvent wake(Int16List pcm, int? wakeEnd) => TriggerEvent(
  source: TriggerKind.wakeWord,
  at: DateTime.utc(2026, 10, 15),
  preRoll: pcm,
  wakeEnd: wakeEnd,
);

void main() {
  const wakeMs = 600;
  const wakeEnd = wakeMs * 16;

  test('ohne Pause: Anfrage steckt im Pre-Roll, Wake Word fehlt im Text und '
      'im Audio', () {
    runFake((async) {
      final h = Harness(
        turns: [ScriptedTurn.text('Licht an.')],
        transcripts: const [
          Transcript(text: 'Wendelin, schalte die Taschenlampe an.'),
        ],
      );
      h.fakeAudio.script(AudioFrames.pattern('.' * 30, frame: frame));
      final pre = cat([speech(wakeMs), speech(900), quiet(900)]);
      expect(h.pipeline.start(trigger: wake(pre, wakeEnd)), isTrue);
      settle(async);
      expect(h.recording.inputs.single.text, 'schalte die Taschenlampe an.');
      // 4 Chunks Rand (stille) + 26 Sprach- + 27 Stille-Chunks; das Wake Word
      // (600 ms = 9600 Samples) ist nicht dabei.
      expect(h.stt.calls.single.samples, 57 * 480);
    });
  });

  test('mit Pause nach dem Wake Word: gleiche Anfrage', () {
    runFake((async) {
      final h = Harness(
        turns: [ScriptedTurn.text('Licht an.')],
        transcripts: const [
          Transcript(text: 'Wendelin schalte die Taschenlampe an'),
        ],
      );
      // 1,2 s Pause, dann die Anfrage live.
      h.fakeAudio.script(
        AudioFrames.pattern('${'.' * 10}${'S' * 20}${'.' * 30}', frame: frame),
      );
      final pre = cat([speech(wakeMs), quiet(600)]);
      h.pipeline.start(trigger: wake(pre, wakeEnd));
      settle(async);
      expect(h.recording.inputs.single.text, 'schalte die Taschenlampe an');
      // Kein Ende wegen der Stille vor der Anfrage: die Aufnahme enthält die
      // Anfrage vollständig (600 ms = 20 Frames Sprache).
      expect(h.stt.calls.single.samples, greaterThan(20 * 480));
    });
  });

  test('nur „Wendelin“: das Overlay wartet auf die Anfrage', () {
    runFake((async) {
      final h = Harness(
        turns: [ScriptedTurn.text('Licht an.')],
        transcripts: const [Transcript(text: 'Mach das Licht an')],
      );
      h.fakeAudio.script(
        AudioFrames.pattern('${'.' * 100}${'S' * 20}${'.' * 30}', frame: frame),
      );
      final pre = cat([speech(wakeMs), quiet(900)]);
      h.pipeline.start(trigger: wake(pre, wakeEnd));
      settle(async);
      expect(h.stt.calls, hasLength(1)); // nur die spätere Anfrage
      expect(h.recording.inputs.single.text, 'Mach das Licht an');
    });
  });

  test('nur Wake Word im Transkript (Wake-Ende unbekannt): weiter zuhören', () {
    runFake((async) {
      final h = Harness(
        turns: [ScriptedTurn.text('Licht an.')],
        transcripts: const [
          Transcript(text: 'Wendelin.'),
          Transcript(text: 'Mach das Licht an'),
        ],
      );
      h.fakeAudio.script(
        AudioFrames.pattern('${'.' * 10}${'S' * 20}${'.' * 30}', frame: frame),
      );
      final pre = cat([speech(wakeMs), quiet(300)]);
      h.pipeline.start(trigger: wake(pre, null));
      settle(async);
      expect(h.stt.calls, hasLength(2));
      expect(h.recording.inputs.single.text, 'Mach das Licht an');
    });
  });

  test('andere Auslöser: Transkript bleibt unverändert', () {
    runFake((async) {
      final h = Harness(
        turns: [ScriptedTurn.text('Ok.')],
        transcripts: const [Transcript(text: 'Wendelin ist ein Name')],
      );
      h.pipeline.start();
      settle(async);
      expect(h.recording.inputs.single.text, 'Wendelin ist ein Name');
    });
  });

  group('stripWakeWord', () {
    test('Schreibvarianten und Anrede', () {
      expect(stripWakeWord('Wendelin, schalte an'), 'schalte an');
      expect(stripWakeWord('wendeline mach Licht'), 'mach Licht');
      expect(
        stripWakeWord('Hey Wendelin: wie spät ist es?'),
        'wie spät ist es?',
      );
      expect(stripWakeWord('Wende Lin, mach Licht'), 'mach Licht');
      expect(stripWakeWord('Fendelien mach Licht'), 'mach Licht');
      expect(stripWakeWord('Wendelmann. Wetter?'), 'Wetter?');
    });

    test('Wendel in den Keller bleibt, getrenntes Wake Word wird gekürzt', () {
      expect(stripWakeWord('Wendel in den Keller'), 'Wendel in den Keller');
      expect(stripWakeWord('Wendelin, mach das Licht an'), 'mach das Licht an');
      expect(stripWakeWord('Wende Lin mach Licht'), 'mach Licht');
    });

    test('nur das Wake Word → leer; mitten im Satz bleibt es', () {
      expect(stripWakeWord('Wendelin.'), '');
      expect(
        stripWakeWord('Ich habe Wendelin gefragt'),
        'Ich habe Wendelin gefragt',
      );
      expect(stripWakeWord('  Schalte das Licht an '), 'Schalte das Licht an');
    });
  });

  group('speechAfterWakeWord', () {
    test('Sprache nach dem Wake Word, aber nicht das Wake Word selbst', () {
      expect(
        speechAfterWakeWord(cat([speech(600), quiet(600)]), wakeEnd),
        isFalse,
      );
      expect(
        speechAfterWakeWord(cat([speech(600), speech(300)]), wakeEnd),
        isTrue,
      );
      // Rand: der Auslauf des Wake Words zählt nicht.
      expect(
        speechAfterWakeWord(
          cat([speech(600), speech(90), quiet(600)]),
          wakeEnd,
        ),
        isFalse,
      );
      expect(speechAfterWakeWord(Int16List(0), null), isFalse);
    });

    Int16List level(int ms, int amp) {
      final f = Int16List(ms * 16);
      for (var i = 0; i < f.length; i++) {
        f[i] = (i ~/ 20).isEven ? amp : -amp;
      }
      return f;
    }

    test('leise Sprache in ruhigem Raum zählt (relativ zum Grundrauschen)', () {
      final pcm = cat([level(400, 40), level(600, 3000), level(900, 500)]);
      expect(speechAfterWakeWord(pcm, 1000 * 16), isTrue);
    });

    test('gleichmäßiges Rauschen nach dem Wake Word ist keine Sprache', () {
      final pcm = cat([level(400, 400), level(600, 3000), level(900, 450)]);
      expect(speechAfterWakeWord(pcm, 1000 * 16), isFalse);
      // aber deutlich lauter als der Raum: Sprache
      final louder = cat([level(400, 400), level(600, 3000), level(900, 2000)]);
      expect(speechAfterWakeWord(louder, 1000 * 16), isTrue);
    });
  });
}
