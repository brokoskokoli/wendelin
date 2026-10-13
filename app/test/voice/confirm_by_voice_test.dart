// B7 (Gerätetest 2026-10-13): after the spoken question Wendelin sometimes
// did not listen, without error or hint. Every way out of the spoken
// confirmation must end in listening (an answer) or in „Antworte per
// Tipp“, with exactly one `confirm-exit` line (WP30).

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'voice_controller_test.dart' show utterance, waitConv, waitVoice;

const _delete = '{"event_id":"e1"}';
const _question = 'Termin löschen? Ja oder nein?';
const _tapPrompt = 'Antworte bitte per Tipp.';

/// Speech output whose utterances end at once, unless they [hang] (the
/// engine never reports the end, until [stop]) or [fail].
final class ScriptedTts implements TextToSpeech {
  ScriptedTts({this.hang = const {}, this.fail = const {}});

  final Set<String> hang;
  final Set<String> fail;
  final spoken = <String>[];
  final _states = StreamController<TtsState>.broadcast(sync: true);
  final _hanging = Queue<Completer<void>>();
  TtsState _state = TtsState.idle;
  int stops = 0;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<TtsVoice>> voices() async => const [];

  @override
  TtsState get state => _state;

  @override
  Stream<TtsState> get states => _states.stream;

  void _set(TtsState s) {
    _state = s;
    _states.add(s);
  }

  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) async {
    spoken.add(text);
    if (fail.contains(text)) throw StateError('TTS kaputt');
    _set(TtsState.speaking);
    if (hang.contains(text)) {
      final c = Completer<void>();
      _hanging.add(c);
      await c.future;
    } else {
      await Future<void>.delayed(Duration.zero);
    }
    _set(TtsState.idle);
  }

  @override
  Future<void> stop() async {
    stops++;
    while (_hanging.isNotEmpty) {
      _hanging.removeFirst().complete();
    }
  }
}

/// Microphone whose [startsLeft]-th start fails, or whose recordings
/// after [silentFrom] deliver nothing; [stuck] keeps reporting a running
/// recording until the next [stop] (a stop that did not finish yet).
final class FlakyAudioInput implements AudioInput {
  FlakyAudioInput(this.inner);

  final FakeAudioInput inner;
  int starts = 0;
  int? failOn;
  int? silentFrom;
  bool stuck = false;

  /// Frames of every recording after the first (the answer).
  List<Int16List>? answer;
  // Closed in stop().
  // ignore: close_sinks
  StreamController<Int16List>? _silent;

  @override
  bool get isRunning => stuck || _silent != null || inner.isRunning;

  @override
  Stream<Int16List> start() {
    starts++;
    if (starts == failOn) throw StateError('AudioRecord fehlt');
    if (silentFrom != null && starts >= silentFrom!) {
      return (_silent = StreamController<Int16List>()).stream;
    }
    if (starts > 1 && answer != null) inner.script(answer!);
    return inner.start();
  }

  @override
  Future<void> stop() async {
    stuck = false;
    final silent = _silent;
    _silent = null;
    await silent?.close();
    await inner.stop();
  }
}

void main() {
  late TestEnv env;
  late ProviderContainer c;
  final lines = <String>[];
  late void Function(String) savedSink;

  setUp(() {
    lines.clear();
    savedSink = voiceLogSink;
    voiceLogSink = lines.add;
    VoiceController.micStartTimeout = const Duration(milliseconds: 150);
    VoiceController.promptTimeout = const Duration(milliseconds: 200);
  });
  tearDown(() {
    voiceLogSink = savedSink;
    VoiceController.micStartTimeout = const Duration(seconds: 3);
    VoiceController.promptTimeout = const Duration(seconds: 15);
    c.dispose();
  });

  VoiceController voice() => c.read(voiceControllerProvider.notifier);
  List<String> exits() => [
    for (final l in lines)
      if (l.contains(' confirm-exit ')) l,
  ];

  /// „Lösch den Zahnarzttermin“ by voice; [answers] are the transcripts of
  /// the recordings after the question.
  Future<void> deleteByVoice({
    required List<Transcript> answers,
    required TextToSpeech tts,
    FlakyAudioInput? audio,
    FakeSpeechToText? stt,
    List<ScriptedTurn>? turns,
  }) async {
    final input = audio ?? FlakyAudioInput(FakeAudioInput(frames: utterance()));
    env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider(
          turns ??
              [
                ScriptedTurn.toolCalls([
                  call('c1', 'calendar__delete_event', _delete),
                ]),
                ScriptedTurn.text('Erledigt.'),
              ],
        ),
      ),
      extraOverrides: [
        activeVoiceProvider.overrideWith(
          (ref) async => VoiceComponents(
            audio: input,
            vad: FakeVoiceActivityDetector(),
            stt:
                stt ??
                FakeSpeechToText([
                  const Transcript(text: 'Lösch den Zahnarzttermin'),
                  ...answers,
                ]),
            textToSpeech: (_) async => tts,
            config: const VoicePipelineConfig(),
          ),
        ),
      ],
    );
    c = env.container();
    await env.calendar.createEvent(zahnarztDraft());
    expect(await voice().start(TriggerKind.pushToTalk), isTrue);
  }

  /// The open confirmation now waits for a tap, and Wendelin said so.
  Future<void> expectTapOnly(ScriptedTts tts, String reason) async {
    await waitVoice(c, (v) => v.tapOnly);
    final v = c.read(voiceControllerProvider);
    expect(v.answersByVoice, isFalse, reason: 'Karte: „Antworte per Tipp“');
    expect(v.awaitingAnswer, isFalse);
    for (var i = 0; i < 50 && !tts.spoken.contains(_tapPrompt); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(tts.spoken, contains(_tapPrompt));
    expect(exits(), hasLength(1));
    expect(exits().single, contains('reason=$reason'));
    expect(exits().single, contains('tap=true'));
    expect(c.read(agentControllerProvider).pending!.answered, isFalse);
    c.read(agentControllerProvider.notifier).answer(approved: false);
    await voice().whenIdle;
    expect(env.calendar.events, hasLength(1));
    expect(c.read(voiceControllerProvider).tapOnly, isFalse);
  }

  /// Listened and the spoken „Ja“ ran the tool.
  Future<void> expectAnswered() async {
    await voice().whenIdle;
    expect(env.calendar.events, isEmpty);
    expect(c.read(agentControllerProvider).tool('c1')!.phase, ToolPhase.done);
    expect(exits(), hasLength(1));
    expect(exits().single, contains('reason=answered(yes)'));
  }

  group('Ausstiegswege der Stimm-Bestätigung (B7)', () {
    test('Normalfall: Frage, Zuhören, „Ja“', () async {
      final tts = ScriptedTts();
      await deleteByVoice(
        answers: const [Transcript(text: 'Ja')],
        tts: tts,
      );
      await expectAnswered();
      expect(tts.spoken, contains(_question));
      expect(
        lines.where(
          (l) => l.contains(' confirm-prompt ') && l.contains('source=confirm'),
        ),
        isNotEmpty,
      );
    });

    test('Frage kommt, während die Antwort noch gesprochen wird', () async {
      final tts = ScriptedTts();
      await deleteByVoice(
        answers: const [Transcript(text: 'Ja')],
        tts: tts,
        turns: [
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', _delete),
          ], text: 'Ich schaue nach. Gleich weg.'),
          ScriptedTurn.text('Erledigt.'),
        ],
      );
      await expectAnswered();
      final question = tts.spoken.indexOf(_question);
      expect(question, greaterThan(tts.spoken.indexOf('Ich schaue nach.')));
    });

    test(
      'Sprachausgabe meldet das Ende der Frage nie: trotzdem zuhören',
      () async {
        // flutter_tts 4.2.5 completes `speak` only on onDone; after onStop or
        // onError the future stays open. Before WP30 the confirmation then
        // waited (up to 2 min) and never listened.
        final tts = ScriptedTts(hang: {_question});
        await deleteByVoice(
          answers: const [Transcript(text: 'Ja')],
          tts: tts,
        );
        await expectAnswered();
        expect(tts.stops, greaterThan(0));
        expect(lines.any((l) => l.contains('result=tts-timeout')), isTrue);
      },
    );

    test('Sprachausgabe der Frage scheitert: trotzdem zuhören', () async {
      final tts = ScriptedTts(fail: {_question});
      await deleteByVoice(
        answers: const [Transcript(text: 'Ja')],
        tts: tts,
      );
      await expectAnswered();
      expect(lines.any((l) => l.contains('result=tts-error')), isTrue);
    });

    test('Mikrofon liefert keine Frames: „Antworte per Tipp“', () async {
      final tts = ScriptedTts();
      final audio = FlakyAudioInput(FakeAudioInput(frames: utterance()))
        ..silentFrom = 2;
      await deleteByVoice(answers: const [], tts: tts, audio: audio);
      await expectTapOnly(tts, 'capture-null(mic-timeout)');
    });

    test('Mikrofon-Start wirft: „Antworte per Tipp“', () async {
      final tts = ScriptedTts();
      final audio = FlakyAudioInput(FakeAudioInput(frames: utterance()))
        ..failOn = 2;
      await deleteByVoice(answers: const [], tts: tts, audio: audio);
      await expectTapOnly(tts, 'capture-null(start-error)');
    });

    test('vorige Aufnahme meldet noch „läuft“: stoppen und zuhören', () async {
      final tts = ScriptedTts();
      final audio = FlakyAudioInput(FakeAudioInput(frames: utterance()));
      await deleteByVoice(
        answers: const [Transcript(text: 'Ja')],
        tts: tts,
        audio: audio,
      );
      // The stop of the command recording has not finished when the
      // question arrives (H2).
      await waitVoice(c, (v) => v.phase == VoiceState.thinking);
      audio.stuck = true;
      await expectAnswered();
      expect(
        lines.any(
          (l) => l.contains(' confirm-wait ') && l.contains('audio-running'),
        ),
        isTrue,
      );
    });

    test('nichts gesagt: „Antworte per Tipp“', () async {
      final tts = ScriptedTts();
      await deleteByVoice(
        answers: const [],
        tts: tts,
        audio: FlakyAudioInput(FakeAudioInput(frames: utterance()))
          ..answer = AudioFrames.pattern('.' * 220),
      );
      await expectTapOnly(tts, 'capture-null(no-speech)');
    });

    test('zweimal unklar: „Antworte per Tipp“', () async {
      final tts = ScriptedTts();
      await deleteByVoice(
        answers: const [
          Transcript(text: 'Vielleicht'),
          Transcript(text: 'Hm, mal sehen'),
        ],
        tts: tts,
      );
      await expectTapOnly(tts, 'unclear');
      expect(tts.spoken, contains('Bitte sag ja oder nein.'));
    });

    test('Erkennung der Antwort scheitert: „Antworte per Tipp“', () async {
      final tts = ScriptedTts();
      final stt = FakeSpeechToText([
        const Transcript(text: 'Lösch den Zahnarzttermin'),
      ]);
      await deleteByVoice(answers: const [], tts: tts, stt: stt);
      await waitVoice(c, (v) => v.awaitingAnswer);
      stt.nextError = const VoiceException(VoiceErrorKind.failed, 'kaputt');
      await expectTapOnly(tts, 'stt-error');
    });

    test('ohne Sprachausgabe: zuhören, ohne Antwort nur Tipp', () async {
      final inner = FlakyAudioInput(FakeAudioInput(frames: utterance()))
        ..answer = AudioFrames.pattern('.' * 220);
      env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider([
            ScriptedTurn.toolCalls([
              call('c1', 'calendar__delete_event', _delete),
            ]),
            ScriptedTurn.text('Erledigt.'),
          ]),
        ),
        extraOverrides: [
          activeVoiceProvider.overrideWith(
            (ref) async => VoiceComponents(
              audio: inner,
              vad: FakeVoiceActivityDetector(),
              stt: FakeSpeechToText(const [
                Transcript(text: 'Lösch den Zahnarzttermin'),
              ]),
              textToSpeech: (_) async => null,
              config: const VoicePipelineConfig(),
            ),
          ),
        ],
      );
      c = env.container();
      await env.calendar.createEvent(zahnarztDraft());
      await voice().start(TriggerKind.pushToTalk);
      await waitVoice(c, (v) => v.tapOnly);
      expect(exits().single, contains('reason=capture-null(no-speech)'));
      expect(c.read(voiceControllerProvider).answersByVoice, isFalse);
      c.read(agentControllerProvider.notifier).answer(approved: false);
      await voice().whenIdle;
    });

    test('Tipp-Antwort während der Frage: kein Tipp-Hinweis', () async {
      final tts = ScriptedTts(hang: {_question});
      VoiceController.promptTimeout = const Duration(seconds: 5);
      await deleteByVoice(answers: const [], tts: tts);
      for (var i = 0; i < 100 && !tts.spoken.contains(_question); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      c.read(agentControllerProvider.notifier).answer(approved: false);
      await tts.stop();
      await voice().whenIdle;
      expect(exits(), hasLength(1));
      expect(exits().single, contains('reason=not-open(answered)'));
      expect(tts.spoken, isNot(contains(_tapPrompt)));
      expect(c.read(voiceControllerProvider).tapOnly, isFalse);
    });

    test(
      'zweite Frage, während die erste noch ausläuft: auch sie wird gehört',
      () async {
        // First question answered by tap while its spoken question still
        // plays; the second confirmation of the same request arrives
        // before the first one has wound down (H4). Before WP30 it was
        // silently skipped.
        final tts = ScriptedTts(hang: {_question});
        VoiceController.promptTimeout = const Duration(seconds: 5);
        await deleteByVoice(
          answers: const [Transcript(text: 'Nein')],
          tts: tts,
          turns: [
            ScriptedTurn.toolCalls([
              call('c1', 'calendar__delete_event', _delete),
              call('c2', 'calendar__delete_event', _delete),
            ]),
            ScriptedTurn.text('Erledigt.'),
          ],
        );
        for (var i = 0; i < 100 && !tts.spoken.contains(_question); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final first = c.read(agentControllerProvider).pending;
        c.read(agentControllerProvider.notifier).answer(approved: true);
        await waitConv(
          c,
          (s) => s.pending != null && !identical(s.pending, first),
        );
        // Only now the first spoken question ends.
        await tts.stop();
        await voice().whenIdle;
        expect(exits(), hasLength(2));
        expect(exits().first, contains('reason=not-open(answered)'));
        expect(exits().last, contains('reason=answered(no)'));
        expect(
          c.read(agentControllerProvider).tool('c2')!.phase,
          ToolPhase.declined,
        );
      },
    );

    test('Abbruch während der Frage: kein Zuhören, kein Hinweis', () async {
      final tts = ScriptedTts(hang: {_question});
      VoiceController.promptTimeout = const Duration(seconds: 5);
      await deleteByVoice(answers: const [], tts: tts);
      for (var i = 0; i < 100 && !tts.spoken.contains(_question); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await voice().cancel();
      await voice().whenIdle;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(exits(), hasLength(1));
      expect(exits().single, contains('reason=not-open(cancelled)'));
      expect(tts.spoken, isNot(contains(_tapPrompt)));
      expect(env.calendar.events, hasLength(1));
    });
  });

  test('getippte Anfrage: kein Zuhören, keine Ausstiegszeile', () async {
    final tts = ScriptedTts();
    await deleteByVoice(
      answers: const [],
      tts: tts,
      turns: [
        ScriptedTurn.text('Hallo.'),
        ScriptedTurn.toolCalls([call('c1', 'calendar__delete_event', _delete)]),
        ScriptedTurn.text('Gut.'),
      ],
    );
    await voice().whenIdle;
    await c.read(agentControllerProvider.notifier).send('Lösch den Termin');
    await waitConv(c, (s) => s.pending != null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(exits(), isEmpty);
    expect(c.read(voiceControllerProvider).answersByVoice, isFalse);
    c.read(agentControllerProvider.notifier).answer(approved: false);
    await c.read(agentControllerProvider.notifier).idle;
  });
}
