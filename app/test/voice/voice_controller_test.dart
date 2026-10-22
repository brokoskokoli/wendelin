import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/l10n/gen/app_localizations_fr.dart';
import 'package:wendelin/ui/design/mic_button.dart';
import 'package:wendelin/voice/level_meter.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_agent/wendelin_agent.dart' show ProviderTarget;
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';

/// One short utterance: 0,3 s speech, then 0,9 s silence.
List<Int16List> utterance() => AudioFrames.pattern('S' * 10 + '.' * 30);

/// Fake voice parts (Audio → VAD → STT → TTS) for the controller.
VoiceComponents fakeVoice({
  List<Transcript> script = const [],
  FakeTextToSpeech? tts,
  AudioInput? audio,
}) => VoiceComponents(
  audio: audio ?? FakeAudioInput(frames: utterance()),
  vad: FakeVoiceActivityDetector(),
  stt: FakeSpeechToText(script),
  textToSpeech: (_) async => tts,
  config: const VoicePipelineConfig(),
);

/// [TestEnv] whose voice parts are [voice] (`null` = no speech).
TestEnv voiceEnv(List<ScriptedTurn> turns, {required VoiceComponents? voice}) =>
    TestEnv(
      providerConfig: scripted(FakeLlmProvider(turns)),
      extraOverrides: [activeVoiceProvider.overrideWith((ref) async => voice)],
    );

Future<ConversationState> waitConv(
  ProviderContainer c,
  bool Function(ConversationState s) test,
) => waitUntil(c, agentControllerProvider, test);

Future<VoiceUiState> waitVoice(
  ProviderContainer c,
  bool Function(VoiceUiState v) test,
) => waitUntil(c, voiceControllerProvider, test);

Future<T> waitUntil<T>(
  ProviderContainer c,
  ProviderListenable<T> provider,
  bool Function(T value) test,
) async {
  final now = c.read(provider);
  if (test(now)) return now;
  final done = Completer<T>();
  final sub = c.listen(provider, (_, next) {
    if (test(next) && !done.isCompleted) done.complete(next);
  });
  try {
    return await done.future.timeout(const Duration(seconds: 5));
  } finally {
    sub.close();
  }
}

const _delete = '{"event_id":"e1"}';

void main() {
  late TestEnv env;
  late ProviderContainer c;

  ProviderContainer start(
    List<ScriptedTurn> turns, {
    required VoiceComponents? voice,
  }) {
    env = voiceEnv(turns, voice: voice);
    return c = env.container();
  }

  tearDown(() => c.dispose());

  VoiceController voice() => c.read(voiceControllerProvider.notifier);

  test(
    'Push-to-talk: Audio → STT → Agent → TTS, mit Auslöser im Audit-Log',
    () async {
      final tts = FakeTextToSpeech();
      final provider = FakeLlmProvider([
        ScriptedTurn.text('Ruhig. Das Wasser hat 19 Grad.'),
      ]);
      env = TestEnv(
        providerConfig: scripted(provider),
        extraOverrides: [
          activeVoiceProvider.overrideWith(
            (ref) async => fakeVoice(
              script: const [
                Transcript(
                  text: 'Wie wird das Meer morgen?',
                  language: 'de',
                  confidence: 0.8,
                ),
              ],
              tts: tts,
            ),
          ),
        ],
      );
      c = env.container();
      final phases = <VoiceState>[];
      c.listen(
        voiceControllerProvider.select((v) => v.phase),
        (_, p) => phases.add(p),
      );

      expect(await voice().start(TriggerKind.pushToTalk), isTrue);
      await voice().whenIdle;

      expect(phases.first, VoiceState.listening);
      expect(
        phases,
        containsAllInOrder([VoiceState.transcribing, VoiceState.thinking]),
      );
      expect(phases.last, VoiceState.idle);
      final s = c.read(agentControllerProvider);
      expect(
        s.entries.whereType<UserEntry>().single.text,
        'Wie wird das Meer morgen?',
      );
      expect(
        s.entries.whereType<AssistantTextEntry>().single.text,
        'Ruhig. Das Wasser hat 19 Grad.',
      );
      expect(tts.spoken, ['Ruhig.', 'Das Wasser hat 19 Grad.']);
      expect(
        provider.requests.single.messages.last.content
            .whereType<TextBlock>()
            .single
            .text,
        'Wie wird das Meer morgen?',
      );

      await c.read(auditRecorderProvider).flush();
      final request = (await env.storage.audit.query()).firstWhere(
        (e) => e.kind == AuditKind.request,
      );
      expect(request.payload, {
        'source': 'voice',
        'trigger': 'pushToTalk',
        'text': 'Wie wird das Meer morgen?',
        'language': 'de',
        'sttConfidence': 0.8,
      });
    },
  );

  test('Tippen beim Zuhören bricht ab: keine Anfrage, Mikrofon aus', () async {
    final audio = FakeAudioInput(
      frames: AudioFrames.pattern('S' * 300),
      frameInterval: const Duration(milliseconds: 5),
    );
    final provider = FakeLlmProvider([ScriptedTurn.text('nie')]);
    env = TestEnv(
      providerConfig: scripted(provider),
      extraOverrides: [
        activeVoiceProvider.overrideWith(
          (ref) async => fakeVoice(audio: audio),
        ),
      ],
    );
    c = env.container();
    await voice().start(TriggerKind.pushToTalk);
    await waitVoice(c, (v) => v.levels.isNotEmpty);
    expect(c.read(voiceControllerProvider).listening, isTrue);

    await voice().tap();
    await voice().whenIdle;
    expect(c.read(voiceControllerProvider).phase, VoiceState.idle);
    expect(audio.isRunning, isFalse);
    expect(provider.requests, isEmpty);
    expect(c.read(agentControllerProvider).entries, isEmpty);
  });

  test('Tippen beim Denken bricht den Lauf ab', () async {
    start([
      ScriptedTurn.hang(partialText: 'Moment'),
    ], voice: fakeVoice(script: const [Transcript(text: 'Erzähl was')]));
    await voice().start(TriggerKind.pushToTalk);
    await waitConv(c, (s) => s.running);
    await waitConv(
      c,
      (s) => s.entries.whereType<AssistantTextEntry>().isNotEmpty,
    );
    expect(c.read(voiceControllerProvider).phase, VoiceState.thinking);

    await voice().tap();
    await voice().whenIdle;
    await c.read(agentControllerProvider.notifier).idle;
    expect(c.read(agentControllerProvider).running, isFalse);
    expect(c.read(voiceControllerProvider).active, isFalse);
  });

  group('Nachfrage bei Ausfall per Stimme (WP128)', () {
    const down = NetworkException('weg');
    late FakeLlmProvider second;

    Future<void> failAndSay(
      List<Transcript> answers, {
      FakeTextToSpeech? tts,
      PrivacyLevel secondPrivacy = PrivacyLevel.standard,
    }) async {
      second = FakeLlmProvider([ScriptedTurn.text('Zweiter hier.')]);
      env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider([ScriptedTurn.error(down), ScriptedTurn.error(down)]),
          others: [
            ProviderTarget(
              profileId: 'zweit',
              modelId: 'zweit-model',
              provider: second,
              privacy: secondPrivacy,
              name: 'Zweit',
            ),
          ],
          names: {'zweit': 'Zweit'},
        ),
        extraOverrides: [
          activeVoiceProvider.overrideWith(
            (ref) async => fakeVoice(
              script: [
                const Transcript(text: 'Wie wird das Wetter', language: 'de'),
                ...answers,
              ],
              tts: tts,
            ),
          ),
        ],
      );
      c = env.container();
      await voice().start(TriggerKind.pushToTalk);
    }

    test('„Ja“ wiederholt den Aufruf beim zweiten Anbieter', () async {
      final tts = FakeTextToSpeech();
      await failAndSay(const [Transcript(text: 'Ja')], tts: tts);
      await voice().whenIdle;
      expect(second.requests, hasLength(1));
      expect(
        tts.spoken,
        contains(
          'Claude Haiku antwortet nicht. Mit Zweit nochmal? '
          'Ja oder nein?',
        ),
      );
      await c.read(auditRecorderProvider).flush();
      final audit = await env.storage.audit.query();
      final offer = audit.firstWhere((e) => e.payload['type'] == 'retryOffer');
      expect(offer.payload['approved'], isTrue);
      expect(offer.payload['failure'], 'network');
      expect(audit.any((e) => e.kind == AuditKind.escalation), isTrue);
    });

    test('„Nein“ lässt es bei der Fehlermeldung, nichts geht raus', () async {
      await failAndSay(const [Transcript(text: 'Nein')]);
      await voice().whenIdle;
      expect(second.requests, isEmpty);
      final s = c.read(agentControllerProvider);
      expect(s.pending, isNull);
      await c.read(auditRecorderProvider).flush();
      final offer = (await env.storage.audit.query()).firstWhere(
        (e) => e.payload['type'] == 'retryOffer',
      );
      expect(offer.payload['approved'], isFalse);
    });
  });

  group('Bestätigung per Stimme', () {
    Future<void> deleteBySaying(
      List<Transcript> answers, {
      FakeTextToSpeech? tts,
    }) async {
      start(
        [
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', _delete),
          ]),
          ScriptedTurn.text('Erledigt.'),
        ],
        voice: fakeVoice(
          script: [
            const Transcript(text: 'Lösch den Zahnarzttermin', language: 'de'),
            ...answers,
          ],
          tts: tts,
        ),
      );
      await env.calendar.createEvent(zahnarztDraft());
      await voice().start(TriggerKind.pushToTalk);
    }

    test('„Ja“ führt das Tool aus; Frage wird vorgelesen', () async {
      final tts = FakeTextToSpeech();
      await deleteBySaying(const [Transcript(text: 'Ja')], tts: tts);
      await voice().whenIdle;
      expect(env.calendar.events, isEmpty);
      expect(c.read(agentControllerProvider).tool('c1')!.phase, ToolPhase.done);
      expect(tts.spoken, contains('Termin löschen? Ja oder nein?'));
      await c.read(auditRecorderProvider).flush();
      final confirmation = (await env.storage.audit.query()).firstWhere(
        (e) => e.kind == AuditKind.confirmation,
      );
      expect(confirmation.payload['approved'], isTrue);
    });

    test(
      'external: nur strikte Zustimmung, „Ja, bitte“/„Okay, warte“ → Tipp',
      () async {
        final tts = FakeTextToSpeech();
        await deleteBySaying(const [
          Transcript(text: 'Ja, bitte'),
          Transcript(text: 'Okay, warte'),
        ], tts: tts);
        await waitConv(c, (s) => s.pending != null);
        await waitVoice(
          c,
          (v) =>
              !v.awaitingAnswer &&
              tts.spoken.contains('Bitte sag ja oder nein.'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(c.read(agentControllerProvider).pending!.answered, isFalse);
        expect(env.calendar.events, hasLength(1));
        c.read(agentControllerProvider.notifier).answer(approved: false);
        await voice().whenIdle;
      },
    );

    test('„Nein“ lehnt ab, das Tool läuft nicht', () async {
      await deleteBySaying(const [Transcript(text: 'Nein')]);
      await voice().whenIdle;
      expect(env.calendar.events, hasLength(1));
      expect(
        c.read(agentControllerProvider).tool('c1')!.phase,
        ToolPhase.declined,
      );
    });

    test('unklar: einmal nachfragen, danach bleibt nur der Tipp', () async {
      final tts = FakeTextToSpeech();
      await deleteBySaying(const [
        Transcript(text: 'Vielleicht'),
        Transcript(text: 'Hm, mal sehen'),
      ], tts: tts);
      await waitConv(c, (s) => s.pending != null);
      // Zwei Versuche, dann wartet die Karte auf einen Tipp.
      await waitVoice(
        c,
        (v) =>
            !v.awaitingAnswer && tts.spoken.contains('Bitte sag ja oder nein.'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final pending = c.read(agentControllerProvider).pending;
      expect(pending, isNotNull);
      expect(pending!.answered, isFalse);
      c.read(agentControllerProvider.notifier).answer(approved: true);
      await voice().whenIdle;
      expect(env.calendar.events, isEmpty);
    });

    test('Tipp während des Zuhörens beendet die Aufnahme', () async {
      final audio = FakeAudioInput(
        frames: AudioFrames.pattern('S' * 10 + '.' * 30),
        frameInterval: const Duration(milliseconds: 2),
      );
      final stt = FakeSpeechToText(const [
        Transcript(text: 'Lösch den Zahnarzttermin'),
      ]);
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
              audio: audio,
              vad: FakeVoiceActivityDetector(),
              stt: stt,
              textToSpeech: (_) async => null,
              config: const VoicePipelineConfig(),
            ),
          ),
        ],
      );
      c = env.container();
      await env.calendar.createEvent(zahnarztDraft());
      await voice().start(TriggerKind.pushToTalk);
      await waitVoice(c, (v) => v.awaitingAnswer);
      audio.script(AudioFrames.pattern('S' * 2000));
      c.read(agentControllerProvider.notifier).answer(approved: false);
      await waitVoice(c, (v) => !v.awaitingAnswer);
      await voice().whenIdle;
      expect(audio.isRunning, isFalse);
      expect(stt.calls, hasLength(1), reason: 'keine Erkennung der Antwort');
      expect(env.calendar.events, hasLength(1));
    });

    test('Abbruch stoppt die gesprochene Bestätigungsfrage (N11)', () async {
      final tts = FakeTextToSpeech(manual: true);
      final audio = FakeAudioInput(
        frames: AudioFrames.pattern('S' * 10 + '.' * 30),
        frameInterval: const Duration(milliseconds: 2),
      );
      final stt = FakeSpeechToText(const [
        Transcript(text: 'Lösch den Zahnarzttermin'),
      ]);
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
              audio: audio,
              vad: FakeVoiceActivityDetector(),
              stt: stt,
              textToSpeech: (_) async => tts,
              config: const VoicePipelineConfig(),
            ),
          ),
        ],
      );
      c = env.container();
      await env.calendar.createEvent(zahnarztDraft());
      await voice().start(TriggerKind.pushToTalk);
      // Die Frage läuft (manuelle Sprachausgabe endet erst mit stop).
      for (var i = 0; i < 100 && tts.current == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(tts.current, 'Termin löschen? Ja oder nein?');
      final starts = audio.startCount;

      await voice().cancel();
      await voice().whenIdle;
      expect(tts.interrupted, ['Termin löschen? Ja oder nein?']);
      expect(tts.current, isNull);
      expect(tts.state, TtsState.idle);
      // Kein Zuhören auf die Antwort danach, nichts gelöscht.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(audio.startCount, starts);
      expect(c.read(voiceControllerProvider).awaitingAnswer, isFalse);
      expect(stt.calls, hasLength(1));
      expect(env.calendar.events, hasLength(1));
      expect(c.read(agentControllerProvider).running, isFalse);
    });

    test('getippte Anfrage: keine Stimm-Bestätigung', () async {
      start([
        ScriptedTurn.toolCalls([call('c1', 'calendar__delete_event', _delete)]),
        ScriptedTurn.text('Gut.'),
      ], voice: fakeVoice(script: const [Transcript(text: 'Ja')]));
      await env.calendar.createEvent(zahnarztDraft());
      // Voice controller exists, but the request is typed.
      c.read(voiceControllerProvider);
      await c.read(agentControllerProvider.notifier).send('Lösch den Termin');
      await waitConv(c, (s) => s.pending != null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(voiceControllerProvider).awaitingAnswer, isFalse);
      expect(c.read(agentControllerProvider).pending!.answered, isFalse);
      c.read(agentControllerProvider.notifier).answer(approved: false);
      await c.read(agentControllerProvider.notifier).idle;
    });
  });

  test(
    'erst Sprache, dann getippte Anfrage: keine Stimm-Bestätigung',
    () async {
      final stt = FakeSpeechToText(const [
        Transcript(text: 'Wie spät ist es?'),
        Transcript(text: 'Ja'),
      ]);
      env = voiceEnv(
        [
          ScriptedTurn.text('Acht Uhr.'),
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', _delete),
          ]),
          ScriptedTurn.text('Gut.'),
        ],
        voice: VoiceComponents(
          audio: FakeAudioInput(frames: utterance()),
          vad: FakeVoiceActivityDetector(),
          stt: stt,
          textToSpeech: (_) async => null,
          config: const VoicePipelineConfig(),
        ),
      );
      c = env.container();
      await env.calendar.createEvent(zahnarztDraft());
      await voice().start(TriggerKind.pushToTalk);
      await voice().whenIdle;
      expect(c.read(voiceControllerProvider).active, isFalse);

      await c.read(agentControllerProvider.notifier).send('Lösch den Termin');
      await waitConv(c, (s) => s.pending != null);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.read(voiceControllerProvider).awaitingAnswer, isFalse);
      expect(
        stt.calls,
        hasLength(1),
        reason: 'kein Mitschnitt für die Antwort',
      );
      expect(c.read(agentControllerProvider).pending!.answered, isFalse);
      c.read(agentControllerProvider.notifier).answer(approved: false);
      await c.read(agentControllerProvider.notifier).idle;
      expect(env.calendar.events, hasLength(1));
    },
  );

  test(
    'suspend: Mikrofon aus, Sprachausgabe gestoppt, Lauf abgebrochen',
    () async {
      final tts = FakeTextToSpeech(manual: true);
      start(
        [ScriptedTurn.text('Ein langer Satz. Und noch einer.')],
        voice: fakeVoice(
          script: const [Transcript(text: 'Erzähl was')],
          tts: tts,
        ),
      );
      await voice().start(TriggerKind.pushToTalk);
      await waitVoice(c, (v) => v.phase == VoiceState.speaking);
      expect(tts.state, TtsState.speaking);
      await voice().suspend();
      expect(tts.state, TtsState.idle);
      expect(tts.stops, greaterThan(0));
      expect(c.read(voiceControllerProvider).active, isFalse);

      // Getippte Anfrage läuft: suspend bricht sie ab.
      c.dispose();
      start([ScriptedTurn.hang(partialText: 'Moment')], voice: fakeVoice());
      unawaited(c.read(agentControllerProvider.notifier).send('Hallo'));
      await waitConv(
        c,
        (s) => s.entries.whereType<AssistantTextEntry>().isNotEmpty,
      );
      await voice().suspend();
      await c.read(agentControllerProvider.notifier).idle;
      expect(c.read(agentControllerProvider).running, isFalse);
    },
  );

  test('Ducking-Fokus busy: Denken/Sprechen an, Ende und Reset aus', () async {
    final tts = FakeTextToSpeech(manual: true);
    start(
      [ScriptedTurn.text('Ein langer Satz. Und noch einer.')],
      voice: fakeVoice(
        script: const [Transcript(text: 'Erzähl was')],
        tts: tts,
      ),
    );
    final focus = c.read(speechFocusProvider);
    expect(focus.busy, isFalse);
    await voice().start(TriggerKind.pushToTalk);
    await waitVoice(c, (v) => v.phase == VoiceState.speaking);
    expect(focus.busy, isTrue);
    await voice().suspend();
    await waitVoice(c, (v) => v.phase == VoiceState.idle);
    expect(focus.busy, isFalse);

    // Reset (demo switch) during the answer: busy must not stay set.
    await voice().start(TriggerKind.pushToTalk);
    await waitVoice(c, (v) => v.phase == VoiceState.speaking);
    expect(focus.busy, isTrue);
    await c.read(demoModeProvider.notifier).set(enabled: true);
    await Future<void>.delayed(Duration.zero);
    expect(focus.busy, isFalse);
  });

  test('ohne Spracherkennung: kein Start, Hinweis', () async {
    start(const [], voice: null);
    expect(await voice().start(TriggerKind.pushToTalk), isFalse);
    expect(c.read(voiceControllerProvider).error, voiceUnavailableError);
  });

  test(
    'ohne Spracherkennung: keine Frage nach dem Mikrofon (WP18-Review a)',
    () async {
      var asked = 0;
      start(const [], voice: null);
      expect(
        await voice().start(
          TriggerKind.pushToTalk,
          prepare: () async {
            asked++;
            return true;
          },
        ),
        isFalse,
      );
      expect(asked, 0);
      expect(c.read(voiceControllerProvider).error, voiceUnavailableError);
    },
  );

  test('Mikrofon verweigert: Fehlertext, wieder bereit', () async {
    start(const [], voice: fakeVoice(audio: DeniedAudioInput()));
    await voice().start(TriggerKind.pushToTalk);
    await voice().whenIdle;
    final v = c.read(voiceControllerProvider);
    expect(v.error, 'Kein Zugriff auf das Mikrofon.');
    expect(v.active, isFalse);
  });

  test('prepare verneint (keine Berechtigung): kein Start', () async {
    var asked = 0;
    start(const [], voice: fakeVoice());
    expect(
      await voice().start(
        TriggerKind.pushToTalk,
        prepare: () async {
          asked++;
          return false;
        },
      ),
      isFalse,
    );
    expect(asked, 1);
    expect(c.read(voiceControllerProvider).error, contains('Mikrofon'));
  });

  group('während der Berechtigungsfrage (M9)', () {
    test('getippte Anfrage gestartet: kein Zuhören danach', () async {
      final audio = FakeAudioInput(frames: utterance());
      start([
        ScriptedTurn.hang(partialText: 'Moment'),
      ], voice: fakeVoice(audio: audio));
      final started = await voice().start(
        TriggerKind.pushToTalk,
        prepare: () async {
          // Der Nutzer tippt, während der Dialog offen ist.
          unawaited(c.read(agentControllerProvider.notifier).send('Getippt'));
          await waitConv(c, (s) => s.running);
          return true;
        },
      );
      expect(started, isFalse);
      expect(audio.startCount, 0);
      expect(c.read(voiceControllerProvider).active, isFalse);
      c.read(agentControllerProvider.notifier).cancel();
      await c.read(agentControllerProvider.notifier).idle;
    });

    test('andere Sprach-Anfrage gestartet: keine zweite', () async {
      final audio = FakeAudioInput(
        frames: utterance(),
        frameInterval: const Duration(milliseconds: 20),
      );
      start(
        [ScriptedTurn.text('Gut.')],
        voice: fakeVoice(
          audio: audio,
          script: const [Transcript(text: 'Hallo')],
        ),
      );
      final started = await voice().start(
        TriggerKind.assistant,
        prepare: () async {
          expect(await voice().start(TriggerKind.pushToTalk), isTrue);
          await waitVoice(c, (v) => v.listening);
          return true;
        },
      );
      expect(started, isFalse);
      expect(audio.startCount, 1, reason: 'nur die erste Anfrage hört zu');
      expect(c.read(voiceControllerProvider).trigger, TriggerKind.pushToTalk);
      await voice().cancel();
      await voice().whenIdle;
    });
  });

  test('nichts verstanden: Hinweis', () async {
    start(
      const [],
      voice: fakeVoice(
        audio: FakeAudioInput(
          frames: AudioFrames.pattern('.' * 20),
          closeAfterFrames: true,
        ),
      ),
    );
    await voice().start(TriggerKind.pushToTalk);
    await voice().whenIdle;
    expect(c.read(voiceControllerProvider).hint, 'Ich habe nichts verstanden.');
  });

  test('Mikrofon-Zustand je Lage', () {
    const idle = VoiceUiState();
    const listening = VoiceUiState(phase: VoiceState.listening);
    const answering = VoiceUiState(awaitingAnswer: true);
    const speaking = VoiceUiState(phase: VoiceState.speaking);
    const preparing = VoiceUiState(preparing: true);
    final cases = <(VoiceUiState, bool, bool, MicState)>[
      (idle, true, false, MicState.idle),
      (idle, false, false, MicState.disabled),
      (idle, false, true, MicState.thinking),
      (idle, true, true, MicState.thinking),
      (listening, true, false, MicState.listening),
      (answering, true, true, MicState.listening),
      (speaking, true, true, MicState.speaking),
      (preparing, true, false, MicState.preparing),
    ];
    for (final (v, available, running, expected) in cases) {
      expect(
        micStateFor(v, available: available, running: running),
        expected,
        reason: '$v $available $running',
      );
    }
  });

  test('Rückfragen in de/fr/en', () {
    final tool = ToolQuestion(
      ConfirmationRequired(
        call: call('c', 'calendar__delete_event', '{}'),
        description: 'x',
        respond: (_) {},
      ),
      request: 'r',
    );
    expect(confirmationPrompt(tool, 'de'), 'Termin löschen? Ja oder nein?');
    expect(confirmationPrompt(tool, null), 'Termin löschen? Ja oder nein?');
    expect(
      confirmationPrompt(tool, 'fr-FR'),
      'Supprimer le rendez-vous ? Oui ou non ?',
    );
    expect(
      confirmationPrompt(tool, 'en'),
      'Delete the appointment? Yes or no?',
    );
    ToolQuestion q(String name, RiskLevel risk) => ToolQuestion(
      ConfirmationRequired(
        call: call('c', name, '{}'),
        description: 'x',
        risk: risk,
        respond: (_) {},
      ),
      request: 'r',
    );
    expect(
      confirmationPrompt(q('memory__forget', RiskLevel.write), 'en'),
      'Delete: memory forget? Yes or no?',
    );
    expect(
      confirmationPrompt(q('web__fetch', RiskLevel.read), 'fr'),
      'Exécuter : web fetch ? Oui ou non ?',
    );
    expect(strictAnswer(q('web__fetch', RiskLevel.read)), isFalse);
    expect(
      strictAnswer(q('calendar__delete_event', RiskLevel.external)),
      isTrue,
    );
    final escalation = EscalationQuestion(
      EscalationConfirmationRequired(
        fromProfile: 'a',
        toProfile: 'b',
        reason: EscalationReason.userRequested,
        respond: (_) {},
      ),
      fromName: 'Phala',
      toName: 'Claude',
    );
    expect(strictAnswer(escalation), isTrue);
    final offer = RetryOfferQuestion(
      RetryOfferRequired(
        fromProfile: 'a',
        toProfile: 'b',
        error: const NetworkException('x'),
        respond: (_) {},
      ),
      fromName: 'Phala',
      toName: 'Claude',
    );
    expect(strictAnswer(offer), isTrue);
    // Like the escalation: a casual „ja, aber …“ does not send the request
    // to another provider.
    YesNo? parse(String t) =>
        VoiceController.recognizer.parse(t, strict: strictAnswer(offer));
    expect(parse('Ja, aber lieber morgen'), isNull);
    expect(parse('ja'), YesNo.yes);
    expect(
      confirmationPrompt(offer, 'en'),
      'Phala is not answering. Try again with Claude? Yes or no?',
    );
    expect(confirmationPrompt(offer, 'fr'), contains('Réessayer avec Claude'));
    expect(
      confirmationPrompt(escalation, 'en'),
      'Hand over to Claude? Yes or no?',
    );
    expect(
      confirmationPrompt(escalation, 'fr'),
      contains('Transmettre à Claude'),
    );
    expect(repeatPrompt('fr'), contains('oui ou non'));
    expect(repeatPrompt('en'), 'Please say yes or no.');
    expect(
      voiceErrorText(AppLocalizationsDe(), StateError('x')),
      isNot(contains('Bad state')),
    );
    expect(
      voiceErrorText(AppLocalizationsDe(), StateError('x')),
      isNot(contains('belegt')),
    );
    expect(
      voiceErrorText(
        AppLocalizationsDe(),
        const VoiceException(
          VoiceErrorKind.busy,
          'Das Mikrofon war noch belegt.',
        ),
      ),
      contains('belegt'),
    );
    expect(
      voiceErrorText(
        AppLocalizationsDe(),
        const VoiceException(VoiceErrorKind.modelMissing, 'egal'),
      ),
      AppLocalizationsDe().voiceErrorModelMissing,
    );
    expect(
      voiceErrorText(
        AppLocalizationsFr(),
        const VoiceException(VoiceErrorKind.busy, 'egal'),
      ),
      AppLocalizationsFr().voiceErrorMicBusy,
    );
    expect(
      voiceErrorText(AppLocalizationsDe(), ArgumentError('geheim')),
      isNot(contains('geheim')),
    );
    expect(
      voiceErrorText(AppLocalizationsDe(), ArgumentError('x')),
      contains('Sprache'),
    );
  });

  test('Pegel: Stille 0, Sprache deutlich, höchstens 6 Balken', () async {
    expect(MeteredAudioInput.levelOf(AudioFrames.silence()), 0);
    expect(MeteredAudioInput.levelOf(AudioFrames.speech()), greaterThan(0.4));
    expect(MeteredAudioInput.levelOf(Int16List(0)), 0);
    final audio = FakeAudioInput(
      frames: AudioFrames.pattern('S' * 200),
      frameInterval: const Duration(milliseconds: 2),
    );
    start(const [], voice: fakeVoice(audio: audio));
    await voice().start(TriggerKind.pushToTalk);
    final v = await waitVoice(c, (v) => v.levels.length == waveBars);
    expect(v.levels.every((l) => l > 0.4), isTrue);
    await voice().cancel();
  });
}
