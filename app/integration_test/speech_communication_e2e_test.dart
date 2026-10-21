// Gerätetest (WP118, K88): Antwort im Gesprächston läuft durch, der
// Audiomodus ist danach wie vorher.
//
// Nur auf einem Emulator:
//   tool/e2e_android.sh integration_test/speech_communication_e2e_test.dart
// Die Antwort ist ein kurzer Ton über die echte Wiedergabe (`audioplayers`),
// den echten Fokus-Kanal und die echte Route (`SpeechRoute.kt`). Geprüft
// wird `AudioManager.mode` vorher, währenddessen (3 = MODE_IN_COMMUNICATION),
// nach der Haltezeit und nach einem Stopp.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/channel_audio_focus_port.dart';
import 'package:wendelin/platform/voice/audio_playback.dart';
import 'package:wendelin/platform/voice/ducking_tts.dart';
import 'package:wendelin/platform/voice/pcm.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final route = ChannelSpeechRoutePort();

  Wav tone() {
    final samples = Int16List(8000); // 0.5 s at 16 kHz
    for (var i = 0; i < samples.length; i++) {
      samples[i] = (math.sin(2 * math.pi * 440 * i / 16000) * 3000).round();
    }
    return Wav(samples);
  }

  SpeechFocus focus(bool on) => SpeechFocus(
    ChannelAudioFocusPort(),
    hold: const Duration(milliseconds: 200),
    route: route,
    communication: () async => on,
  );

  Future<void> speak(
    SpeechFocus f,
    AudioplayersPlayback p, {
    void Function()? during,
  }) async {
    final generation = f.generation;
    await f.begin();
    try {
      during?.call();
      await p.play(tone());
    } finally {
      f.end(generation);
    }
  }

  test('Schalter an: Modus 3 während der Antwort, danach wie vorher', () async {
    final before = await route.audioMode();
    final f = focus(true);
    final p = AudioplayersPlayback(null, () => f.routed);
    addTearDown(p.dispose);
    await speak(f, p);
    final during = await route.audioMode();
    expect(during, 3, reason: 'Haltezeit läuft noch (vorher: $before)');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(f.routed, isFalse);
    expect(await route.audioMode(), before);
  });

  test('Stopp: Zustand sofort wie vorher', () async {
    final before = await route.audioMode();
    final f = focus(true);
    final p = AudioplayersPlayback(null, () => f.routed);
    addTearDown(p.dispose);
    await f.begin();
    expect(f.routed, isTrue);
    expect(await route.audioMode(), 3);
    await p.stop();
    f.drop();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await route.audioMode(), before);
  });

  test('Schalter aus: Modus bleibt unverändert', () async {
    final before = await route.audioMode();
    final f = focus(false);
    final p = AudioplayersPlayback(null, () => f.routed);
    addTearDown(p.dispose);
    await speak(f, p, during: () => expect(f.routed, isFalse));
    expect(await route.audioMode(), before);
  });
}
