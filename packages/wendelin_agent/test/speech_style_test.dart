// WP41: vorlesefreundliche Antworten – Stufe 1 (Hinweis im dynamischen
// Prompt-Teil) und Stufe 2 (<spoken>-Block).

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/src/run/spoken_block.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'support.dart';

ContextBuilder _builder({bool two = false}) => ContextBuilder(
  config: AgentConfig(spokenVersions: two),
  clock: FixedClock(DateTime.utc(2026, 10, 13, 9, 5)),
  device: device,
  catalog: FakeToolCatalog(const []),
  memory: FixedMemoryRetriever(const [
    MemoryItem(id: 'm', text: 'Frau heißt Anna.'),
  ]),
);

UserInput _in(InputSource source) => UserInput(text: 'Hallo', source: source);

(SplitText, SplitText) _feed(List<String> deltas) {
  final s = SpokenBlockSplitter();
  final texts = StringBuffer();
  String? spoken;
  for (final d in deltas) {
    final r = s.add(d);
    texts.write(r.text);
    spoken ??= r.spoken;
  }
  final rest = s.finish();
  texts.write(rest.text);
  return ((text: texts.toString(), spoken: spoken), rest);
}

void main() {
  group('Stufe 1: Hinweis im dynamischen Teil', () {
    test('getippt: Prompt unverändert, kein Hinweis', () async {
      final b = _builder();
      final ctx = await b.build(_in(InputSource.text));
      expect(ctx.speech, SpeechStyle.none);
      expect(ctx.systemPrompt, isNot(contains('Sprachausgabe')));
      expect(ctx.systemPrompt, b.systemPrompt(memories: ctx.memories));
    });

    test(
      'gesprochen: Hinweis steht am Ende, stabiler Teil byte-gleich',
      () async {
        final b = _builder();
        final text = await b.build(_in(InputSource.text));
        final voice = await b.build(_in(InputSource.voice));
        expect(voice.speech, SpeechStyle.hint);
        // Everything before the hint (stable part, date, memory) is identical.
        expect(
          voice.systemPrompt,
          '${text.systemPrompt}\n\n${ContextBuilder.speechHint}',
        );
        final stableEnd = text.systemPrompt.indexOf('Umgebung:');
        expect(
          voice.systemPrompt.substring(0, stableEnd),
          text.systemPrompt.substring(0, stableEnd),
        );
        expect(
          voice.systemPrompt.indexOf('Sprachausgabe'),
          greaterThan(voice.systemPrompt.indexOf('Gedächtnis')),
        );
        expect(voice.systemPrompt, isNot(contains('<spoken>')));
      },
    );

    test('Sprach-Anfrage bekommt den Hinweis im Modellaufruf', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.text('Ok.'),
        ScriptedTurn.text('Ok.'),
      ]);
      final h = Harness(primary: a);
      await h.run('Hallo', source: InputSource.voice);
      await h.run('Hallo');
      expect(provider.requests[0].systemPrompt, contains('Sprachausgabe'));
      expect(
        provider.requests[1].systemPrompt,
        isNot(contains('Sprachausgabe')),
      );
    });

    test('Eskalation ohne Sprache bekommt keinen Hinweis', () async {
      final (a, pa) = scripted('a', [ScriptedTurn.text('Ok.')]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('Besser.')]);
      final h = Harness(primary: a, chain: [b]);
      await h.run('Hallo');
      await h.run('nochmal', requestEscalation: true);
      expect(pa.requests.single.systemPrompt, isNot(contains('Sprachausgabe')));
      expect(pb.requests.single.systemPrompt, isNot(contains('Sprachausgabe')));
    });
  });

  group('Stufe 2: Block im Stream', () {
    test('Prompt nennt den Block nur bei Einstellung und Sprache', () async {
      final b = _builder(two: true);
      final voice = await b.build(_in(InputSource.voice));
      expect(voice.speech, SpeechStyle.twoVersions);
      expect(voice.systemPrompt, contains('<spoken>'));
      expect(voice.systemPrompt, contains(ContextBuilder.speechHint));
      final text = await b.build(_in(InputSource.text));
      expect(text.systemPrompt, isNot(contains('<spoken>')));
      expect(text.systemPrompt, isNot(contains('Sprachausgabe')));
    });

    test('Block über mehrere Deltas', () {
      final (r, _) = _feed([
        '<spo',
        'ken>Du hast zwei ',
        'Termine.</spo',
        'ken>',
        '\n\nDetails: ',
        'a, b',
      ]);
      expect(r.spoken, 'Du hast zwei Termine.');
      expect(r.text, 'Details: a, b');
    });

    test('Block in einem Delta, Text direkt dahinter', () {
      final (r, _) = _feed(['  <spoken>Kurz.</spoken>Lang.']);
      expect((r.spoken, r.text), ('Kurz.', 'Lang.'));
    });

    test('kein Block: Text unverändert, auch mit Spitzklammer', () {
      for (final t in ['Hallo Welt', '<b>fett</b>', '<spo', '  Ok']) {
        final (r, _) = _feed([
          t.substring(0, t.length ~/ 2),
          t.substring(t.length ~/ 2),
        ]);
        expect((r.spoken, r.text), (null, t.trimLeft()));
      }
    });

    test('unvollständiger Block: Inhalt wird Text, nichts Gesprochenes', () {
      final (r, _) = _feed(['<spoken>Halber ', 'Satz']);
      expect((r.spoken, r.text), (null, 'Halber Satz'));
    });

    test('zu langer Block gilt als kaputt', () {
      final s = SpokenBlockSplitter(maxBlock: 10);
      final r = s.add('<spoken>${'x' * 30}');
      expect((r.spoken, r.text), (null, 'x' * 30));
      expect(s.add(' weiter').text, ' weiter');
    });

    test('leerer Block: Rückfall', () {
      final (r, _) = _feed(['<spoken></spoken>Text']);
      expect((r.spoken, r.text), (null, 'Text'));
    });

    test(
      'Runner: Ereignisse, Anzeige, Endtext und Verlauf ohne Block',
      () async {
        final (a, _) = scripted('a', [
          ScriptedTurn.text(
            '<spoken>Zwei Termine heute.</spoken>\n\n**Termine**\n- 10:00 Zahnarzt\n- 14:00 Chor',
          ),
        ]);
        final h = Harness(
          primary: a,
          config: const AgentConfig(spokenVersions: true),
        );
        final events = await h.run('Termine?', source: InputSource.voice);
        final spoken = events.whereType<AgentSpokenText>().single;
        expect(spoken.text, 'Zwei Termine heute.');
        // Spoken comes before the first text delta.
        expect(
          events.indexOf(spoken),
          lessThan(events.indexWhere((e) => e is AgentTextDelta)),
        );
        const written = '**Termine**\n- 10:00 Zahnarzt\n- 14:00 Chor';
        expect(streamedText(events), written);
        expect((terminal(events) as AgentDone).finalText, written);
        expect(h.conversation.messages.last, Message.assistantText(written));
      },
    );

    test('Runner: fehlender Block fällt auf den Text zurück', () async {
      final (a, _) = scripted('a', [ScriptedTurn.text('Nur Text.')]);
      final h = Harness(
        primary: a,
        config: const AgentConfig(spokenVersions: true),
      );
      final events = await h.run('Hallo', source: InputSource.voice);
      expect(events.whereType<AgentSpokenText>(), isEmpty);
      expect(streamedText(events), 'Nur Text.');
    });

    test('Runner: getippte Anfrage wird nicht zerlegt', () async {
      final (a, _) = scripted('a', [ScriptedTurn.text('<spoken>x</spoken>y')]);
      final h = Harness(
        primary: a,
        config: const AgentConfig(spokenVersions: true),
      );
      final events = await h.run('Hallo');
      expect(events.whereType<AgentSpokenText>(), isEmpty);
      expect(streamedText(events), '<spoken>x</spoken>y');
    });

    test(
      'Eskalation: der Verlauf für das nächste Modell hat keinen Block',
      () async {
        final (a, _) = scripted('a', [
          ScriptedTurn.text('<spoken>Eins.</spoken>Eins lang.'),
        ]);
        final (b, pb) = scripted('b', [ScriptedTurn.text('Besser.')]);
        final h = Harness(
          primary: a,
          chain: [b],
          config: const AgentConfig(spokenVersions: true),
        );
        await h.run('Hallo', source: InputSource.voice);
        await h.run(
          'nochmal',
          requestEscalation: true,
          source: InputSource.voice,
        );
        final sent = pb.requests.single.messages.map((m) => m.text).join('\n');
        expect(sent, contains('Eins lang.'));
        expect(sent, isNot(contains('spoken')));
      },
    );
  });
}
