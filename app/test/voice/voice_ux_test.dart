// WP31: Abbruch („Stopp“), Rückgängig während der Sprachausgabe (B9),
// „Neues Gespräch“ per Stimme.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'voice_controller_test.dart' show fakeVoice, waitVoice;

const _create =
    '{"title":"Tauchen","start":"2026-10-14T10:00","end":"2026-10-14T11:00"}';

void main() {
  late TestEnv env;
  late ProviderContainer c;

  ProviderContainer start(
    List<ScriptedTurn> turns, {
    required List<Transcript> script,
    FakeTextToSpeech? tts,
  }) {
    env = TestEnv(
      providerConfig: scripted(FakeLlmProvider(turns)),
      extraOverrides: [
        activeVoiceProvider.overrideWith(
          (ref) async => fakeVoice(script: script, tts: tts),
        ),
      ],
    );
    c = env.container();
    // The UI keeps the controller alive from the start.
    c.read(voiceControllerProvider);
    return c;
  }

  VoiceController voice() => c.read(voiceControllerProvider.notifier);
  AgentController agent() => c.read(agentControllerProvider.notifier);

  setUp(() {
    VoiceController.promptTimeout = const Duration(milliseconds: 200);
  });
  tearDown(() {
    VoiceController.promptTimeout = const Duration(seconds: 15);
    c.dispose();
  });

  group('B5: Stopp', () {
    test(
      'Stopp-Äußerung: „Abgebrochen“ als Meta-Zeile, Verlauf bleibt',
      () async {
        start(
          [ScriptedTurn.text('Hallo.')],
          script: const [Transcript(text: 'Stopp')],
        );
        await agent().send('Hallo');
        await agent().idle;
        await voice().start(TriggerKind.pushToTalk);
        await voice().whenIdle;

        final s = c.read(agentControllerProvider);
        expect(s.entries.whereType<UserEntry>().single.text, 'Hallo');
        expect(
          s.entries.whereType<NoticeEntry>().map((n) => n.text),
          contains('Abgebrochen.'),
        );
        final v = c.read(voiceControllerProvider);
        expect(v.stopCount, 1);
        expect(v.hint, 'Abgebrochen.');
      },
    );

    test(
      'Tipp-Abbruch beim Zuhören: Status „Abgebrochen“, Overlay-Stopp-Zähler',
      () async {
        start(const [], script: const []);
        await voice().start(TriggerKind.pushToTalk);
        await waitVoice(c, (v) => v.phase == VoiceState.listening);
        await voice().cancel();
        final v = c.read(voiceControllerProvider);
        expect(v.hint, 'Abgebrochen.');
        // Wie beim Stopp-Wort: das Overlay blendet den alten Austausch aus
        // und schließt (je nach Einstellung).
        expect(v.stopCount, 1);
      },
    );
  });

  group('B9: Rückgängig während der Sprachausgabe', () {
    final answer = ScriptedTurn.text('Erledigt, Tauchen steht morgen um 10.');
    final create = ScriptedTurn.toolCalls([
      call('c1', 'calendar__create_event', _create),
    ]);

    test(
      'Stimme: Ausgabe stoppt sofort, „Zurückgenommen.“ wird gesprochen',
      () async {
        final tts = FakeTextToSpeech(
          utteranceDuration: const Duration(milliseconds: 120),
        );
        start(
          [create, answer],
          script: const [Transcript(text: 'Trag Tauchen ein', language: 'de')],
          tts: tts,
        );
        await voice().start(TriggerKind.pushToTalk);
        await waitVoice(c, (v) => v.phase == VoiceState.speaking);
        expect(tts.current, isNotNull);

        final text = await voice().undo('c1');

        expect(text, 'Zurückgenommen.');
        expect(tts.interrupted, isNotEmpty);
        expect(tts.spoken.last, 'Zurückgenommen.');
        expect(env.calendar.events, isEmpty);
        final s = c.read(agentControllerProvider);
        expect(s.tool('c1')!.undo, UndoPhase.undone);
        expect(s.entries.whereType<NoticeEntry>().last.text, 'Zurückgenommen.');
      },
    );

    for (final (lang, expected) in [
      ('de', 'Zurückgenommen.'),
      ('fr', 'Annulé.'),
      ('en', 'Undone.'),
    ]) {
      test('Sprache der Anfrage: $lang', () async {
        final tts = FakeTextToSpeech(
          utteranceDuration: const Duration(milliseconds: 120),
        );
        start(
          [create, answer],
          script: [Transcript(text: 'x', language: lang)],
          tts: tts,
        );
        await voice().start(TriggerKind.pushToTalk);
        await waitVoice(c, (v) => v.phase == VoiceState.speaking);
        expect(await voice().undo('c1'), expected);
        expect(tts.spoken.last, expected);
      });
    }

    test('getippt bei englischer App: Satz auf Englisch', () async {
      start([create], script: const []);
      await c.read(uiLanguageProvider.notifier).set('en');
      await agent().send('Add diving');
      await agent().idle;

      final text = c
          .read(agentControllerProvider)
          .entries
          .whereType<AssistantTextEntry>()
          .last
          .text;
      expect(text, startsWith('The event “Tauchen” is in your calendar'));
    });

    test('getippte Anfrage: nur Anzeige, kein Ton', () async {
      final tts = FakeTextToSpeech();
      start([create], script: const [], tts: tts);
      await agent().send('Trag Tauchen ein');
      await agent().idle;

      expect(await voice().undo('c1'), 'Zurückgenommen.');

      expect(tts.spoken, isEmpty);
      expect(
        c
            .read(agentControllerProvider)
            .entries
            .whereType<NoticeEntry>()
            .last
            .text,
        'Zurückgenommen.',
      );
    });

    test('Rückgängig stoppt eine gesprochene Bestätigungsfrage', () async {
      final tts = FakeTextToSpeech(
        utteranceDuration: const Duration(milliseconds: 120),
      );
      start(
        [
          create,
          ScriptedTurn.toolCalls([
            call('c2', 'calendar__delete_event', '{"event_id":"e1"}'),
          ]),
          ScriptedTurn.text('Erledigt.'),
        ],
        script: const [Transcript(text: 'Lösch den Termin', language: 'de')],
        tts: tts,
      );
      await env.calendar.createEvent(zahnarztDraft());
      await agent().send('Trag Tauchen ein');
      await agent().idle;
      await voice().start(TriggerKind.pushToTalk);
      for (var i = 0; i < 100 && tts.current == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(tts.current, 'Termin löschen? Ja oder nein?');
      expect(c.read(voiceControllerProvider).phase, isNot(VoiceState.idle));

      await voice().undo('c1');

      expect(tts.interrupted, contains('Termin löschen? Ja oder nein?'));
      // Typed card: no sound, and nothing keeps talking.
      expect(tts.current, isNull);
      expect(tts.spoken, ['Termin löschen? Ja oder nein?']);
      expect(env.calendar.events, hasLength(1));
      expect(c.read(agentControllerProvider).running, isFalse);
    });

    test('Rückgängig in der Denkphase beendet die Sprachanfrage', () async {
      final tts = FakeTextToSpeech(
        utteranceDuration: const Duration(milliseconds: 120),
      );
      start(
        [
          create,
          ScriptedTurn.toolCalls([
            call('c2', 'calendar__delete_event', '{"event_id":"e1"}'),
          ]),
          ScriptedTurn.text('Erledigt.'),
        ],
        script: const [Transcript(text: 'Lösch den Termin', language: 'de')],
        tts: tts,
      );
      await env.calendar.createEvent(zahnarztDraft());
      await agent().send('Trag Tauchen ein');
      await agent().idle;
      await voice().start(TriggerKind.pushToTalk);
      await waitVoice(c, (v) => v.phase == VoiceState.thinking);

      await voice().undo('c1');
      await voice().whenIdle;

      expect(c.read(voiceControllerProvider).phase, VoiceState.idle);
      expect(c.read(agentControllerProvider).running, isFalse);
      expect(env.calendar.events, hasLength(1));
    });

    test('Art der Anfrage gehört zur Karte: Sprach-Karte nach Tipp', () async {
      final tts = FakeTextToSpeech();
      start(
        [
          create,
          ScriptedTurn.toolCalls([
            call('c2', 'calendar__create_event', _create),
          ]),
        ],
        script: const [Transcript(text: 'Trag Tauchen ein', language: 'de')],
        tts: tts,
      );
      await voice().start(TriggerKind.pushToTalk);
      await voice().whenIdle;
      await agent().send('Und nochmal');
      await agent().idle;
      tts.spoken.clear();

      expect(await voice().undo('c1'), 'Zurückgenommen.');
      expect(tts.spoken, ['Zurückgenommen.']);
      tts.spoken.clear();
      expect(await voice().undo('c2'), 'Zurückgenommen.');
      expect(tts.spoken, isEmpty);
    });

    test('Art der Anfrage gehört zur Karte: Tipp-Karte nach Sprache', () async {
      final tts = FakeTextToSpeech();
      start(
        [
          create,
          ScriptedTurn.toolCalls([
            call('c2', 'calendar__create_event', _create),
          ]),
        ],
        script: const [Transcript(text: 'Trag Tauchen ein', language: 'de')],
        tts: tts,
      );
      await agent().send('Trag Tauchen ein');
      await agent().idle;
      await voice().start(TriggerKind.pushToTalk);
      await voice().whenIdle;
      tts.spoken.clear();

      expect(await voice().undo('c1'), 'Zurückgenommen.');
      expect(tts.spoken, isEmpty);
      expect(await voice().undo('c2'), 'Zurückgenommen.');
      expect(tts.spoken, ['Zurückgenommen.']);
    });

    test('Neues Gespräch leert die Zuordnung', () async {
      final tts = FakeTextToSpeech();
      start(
        [create, create],
        script: const [Transcript(text: 'Trag Tauchen ein', language: 'de')],
        tts: tts,
      );
      await voice().start(TriggerKind.pushToTalk);
      await voice().whenIdle;
      await agent().newTopic();
      await agent().send('Tipp');
      await agent().idle;
      tts.spoken.clear();

      expect(await voice().undo('c1'), 'Zurückgenommen.');
      expect(tts.spoken, isEmpty);
    });

    test('Zweites Rückgängig stoppt das noch gesprochene erste', () async {
      final tts = FakeTextToSpeech(
        utteranceDuration: const Duration(milliseconds: 120),
      );
      start(
        [
          create,
          ScriptedTurn.toolCalls([
            call('c2', 'calendar__create_event', _create),
          ]),
        ],
        script: const [Transcript(text: 'Trag Tauchen ein', language: 'de')],
        tts: tts,
      );
      await voice().start(TriggerKind.pushToTalk);
      await voice().whenIdle;
      await agent().send('Und nochmal');
      await agent().idle;
      tts.spoken.clear();
      tts.interrupted.clear();

      final first = voice().undo('c1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tts.current, 'Zurückgenommen.');
      final second = voice().undo('c2');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tts.interrupted, ['Zurückgenommen.']);
      await Future.wait([first, second]);
    });

    test('Rückgängig scheitert: kein Text, kein Ton', () async {
      final tts = FakeTextToSpeech();
      start(const [], script: const [], tts: tts);
      expect(await voice().undo('unbekannt'), isNull);
      expect(tts.spoken, isEmpty);
    });
  });

  group('Neues Gespräch per Stimme', () {
    for (final phrase in ['Neues Thema', 'Vergiss das, bitte', 'New topic']) {
      test('„$phrase“ leert den Verlauf, nichts geht ans Modell', () async {
        start(
          [ScriptedTurn.text('Hallo.')],
          script: [Transcript(text: phrase)],
        );
        await agent().send('Hallo');
        await agent().idle;
        expect(c.read(agentControllerProvider).entries.length, greaterThan(2));

        await voice().start(TriggerKind.pushToTalk);
        await voice().whenIdle;

        final entries = c.read(agentControllerProvider).entries;
        expect(entries.whereType<UserEntry>(), isEmpty);
        expect(entries.whereType<SessionStartEntry>(), hasLength(1));
      });
    }
  });

  group('B8: gesprochene Frage nennt die Notiz', () {
    ToolQuestion q(String description) => ToolQuestion(
      ConfirmationRequired(
        call: call('c', 'obsidian__replace_section', '{}'),
        description: description,
        respond: (_) {},
      ),
      request: 'r',
    );
    const text =
        'Gefunden: Wendelin-Test\n'
        'Abschnitt „Status“ in „Projekte/Wendelin-Test.md“ ersetzen:\n+ neu';
    for (final (lang, expected) in [
      ('de', 'In Wendelin-Test den Abschnitt Status ersetzen, soll ich?'),
      ('fr', 'Dans Wendelin-Test, remplacer la section Status, d’accord ?'),
      ('en', 'In Wendelin-Test, replace the section Status, shall I?'),
    ]) {
      test(lang, () => expect(confirmationPrompt(q(text), lang), expected));
    }

    test('Ersatztext ohne Notizangabe: allgemeine Frage', () {
      expect(
        confirmationPrompt(q('Notizabschnitt ersetzen'), 'de'),
        'Soll ich das tun? Ja oder nein?',
      );
    });
  });
}
