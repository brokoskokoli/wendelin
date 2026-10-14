import 'dart:typed_data';

import 'package:test/test.dart';

import '../src/wake/keyword_spec.dart';
import '../src/wake/wake_word_engine.dart';
import 'voice_contracts.dart';

/// Contract for every [WakeWordEngine] (app implementation, fakes).
///
/// [wakeAudio] must be frames after which the engine reports at least one
/// hit for `wake`; [quietAudio] frames that never produce a hit (silence).
void wakeWordEngineContract(
  VoiceFactory<WakeWordEngine> create, {
  required List<Int16List> Function() wakeAudio,
  required List<Int16List> Function() quietAudio,
  String name = 'WakeWordEngine',
}) {
  const keywords = [KeywordSpec.wendelin];
  Future<List<WakeWordHit>> feed(WakeWordEngine e, List<Int16List> fr) async =>
      [for (final f in fr) ...await e.accept(f)];

  group('$name erfüllt den WakeWordEngine-Vertrag', () {
    test('accept vor open und nach close wirft StateError', () async {
      final e = await create();
      expect(() => e.accept(Int16List(160)), throwsStateError);
      await e.open(keywords);
      await e.close();
      expect(() => e.accept(Int16List(160)), throwsStateError);
    });

    test('open zweimal wirft StateError, close ist idempotent', () async {
      final e = await create();
      await e.open(keywords);
      await expectLater(e.open(keywords), throwsStateError);
      await e.close();
      await e.close();
    });

    test('Stille liefert keinen Treffer, das Wort liefert wake', () async {
      final e = await create();
      await e.open(keywords);
      expect(await feed(e, quietAudio()), isEmpty);
      e.reset();
      final hits = await feed(e, wakeAudio());
      expect(hits, isNotEmpty);
      expect(hits.first.keywordId, 'wake');
      expect(hits.first.endSample, greaterThan(0));
      await e.close();
    });

    test('reset beginnt einen neuen Strom (Positionen ab 0)', () async {
      final e = await create();
      await e.open(keywords);
      final first = await feed(e, wakeAudio());
      e.reset();
      final second = await feed(e, wakeAudio());
      expect(second.first.endSample, first.first.endSample);
      await e.close();
    });
  });
}
