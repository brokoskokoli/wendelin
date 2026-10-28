// Gerätetest (WP165): Es gibt keinen Kommunikationsmodus mehr. Auch mit dem
// alten gespeicherten Wert `voice.speechCommunication=true` bleibt der
// Audiomodus während und nach der Antwort `MODE_NORMAL` (0): Antwort,
// Stopp, Folgerunde.
//
// Nur auf einem Emulator:
//   tool/e2e_android.sh integration_test/communication_mode_normal_e2e_test.dart
// Die Antwort ist ein kurzer Ton über die echte Wiedergabe (`audioplayers`)
// und den echten Fokus-Kanal; `AudioManager.mode` kommt über denselben Kanal.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/main.dart' as app show openAppStorage;
import 'package:wendelin/platform/channel_audio_focus_port.dart';
import 'package:wendelin/platform/voice/audio_playback.dart';
import 'package:wendelin/platform/voice/ducking_tts.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// The retired setting, by its raw key.
final _legacy = SettingKey.boolean('voice.speechCommunication');

const _modeNormal = 0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final mode = ChannelAudioMode();

  Wav tone() {
    final samples = Int16List(16000); // 1 s at 16 kHz
    for (var i = 0; i < samples.length; i++) {
      samples[i] = (math.sin(2 * math.pi * 440 * i / 16000) * 3000).round();
    }
    return Wav(samples);
  }

  /// Plays one answer; reads the audio mode while the tone plays.
  Future<int?> speakAndRead(SpeechFocus f, AudioplayersPlayback p) async {
    final generation = f.generation;
    await f.begin();
    try {
      final playing = p.play(tone());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final during = await mode.read();
      await playing;
      return during;
    } finally {
      f.end(generation);
    }
  }

  testWidgets('Altwert true: Antwort, Stopp, Folgerunde, Modus bleibt NORMAL', (
    tester,
  ) async {
    final (storage, _) = await app.openAppStorage();
    await storage.settings.set(_legacy, true);
    expect(await storage.settings.get(_legacy), isTrue);

    final f = SpeechFocus(
      ChannelAudioFocusPort(),
      hold: const Duration(milliseconds: 200),
    );
    final p = AudioplayersPlayback();
    addTearDown(p.dispose);
    expect(await mode.read(), _modeNormal, reason: 'vorher');

    // Round 1: the answer plays to the end.
    expect(await speakAndRead(f, p), _modeNormal, reason: 'während Antwort 1');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(await mode.read(), _modeNormal, reason: 'nach Antwort 1');

    // Stop in the middle of an answer.
    await f.begin();
    unawaited(p.play(tone()));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await mode.read(), _modeNormal, reason: 'während Antwort 2');
    await p.stop();
    f.drop();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await mode.read(), _modeNormal, reason: 'nach Stopp');

    // Follow-up round.
    expect(await speakAndRead(f, p), _modeNormal, reason: 'während Folgerunde');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(await mode.read(), _modeNormal, reason: 'nach Folgerunde');
  });

  testWidgets('Start löscht den Altwert (openAppStorage ruft die Migration)', (
    tester,
  ) async {
    final (first, _) = await app.openAppStorage();
    await first.settings.set(_legacy, true);
    final (second, _) = await app.openAppStorage();
    expect(await second.settings.get(_legacy), isNull);
  });
}
