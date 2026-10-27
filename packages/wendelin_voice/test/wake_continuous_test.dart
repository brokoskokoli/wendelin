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
      // Endpoint inside the pre-roll: the microphone is not needed (WP146).
      expect(h.fakeAudio.startCount, 0);
    });
  });

  test('nur Weckwort im ersten Segment: der Rest des Pre-Rolls wird '
      'weiter eingespeist, kein Mikrofon (WP146)', () {
    runFake((async) {
      final h = Harness(
        turns: [ScriptedTurn.text('Licht an.')],
        transcripts: const [
          Transcript(text: 'Hey Wendelin.'),
          Transcript(text: 'Mach das Licht an'),
        ],
      );
      // Stage 2 took its time: the request was spoken meanwhile.
      final pre = cat([speech(600), quiet(1000), speech(900), quiet(900)]);
      expect(h.pipeline.start(trigger: wake(pre, 200 * 16)), isTrue);
      settle(async);
      expect(h.stt.calls, hasLength(2));
      expect(h.recording.inputs.single.text, 'Mach das Licht an');
      // Request of 900 ms plus end silence, not the wake word or the pause.
      expect(h.stt.calls.last.samples, inInclusiveRange(30 * 480, 70 * 480));
      expect(h.fakeAudio.startCount, 0);
      expect(
        h.diagnostics.where((d) => d.startsWith('relisten reason=wake-only')),
        hasLength(1),
      );
    });
  });

  test('nur Weckwort, Anfrage nicht im Pre-Roll: der Rest läuft durch, danach live (WP146)', () {
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
      final pre = cat([speech(600), quiet(1000)]);
      h.pipeline.start(trigger: wake(pre, 200 * 16));
      settle(async);
      expect(h.stt.calls, hasLength(2));
      expect(h.fakeAudio.startCount, 1);
    });
  });

  test('nur Weckwort, Befehl über das Ende des Vorlaufs hinaus: das früh '
      'geöffnete Mikrofon bleibt offen, nichts geht verloren (WP146)', () {
    runFake((async) {
      // Like the primed microphone: it records from before the pipeline
      // starts and replays what it buffered.
      final mic = _HeldMic(AudioFrames.pattern('S' * 20, frame: frame));
      final h = Harness(
        turns: [ScriptedTurn.text('Licht an.')],
        transcripts: const [
          Transcript(text: 'Wendelin.'),
          Transcript(text: 'Mach das Licht an'),
        ],
        audio: mic,
      );
      // The pre-roll ends after the wake word and a pause: decided inside it.
      final pre = cat([speech(600), quiet(1000)]);
      h.pipeline.start(trigger: wake(pre, 200 * 16));
      settle(async);
      expect(h.stt.calls, hasLength(2));
      // The request the microphone heard meanwhile is in the second pass.
      expect(
        h.stt.calls.last.samples,
        greaterThanOrEqualTo(20 * 480),
        reason: 'gepufferte Sprache nicht verworfen',
      );
      expect(mic.lostSamples, 0);
      expect(mic.running, isFalse, reason: 'am Ende gestoppt');
    });
  });

  test('Pegel-Log: nur Zahlen, pro Sekunde (WP146)', () {
    runFake((async) {
      final h = Harness(
        turns: [ScriptedTurn.text('Ok.')],
        transcripts: const [Transcript(text: 'Wie spät ist es')],
      );
      h.fakeAudio.script(
        AudioFrames.pattern('${'S' * 40}${'.' * 30}', frame: frame),
      );
      h.pipeline.start();
      settle(async);
      final levels = h.diagnostics.where((d) => d.startsWith('mic-level'));
      expect(levels, isNotEmpty);
      for (final l in levels) {
        expect(
          l,
          matches(RegExp(r'^mic-level s=\d+ rms=-?\d+ peak=-?\d+ zero=\d+$')),
        );
      }
    });
  });

  test(
    'Diagnose-Zeilen der Übergabe: nur Zahlen und Codes, kein Text (WP146)',
    () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Geheimantwort.')],
          transcripts: const [
            Transcript(text: 'Hey Xylophon.'),
            Transcript(text: 'Mach das Geheimlicht an'),
          ],
        );
        final pre = cat([speech(600), quiet(1000), speech(900), quiet(900)]);
        h.pipeline.start(trigger: wake(pre, 200 * 16));
        settle(async);
        expect(
          h.diagnostics.where(
            (d) => d.startsWith('relisten') || d.startsWith('preroll-fed'),
          ),
          isNotEmpty,
        );
        // Positive list: event name, then key=number|bool pairs.
        final allowed = RegExp(r'^[a-z-]+( \w+=(-?\d+|true|false|[a-z-]+))*$');
        for (final d in h.diagnostics) {
          expect(d, matches(allowed));
          expect(d, isNot(contains('Xylophon')));
          expect(d, isNot(contains('Geheim')));
        }
      });
    },
  );

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

  test('wake-strip: Zahlen zum Rest des Weckworts, nie Text (WP146)', () {
    runFake((async) {
      final h = Harness(
        turns: [ScriptedTurn.text('Licht an.')],
        transcripts: const [
          Transcript(text: 'Dillin schalte das Geheimlicht an'),
        ],
      );
      final content = <(String, Map<String, Object?>)>[];
      h.pipeline.contentLog = (event, fields) => content.add((event, fields));
      h.fakeAudio.script(AudioFrames.pattern('.' * 30, frame: frame));
      final pre = cat([speech(wakeMs), speech(900), quiet(900)]);
      h.pipeline.start(trigger: wake(pre, wakeEnd));
      settle(async);
      final line = h.diagnostics.singleWhere((d) => d.startsWith('wake-strip'));
      // Pre-roll from the wake end: 4 chunks margin, then 26 speech chunks.
      expect(
        line,
        'wake-strip speechMs=780 removed=false firstLen=6 firstDist=5 '
        'tailDist=2 restWords=5',
      );
      expect(line, isNot(contains('Geheim')));
      // Developer mode (WP148): the content goes to contentLog only.
      final c = content.singleWhere((e) => e.$1 == 'wake-strip').$2;
      expect(c['text'], 'Dillin schalte das Geheimlicht an');
      expect(c['rest'], contains('Geheimlicht'));
    });
  });

  test('wake-strip: speechMs endet an der ersten Pause im Vorlauf', () {
    runFake((async) {
      final h = Harness(
        turns: [ScriptedTurn.text('Licht an.')],
        transcripts: const [Transcript(text: 'Wendelin schalte das Licht an')],
      );
      h.fakeAudio.script(AudioFrames.pattern('.' * 30, frame: frame));
      final pre = cat([
        speech(wakeMs),
        speech(300),
        quiet(300),
        speech(300),
        quiet(900),
      ]);
      h.pipeline.start(trigger: wake(pre, wakeEnd));
      settle(async);
      final line = h.diagnostics.singleWhere((d) => d.startsWith('wake-strip'));
      expect(line, contains('speechMs=180 removed=true'));
    });
  });

  test('wakeStripLog: entfernt, Rest leer, zu lang', () {
    expect(
      wakeStripLog('Wendelin mach Licht', 'mach Licht', speechMs: 5),
      'wake-strip speechMs=5 removed=true firstLen=4 firstDist=99 tailDist=4 '
      'restWords=2',
    );
    expect(
      wakeStripLog('Wendelin', '', speechMs: -1),
      'wake-strip speechMs=-1 removed=true firstLen=0 firstDist=-1 '
      'tailDist=-1 restWords=0',
    );
    expect(
      wakeStripLog('Lin mach', 'Lin mach', speechMs: 0),
      contains('removed=false firstLen=3 firstDist=99 tailDist=0'),
    );
    expect(
      wakeStripLog('x', 'Donaudampfschifffahrt', speechMs: 0),
      contains('firstDist=99 tailDist=99'),
    );
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

    test('jede Schreibweise von „Hey“ wird mit entfernt (WP156)', () {
      for (final g in [...heyWords, 'Hallo', 'OK', 'Okay', 'Hej', 'Hay']) {
        expect(
          stripWakeWord('$g Wendelin, schalte an'),
          'schalte an',
          reason: g,
        );
      }
      expect(stripWakeWord('Ei Wendelin'), '');
    });

    test('andere Wörter vor dem Wake Word bleiben stehen (WP156)', () {
      for (final w in ['Danke', 'Also', 'Ach', 'Na', 'Nein']) {
        expect(
          stripWakeWord('$w Wendelin, schalte an'),
          '$w Wendelin, schalte an',
          reason: w,
        );
      }
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

  test(
    'Stoppwort nur als ganze Äußerung: „Licht an“ ist kein Stopp (WP73)',
    () {
      bool stop(String t) => isStopCommand(
        stripWakeWord(t),
        stopWords: VoicePipelineConfig.defaultStopWords,
        fillerWords: VoicePipelineConfig.defaultFillerWords,
        stopPhrases: VoicePipelineConfig.defaultStopPhrases,
      );
      expect(stop('Wendelin, Licht an'), isFalse);
      expect(stop('Wendelin, mach das Licht an, halt nein stopp'), isFalse);
      expect(stop('Wendelin, stopp'), isTrue);
    },
  );

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

    test(
      'Gerät: Pre-Roll nur aus dem Wake Word, Anfrage ohne Pause (WP73)',
      () {
        // 300 ms Wake Word (laut), danach normal laute Sprache. Das Wake Word
        // darf nicht das „Grundrauschen“ sein: ohne Raum davor gibt es keinen
        // Grundpegel, nur die Mindestschwelle.
        final onlyWord = cat([
          level(300, 1500),
          level(200, 60),
          level(1200, 1200),
        ]);
        expect(speechAfterWakeWord(onlyWord, 300 * 16), isTrue);
        // Mit Raum davor (2,5 s Pre-Roll): Raum bestimmt die Schwelle.
        final withRoom = cat([
          level(1700, 50),
          level(800, 1500),
          level(200, 60),
          level(1200, 1200),
        ]);
        expect(speechAfterWakeWord(withRoom, 2500 * 16), isTrue);
        // Stille nach dem Wake Word bleibt Stille (Ton wird gespielt).
        final silent = cat([
          level(1700, 50),
          level(800, 1500),
          level(1500, 50),
        ]);
        expect(speechAfterWakeWord(silent, 2500 * 16), isFalse);
      },
    );

    test('gleichmäßiges Rauschen nach dem Wake Word ist keine Sprache', () {
      final pcm = cat([level(400, 400), level(600, 3000), level(900, 450)]);
      expect(speechAfterWakeWord(pcm, 1000 * 16), isFalse);
      // aber deutlich lauter als der Raum: Sprache
      final louder = cat([level(400, 400), level(600, 3000), level(900, 2000)]);
      expect(speechAfterWakeWord(louder, 1000 * 16), isTrue);
    });
  });

  group('Tonaufnahme der ganzen Interaktion (WP148)', () {
    DevClips hook(List<DevClip> out, {bool on = true}) =>
        DevClips(enabled: () => on, write: out.add);

    test('Vorlauf + Mikrofon in einer Datei, Marken stimmen mit den Samples', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Licht an.')],
          transcripts: const [
            Transcript(text: 'Wendelin.'),
            Transcript(text: 'Mach das Licht an'),
          ],
        );
        final clips = <DevClip>[];
        h.pipeline.devClips = hook(clips);
        h.fakeAudio.script(
          AudioFrames.pattern(
            '${'.' * 10}${'S' * 20}${'.' * 30}',
            frame: frame,
          ),
        );
        final pre = cat([speech(600), quiet(1000)]);
        h.pipeline.start(trigger: wake(pre, 200 * 16));
        settle(async);
        // Zwei Aufnahmen (Weckwort allein, dann der Rest live): je eine Datei.
        final rec = clips.where((c) => c.event == 'rec').toList();
        expect(rec, isNotEmpty);
        final first = rec.first;
        expect(first.marksMs['preRoll'], 0);
        expect(first.marksMs['wakeEnd'], 200);
        // Der Vorlauf steht vollständig und unverändert am Anfang.
        expect(first.pcm.sublist(0, pre.length), pre);
        // Mikrofon (falls geöffnet) beginnt genau hinter dem Vorlauf.
        final mic = rec.last.marksMs['mic'];
        if (mic != null) {
          expect(rec.last.pcm.length, greaterThan(mic * 16));
        }
      });
    });

    test('Entscheidung im Vorlauf: Datei = Vorlauf, ohne Mikrofon', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Licht an.')],
          transcripts: const [Transcript(text: 'Wendelin, mach Licht an.')],
        );
        final clips = <DevClip>[];
        h.pipeline.devClips = hook(clips);
        final pre = cat([speech(600), speech(900), quiet(900)]);
        h.pipeline.start(trigger: wake(pre, 600 * 16));
        settle(async);
        final rec = clips.singleWhere((c) => c.event == 'rec');
        expect(rec.pcm.length, pre.length);
        expect(rec.marksMs.containsKey('mic'), isFalse);
        // Sprache beginnt hinter dem Weckwort (Rand 100 ms), Ende davor.
        expect(rec.marksMs['speechStart'], greaterThanOrEqualTo(600));
        expect(rec.marksMs['speechEnd'], lessThanOrEqualTo(ms(pre.length)));
      });
    });

    test('ohne Entwicklermodus: keine Aufnahme gesammelt', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Licht an.')],
          transcripts: const [Transcript(text: 'Wendelin, mach Licht an.')],
        );
        final clips = <DevClip>[];
        h.pipeline.devClips = hook(clips, on: false);
        h.pipeline.start(
          trigger: wake(cat([speech(600), speech(900), quiet(900)]), 600 * 16),
        );
        settle(async);
        expect(clips, isEmpty);
        expect(h.recording.inputs, isNotEmpty); // die Pipeline lief
      });
    });
  });
}

/// An open microphone with buffered [frames] that are replayed on [start]; a
/// [stop] before drops them (like a restarted microphone).
final class _HeldMic implements AudioInput {
  _HeldMic(this._frames);

  final List<Int16List> _frames;
  bool running = true;
  int lostSamples = 0;

  @override
  bool get isRunning => running;

  @override
  Stream<Int16List> start() {
    if (!running) return const Stream.empty();
    final frames = List.of(_frames);
    _frames.clear();
    return Stream.fromIterable(frames);
  }

  @override
  Future<void> stop() async {
    running = false;
    for (final f in _frames) {
      lostSamples += f.length;
    }
    _frames.clear();
  }
}

int ms(int samples) => samplesToDuration(samples).inMilliseconds;
