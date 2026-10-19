import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/speaker_providers.dart';
import 'package:wendelin/di/voice_settings_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/ui/design/design.dart' show WSwitch;
import 'package:wendelin/ui/settings/speaker/speaker_screen.dart';
import 'package:wendelin/voice/speaker/speaker_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import '../support/wake_support.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;

/// Returns the scripted embeddings one per call.
final class ScriptedEmbedder implements SpeakerEmbedder {
  ScriptedEmbedder(this.vectors);
  final List<List<double>> vectors;
  int calls = 0;
  int releases = 0;

  @override
  Future<Float32List> embed(Int16List pcm) async =>
      Float32List.fromList(vectors[calls++ % vectors.length]);

  @override
  Future<void> release() async => releases++;
}

TestEnv speakerEnv({
  bool installed = true,
  List<List<double>>? vectors,
  ScriptedEmbedder? embedder,
}) {
  final env = TestEnv(
    extraOverrides: [
      wakeAudioProvider.overrideWithValue(
        SequenceAudio([for (var i = 0; i < 5; i++) recording(speech: 1600)]),
      ),
      speakerEmbedderProvider.overrideWithValue(
        embedder ??
            ScriptedEmbedder(
              vectors ??
                  [
                    [1, 0, 0],
                    [0.95, 0.1, 0],
                    [0.97, 0.05, 0.1],
                    [0.93, 0.12, 0.05],
                    [0.96, 0.08, 0.02],
                  ],
            ),
      ),
    ],
  );
  if (installed) env.speechModels.installed.add('speaker-campplus');
  return env;
}

Future<ProviderContainer> pump(WidgetTester tester, TestEnv env) async {
  setView(tester, const Size(390, 2000));
  await tester.pumpWidget(env.app(home: const SpeakerScreen()));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(SpeakerScreen)));
}

Future<void> addPerson(WidgetTester tester, String name) async {
  await tester.tap(find.text('Person einlernen'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  await tester.tap(find.text('Weiter'));
  await tester.pump();
}

void main() {
  testWidgets('Schalter ist aus und warnt, dass die Stimme kein Login ist', (
    tester,
  ) async {
    final env = speakerEnv();
    final c = await pump(tester, env);
    expect(find.textContaining('keine sichere Anmeldung'), findsOneWidget);
    expect(tester.widget<WSwitch>(find.byType(WSwitch)).value, isFalse);
    expect(c.read(speakerRecognizerProvider), isNull);

    await tester.tap(find.byType(WSwitch));
    await settle(tester);
    expect(
      (await c.read(voiceSettingsProvider.future)).speakerRecognition,
      isTrue,
    );
    expect(c.read(speakerRecognizerProvider), isNotNull);
  });

  testWidgets('ohne Modell ist Einlernen gesperrt', (tester) async {
    final env = speakerEnv(installed: false);
    await pump(tester, env);
    expect(find.text('Lade zuerst das Modell.'), findsOneWidget);
    await tester.tap(find.text('Person einlernen'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Einlernen: fünf Sätze, Ergebnis, Person in der Liste, '
      'verschlüsselt gespeichert, Löschen entfernt alles', (tester) async {
    final env = speakerEnv();
    final c = await pump(tester, env);
    expect(find.text('Noch niemand eingelernt.'), findsOneWidget);

    await addPerson(tester, 'Anna');
    await settle(
      tester,
      until: () => find.text('Eingelernt').evaluate().isNotEmpty,
    );
    expect(find.text('Eingelernt'), findsOneWidget);
    expect(find.textContaining('Gleichmäßigkeit'), findsOneWidget);
    expect(await env.secrets.listKeys(), [
      SecretSpeakerProfileStore.profilesKey,
    ]);
    await tester.tap(find.text('Fertig'));
    await settle(tester);
    expect(find.text('Anna'), findsOneWidget);
    expect((await c.read(speakerProfilesProvider.future)).single.name, 'Anna');

    // Antippen öffnet die Person (WP92b); dort löscht man sie.
    await tester.tap(find.text('Anna'));
    await settle(tester);
    await tester.tap(find.text('Person löschen'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Löschen'),
      ),
    );
    await settle(tester);
    expect(find.text('Anna'), findsNothing);
    expect(find.text('Noch niemand eingelernt.'), findsOneWidget);
    expect(await env.secrets.listKeys(), isEmpty);
  });

  testWidgets('verschiedene Stimmen: Fehlermeldung, nichts gespeichert', (
    tester,
  ) async {
    final env = speakerEnv(
      vectors: [
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1],
        [-1, 0, 0],
        [0, -1, 0],
      ],
    );
    await pump(tester, env);
    await addPerson(tester, 'Anna');
    await settle(
      tester,
      until: () => find.text('Noch einmal').evaluate().isNotEmpty,
    );
    expect(find.textContaining('nicht nach derselben Person'), findsOneWidget);
    expect(find.text('Noch einmal'), findsOneWidget);
    expect(await env.secrets.listKeys(), isEmpty);
  });

  testWidgets('Einlernen bei ausgeschaltetem Schalter gibt das Modell frei', (
    tester,
  ) async {
    final embedder = ScriptedEmbedder([
      [1, 0, 0],
      [0.95, 0.1, 0],
      [0.97, 0.05, 0.1],
      [0.93, 0.12, 0.05],
      [0.96, 0.08, 0.02],
    ]);
    final env = speakerEnv(embedder: embedder);
    await pump(tester, env);
    final before = embedder.releases;
    await addPerson(tester, 'Anna');
    await settle(
      tester,
      until: () => find.text('Eingelernt').evaluate().isNotEmpty,
    );
    expect(embedder.calls, 5);
    expect(embedder.releases, before + 1);
  });

  testWidgets('Einlernen bei eingeschaltetem Schalter behält das Modell', (
    tester,
  ) async {
    final embedder = ScriptedEmbedder([
      [1, 0, 0],
      [0.95, 0.1, 0],
      [0.97, 0.05, 0.1],
      [0.93, 0.12, 0.05],
      [0.96, 0.08, 0.02],
    ]);
    final env = speakerEnv(embedder: embedder);
    await pump(tester, env);
    await tester.tap(find.byType(WSwitch));
    await settle(tester);
    final before = embedder.releases;
    await addPerson(tester, 'Anna');
    await settle(
      tester,
      until: () => find.text('Eingelernt').evaluate().isNotEmpty,
    );
    expect(embedder.releases, before);
  });

  testWidgets('Ausschalten gibt das Modell frei', (tester) async {
    final embedder = ScriptedEmbedder([
      [1, 0, 0],
    ]);
    final env = speakerEnv(embedder: embedder);
    final c = await pump(tester, env);
    await tester.tap(find.byType(WSwitch));
    await settle(tester);
    expect(c.read(speakerRecognizerProvider), isNotNull);
    final before = embedder.releases;
    await tester.tap(find.byType(WSwitch));
    await settle(tester);
    expect(c.read(speakerRecognizerProvider), isNull);
    expect(embedder.releases, before + 1);
  });
}
