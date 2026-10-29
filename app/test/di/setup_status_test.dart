import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/setup_status.dart';

const _all = SetupFacts(
  providerConfigured: true,
  speechReady: true,
  wakeReady: true,
  speakerEnrolled: true,
);

void main() {
  group('SetupPage', () {
    test('nur Anbieter und Sprache sind Pflicht', () {
      expect(SetupPage.values.where((p) => p.isRequired), [
        SetupPage.provider,
        SetupPage.speech,
      ]);
    });

    test('parse: Name oder Anfang', () {
      expect(SetupPage.parse('speech'), SetupPage.speech);
      expect(SetupPage.parse(null), SetupPage.welcome);
      expect(SetupPage.parse('gibtsNicht'), SetupPage.welcome);
    });
  });

  group('stateOf', () {
    test('abgeleitet aus den Fakten', () {
      expect(_all.stateOf(SetupPage.provider), PageState.met);
      expect(
        const SetupFacts(providerConfigured: false).stateOf(SetupPage.provider),
        PageState.unmet,
      );
      expect(const SetupFacts().stateOf(SetupPage.speech), PageState.unknown);
      expect(const SetupFacts().stateOf(SetupPage.wakeWord), PageState.unknown);
      expect(
        const SetupFacts().stateOf(SetupPage.personalization),
        PageState.unknown,
      );
    });

    test('Seiten ohne eigenen Stand', () {
      for (final p in [
        SetupPage.welcome,
        SetupPage.integrations,
        SetupPage.done,
      ]) {
        expect(_all.stateOf(p), PageState.none);
      }
    });
  });

  group('canAdvance (fail-closed)', () {
    test('Pflichtseite nur mit erfülltem Stand', () {
      expect(_all.canAdvance(SetupPage.provider), isTrue);
      expect(
        const SetupFacts(providerConfigured: false)
            .canAdvance(SetupPage.provider),
        isFalse,
      );
      expect(const SetupFacts().canAdvance(SetupPage.provider), isFalse);
      expect(const SetupFacts().canAdvance(SetupPage.speech), isFalse);
      expect(
        const SetupFacts(speechReady: false).canAdvance(SetupPage.speech),
        isFalse,
      );
    });

    test('optionale Seiten gehen immer, auch unbekannt oder unerfüllt', () {
      const none = SetupFacts(wakeReady: false, speakerEnrolled: false);
      for (final p in [
        SetupPage.welcome,
        SetupPage.wakeWord,
        SetupPage.integrations,
        SetupPage.personalization,
      ]) {
        expect(none.canAdvance(p), isTrue, reason: p.name);
        expect(const SetupFacts().canAdvance(p), isTrue, reason: p.name);
      }
    });

    test('canFinish braucht beide Pflichtseiten', () {
      expect(_all.canFinish, isTrue);
      expect(
        const SetupFacts(providerConfigured: true, speechReady: true).canFinish,
        isTrue,
        reason: 'Optionales fehlt, geht trotzdem',
      );
      expect(
        const SetupFacts(providerConfigured: true).canFinish,
        isFalse,
        reason: 'Sprache unbekannt',
      );
      expect(
        const SetupFacts(speechReady: true).canFinish,
        isFalse,
        reason: 'Anbieter unbekannt',
      );
      expect(
        const SetupFacts(
          providerConfigured: false,
          speechReady: true,
        ).canFinish,
        isFalse,
      );
    });
  });

  group('effectivePage', () {
    test('nie hinter einer bekannt unerfüllten Pflichtseite', () {
      const f = SetupFacts(providerConfigured: false, speechReady: true);
      expect(f.effectivePage(SetupPage.personalization), SetupPage.provider);
      expect(f.effectivePage(SetupPage.speech), SetupPage.provider);
      expect(f.effectivePage(SetupPage.provider), SetupPage.provider);
      expect(f.effectivePage(SetupPage.welcome), SetupPage.welcome);
    });

    test('unbekannt springt nicht zurück (kein Flackern beim Laden)', () {
      expect(
        const SetupFacts().effectivePage(SetupPage.integrations),
        SetupPage.integrations,
      );
    });

    test('erfüllt: bleibt', () {
      expect(_all.effectivePage(SetupPage.done), SetupPage.done);
    });

    test('zweite Pflichtseite bekannt unerfüllt', () {
      const f = SetupFacts(providerConfigured: true, speechReady: false);
      expect(f.effectivePage(SetupPage.done), SetupPage.speech);
    });
  });
}
