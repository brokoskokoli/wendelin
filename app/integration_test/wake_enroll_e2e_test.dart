// Gerätetest WP60: „Wendelin lernt deine Stimme“. Einlernen mit 15 WAV-
// Dateien (synthetische Stimme Anna) über die echte Oberfläche, die
// ONNX-Merkmalskette auf dem onnxruntime der App, danach der Test-Modus mit
// einer WAV, die „Wendelin“ enthält (Kandidat + Nachprüfung mit Whisper
// base), und einer ohne (kein Kandidat). Prüft außerdem, dass beim Einlernen
// keine Audiodateien entstehen.
//
// Nur mit `WENDELIN_MODELS=<dir> tool/e2e_android.sh
// integration_test/wake_enroll_e2e_test.dart`; <dir>/wake-features/ (die
// beiden openWakeWord-ONNX-Dateien) und <dir>/wake-e2e/ (Anna_01–15.wav,
// test-solo.wav, test-neg.wav) kommen per `run-as` in die App-Daten.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

/// Hands out the WAV that fits the current phase of the test.
final class _SwitchableAudio implements AudioInput {
  AudioInput? inner;

  @override
  bool get isRunning => inner?.isRunning ?? false;

  @override
  Stream<Int16List> start() => inner!.start();

  @override
  Future<void> stop() async => inner?.stop();
}

Future<Set<String>> _files() async {
  final out = <String>{};
  for (final dir in [
    await getTemporaryDirectory(),
    await getApplicationCacheDirectory(),
    await getApplicationDocumentsDirectory(),
  ]) {
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      out.add(f.path);
    }
  }
  return out;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (voiceE2e) await waitForDeviceFiles();
  });

  testWidgets(
    'Einlernen mit WAVs und Treffer im Test-Modus',
    (tester) async {
      final dir = '${(await e2eDirectory()).path}/wake';
      final audio = _SwitchableAudio();
      final app = E2eApp(
        extraOverrides: [wakeAudioProvider.overrideWithValue(audio)],
      );
      await app.storage.settings.set(
        voiceSettingsKey,
        VoiceSettings(sttModel: 'whisper-base'),
      );
      final before = await _files();
      final c = await app.pump(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(nav.pushNamed(AppRoutes.wakeWord));
      await pumpUntil(tester, find.text('Aktivierungswort'));
      await pumpUntil(tester, find.text('Stimme einlernen'));
      await tester.pump(const Duration(seconds: 1));

      // Einlernen: 15 Aufnahmen, vierfache Geschwindigkeit.
      audio.inner = WavAudioInput.sequence([
        for (var i = 1; i <= 15; i++)
          WavAudioInput.file('$dir/Anna_${i.toString().padLeft(2, '0')}.wav')
              .samples,
      ], speed: 4);
      await tester.tap(find.text('Stimme einlernen'));
      await pumpUntil(tester, find.text('Weiter'));
      await tester.enterText(find.byType(TextField), 'Anna');
      await tester.tap(find.text('Weiter'));
      await pumpUntil(
        tester,
        find.text('Speichern'),
        timeout: const Duration(minutes: 3),
      );
      await tester.tap(find.text('Speichern'));
      await pumpUntil(tester, find.textContaining('15 Aufnahmen'));

      final speakers = await c.read(wakeSpeakersProvider.future);
      final t = (await c.read(
        wakeTemplatesProvider(speakers.single.id).future,
      ))!;
      expect(t.embeddings, hasLength(15));
      expect(t.embeddings.first, hasLength(1536));
      // ignore: avoid_print
      print(
        'WP60 eingelernt: ${t.embeddings.length} Vorlagen, Schwelle '
        '${t.threshold.toStringAsFixed(3)}, '
        'LOO ${(leaveOneOutScores(t.embeddings)..sort()).map((e) => e.toStringAsFixed(2)).join(' ')}',
      );
      expect(await _files(), before, reason: 'kein Audio auf der Platte');

      // Test-Modus: ohne „Wendelin“ kein Kandidat.
      Future<void> tryOut(String wav) async {
        // Wie im Alltag läuft das Mikrofon schon eine Weile: Das erste
        // Fenster braucht 2 s Audio, das Wort soll darin nicht am Rand liegen.
        audio.inner = WavAudioInput(
          Wav.read('$dir/$wav').samples,
          leadingSilence: const Duration(milliseconds: 1500),
        );
        await tester.tap(find.text('Jetzt ausprobieren'));
        await pumpUntil(tester, find.textContaining('Hört zu'));
      }

      await tryOut('test-neg.wav');
      await tester.pump(const Duration(seconds: 12));
      // ignore: avoid_print
      print(
        'WP60 neg: ${find.textContaining('Kandidat').evaluate().length} Kandidaten',
      );
      expect(find.textContaining('Kandidat ·'), findsNothing);
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      // Mit „Wendelin“: Kandidat und Nachprüfung getrennt.
      await tryOut('test-solo.wav');
      await tester.pump(const Duration(seconds: 6));
      // ignore: avoid_print
      print(
        'WP60 pos-Status: ${find.textContaining('Hört zu').evaluate().map((e) => (e.widget as Text).data).toList()}',
      );
      await pumpUntil(
        tester,
        find.textContaining('Kandidat ·'),
        timeout: const Duration(seconds: 40),
      );
      await pumpUntil(
        tester,
        find.textContaining('Nachprüfung: '),
        timeout: const Duration(seconds: 5),
      );
      await pumpUntil(
        tester,
        find.textContaining(RegExp('Nachprüfung: (bestätigt|nicht)')),
        timeout: const Duration(seconds: 120),
      );
      final shown = find
          .textContaining('Kandidat ·')
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .toList();
      // ignore: avoid_print
      print(
        'WP60 pos: $shown ${find.textContaining('Nachprüfung: ').evaluate().map((e) => (e.widget as Text).data).toList()}',
      );
      expect(find.textContaining('Nachprüfung: bestätigt'), findsOneWidget);
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      // Zur Einordnung (ohne Erwartung): eine andere Äußerung derselben
      // Stimme, nicht aus dem Einlern-Satz.
      await tryOut('test-pos.wav');
      await tester.pump(const Duration(seconds: 8));
      // ignore: avoid_print
      print(
        'WP60 pos2-Status: ${find.textContaining('Hört zu').evaluate().map((e) => (e.widget as Text).data).toList()}',
      );
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(await _files(), before);
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
