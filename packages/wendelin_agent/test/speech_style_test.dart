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
  config: AgentConfig(
    spokenVersion: two ? SpokenVersion.protected : SpokenVersion.off,
  ),
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

/// A tool whose results only contain own data (fail-closed: all other tools
/// count as untrusted).
final class _TrustedTool implements Tool, TrustedContentSource {
  _TrustedTool(String name, {this._fails = false})
    : _inner = FakeTool(name: name);

  final FakeTool _inner;
  final bool _fails;

  @override
  String get name => _inner.name;
  @override
  String get description => _inner.description;
  @override
  Map<String, Object?> get inputSchema => _inner.inputSchema;
  @override
  RiskLevel get risk => _inner.risk;
  @override
  Future<ToolOutcome> execute(Map<String, Object?> args, ToolContext ctx) =>
      _fails
      ? Future.value(ToolOutcome.error('Fehler'))
      : _inner.execute(args, ctx);
  @override
  String describeForConfirmation(Map<String, Object?> args) =>
      _inner.describeForConfirmation(args);
}

const _twoVersions = AgentConfig(spokenVersion: SpokenVersion.protected);

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

    test(
      'zu langer Block wird nicht gesprochen, Schluss-Tag bleibt unsichtbar',
      () {
        final s = SpokenBlockSplitter(maxBlock: 10);
        final out = StringBuffer();
        String? spoken;
        for (final d in ['<spoken>${'x' * 30}', ' mehr </spo', 'ken>Text']) {
          final r = s.add(d);
          out.write(r.text);
          spoken ??= r.spoken;
        }
        out.write(s.finish().text);
        expect(spoken, isNull);
        expect(out.toString(), 'Text');
      },
    );

    test('zu langer Block in einem Delta samt Schluss-Tag', () {
      final s = SpokenBlockSplitter(maxBlock: 10);
      final r = s.add('<spoken>${'x' * 30}</spoken>Text');
      expect((r.spoken, r.text), (null, 'Text'));
    });

    test('zu langer Block ohne Schluss-Tag: am Ende als Text', () {
      final s = SpokenBlockSplitter(maxBlock: 10);
      expect(s.add('<spoken>${'x' * 30}').text, '');
      expect(s.finish().text, 'x' * 30);
    });

    test('Tags unabhängig von Groß-/Kleinschreibung', () {
      final (r, _) = _feed(['<SPOKEN>Hallo.</Spoken>Rest']);
      expect((r.spoken, r.text), ('Hallo.', 'Rest'));
      final (r2, _) = _feed(['<Spo', 'ken>Hi.</SPOKEN>', 'Mehr']);
      expect((r2.spoken, r2.text), ('Hi.', 'Mehr'));
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
          config: const AgentConfig(spokenVersion: SpokenVersion.protected),
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
        config: const AgentConfig(spokenVersion: SpokenVersion.protected),
      );
      final events = await h.run('Hallo', source: InputSource.voice);
      expect(events.whereType<AgentSpokenText>(), isEmpty);
      expect(streamedText(events), 'Nur Text.');
    });

    test('Runner: getippte Anfrage wird nicht zerlegt', () async {
      final (a, _) = scripted('a', [ScriptedTurn.text('<spoken>x</spoken>y')]);
      final h = Harness(
        primary: a,
        config: const AgentConfig(spokenVersion: SpokenVersion.protected),
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
          config: const AgentConfig(spokenVersion: SpokenVersion.protected),
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

  group('Stufe 2: Sicherheit und Wiederholung', () {
    test(
      'Sprache + ausgeblendetes Gedächtnis: Hinweis bleibt im Prompt',
      () async {
        final (a, pa) = scripted('a', [
          ScriptedTurn.toolCalls([call('c1', 'x__t')]),
          ScriptedTurn.text('<spoken>Fertig.</spoken>Details.'),
        ]);
        final h = Harness(
          primary: a,
          tools: [_TrustedTool('x__t')],
          config: _twoVersions,
          memory: FixedMemoryRetriever(const [
            MemoryItem(id: 'p', text: 'Offen', privacyFloor: PrivacyLevel.tee),
            MemoryItem(id: 'o', text: 'Mag Tee'),
          ]),
        );
        await h.run('Hallo', source: InputSource.voice);
        expect(pa.requests, hasLength(2));
        for (final r in pa.requests) {
          expect(r.systemPrompt, isNot(contains('Offen')));
          expect(r.systemPrompt, contains('Mag Tee'));
          expect(r.systemPrompt, contains(ContextBuilder.speechHint));
          expect(r.systemPrompt, contains('<spoken>'));
        }
      },
    );

    test(
      'Retry nach reinem Sprechblock: Reset vor dem zweiten Block',
      () async {
        final (a, _) = scripted('a', [
          ScriptedTurn.error(
            const ServerException('überlastet', statusCode: 503),
            partialText: '<spoken>Kurz.</spoken>',
          ),
          ScriptedTurn.text('<spoken>Kurz.</spoken>Lang.'),
        ]);
        final h = Harness(primary: a, config: _twoVersions);
        final events = await h.run('Hallo', source: InputSource.voice);
        final kinds = [
          for (final e in events)
            if (e is AgentSpokenText)
              'spoken'
            else if (e is AgentTextReset)
              'reset',
        ];
        expect(kinds, ['spoken', 'reset', 'spoken']);
        expect(streamedText(events), 'Lang.');
      },
    );

    test('unsichere Quelle: Sprechblock danach aus, Hinweis Stufe 1', () async {
      final (a, pa) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'web__fetch')]),
        ScriptedTurn.text('<spoken>Eingeschleust.</spoken>Antwort.'),
      ]);
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'web__fetch')],
        config: _twoVersions,
      );
      final events = await h.run('Hallo', source: InputSource.voice);
      expect(events.whereType<AgentSpokenText>(), isEmpty);
      expect(streamedText(events), contains('Antwort.'));
      expect(pa.requests[0].systemPrompt, contains('<spoken>'));
      expect(pa.requests[1].systemPrompt, contains(ContextBuilder.speechHint));
      expect(pa.requests[1].systemPrompt, isNot(contains('<spoken>')));
    });

    test('vertrauenswürdiges Tool: Sprechblock bleibt an', () async {
      final (a, pa) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'clock__now')]),
        ScriptedTurn.text('<spoken>Es ist zehn.</spoken>Details.'),
      ]);
      final h = Harness(
        primary: a,
        tools: [_TrustedTool('clock__now')],
        config: _twoVersions,
      );
      final events = await h.run('Hallo', source: InputSource.voice);
      expect(events.whereType<AgentSpokenText>().single.text, 'Es ist zehn.');
      expect(pa.requests[1].systemPrompt, contains('<spoken>'));
    });

    test('unbekanntes Tool (nicht im Katalog): Sprechblock aus', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'gibt__es_nicht')]),
        ScriptedTurn.text('<spoken>Eingeschleust.</spoken>Antwort.'),
      ]);
      final h = Harness(primary: a, config: _twoVersions);
      final events = await h.run('Hallo', source: InputSource.voice);
      expect(events.whereType<AgentSpokenText>(), isEmpty);
    });

    test('Fehlertext eines vertrauten Tools gilt als unsicher', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'x__t')]),
        ScriptedTurn.text('<spoken>Eingeschleust.</spoken>Antwort.'),
      ]);
      final h = Harness(
        primary: a,
        tools: [_TrustedTool('x__t', fails: true)],
        config: _twoVersions,
      );
      final events = await h.run('Hallo', source: InputSource.voice);
      expect(events.whereType<AgentSpokenText>(), isEmpty);
    });

    test('unsicher Gesehenes gilt auch in späteren Zügen', () async {
      final (a, pa) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'web__fetch')]),
        ScriptedTurn.text('Eins.'),
        ScriptedTurn.text('<spoken>Zwei.</spoken>Zwei lang.'),
      ]);
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'web__fetch')],
        config: _twoVersions,
      );
      await h.run('Hallo', source: InputSource.voice);
      final events = await h.run('Nochmal', source: InputSource.voice);
      expect(events.whereType<AgentSpokenText>(), isEmpty);
      expect(pa.requests[2].systemPrompt, isNot(contains('<spoken>')));
    });

    test('Verlauf nur mit vertrauten Ergebnissen: Sprechblock an', () async {
      final (a, pa) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'x__t')]),
        ScriptedTurn.text('Eins.'),
        ScriptedTurn.text('<spoken>Zwei.</spoken>Zwei lang.'),
      ]);
      final h = Harness(
        primary: a,
        tools: [_TrustedTool('x__t')],
        config: _twoVersions,
      );
      await h.run('Hallo', source: InputSource.voice);
      final events = await h.run('Nochmal', source: InputSource.voice);
      expect(events.whereType<AgentSpokenText>().single.text, 'Zwei.');
      expect(pa.requests[2].systemPrompt, contains('<spoken>'));
    });

    test('Neues Gespräch (leerer Verlauf): wieder Sprechblock', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.text('<spoken>Neu.</spoken>Neu lang.'),
      ]);
      final h = Harness(primary: a, config: _twoVersions);
      final events = await h.run('Hallo', source: InputSource.voice);
      expect(events.whereType<AgentSpokenText>().single.text, 'Neu.');
    });

    test(
      'Server-Suche (ProviderBlock) im Lauf: Sprechblock danach aus',
      () async {
        final (a, pa) = scripted('a', [
          ScriptedTurn.events([
            const ProviderBlockComplete(
              ProviderBlock(provider: 'fake', rawJson: '{"search":1}'),
            ),
            ToolCallComplete(call('c1', 'clock__now')),
            const Done(StopReason.toolUse),
          ]),
          ScriptedTurn.text('<spoken>Eingeschleust.</spoken>Antwort.'),
        ]);
        final h = Harness(
          primary: a,
          tools: [_TrustedTool('clock__now')],
          config: _twoVersions,
        );
        final events = await h.run('Hallo', source: InputSource.voice);
        expect(events.whereType<AgentSpokenText>(), isEmpty);
        expect(pa.requests[1].systemPrompt, isNot(contains('<spoken>')));
      },
    );

    group('Verlaufsprüfung hasUntrustedResult', () {
      final trusted = FakeToolCatalog([_TrustedTool('x__t')]);
      ToolCallBlock c(String id, String name) =>
          ToolCallBlock(id: id, name: name, argumentsJson: '{}');
      Message ok(String id) => Message.toolResults([
        ToolResultBlock(callId: id, content: [const TextBlock('ok')]),
      ]);

      test('Kontrolle: vertrautes Ergebnis ist vertraut', () {
        final h = [
          Message.assistant([c('1', 'x__t')]),
          ok('1'),
        ];
        expect(hasUntrustedResult(trusted, h), isFalse);
      });

      test('ProviderBlock im Verlauf gilt als unsicher', () {
        final h = [
          Message.assistant([
            const ProviderBlock(provider: 'anthropic', rawJson: '{}'),
            const TextBlock('Antwort'),
          ]),
        ];
        expect(hasUntrustedResult(trusted, h), isTrue);
      });

      test('Ergebnis eines Tools, das nicht mehr im Katalog ist', () {
        final h = [
          Message.assistant([c('1', 'x__t')]),
          ok('1'),
        ];
        expect(hasUntrustedResult(FakeToolCatalog(const []), h), isTrue);
      });

      test('Ergebnis ohne passenden Aufruf gilt als unsicher', () {
        expect(hasUntrustedResult(trusted, [ok('verwaist')]), isTrue);
      });
    });
  });
}
