import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/wake/wake_stage2_gap.dart';
import 'package:wendelin/ui/settings/wake/wake_enroll_screen.dart';
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
  final cases = <(String, bool, Set<String>, WakeStage2Gap?)>[
    ('ohne Folgen, ohne Modell', false, {}, WakeStage2Gap.modelMissing),
    ('mit Folgen, ohne Modell', true, {}, null),
    (
      'ohne Folgen, nur Parakeet',
      false,
      {'parakeet-tdt-0.6b-v3'},
      WakeStage2Gap.noSequences,
    ),
    (
      'ohne Folgen, nur Whisper',
      false,
      {'whisper-base'},
      WakeStage2Gap.noSequences,
    ),
    ('mit Folgen, nur Parakeet', true, {'parakeet-tdt-0.6b-v3'}, null),
  ];
  for (final (name, seq, models, gap) in cases) {
    testWidgets('Lücke Stufe 2: $name -> $gap', (tester) async {
      final (_, c) = await pumpGap(tester, sequences: seq, models: models);
      expect(c.read(wakeStage2GapProvider), gap);
      expect(
        find.byKey(const ValueKey('wakeStage2Gap')),
        gap == WakeStage2Gap.modelMissing ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('wakeStage2NoSeq')),
        gap == WakeStage2Gap.noSequences ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Erkennungsmodell laden'),
        gap == WakeStage2Gap.modelMissing ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Aktivierungswort neu einlernen'),
        gap == WakeStage2Gap.noSequences ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('Knopf „neu einlernen“ öffnet das Einlernen', (tester) async {
    await pumpGap(tester, sequences: false, models: {'whisper-base'});
    await tester.tap(find.text('Aktivierungswort neu einlernen'));
    await tester.pumpAndSettle();
    expect(find.byType(WakeEnrollScreen), findsOneWidget);
  });

  testWidgets('Knopf „neu einlernen“ führt zur Stimme ohne Folgen, nicht zur '
      'ersten', (tester) async {
    final env = wakeEnv(installed: false);
    env.speechModels.installed.addAll(['wake-features', 'whisper-base']);
    final store = SecretWakeTemplateStore(env.secrets);
    await store.save(templates('a', count: 9, sequences: true));
    await store.save(templates('b', count: 9));
    await store.saveSpeakers(const [
      WakeSpeaker(id: 'a', name: 'Anna'),
      WakeSpeaker(id: 'b', name: 'Bert'),
    ]);
    final c = await pumpWake(tester, env, const WakeWordScreen());
    expect(c.read(wakeSpeakerWithoutSequencesProvider)?.id, 'b');
    await tester.tap(find.text('Aktivierungswort neu einlernen'));
    await tester.pumpAndSettle();
    final screen = tester.widget<WakeEnrollScreen>(
      find.byType(WakeEnrollScreen),
    );
    expect(screen.speakerId, 'b');
    expect(screen.name, 'Bert');
  });

  test('Regel wakeStage2GapOf: Matrix, Modell fehlt geht vor', () {
    WakeStage2Gap? gap(bool voice, bool noSeq, bool b, bool installed) =>
        wakeStage2GapOf(
          anyVoice: voice,
          anyWithoutSequences: noSeq,
          verifierB: b,
          recognizerInstalled: installed,
        );
    // No voice: nothing to check.
    expect(gap(false, false, true, false), isNull);
    expect(gap(false, false, false, false), isNull);
    // B on, all voices with sequences: B decides.
    expect(gap(true, false, true, false), isNull);
    // B on, a voice without sequences: model missing before no_sequences.
    expect(gap(true, true, true, false), WakeStage2Gap.modelMissing);
    expect(gap(true, true, true, true), WakeStage2Gap.noSequences);
    // B off: the recognizer decides alone; only its absence is a gap, and
    // enrolling again would not help.
    expect(gap(true, true, false, false), WakeStage2Gap.modelMissing);
    expect(gap(true, false, false, false), WakeStage2Gap.modelMissing);
    expect(gap(true, true, false, true), isNull);
    expect(gap(true, false, false, true), isNull);
    expect(WakeStage2Gap.noSequences.logName, 'no_sequences');
    expect(WakeStage2Gap.modelMissing.logName, 'model_missing');
  });

  testWidgets('keine eingelernte Stimme: keine Lücke', (tester) async {
    final env = wakeEnv(installed: false);
    env.speechModels.installed.add('wake-features');
    final c = await pumpWake(tester, env, const WakeWordScreen());
    expect(c.read(wakeStage2GapProvider), isNull);
  });

  testWidgets('Knopf lädt Parakeet über die Modellverwaltung', (tester) async {
    final (env, _) = await pumpGap(tester, sequences: false, models: {});
    expect(env.speechModels.running, isEmpty);
    await tester.tap(find.text('Erkennungsmodell laden'));
    await tester.pump();
    expect(env.speechModels.running.keys, contains('parakeet-tdt-0.6b-v3'));
  });

  test('Installationsstand noch nicht gelesen: kein Modell-Urteil', () {
    expect(wakeStage2RecognizerInstalled(const {}), isNull);
    expect(
      wakeStage2RecognizerInstalled({
        for (final m in SpeechModelCatalog.standard.models)
          m.id: const ModelState(ModelPhase.unknown),
      }),
      isNull,
    );
    expect(
      wakeStage2RecognizerInstalled({
        for (final m in SpeechModelCatalog.standard.models)
          m.id: const ModelState(ModelPhase.absent),
      }),
      isFalse,
    );
  });
}
