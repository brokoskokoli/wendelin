// Gerätetest WP66: Untermenü „Stimmen“. Lädt die Stimme Kerstin (echter
// Download mit Prüfsumme, Netz nötig), wählt sie und löst „Probe hören“ aus.
// Belegt wird mit einer aufzeichnenden Wiedergabe (statt Lautsprecher), dass
// die gewählte Stimme eine gültige WAV erzeugt.
//
//   tool/e2e_android.sh integration_test/voice_voices_e2e_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/model_download_row.dart';

import 'support/e2e.dart';

final class _RecordingPlayback implements AudioPlayback {
  final played = <Wav>[];
  @override
  Future<void> play(Wav wav) async => played.add(wav);
  @override
  Future<void> stop() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Stimmen: Kerstin laden, wählen, Probe hören', (tester) async {
    final playback = _RecordingPlayback();
    final app = E2eApp(
      startup: const StartupSettings(onboardingDone: true),
      extraOverrides: [
        sherpaTtsProvider.overrideWith(
          (ref) => createSherpaTts(ref, playback: playback),
        ),
      ],
    );
    final c = await app.pump(tester);
    await pumpUntil(tester, find.byType(MainScreen));
    c.read(voiceSettingsProvider); // warm up
    Navigator.of(tester.element(find.byType(MainScreen)))
        .pushNamed(AppRoutes.voices);
    await pumpUntil(tester, find.text('Deutsch'));

    const name = 'Deutsch – Kerstin (weiblich)';
    await tester.ensureVisible(find.text(name));
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byWidgetPredicate((w) => w is ModelDownloadRow),
    );
    await pumpUntil(
      tester,
      find.descendant(of: row, matching: find.text('Laden')),
    );
    await tester.tap(find.descendant(of: row, matching: find.text('Laden')));
    await pumpUntil(
      tester,
      find.descendant(of: row, matching: find.textContaining(' · geladen')),
      timeout: const Duration(minutes: 5),
    );
    expect(
      c.read(modelStatesProvider)['tts-de-kerstin']?.phase,
      ModelPhase.installed,
    );

    // Choose it (tap the row), then „Probe hören“.
    await tester.tap(find.text('Deutsch – Kerstin (weiblich)'));
    await pumpFor(tester);
    expect(
      c.read(voiceSettingsProvider).value?.sherpaVoices['de'],
      'tts-de-kerstin',
    );
    final probe = find.byKey(const Key('probe-de'));
    await tester.ensureVisible(probe);
    await tester.tap(probe);
    final end = DateTime.now().add(const Duration(minutes: 2));
    while (playback.played.isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(playback.played, isNotEmpty, reason: 'Probe hat nichts erzeugt');
    final wav = playback.played.first;
    expect(wav.samples.length, greaterThan(8000));
    expect(wav.duration, greaterThan(const Duration(seconds: 1)));
    // ignore: avoid_print
    print(
      'WP66-E2E voice=tts-de-kerstin samples=${wav.samples.length} dur=${wav.duration}',
    );
  });
}
