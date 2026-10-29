import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/platform/wake/wake_detector.dart';
import 'package:wendelin/ui/design/design.dart' show WSwitch;
import 'package:wendelin/ui/settings/wake/wake_calibrate_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_enroll_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_models.dart';
import 'package:wendelin/ui/settings/wake/wake_test_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_word_screen.dart';
import 'package:wendelin/voice/wake/utterance_capture.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import '../support/wake_support.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;

Float32List v(List<double> x) => Float32List.fromList(x);

WakeTemplates templates(
  String id, {
  double threshold = 0.9,
  String? center = wakeCenterId,
  int count = 2,
  bool sequences = false,
}) => WakeTemplates(
  speakerId: id,
  featureVersion: 'fake-1',
  center: center,
  threshold: threshold,
  embeddings: [
    v([1, 0, 0, 0]),
    v([0.98, 0.2, 0, 0]),
    for (var i = 2; i < count; i++) v([0.97, 0.02 * i, 0, 0]),
  ],
  sequences: [
    if (sequences)
      WakeTemplateSequence(word: WakeTemplates.wordW, values: Float32List(288)),
  ],
);

/// Env with the wake models "installed", scripted audio and fake chain.
TestEnv wakeEnv({
  AudioInput? audio,
  WakeEnrollVerifier? verifier,
  Float32List Function(int)? vector,
  bool installed = true,
  Future<WakeEnrollVerifier?>? enrollVerifier,
  List<Override> extra = const [],
}) {
  final env = TestEnv(
    extraOverrides: [
      wakeAudioProvider.overrideWithValue(audio ?? SequenceAudio([])),
      wakeFeaturesFactoryProvider.overrideWithValue(
        () => fakeFeatures(vector: vector),
      ),
      wakeVerifierProvider.overrideWith((ref) async => verifier),
      wakeEnrollVerifierProvider.overrideWith(
        (ref) => enrollVerifier ?? Future.value(verifier ?? FakeWakeVerifier()),
      ),
      wakePromptToneProvider.overrideWithValue(() async {}),
      wakeEnrollPauseProvider.overrideWithValue(Duration.zero),
      ...extra,
    ],
  );
  if (installed) {
    env.speechModels.installed.addAll(['wake-features', 'whisper-small']);
  }
  return env;
}

Future<ProviderContainer> pumpWake(
  WidgetTester tester,
  TestEnv env,
  Widget screen,
) async {
  setView(tester, const Size(390, 3000));
  await tester.pumpWidget(env.app(home: screen));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byWidget(screen)));
}

Future<void> seconds(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Pumps (with a little real time, the fakes use real streams) until [f]
/// is on screen.
Future<void> until(WidgetTester tester, Finder f, {bool many = false}) async {
  try {
    await pumpUntil(
      tester,
      () => f.evaluate().isNotEmpty,
      pump: const Duration(milliseconds: 100),
    );
  } on TestFailure {
    // Falls through to the diagnostic below.
  }
  if (f.evaluate().isEmpty) {
    final texts = find
        .byType(RichText)
        .evaluate()
        .map(
          (e) =>
              (e.widget as RichText).text.toPlainText().replaceAll('\n', ' '),
        );
    fail('nicht gefunden: $f; sichtbar: ${texts.join(' | ')}');
  }
  expect(f, many ? findsWidgets : findsOneWidget);
}

Future<void> startEnroll(WidgetTester tester, {String name = 'Anna'}) async {
  await tester.tap(find.text('Stimme einlernen'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  await tester.tap(find.text('Weiter'));
  await tester.pump();
}

void main() {
  group('Erkennung (WP129)', () {
    testWidgets('automatisch ist gewählt; Modell wählen speichert und zeigt '
        'den Download samt Hinweis', (tester) async {
      final env = wakeEnv();
      final c = await pumpWake(tester, env, const WakeWordScreen());
      expect(find.text('Erkennung'), findsOneWidget);
      expect(find.text('Automatisch'), findsOneWidget);
      // Auto: die Station braucht das Modell, also steht der Download da.
      expect(find.byKey(const ValueKey('wakeClassifierMissing')), findsOne);
      expect(find.textContaining('trainierte'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('wakeDetector.model')));
      await tester.pump();
      expect(
        await c.read(wakeDetectorProvider.future),
        WakeDetectorChoice.model,
      );
      expect(await env.storage.settings.get(wakeDetectorKey), 'model');
      expect(find.byKey(const ValueKey('wakeClassifierMissing')), findsOne);
    });

    testWidgets('kein Modell und keine Stimme: Hinweis „nichts zu hören“; '
        'mit Stimme nicht', (tester) async {
      final env = wakeEnv();
      await pumpWake(tester, env, const WakeWordScreen());
      expect(find.byKey(const ValueKey('wakeNothingToHear')), findsOne);
    });

    testWidgets('Automatisch, Modell da, keine Stimme: Hinweis; Wahl „Modell“: '
        'keiner (Modell hört allein)', (tester) async {
      final env = wakeEnv();
      env.speechModels.installed.add(
        SpeechModelCatalog.wakeClassifierWendelin.id,
      );
      await pumpWake(tester, env, const WakeWordScreen());
      expect(find.byKey(const ValueKey('wakeNothingToHear')), findsOne);
      expect(find.textContaining('Automatisch hört'), findsOne);
      await tester.tap(find.byKey(const ValueKey('wakeDetector.model')));
      await tester.pump();
      expect(find.byKey(const ValueKey('wakeNothingToHear')), findsNothing);
    });

    testWidgets('kein Modell, aber eine Stimme: kein Hinweis', (tester) async {
      final env = wakeEnv();
      final store = SecretWakeTemplateStore(env.secrets);
      await store.save(templates('a'));
      await store.saveSpeakers(const [WakeSpeaker(id: 'a', name: 'Anna')]);
      await pumpWake(tester, env, const WakeWordScreen());
      expect(find.byKey(const ValueKey('wakeClassifierMissing')), findsOne);
      expect(find.byKey(const ValueKey('wakeNothingToHear')), findsNothing);
    });

    testWidgets(
      'Vorlagen: kein Hinweis; das Modell steht trotzdem oben (WP173)',
      (tester) async {
        final env = wakeEnv();
        await pumpWake(tester, env, const WakeWordScreen());
        await tester.tap(find.byKey(const ValueKey('wakeDetector.templates')));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('wakeClassifierMissing')),
          findsNothing,
        );
        expect(
          find.textContaining(
            SpeechModelCatalog.wakeClassifierWendelin.displayName,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('Modell geladen: kein Hinweis mehr', (tester) async {
      final env = wakeEnv();
      env.speechModels.installed.add(
        SpeechModelCatalog.wakeClassifierWendelin.id,
      );
      await pumpWake(tester, env, const WakeWordScreen());
      expect(find.byKey(const ValueKey('wakeClassifierMissing')), findsNothing);
      expect(
        find.textContaining(
          SpeechModelCatalog.wakeClassifierWendelin.displayName,
        ),
        findsWidgets,
      );
    });
  });

  group('Übersicht', () {
    testWidgets('ohne Modelle ist Einlernen gesperrt, mit Modellen offen', (
      tester,
    ) async {
      final env = wakeEnv(installed: false);
      await pumpWake(tester, env, const WakeWordScreen());
      expect(find.text('Noch keine Stimme'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Stimme einlernen'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('zuerst das Sprachmodell geladen werden'),
        findsOneWidget,
      );
    });

    testWidgets('ohne Modell: Kalibrieren und Ausprobieren gesperrt, '
        'Laden-Button lädt das Merkmalsmodell', (tester) async {
      final env = wakeEnv(installed: false);
      final c = await pumpWake(tester, env, const WakeWordScreen());
      for (final label in [
        'Kalibrieren (30 min, empfohlen)',
        'Jetzt ausprobieren',
      ]) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNull,
          reason: label,
        );
      }
      expect(c.read(wakeMissingModelsProvider).map((m) => m.id), [
        'wake-features',
      ]);
      await tester.tap(find.text('Sprachmodell laden'));
      await tester.pump();
      expect(env.speechModels.running.keys, contains('wake-features'));
    });

    testWidgets('ohne Whisper bleiben alle Abläufe offen, nur Hinweis '
        'beim Ausprobieren, nur bei eingeschalteter Nachprüfung', (
      tester,
    ) async {
      final env = wakeEnv(installed: false);
      env.speechModels.installed.add('wake-features');
      final c = await pumpWake(tester, env, const WakeWordScreen());
      expect(c.read(wakeMissingModelsProvider), isEmpty);
      expect(c.read(wakeVerifyMissingProvider).map((m) => m.id), [
        'whisper-small',
      ]);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Stimme einlernen'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.byKey(const ValueKey('wakeModelsMissing')), findsNothing);
      expect(find.byKey(const ValueKey('wakeVerifyMissing')), findsOneWidget);
      expect(find.textContaining('Für die Nachprüfung'), findsOneWidget);
      await tester.tap(find.text('Sprachmodell laden'));
      await tester.pump();
      expect(env.speechModels.running.keys, contains('whisper-small'));
      await c.read(wakeVerifyProvider.notifier).set(enabled: false);
      expect(c.read(wakeVerifyMissingProvider), isEmpty);
    });

    testWidgets('Nachprüfung ist standardmäßig an und lässt sich abschalten', (
      tester,
    ) async {
      final env = wakeEnv();
      final c = await pumpWake(tester, env, const WakeWordScreen());
      final sw = find.descendant(
        of: find.ancestor(
          of: find.text('Nachprüfung (Stufe 2)'),
          matching: find.byType(InkWell),
        ),
        matching: find.byType(WSwitch),
      );
      expect(tester.widget<WSwitch>(sw).value, isTrue);
      expect(await c.read(wakeVerifyProvider.future), isTrue);
      await tester.tap(sw);
      await settle(tester);
      expect(tester.widget<WSwitch>(sw).value, isFalse);
      expect(await c.read(wakeVerifyProvider.future), isFalse);
      expect(await env.storage.settings.get(wakeVerifyKey), isFalse);
    });

    testWidgets('alte (rohe) Vorlagen: Hinweis, nicht kalibrierbar/testbar', (
      tester,
    ) async {
      final env = wakeEnv();
      final store = SecretWakeTemplateStore(env.secrets);
      await store.save(templates('a', center: null));
      await store.saveSpeakers(const [WakeSpeaker(id: 'a', name: 'Anna')]);
      await pumpWake(tester, env, const WakeWordScreen());
      expect(find.textContaining('veraltet'), findsOneWidget);
      expect(find.textContaining('Aufnahmen · Schwelle'), findsNothing);
      await tester.tap(find.text('Kalibrieren (30 min, empfohlen)'));
      await tester.pumpAndSettle();
      expect(find.byType(WakeCalibrateScreen), findsNothing);
      // Row detail plus the snack bar: no silent no-op.
      expect(find.textContaining('veraltet'), findsNWidgets(2));
      ScaffoldMessenger.of(tester.element(find.byType(WakeWordScreen)))
          .clearSnackBars();
      await tester.pumpAndSettle();
      expect(find.textContaining('veraltet'), findsOneWidget);
      await tester.tap(find.text('Jetzt ausprobieren'));
      await tester.pumpAndSettle();
      expect(find.byType(WakeTestScreen), findsNothing);
      expect(find.textContaining('veraltet'), findsNWidgets(2));
    });

    testWidgets('mit Folgen für Prüfer B: kein Hinweis zum Neu-Einlernen', (
      tester,
    ) async {
      final env = wakeEnv();
      final store = SecretWakeTemplateStore(env.secrets);
      await store.save(templates('a', count: 9, sequences: true));
      await store.saveSpeakers(const [WakeSpeaker(id: 'a', name: 'Anna')]);
      await pumpWake(tester, env, const WakeWordScreen());
      expect(find.text('9 Aufnahmen · Schwelle 0.90'), findsOneWidget);
      expect(find.textContaining('Neu einlernen für den Prüfer'), findsNothing);
    });

    testWidgets('Sprecherverwaltung: listen, neu einlernen, einzeln löschen', (
      tester,
    ) async {
      final env = wakeEnv();
      final store = SecretWakeTemplateStore(env.secrets);
      await store.save(templates('a'));
      await store.save(templates('b', threshold: 0.88, count: 9));
      await store.saveSpeakers(const [
        WakeSpeaker(id: 'a', name: 'Anna'),
        WakeSpeaker(id: 'b', name: ''),
      ]);
      final c = await pumpWake(tester, env, const WakeWordScreen());
      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Person 2'), findsOneWidget);
      expect(
        find.text('9 Aufnahmen · Schwelle 0.88\nNeu einlernen für den Prüfer.'),
        findsOneWidget,
        reason: 'ohne Folgen für Prüfer B (WP143)',
      );
      expect(find.textContaining('Nur 2 brauchbare'), findsOneWidget);
      expect(find.text('Weitere Person einlernen'), findsOneWidget);

      await tester.tap(find.byTooltip('Aktionen für Anna'));
      await tester.pumpAndSettle();
      expect(find.text('Neu einlernen'), findsOneWidget);
      await tester.tap(find.text('Löschen'));
      await settle(tester);
      expect(find.text('Anna'), findsNothing);
      expect(await store.load('a'), isNull, reason: 'Vorlagen gehen mit');
      expect(await store.load('b'), isNotNull);
      expect((await c.read(wakeSpeakersProvider.future)).single.id, 'b');

      await tester.tap(find.text('Alle Stimmen löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await settle(tester);
      expect(await store.speakers(), isEmpty);
      expect(await env.secrets.listKeys(), isEmpty);
      expect(find.text('Noch keine Stimme'), findsOneWidget);
    });
  });

  group('Einlernen', () {
    testWidgets('15 gültige Aufnahmen: Fortschritt, Speichern, Sprecher da', (
      tester,
    ) async {
      final audio = SequenceAudio([for (var i = 0; i < 15; i++) recording()]);
      final env = wakeEnv(audio: audio);
      final c = await pumpWake(tester, env, const WakeWordScreen());
      await startEnroll(tester);
      await until(tester, find.text('1 von 15'));
      expect(find.text('Sag jetzt: „Hey Wendelin“'), findsOneWidget);
      expect(find.text(enrollHint(AppLocalizationsDe(), 1)), findsOneWidget);
      await until(tester, find.text('Speichern'));
      expect(find.text('15 von 15'), findsOneWidget);
      expect(find.text('Alle Aufnahmen sind da.'), findsOneWidget);

      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(find.text('Anna'), findsOneWidget);
      expect(find.textContaining('15 Aufnahmen · Schwelle'), findsOneWidget);
      final id = (await c.read(wakeSpeakersProvider.future)).single.id;
      final t = (await SecretWakeTemplateStore(env.secrets).load(id))!;
      expect(t.embeddings, hasLength(15));
      expect(audio.starts, 15);
    });

    testWidgets('zu leise: Hinweis, zählt nicht', (tester) async {
      final audio = SequenceAudio([
        recording(amplitude: 200),
        for (var i = 0; i < 3; i++) recording(),
      ]);
      final env = wakeEnv(audio: audio);
      await pumpWake(tester, env, const WakeWordScreen());
      await startEnroll(tester);
      await until(
        tester,
        find.text(verdictText(AppLocalizationsDe(), UtteranceVerdict.tooQuiet)),
      );
      expect(find.text('0 von 15'), findsOneWidget);
      await until(tester, find.text('2 von 15'));
      expect(find.text('Mit 2 Aufnahmen speichern'), findsNothing);
    });

    testWidgets('Erkenner fehlt dauerhaft: klarer Hinweis statt stiller '
        'Ablehnung', (tester) async {
      final audio = SequenceAudio([for (var i = 0; i < 3; i++) recording()]);
      final env = wakeEnv(
        audio: audio,
        // Never ready: the wait runs into its limit, no recognizer.
        enrollVerifier: Completer<WakeEnrollVerifier?>().future,
        extra: [
          wakeEnrollVerifierWaitProvider.overrideWithValue(
            const Duration(milliseconds: 200),
          ),
        ],
      );
      await pumpWake(tester, env, const WakeWordScreen());
      await startEnroll(tester);
      await until(tester, find.textContaining('Spracherkennung fehlt'));
      expect(find.text('0 von 15'), findsOneWidget);
    });

    testWidgets('ab 8 Aufnahmen vorzeitig speichern', (tester) async {
      final audio = SequenceAudio([for (var i = 0; i < 9; i++) recording()]);
      final env = wakeEnv(audio: audio);
      await pumpWake(tester, env, const WakeWordScreen());
      await startEnroll(tester);
      await until(tester, find.text('Mit 8 Aufnahmen speichern'));
      await tester.tap(find.textContaining('Aufnahmen speichern'));
      await settle(tester);
      expect(find.textContaining('Aufnahmen · Schwelle'), findsOneWidget);
    });

    testWidgets('Abbruch: nichts wird gespeichert', (tester) async {
      final audio = SequenceAudio([for (var i = 0; i < 15; i++) recording()]);
      final env = wakeEnv(audio: audio);
      final c = await pumpWake(tester, env, const WakeWordScreen());
      await startEnroll(tester);
      await until(tester, find.text('2 von 15'));
      await tester.tap(find.text('Abbrechen'));
      await settle(tester);
      expect(find.text('Noch keine Stimme'), findsOneWidget);
      expect(await c.read(wakeSpeakersProvider.future), isEmpty);
      expect(await env.secrets.listKeys(), isEmpty);
    });

    testWidgets('ohne Mikrofon-Erlaubnis startet nichts', (tester) async {
      final env = wakeEnv();
      env.microphone.granted = false;
      await pumpWake(tester, env, const WakeWordScreen());
      await startEnroll(tester);
      await tester.pumpAndSettle();
      // Erklärdialog, „Nicht jetzt“.
      await tester.tap(find.text('Nicht jetzt'));
      await settle(tester);
      expect(
        find.text('Ohne Mikrofon kann Wendelin deine Stimme nicht lernen.'),
        findsOneWidget,
      );
    });
  });

  group('Kalibrieren', () {
    Future<WakeTemplates> stored(TestEnv env) async {
      final store = SecretWakeTemplateStore(env.secrets);
      await store.save(templates('a'));
      return (await store.load('a'))!;
    }

    testWidgets('Ergebnis zeigt Schwelle und Fehlalarme pro Stunde', (
      tester,
    ) async {
      var n = 0;
      final env = wakeEnv(
        audio: SilentSeconds(150),
        vector: (end) => ++n % 40 == 0 ? v([0.7, 0.7, 0, 0]) : v([0, 0, 1, 0]),
      );
      final t = await tester.runAsync(() => stored(env));
      await pumpWake(
        tester,
        env,
        WakeCalibrateScreen(
          templates: t!,
          duration: const Duration(minutes: 2),
        ),
      );
      await until(tester, find.text('Kalibriert.'));
      expect(find.textContaining('Fehlalarme pro Stunde'), findsOneWidget);
      expect(find.text('Fertig'), findsOneWidget);
      final saved = (await SecretWakeTemplateStore(env.secrets).load('a'))!;
      expect(saved.threshold, isNot(0.9));
    });

    testWidgets('Abbruch ändert nichts', (tester) async {
      final env = wakeEnv(audio: SilentSeconds(150));
      final t = await tester.runAsync(() => stored(env));
      await pumpWake(
        tester,
        env,
        WakeCalibrateScreen(
          templates: t!,
          duration: const Duration(minutes: 2),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Abbrechen'));
      await settle(tester);
      expect(
        (await SecretWakeTemplateStore(env.secrets).load('a'))!.threshold,
        0.9,
      );
    });
  });

  group('Ausprobieren', () {
    testWidgets('Kandidat und Nachprüfung stehen getrennt', (tester) async {
      final env = wakeEnv(
        audio: SilentSeconds(10),
        verifier: FakeWakeVerifier(answer: (n) => n == 1),
        vector: (end) => end < 40000 ? v([0, 1, 0, 0]) : v([1, 0, 0, 0]),
      );
      await pumpWake(tester, env, WakeTestScreen(speakers: [templates('a')]));
      await until(tester, find.textContaining('Kandidat ·'), many: true);
      await seconds(tester, 8);
      expect(find.textContaining('Nachprüfung: bestätigt'), findsOneWidget);
      expect(find.textContaining('Nachprüfung: nicht bestätigt'), findsWidgets);
      expect(find.textContaining('höchste Ähnlichkeit 1.00'), findsOneWidget);
    });

    for (final (kind, name) in [
      ('parakeet', 'Parakeet'),
      ('whisper', 'Whisper'),
    ]) {
      testWidgets('Nachprüfung nennt den Prüfer: $kind (WP146)', (
        tester,
      ) async {
        final env = wakeEnv(
          audio: SilentSeconds(10),
          verifier: FakeWakeVerifier(kind: kind),
          vector: (end) => v([1, 0, 0, 0]),
        );
        await pumpWake(tester, env, WakeTestScreen(speakers: [templates('a')]));
        await until(tester, find.textContaining('Kandidat ·'), many: true);
        await seconds(tester, 8);
        expect(
          find.textContaining(
            'Nachprüfung: bestätigt (Befehlserkennung: $name)',
          ),
          findsWidgets,
        );
      });
    }

    testWidgets('Prüfer B steht im Test nie als Entscheider (WP146)', (
      tester,
    ) async {
      final env = wakeEnv(
        audio: SilentSeconds(10),
        verifier: FakeWakeVerifier(kind: 'b'),
        vector: (end) => v([1, 0, 0, 0]),
      );
      await pumpWake(tester, env, WakeTestScreen(speakers: [templates('a')]));
      await until(tester, find.textContaining('Kandidat ·'), many: true);
      await seconds(tester, 8);
      expect(find.textContaining('Prüfer'), findsNothing);
      expect(find.textContaining('(Befehlserkennung:'), findsNothing);
    });

    testWidgets('unbekannter Prüfer: nur das Ergebnis, keine Klammer', (
      tester,
    ) async {
      final env = wakeEnv(
        audio: SilentSeconds(10),
        verifier: FakeWakeVerifier(),
        vector: (end) => v([1, 0, 0, 0]),
      );
      await pumpWake(tester, env, WakeTestScreen(speakers: [templates('a')]));
      await until(tester, find.textContaining('Kandidat ·'), many: true);
      await seconds(tester, 8);
      expect(find.textContaining('Nachprüfung: bestätigt ·'), findsWidgets);
      expect(find.textContaining('(Befehlserkennung:'), findsNothing);
    });

    testWidgets('ohne Whisper: „nicht möglich“ statt stiller Bestätigung', (
      tester,
    ) async {
      final env = wakeEnv(
        audio: SilentSeconds(6),
        vector: (end) => v([1, 0, 0, 0]),
      );
      await pumpWake(tester, env, WakeTestScreen(speakers: [templates('a')]));
      await until(tester, find.textContaining('Kandidat ·'), many: true);
      expect(find.textContaining('nicht möglich'), findsWidgets);
    });

    testWidgets('ohne Treffer: Hinweis und höchste Ähnlichkeit', (
      tester,
    ) async {
      final env = wakeEnv(
        audio: SilentSeconds(6),
        vector: (end) => v([0.6, 0.8, 0, 0]),
      );
      await pumpWake(tester, env, WakeTestScreen(speakers: [templates('a')]));
      await until(tester, find.textContaining('höchste Ähnlichkeit 0.75'));
      expect(find.text('Noch kein Treffer.'), findsOneWidget);
    });
  });
}

/// [seconds] seconds of silence in 100 ms frames (delivered at once), then
/// the stream ends.
final class SilentSeconds implements AudioInput {
  SilentSeconds(this.seconds);
  final int seconds;
  bool _on = false;

  @override
  bool get isRunning => _on;

  @override
  Stream<Int16List> start() {
    _on = true;
    return Stream.fromIterable([
      for (var i = 0; i < seconds * 10; i++) Int16List(1600),
    ]);
  }

  @override
  Future<void> stop() async => _on = false;
}
