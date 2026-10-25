import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/conversation_offer.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'voice_controller_test.dart' show utterance, waitVoice;

const _eins = Transcript(text: 'Eins', language: 'de');
const _zwei = Transcript(text: 'Zwei', language: 'de');

VoiceComponents _components({
  required FakeAudioInput audio,
  FakeTextToSpeech? tts,
  VoicePipelineConfig config = const VoicePipelineConfig(),
  BargeInDetector? detector,
  List<Transcript> script = const [_eins, _zwei],
}) => VoiceComponents(
  audio: audio,
  vad: FakeVoiceActivityDetector(),
  stt: FakeSpeechToText(script),
  textToSpeech: (_) async => tts,
  config: config,
  bargeInDetector: detector,
);

void main() {
  late ProviderContainer c;
  late List<String> log;
  late void Function(String) savedSink;

  setUp(() {
    log = [];
    savedSink = voiceLogSink;
    voiceLogSink = log.add;
  });
  tearDown(() {
    voiceLogSink = savedSink;
    c.dispose();
  });

  ProviderContainer open(
    List<ScriptedTurn> turns,
    VoiceComponents voice, {
    VoiceSettings? settings,
  }) {
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider(turns)),
      extraOverrides: [activeVoiceProvider.overrideWith((ref) async => voice)],
    );
    if (settings != null) {
      env.storage.settings.set(voiceSettingsKey, settings);
    }
    return c = env.container();
  }

  VoiceController voice() => c.read(voiceControllerProvider.notifier);

  group('Folgefenster (Gesprächsmodus)', () {
    test(
      'Folgefrage im Fenster ohne Tipp: zwei Anfragen, Fenster sichtbar',
      () async {
        final audio = FakeAudioInput(frames: utterance());
        open(
          [ScriptedTurn.text('Erste.'), ScriptedTurn.text('Zweite.')],
          _components(
            audio: audio,
            tts: FakeTextToSpeech(),
            config: const VoicePipelineConfig(
              conversationMode: true,
              followUpWindow: Duration(seconds: 2),
              maxFollowUps: 1,
            ),
          ),
        );
        final windows = <VoiceUiState>[];
        c.listen(voiceControllerProvider, (_, v) {
          if (v.followUp) windows.add(v);
        });

        expect(await voice().start(TriggerKind.pushToTalk), isTrue);
        await voice().whenIdle;

        final users = c
            .read(agentControllerProvider)
            .entries
            .whereType<UserEntry>()
            .map((e) => e.text);
        expect(users, ['Eins', 'Zwei'], reason: 'ein Tipp, zwei Anfragen');
        expect(windows, isNotEmpty);
        expect(windows.first.followUpWindow, const Duration(seconds: 2));
        expect(windows.first.followUpUntil, isNotNull);
        expect(c.read(voiceControllerProvider).followUp, isFalse);
        expect(log.where((l) => l.contains('conv-exit')), hasLength(1));
        expect(log.any((l) => l.contains('reason=maxfollowups')), isFalse);
      },
    );

    test('Folgefenster offen, App in den Hintergrund: Mikrofon aus', () async {
      final audio = FakeAudioInput(frames: utterance());
      open(
        [ScriptedTurn.text('Erste.')],
        _components(
          audio: audio,
          tts: FakeTextToSpeech(),
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 30),
          ),
        ),
      );
      expect(await voice().start(TriggerKind.pushToTalk), isTrue);
      await waitVoice(c, (v) => v.phase == VoiceState.thinking);
      audio.script(AudioFrames.pattern('.' * 2000));
      await waitVoice(c, (v) => v.followUp);
      await waitUntilTrue(() => audio.isRunning);
      expect(audio.isRunning, isTrue, reason: 'Fenster offen');

      await voice().suspend(); // paused / hidden
      // At once, not through the silence timeout of the window.
      expect(audio.isRunning, isFalse, reason: 'Mikrofon sofort aus');
      // The window does not end through the silence timeout (the diagnostic
      // line `listen-end` of the cut recording may say so; only the end of
      // the conversation counts).
      expect(
        log.any((l) => l.contains('conv-exit') && l.contains('reason=silence')),
        isFalse,
      );
      await voice().whenIdle;
      expect(c.read(voiceControllerProvider).followUp, isFalse);
      expect(c.read(voiceControllerProvider).active, isFalse);
      expect(audio.isRunning, isFalse, reason: 'Mikrofon aus');
    });

    test('Fenster abgelaufen: Mikrofon aus, Gespräch endet leise', () async {
      final audio = FakeAudioInput(frames: utterance());
      open(
        [ScriptedTurn.text('Erste.')],
        _components(
          audio: audio,
          tts: FakeTextToSpeech(),
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(milliseconds: 300),
          ),
        ),
      );
      expect(await voice().start(TriggerKind.pushToTalk), isTrue);
      await waitVoice(c, (v) => v.phase == VoiceState.thinking);
      audio.script(AudioFrames.pattern('.' * 2000)); // nobody speaks
      await voice().whenIdle;

      final v = c.read(voiceControllerProvider);
      expect(v.active, isFalse);
      expect(v.followUp, isFalse);
      expect(audio.isRunning, isFalse, reason: 'Mikrofon aus');
      expect(
        c.read(agentControllerProvider).entries.whereType<UserEntry>(),
        hasLength(1),
      );
      expect(
        log.where(
          (l) => l.contains('conv-exit') && l.contains('reason=silence'),
        ),
        hasLength(1),
      );
      expect(v.hint, isNull, reason: 'das Fenster schließt ohne Hinweis');
    });

    test('Standard (Gesprächsmodus aus): kein Folgefenster', () async {
      final audio = FakeAudioInput(frames: utterance());
      open([
        ScriptedTurn.text('Erste.'),
      ], _components(audio: audio, tts: FakeTextToSpeech()));
      await voice().start(TriggerKind.pushToTalk);
      await voice().whenIdle;
      expect(audio.startCount, 1);
      expect(log.any((l) => l.contains('conv-exit')), isFalse);
    });
  });

  group('Barge-in', () {
    Future<(FakeBargeInDetector, FakeTextToSpeech, FakeAudioInput)> speaking(
      BargeInMode mode,
    ) async {
      final tts = FakeTextToSpeech(manual: true);
      final audio = FakeAudioInput(frames: utterance());
      // Like the real detector it holds the shared microphone (WP64).
      final detector = FakeBargeInDetector(
        audio: audio,
        stopDelay: const Duration(milliseconds: 80),
      );
      open(
        [ScriptedTurn.text('Ein langer Satz. Noch einer.')],
        _components(
          audio: audio,
          tts: tts,
          detector: detector,
          config: VoicePipelineConfig(bargeIn: mode),
          script: const [_eins],
        ),
      );
      await voice().start(TriggerKind.pushToTalk);
      await waitVoice(c, (v) => v.phase == VoiceState.speaking);
      if (mode != BargeInMode.off) {
        await waitUntilTrue(() => detector.isRunning);
      }
      return (detector, tts, audio);
    }

    test('„Wendelin“ stoppt die Ausgabe und hört wieder zu', () async {
      final (detector, tts, audio) = await speaking(BargeInMode.keywords);
      final starts = audio.startCount;
      audio.script(AudioFrames.pattern('.' * 2000));
      detector.emit(const BargeInSignal.keyword(BargeInKeyword.wake));
      expect(tts.stops, greaterThan(0));
      await waitVoice(c, (v) => v.phase == VoiceState.listening);
      // The recording starts once the detector has released the microphone.
      await waitUntilTrue(() => audio.startCount > starts);
      expect(c.read(voiceControllerProvider).error, isNull);
      await voice().cancel();
    });

    test('Modus aus: das Signal bleibt wirkungslos', () async {
      final (detector, tts, _) = await speaking(BargeInMode.off);
      expect(detector.startCount, 0, reason: 'läuft gar nicht erst an');
      detector.emit(const BargeInSignal.keyword(BargeInKeyword.wake));
      expect(tts.stops, 0);
      await voice().cancel();
    });
  });

  group('Pipeline-Konfiguration aus den Einstellungen', () {
    test(
      'Standard: Gesprächsmodus aus, Barge-in aus (kein Detektor)',
      () async {
        c = TestEnv().container();
        final config = await c.read(voicePipelineConfigProvider.future);
        expect(config.conversationMode, isFalse);
        expect(config.bargeIn, BargeInMode.off);
        expect(c.read(bargeInAvailableProvider), isFalse);
      },
    );

    test('Einstellung an, Detektor da: beides wirkt', () async {
      final env = TestEnv(
        extraOverrides: [
          bargeInDetectorProvider.overrideWithValue(FakeBargeInDetector()),
        ],
      );
      await env.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(conversationMode: true),
      );
      c = env.container();
      final config = await c.read(voicePipelineConfigProvider.future);
      expect(config.conversationMode, isTrue);
      expect(config.bargeIn, BargeInMode.keywords);
    });
  });

  group('Einmalige Nachfrage nach der ersten Antwort', () {
    Future<void> ask(String answer, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await voice().start(TriggerKind.pushToTalk);
        await voice().whenIdle;
        // The offer reads the settings first.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    VoiceComponents parts(FakeAudioInput audio) => _components(
      audio: audio,
      tts: FakeTextToSpeech(),
      script: const [_eins],
    );

    test('Antwort mit Rückfrage: Frage erscheint, „Ja“ speichert', () async {
      open([
        ScriptedTurn.text('Soll ich das eintragen?'),
      ], parts(FakeAudioInput(frames: utterance())));
      c.listen(conversationOfferProvider, (_, _) {});
      expect(c.read(conversationOfferProvider), isFalse);
      await ask('x');
      expect(c.read(conversationOfferProvider), isTrue);

      await c.read(conversationOfferProvider.notifier).answer(yes: true);
      final s = await c.read(voiceSettingsProvider.future);
      expect(s.conversationMode, isTrue);
      expect(s.conversationAsked, isTrue);
      expect(c.read(conversationOfferProvider), isFalse);
    });

    test(
      'Overlay-Engine setzt, Hauptbildschirm (zweiter Container) zeigt',
      () async {
        final env = TestEnv(
          providerConfig: scripted(
            FakeLlmProvider([ScriptedTurn.text('Soll ich das eintragen?')]),
          ),
          extraOverrides: [
            activeVoiceProvider.overrideWith(
              (ref) async => parts(FakeAudioInput(frames: utterance())),
            ),
          ],
        );
        final overlay = c = env.container();
        await ask('x');
        final stored = await env.storage.settings.get(voiceSettingsKey);
        expect(stored?.conversationOfferPending, isTrue);
        overlay.dispose();

        // Main engine: same storage, own memory.
        final main = c = env.container();
        main.listen(conversationOfferProvider, (_, _) {});
        await main.read(voiceSettingsProvider.future);
        expect(main.read(conversationOfferProvider), isTrue);

        await main.read(conversationOfferProvider.notifier).answer(yes: true);
        expect(main.read(conversationOfferProvider), isFalse);
        final done = await env.storage.settings.get(voiceSettingsKey);
        expect(done?.conversationAsked, isTrue);
        expect(done?.conversationOfferPending, isFalse);
      },
    );

    test('„Nein“ speichert, die Frage kommt nie wieder', () async {
      open([
        ScriptedTurn.text('Soll ich das eintragen?'),
        ScriptedTurn.text('Und noch etwas?'),
      ], parts(FakeAudioInput(frames: utterance())));
      c.listen(conversationOfferProvider, (_, _) {});
      await ask('x');
      await c.read(conversationOfferProvider.notifier).answer(yes: false);
      final s = await c.read(voiceSettingsProvider.future);
      expect(s.conversationMode, isFalse);
      expect(s.conversationAsked, isTrue);

      await ask('y');
      expect(c.read(conversationOfferProvider), isFalse);
    });

    test('Antwort ohne Rückfrage, erste Anfrage: keine Frage', () async {
      open([
        ScriptedTurn.text('Es ist vierzehn Uhr.'),
      ], parts(FakeAudioInput(frames: utterance())));
      c.listen(conversationOfferProvider, (_, _) {});
      await ask('x');
      expect(c.read(conversationOfferProvider), isFalse);
    });

    test('zweite Sprachanfrage kurz danach: Frage erscheint', () async {
      open([
        ScriptedTurn.text('Eins.'),
        ScriptedTurn.text('Zwei.'),
      ], parts(FakeAudioInput(frames: utterance())));
      c.listen(conversationOfferProvider, (_, _) {});
      await ask('x');
      expect(c.read(conversationOfferProvider), isFalse);
      await ask('y');
      expect(c.read(conversationOfferProvider), isTrue);
    });

    test('in den Einstellungen gewählt: die Frage entfällt', () async {
      open(
        [ScriptedTurn.text('Soll ich das eintragen?')],
        parts(FakeAudioInput(frames: utterance())),
        settings: const VoiceSettings(conversationAsked: true),
      );
      c.listen(conversationOfferProvider, (_, _) {});
      await ask('x');
      expect(c.read(conversationOfferProvider), isFalse);
    });

    test('abgebrochene Anfrage zählt nicht', () async {
      final audio = FakeAudioInput(frames: utterance());
      open(
        [ScriptedTurn.text('Soll ich das eintragen?')],
        _components(
          audio: audio,
          tts: FakeTextToSpeech(manual: true),
          script: const [_eins],
        ),
      );
      c.listen(conversationOfferProvider, (_, _) {});
      await voice().start(TriggerKind.pushToTalk);
      await waitVoice(c, (v) => v.phase == VoiceState.speaking);
      await voice().cancel();
      await voice().whenIdle;
      expect(c.read(conversationOfferProvider), isFalse);
    });
  });
}

Future<void> waitUntilTrue(bool Function() test) async {
  for (var i = 0; i < 200 && !test(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(test(), isTrue);
}
