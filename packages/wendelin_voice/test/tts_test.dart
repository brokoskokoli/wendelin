import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const ms100 = Duration(milliseconds: 100);

void main() {
  group('SpeechQueue', () {
    test('spricht nacheinander und meldet idle', () {
      fakeAsync((async) {
        final tts = FakeTextToSpeech(utteranceDuration: ms100);
        final started = <String>[];
        var idle = 0;
        final q = SpeechQueue(
          tts,
          voice: 'v',
          language: 'de',
          rate: 1.2,
          onStart: started.add,
          onIdle: () => idle++,
        );
        expect(q.isIdle, isTrue);
        q.addAll(['A.', 'B.']);
        expect(q.current, 'A.');
        expect(q.pending, ['B.']);
        async.elapse(ms100);
        expect(q.current, 'B.');
        async.elapse(ms100);
        expect(q.isIdle, isTrue);
        expect(started, ['A.', 'B.']);
        expect(idle, 1);
        expect(tts.calls.first.voice, 'v');
        expect(tts.calls.first.language, 'de');
        expect(tts.calls.first.rate, 1.2);
      });
    });

    test('dropSegment entfernt nur wartende Sätze des Abschnitts', () {
      fakeAsync((async) {
        final tts = FakeTextToSpeech(utteranceDuration: ms100);
        final q = SpeechQueue(tts)
          ..addAll(['A0.'])
          ..addAll(['B0.'])
          ..addAll(['A1.', 'B1.'], segment: 1);
        expect(q.dropSegment(1), ['A1.', 'B1.']);
        expect(q.dropSegment(0), ['B0.']); // the playing one stays
        async.elapse(const Duration(seconds: 1));
        expect(tts.spoken, ['A0.']);
      });
    });

    test(
      'stop leert die Schlange, stoppt die Ausgabe, nimmt nichts mehr an',
      () {
        fakeAsync((async) {
          final tts = FakeTextToSpeech(utteranceDuration: ms100);
          var idle = 0;
          final q = SpeechQueue(tts, onIdle: () => idle++)
            ..addAll(['A.', 'B.']);
          var done = false;
          q.whenIdle.then((_) => done = true);
          q.stop();
          async.flushMicrotasks();
          expect(done, isTrue);
          expect(tts.interrupted, ['A.']);
          q.addAll(['C.']);
          async.elapse(const Duration(seconds: 1));
          expect(tts.spoken, ['A.']);
          expect(idle, 0);
          var again = false;
          q.whenIdle.then((_) => again = true);
          async.flushMicrotasks();
          expect(again, isTrue);
        });
      },
    );

    test('Fehler der Engine wird gemeldet, die Schlange läuft weiter', () {
      fakeAsync((async) {
        final tts = FakeTextToSpeech()..nextError = StateError('kaputt');
        final errors = <Object>[];
        SpeechQueue(tts, onError: errors.add).addAll(['A.', 'B.']);
        async.flushMicrotasks();
        expect(errors, hasLength(1));
        expect(tts.spoken, ['B.']);
      });
    });

    group('Vorlauf-Synthese (WP120)', () {
      const syn = Duration(seconds: 2);
      const play = Duration(seconds: 3);

      test('Satz 2 wird synthetisiert, während Satz 1 spielt', () {
        fakeAsync((async) {
          final tts = FakeTextToSpeech(
            utteranceDuration: play,
            synthesisDuration: syn,
          );
          final q = SpeechQueue(tts)..addAll(['A.', 'B.']);
          async.elapse(syn); // A ready and playing
          expect(tts.current, 'A.');
          expect(tts.prepared, ['A.', 'B.']); // B is in synthesis now
          async.elapse(play); // A ends; B was ready since 2 s into A
          expect(tts.current, 'B.');
          expect(tts.spoken, ['A.', 'B.']);
          async.elapse(play);
          expect(q.isIdle, isTrue);
          // 2 s + 3 s + 3 s: no pause of the synthesis between A and B.
        });
      });

      test('ein später eintreffender Satz wird sofort vorbereitet', () {
        fakeAsync((async) {
          final tts = FakeTextToSpeech(
            utteranceDuration: play,
            synthesisDuration: syn,
          );
          final q = SpeechQueue(tts)..addAll(['A.']);
          async.elapse(syn);
          expect(tts.prepared, ['A.']);
          q.addAll(['B.']);
          expect(tts.prepared, ['A.', 'B.']);
          q.addAll(['C.']); // lead of one sentence only
          expect(tts.prepared, ['A.', 'B.']);
          expect(q.hasPrepared, isTrue);
        });
      });

      test('interrupt verwirft den vorbereiteten Satz', () {
        fakeAsync((async) {
          final tts = FakeTextToSpeech(
            utteranceDuration: play,
            synthesisDuration: syn,
          );
          final q = SpeechQueue(tts)..addAll(['A.', 'B.']);
          async.elapse(syn);
          q.interrupt();
          async.elapse(const Duration(seconds: 10));
          expect(tts.discarded, ['B.']);
          expect(tts.spoken, ['A.']);
          expect(q.pending, isEmpty);
        });
      });

      test('stop verwirft den vorbereiteten Satz', () {
        fakeAsync((async) {
          final tts = FakeTextToSpeech(
            utteranceDuration: play,
            synthesisDuration: syn,
          );
          SpeechQueue(tts)
            ..addAll(['A.', 'B.'])
            ..stop();
          async.elapse(const Duration(seconds: 10));
          expect(tts.discarded, contains('B.'));
          expect(tts.spoken, isNot(contains('B.')));
        });
      });

      test(
        'dropSegment verwirft den vorbereiteten Satz, der nächste rückt nach',
        () {
          fakeAsync((async) {
            final tts = FakeTextToSpeech(
              utteranceDuration: play,
              synthesisDuration: syn,
            );
            final q = SpeechQueue(tts)
              ..addAll(['A.'])
              ..addAll(['B.'], segment: 1)
              ..addAll(['C.'], segment: 2);
            async.elapse(syn);
            expect(q.dropSegment(1), ['B.']);
            expect(tts.discarded, ['B.']);
            expect(tts.prepared, ['A.', 'B.', 'C.']); // C takes the lead
            async.elapse(const Duration(seconds: 10));
            expect(tts.spoken, ['A.', 'C.']);
          });
        },
      );

      test('Fehler beim Sprechen eines vorbereiteten Satzes: weiter', () {
        fakeAsync((async) {
          final tts = FakeTextToSpeech(utteranceDuration: ms100);
          final errors = <Object>[];
          SpeechQueue(tts, onError: errors.add).addAll(['A.', 'B.']);
          tts.nextError = StateError('kaputt');
          async.elapse(const Duration(seconds: 1));
          expect(errors, hasLength(1));
          expect(tts.spoken, ['A.']);
        });
      });
    });
  });

  group('TtsSelector (K7)', () {
    test('automatisch: Systemstimme, wenn installiert', () async {
      final system = FakeTextToSpeech();
      final sherpa = FakeTextToSpeech();
      final s = await TtsSelector(system: system, sherpa: sherpa).select();
      expect(s.engine, TtsEngine.system);
      expect(s.tts, same(system));
      expect(s.fallback, isFalse);
    });

    test(
      'automatisch: ohne Systemstimme sherpa, ohne Fallback-Hinweis',
      () async {
        final system = FakeTextToSpeech(available: false);
        final sherpa = FakeTextToSpeech();
        final s = await TtsSelector(system: system, sherpa: sherpa).select();
        expect(s.engine, TtsEngine.sherpa);
        expect(s.tts, same(sherpa));
        expect(s.fallback, isFalse);
      },
    );

    test('Einstellung sherpa überschreibt die Systemstimme', () async {
      final system = FakeTextToSpeech();
      final sherpa = FakeTextToSpeech();
      final s = await TtsSelector(
        system: system,
        sherpa: sherpa,
        preference: () => TtsPreference.sherpa,
      ).select();
      expect(s.engine, TtsEngine.sherpa);
      expect(s.fallback, isFalse);
    });

    test(
      'bevorzugte Engine fehlt: andere Engine mit Fallback-Hinweis',
      () async {
        final system = FakeTextToSpeech();
        final noSherpa = await TtsSelector(
          system: system,
          preference: () => TtsPreference.sherpa,
        ).select();
        expect(noSherpa.engine, TtsEngine.system);
        expect(noSherpa.fallback, isTrue);

        final sherpa = FakeTextToSpeech();
        final noSystem = await TtsSelector(
          system: FakeTextToSpeech(available: false),
          sherpa: sherpa,
          preference: () => TtsPreference.system,
        ).select();
        expect(noSystem.engine, TtsEngine.sherpa);
        expect(noSystem.fallback, isTrue);
      },
    );

    test('keine Engine: nur Text', () async {
      final selector = TtsSelector(
        system: _ThrowingAvailability(),
        sherpa: FakeTextToSpeech(available: false),
      );
      final s = await selector.select();
      expect(s.engine, TtsEngine.none);
      expect(s.tts, isNull);
      expect(await selector.current(), isNull);
      expect(s.toString(), contains('none'));
    });

    test('Sprache: Engine ohne Stimme der Sprache wird übersprungen', () async {
      final system = FakeTextToSpeech(
        voices: const [TtsVoice(id: 'de', language: 'de-DE')],
      );
      final sherpa = FakeTextToSpeech(
        voices: const [TtsVoice(id: 'fr', language: 'fr')],
      );
      final selector = TtsSelector(system: system, sherpa: sherpa);
      expect((await selector.select(language: 'de')).tts, same(system));
      expect((await selector.select(language: 'fr-CH')).tts, same(sherpa));
      expect((await selector.select(language: 'it')).engine, TtsEngine.none);
      expect(await selector.current('fr'), same(sherpa));
    });

    test(
      'Sprache: leere Stimmenliste gilt als passend, Fehler als nicht',
      () async {
        final system = FakeTextToSpeech(voices: const []);
        expect(
          (await TtsSelector(system: system).select(language: 'fr')).tts,
          same(system),
        );
        final broken = _ThrowingVoices();
        expect(
          (await TtsSelector(system: broken).select(language: 'fr')).engine,
          TtsEngine.none,
        );
        expect((await TtsSelector(system: broken).select()).tts, same(broken));
      },
    );

    test('Einstellung wird bei jeder Auswahl neu gelesen', () async {
      var pref = TtsPreference.automatic;
      final system = FakeTextToSpeech();
      final sherpa = FakeTextToSpeech();
      final selector = TtsSelector(
        system: system,
        sherpa: sherpa,
        preference: () => pref,
      );
      expect(await selector.current(), same(system));
      pref = TtsPreference.sherpa;
      expect(await selector.current(), same(sherpa));
    });
  });

  group('Fakes', () {
    test('FakeTextToSpeech: manueller Modus und Warteschlange', () {
      fakeAsync((async) {
        final tts = FakeTextToSpeech(manual: true);
        var first = false;
        var second = false;
        tts.speak('A').then((_) => first = true);
        tts.speak('B').then((_) => second = true);
        async.flushMicrotasks();
        expect(tts.spoken, ['A']);
        tts.completeCurrent();
        async.flushMicrotasks();
        expect(first, isTrue);
        expect(tts.spoken, ['A', 'B']);
        tts.stop();
        async.flushMicrotasks();
        expect(second, isTrue);
        expect(tts.state, TtsState.idle);
      });
    });

    test('FakeTextToSpeech: stop verwirft auch wartende Ausgaben', () {
      fakeAsync((async) {
        final tts = FakeTextToSpeech(manual: true);
        tts.speak('A');
        final b = tts.speak('B');
        async.flushMicrotasks();
        tts.stop();
        var done = false;
        b.then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(tts.spoken, ['A']);
      });
    });

    test('FakeTriggerSource stempelt mit der Uhr', () async {
      final clock = FixedClock(DateTime.utc(2026, 10, 13));
      final source = FakeTriggerSource(clock);
      final got = source.triggers.first;
      final e = source.fire(TriggerKind.assistant);
      expect(await got, e);
      expect(e.at, DateTime.utc(2026, 10, 13));
      expect(e, TriggerEvent(source: TriggerKind.assistant, at: e.at));
      expect(e.hashCode, TriggerEvent(source: e.source, at: e.at).hashCode);
      expect(e.toString(), contains('assistant'));
    });
  });

  textToSpeechContract(FakeTextToSpeech.new, name: 'FakeTextToSpeech');
  textToSpeechContract(
    () => FakeTextToSpeech(utteranceDuration: const Duration(milliseconds: 5)),
    name: 'FakeTextToSpeech (mit Dauer)',
  );
}

final class _ThrowingAvailability implements TextToSpeech {
  @override
  Future<bool> get isAvailable => Future.error(StateError('Dienst weg'));

  @override
  Future<List<TtsVoice>> voices() async => const [];

  @override
  TtsState get state => TtsState.idle;

  @override
  Stream<TtsState> get states => const Stream.empty();

  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) async {}

  @override
  Future<void> stop() async {}
}

final class _ThrowingVoices implements TextToSpeech {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<TtsVoice>> voices() => Future.error(StateError('weg'));

  @override
  TtsState get state => TtsState.idle;

  @override
  Stream<TtsState> get states => const Stream.empty();

  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) async {}

  @override
  Future<void> stop() async {}
}
