// WP60: Goldens des Einlernens (nur macOS aktualisieren).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/di/wake_service.dart';
import 'package:wendelin/di/wake_settings.dart';
import 'package:wendelin/ui/settings/wake/wake_calibrate_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_enroll_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_test_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_word_screen.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_voice/fakes.dart';

import '../support/wake_support.dart';
import '../ui/helpers.dart';
import 'onboarding_settings_goldens_test.dart' show pumpGoldenScreen;
import 'wake_word_screen_test.dart'
    show SilentSeconds, templates, until, wakeEnv;

/// Audio that serves the scripted recordings and then waits for ever.
final class HangingAudio extends SequenceAudio {
  HangingAudio(super.recordings);

  @override
  Stream<Int16List> start() {
    if (starts >= recordings.length) {
      starts++;
      return StreamController<Int16List>().stream;
    }
    return super.start();
  }
}

Future<void> golden(WidgetTester tester, String name) =>
    expectLater(find.byKey(goldenKey), matchesGoldenFile('goldens/$name.png'));

void main() {
  testWidgets('Golden Aktivierungswort mit zwei Stimmen', tags: ['golden'], (
    tester,
  ) async {
    final env = wakeEnv();
    final store = SecretWakeTemplateStore(env.secrets);
    await tester.runAsync(() async {
      await store.save(templates('a', threshold: 0.93));
      await store.save(templates('b', threshold: 0.88));
      await store.saveSpeakers(const [
        WakeSpeaker(id: 'a', name: 'Anna'),
        WakeSpeaker(id: 'b', name: ''),
      ]);
    });
    await pumpGoldenScreen(tester, env, const WakeWordScreen());
    // Settings, status and voices load asynchronously (secret store).
    final c = ProviderScope.containerOf(
      tester.element(find.byType(WakeWordScreen)),
    );
    await pumpUntil(
      tester,
      () => [
        c.read(wakeServiceProvider),
        c.read(wakeStatusProvider),
        c.read(wakeSpeakersProvider),
        c.read(wakeVerifyProvider),
        c.read(wakeToneProvider),
      ].every((v) => v.hasValue),
    );
    await tester.pumpAndSettle();
    await golden(tester, 'wake_uebersicht');
  });

  testWidgets('Golden Einlernen läuft (3 von 15)', tags: ['golden'], (
    tester,
  ) async {
    final env = wakeEnv(
      audio: HangingAudio([for (var i = 0; i < 3; i++) recording()]),
    );
    await pumpGoldenScreen(
      tester,
      env,
      const WakeEnrollScreen(speakerId: 'a', name: 'Anna'),
    );
    await until(tester, find.text('3 von 15'));
    await tester.pump(const Duration(milliseconds: 100));
    await golden(tester, 'wake_einlernen');
  });

  testWidgets('Golden Kalibrieren läuft', tags: ['golden'], (tester) async {
    final env = wakeEnv(audio: HangingAudio([]));
    await pumpGoldenScreen(
      tester,
      env,
      WakeCalibrateScreen(templates: templates('a')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await golden(tester, 'wake_kalibrieren');
  });

  testWidgets(
    'Golden Ausprobieren: Kandidat und Nachprüfung getrennt',
    tags: ['golden'],
    (tester) async {
      final env = wakeEnv(
        audio: SilentSeconds(10),
        verifier: FakeWakeVerifier(answer: (n) => n == 1),
        vector: (end) => end < 40000
            ? Float32List.fromList([0.5, 0.86, 0, 0])
            : Float32List.fromList([1, 0.05, 0, 0]),
      );
      await pumpGoldenScreen(
        tester,
        env,
        WakeTestScreen(speakers: [templates('a')]),
      );
      await until(tester, find.textContaining('Nachprüfung: bestätigt'));
      await until(
        tester,
        find.textContaining('Nachprüfung: nicht bestätigt'),
        many: true,
      );
      await golden(tester, 'wake_ausprobieren');
    },
  );
}
