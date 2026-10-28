// Gerätetest (WP165): Es gibt keinen Kommunikationsmodus mehr. Auch mit dem
// alten gespeicherten Wert `voice.speechCommunication=true` bleibt der
// Audiomodus während und nach der Antwort `MODE_NORMAL` (0): Antwort,
// Stopp, Folgerunde.
//
// Nur auf einem Emulator:
//   tool/e2e_android.sh integration_test/communication_mode_normal_e2e_test.dart
// Die Antwort läuft über die echten Provider (`speechFocusProvider`,
// `createSherpaTts` mit echter Wiedergabe `audioplayers` und echtem
// Fokus-Kanal); nur die Synthese liefert einen Ton. `AudioManager.mode`
// kommt über denselben Kanal.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/core_providers.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/main.dart' as app show openAppStorage;
import 'package:wendelin/platform/channel_audio_focus_port.dart';
import 'package:wendelin/platform/voice/ducking_tts.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// The retired setting, by its raw key.
final _legacy = SettingKey.boolean('voice.speechCommunication');

const _modeNormal = 0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final mode = ChannelAudioMode();

  testWidgets('Altwert true: Antwort, Stopp, Folgerunde, Modus bleibt NORMAL', (
    tester,
  ) async {
    final storage = openInMemoryStorage();
    addTearDown(storage.close);
    // The retired value stays stored (no migration here): it must have no
    // effect on the playback.
    await storage.settings.set(_legacy, true);
    expect(await storage.settings.get(_legacy), isTrue);

    final c = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        sherpaSynthesizerProvider.overrideWithValue(_ToneSynthesizer()),
      ],
    );
    addTearDown(c.dispose);
    final real = Provider<TextToSpeech>(
      (ref) => createSherpaTts(ref, installed: () async => const [_voice]),
    );
    final tts = DuckingTextToSpeech(c.read(real), c.read(speechFocusProvider));

    expect(await mode.read(), _modeNormal, reason: 'vorher');

    /// Speaks one answer and reads the audio mode until it ended.
    Future<List<int?>> speakAndSample() async {
      var done = false;
      final spoken = tts.speak('Hallo', language: 'de').whenComplete(() {
        done = true;
      });
      final samples = <int?>[];
      while (!done) {
        samples.add(await mode.read());
      }
      await spoken;
      return samples;
    }

    // Round 1: the answer plays to the end.
    final first = await speakAndSample();
    expect(first, isNotEmpty);
    expect(first, everyElement(_modeNormal), reason: 'während Antwort 1');
    expect(await mode.read(), _modeNormal, reason: 'nach Antwort 1');

    // Stop in the middle of an answer.
    final stopped = tts.speak('Hallo', language: 'de');
    final during = await mode.read();
    expect(during, _modeNormal, reason: 'während Antwort 2');
    await tts.stop();
    await stopped.then((_) {}, onError: (_) {});
    expect(await mode.read(), _modeNormal, reason: 'nach Stopp');

    // Follow-up round.
    final second = await speakAndSample();
    expect(second, isNotEmpty);
    expect(second, everyElement(_modeNormal), reason: 'während Folgerunde');
    expect(await mode.read(), _modeNormal, reason: 'nach Folgerunde');
  });

  testWidgets('Start löscht den Altwert (openAppStorage ruft die Migration)', (
    tester,
  ) async {
    final (first, _) = await app.openAppStorage();
    await first.settings.set(_legacy, true);
    await first.close();
    final (second, _) = await app.openAppStorage();
    addTearDown(second.close);
    expect(await second.settings.get(_legacy), isNull);
  });
}

const _voice = SherpaVoice(
  id: 'tts-de-thorsten',
  language: 'de',
  name: 'Deutsch – Thorsten',
  files: PiperVoiceFiles(model: 'm', tokens: 't', dataDir: 'd'),
);

/// A 1 s tone instead of a voice model.
final class _ToneSynthesizer implements SpeechSynthesizer {
  @override
  Future<Wav> synthesize(
    String text, {
    required String voiceId,
    double speed = 1.0,
  }) async {
    final samples = Int16List(16000);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = (math.sin(2 * math.pi * 440 * i / 16000) * 3000).round();
    }
    return Wav(samples);
  }

  @override
  Future<void> dispose() async {}
}
