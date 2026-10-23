import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/l10n/gen/app_localizations_en.dart';
import 'package:wendelin/l10n/gen/app_localizations_fr.dart';
import 'package:wendelin/ui/settings/wake/wake_enroll_screen.dart';
import 'package:wendelin/voice/wake/utterance_capture.dart';
import 'package:wendelin/voice/wake/wake_template_audit.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// A word-like template: the fixed mean plus a shared direction and a bit of
/// per-recording variation; [stray] points elsewhere.
Float32List tpl(int i, {bool stray = false}) {
  final r = math.Random(i);
  return Float32List.fromList([
    for (var k = 0; k < 1536; k++)
      wakeCenterMean[k] +
          (stray ? (k.isEven ? 1 : -1) : (k % 3 == 0 ? 1 : -0.3)) +
          (r.nextDouble() - 0.5) * 0.2,
  ]);
}

WakeTemplates stored(List<Float32List> e, {String? center = wakeCenterId}) =>
    WakeTemplates(
      speakerId: 'a',
      featureVersion: 'v',
      threshold: 0.5,
      embeddings: e,
      center: center,
    );

void main() {
  test(
    'Altbestand: Ausreißer werden einmal entfernt und gespeichert',
    () async {
      final store = FakeWakeTemplateStore();
      await store.save(
        stored([for (var i = 0; i < 9; i++) tpl(i), tpl(100, stray: true)]),
      );
      final first = await auditTemplates(store, 'a');
      expect(first!.removed, 1);
      expect(first.left, 9);
      expect((await store.load('a'))!.embeddings, hasLength(9));
      final again = await auditTemplates(store, 'a');
      expect(again!.removed, 0, reason: 'zweiter Lauf ändert nichts');
    },
  );

  test('zu wenig übrig: Neu einlernen wird verlangt', () async {
    final store = FakeWakeTemplateStore();
    await store.save(
      stored([for (var i = 0; i < 5; i++) tpl(i), tpl(100, stray: true)]),
    );
    final a = await auditTemplates(store, 'a');
    expect(a!.needsRelearn(8), isTrue);
    expect(a.needsRelearn(5), isFalse);
  });

  test('nichts zu prüfen: andere Kennung, leer, fehlend', () async {
    final store = FakeWakeTemplateStore();
    expect(await auditTemplates(store, 'x'), isNull);
    await store.save(stored([tpl(1)], center: null));
    expect(await auditTemplates(store, 'a'), isNull);
    expect((await store.load('a'))!.embeddings, hasLength(1));
  });

  test('Fehler im Speicher: kein Absturz, nichts geändert', () async {
    final store = _Broken();
    expect(await auditTemplates(store, 'a'), isNull);
  });

  test('Hinweistexte der neuen Urteile in de, en, fr', () {
    for (final l in [
      AppLocalizationsDe(),
      AppLocalizationsEn(),
      AppLocalizationsFr(),
    ]) {
      for (final v in [
        UtteranceVerdict.notWord,
        UtteranceVerdict.inconsistent,
        UtteranceVerdict.unchecked,
      ]) {
        expect(verdictText(l, v, word: 'Wendelin'), isNotEmpty);
      }
      expect(l.wakeEnrollRejected(3), contains('3'));
      expect(l.wakeWordTemplatesFew(4), contains('4'));
    }
    expect(
      verdictText(
        AppLocalizationsDe(),
        UtteranceVerdict.notWord,
        word: 'Wendelin',
      ),
      contains('Nicht als „Wendelin“ erkannt'),
    );
  });
}

final class _Broken implements WakeTemplateStore {
  @override
  Future<WakeTemplates?> load(String speakerId) => throw StateError('kaputt');
  @override
  Future<void> save(WakeTemplates templates) => throw StateError('kaputt');
  @override
  Future<void> delete(String speakerId) => throw StateError('kaputt');
}
