// WP31: Abbruch („Stopp“), Rückgängig während der Sprachausgabe (B9),
// „Neues Gespräch“ per Stimme.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
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
    return c = env.container();
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
      'Tipp-Abbruch beim Zuhören: Status „Abgebrochen“, kein Stopp-Zähler',
      () async {
        start(const [], script: const []);
        await voice().start(TriggerKind.pushToTalk);
        await waitVoice(c, (v) => v.phase == VoiceState.listening);
        await voice().cancel();
        final v = c.read(voiceControllerProvider);
        expect(v.hint, 'Abgebrochen.');
        expect(v.stopCount, 0);
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
        final tts = FakeTextToSpeech(manual: true);
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
        final tts = FakeTextToSpeech(manual: true);
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

    test('getippte Anfrage: nur Anzeige, kein Ton', () async {
      final tts = FakeTextToSpeech();
      start([create, answer], script: const [], tts: tts);
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
