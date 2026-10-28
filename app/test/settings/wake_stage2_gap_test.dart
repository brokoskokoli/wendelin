import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/settings/wake/wake_models.dart';
import 'package:wendelin/ui/settings/wake/wake_word_screen.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'wake_word_screen_test.dart' show pumpWake, templates, wakeEnv;

/// WP171: the hint „Erkennungsmodell laden“ when stage 2 cannot decide.
Future<(TestEnv, ProviderContainer)> pumpGap(
  WidgetTester tester, {
  required bool sequences,
  required Set<String> models,
}) async {
  final env = wakeEnv(installed: false);
  env.speechModels.installed
    ..add('wake-features')
    ..addAll(models);
  final store = SecretWakeTemplateStore(env.secrets);
  await store.save(templates('a', count: 9, sequences: sequences));
  await store.saveSpeakers(const [WakeSpeaker(id: 'a', name: 'Anna')]);
  final c = await pumpWake(tester, env, const WakeWordScreen());
  return (env, c);
}

void main() {
  final cases = <(String, bool, Set<String>, bool)>[
    ('ohne Folgen, ohne Modell', false, {}, true),
    ('mit Folgen, ohne Modell', true, {}, false),
    ('ohne Folgen, nur Parakeet', false, {'parakeet-tdt-0.6b-v3'}, false),
    ('ohne Folgen, nur Whisper', false, {'whisper-base'}, false),
    ('mit Folgen, nur Parakeet', true, {'parakeet-tdt-0.6b-v3'}, false),
  ];
  for (final (name, seq, models, gap) in cases) {
    testWidgets('Lücke Stufe 2: $name -> $gap', (tester) async {
      final (_, c) = await pumpGap(tester, sequences: seq, models: models);
      expect(c.read(wakeStage2GapProvider), gap);
      expect(
        find.byKey(const ValueKey('wakeStage2Gap')),
        gap ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Erkennungsmodell laden'),
        gap ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('keine eingelernte Stimme: keine Lücke', (tester) async {
    final env = wakeEnv(installed: false);
    env.speechModels.installed.add('wake-features');
    final c = await pumpWake(tester, env, const WakeWordScreen());
    expect(c.read(wakeStage2GapProvider), isFalse);
  });

  testWidgets('Knopf lädt Parakeet über die Modellverwaltung', (tester) async {
    final (env, _) = await pumpGap(tester, sequences: false, models: {});
    expect(env.speechModels.running, isEmpty);
    await tester.tap(find.text('Erkennungsmodell laden'));
    await tester.pump();
    expect(env.speechModels.running.keys, contains('parakeet-tdt-0.6b-v3'));
  });

  test('Installationsstand noch nicht gelesen: kein Modell-Urteil', () {
    expect(wakeStage2HasNoModel(const {}), isFalse);
    expect(
      wakeStage2HasNoModel({
        for (final m in SpeechModelCatalog.standard.models)
          m.id: const ModelState(ModelPhase.unknown),
      }),
      isFalse,
    );
  });
}
