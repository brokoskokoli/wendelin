// WP135 D: the fast path runs a recognized simple request as a tool call
// without a model call.

import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';
import 'fixed_confirmation_test.dart' show flashlight;

/// Recognizes exactly [text] (and records what it was asked).
final class _Match implements FastPath {
  _Match(this.text, {this.tool = 'flashlight__set', this.fail = false});

  final String text;
  final String tool;
  final bool fail;
  final asked = <(String, String?)>[];

  @override
  Future<FastPathCall?> match(String text, {required String? language}) async {
    asked.add((text, language));
    if (fail) throw StateError('matcher kaputt');
    return text == this.text
        ? FastPathCall(tool: tool, arguments: const {'on': true})
        : null;
  }
}

/// Routes like a spoken trigger: the text for the model differs from what
/// was said („nimm das große Modell: …“).
final class _Stripping implements ProviderResolver {
  _Stripping(this.target);

  final ProviderTarget target;

  @override
  Resolution resolve(UserInput input) =>
      Resolution(target: target, reason: 'Auslöser', effectiveText: 'Rest');

  @override
  Resolution? escalate(Resolution current, EscalationReason reason) => null;
}

const _sentence = 'Die Taschenlampe ist an.';

void main() {
  group('Schnellweg', () {
    test('Treffer: kein Modellaufruf, Satz, Verlauf wie beim Modell', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('nie')]);
      final fast = <(String, String)>[];
      final tool = flashlight(undo: true);
      final h = Harness(
        primary: a,
        tools: [tool],
        fastPath: _Match('Taschenlampe an'),
        onFastPath: (s, t) => fast.add((s, t)),
      );
      final events = await h.run('Taschenlampe an', language: 'de-DE');

      expect(provider.requests, isEmpty);
      expect(tool.callCount, 1);
      final done = terminal(events) as AgentDone;
      expect(done.finalText, _sentence);
      expect(done.fixed, isTrue);
      expect(done.stopReason, StopReason.endTurn);
      expect(streamedText(events), _sentence);
      expect(events.whereType<UsageReported>(), isEmpty);
      expect(fast, [('s1', 'flashlight__set')]);
      // Same events as a model call: the card (with undo) and its result.
      final started = events.whereType<ToolCallStarted>().single;
      final finished = events.whereType<ToolCallFinished>().single;
      expect(started.call.name, 'flashlight__set');
      expect(finished.call.id, started.call.id);
      expect(finished.outcome.undo, isNotNull);
      final id = started.call.id;
      expect(h.conversation.messages, [
        Message.user('Taschenlampe an'),
        Message.assistant([
          ToolCallBlock(
            id: id,
            name: 'flashlight__set',
            argumentsJson: '{"on":true}',
          ),
        ]),
        Message.toolResults([
          ToolResultBlock(callId: id, content: const [TextBlock('ok')]),
        ]),
        Message.assistantText(_sentence),
      ]);
    });

    test('Rückgängig: die Undo-Aktion des Ausgangs läuft', () async {
      final (a, _) = scripted('a', const []);
      final tool = flashlight(undo: true);
      final h = Harness(
        primary: a,
        tools: [tool],
        fastPath: _Match('Taschenlampe an'),
      );
      final events = await h.run('Taschenlampe an');
      final finished = events.whereType<ToolCallFinished>().single;
      await finished.outcome.undo!.run();
      expect(tool.undoCount, 1);
    });

    test(
      'Fehler des Tools: Modell übernimmt, sieht Aufruf und Ergebnis',
      () async {
        final (a, provider) = scripted('a', [ScriptedTurn.text('Ging nicht.')]);
        final fast = <String>[];
        final h = Harness(
          primary: a,
          tools: [
            flashlight(
              outcome: ToolOutcome(
                content: const [TextBlock('kaputt')],
                isError: true,
                fixed: const ConfirmationSentence('flashlight.on'),
              ),
            ),
          ],
          fastPath: _Match('Taschenlampe an'),
          onFastPath: (_, t) => fast.add(t),
        );
        final events = await h.run('Taschenlampe an');
        expect(provider.requests, hasLength(1));
        final roles = provider.requests.single.messages.map((m) => m.role);
        expect(roles, [Role.user, Role.assistant, Role.tool]);
        expect(
          provider.requests.single.messages[1].content.single,
          isA<ToolCallBlock>().having((c) => c.name, 'name', 'flashlight__set'),
        );
        expect((terminal(events) as AgentDone).finalText, 'Ging nicht.');
        expect((terminal(events) as AgentDone).fixed, isFalse);
        expect(fast, isEmpty);
      },
    );

    test('abgelehnte Bestätigung: Modell übernimmt', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('Gut, nicht.')]);
      final tool = flashlight(risk: RiskLevel.external);
      final h = Harness(
        primary: a,
        tools: [tool],
        fastPath: _Match('Taschenlampe an'),
      );
      await h.run(
        'Taschenlampe an',
        onEvent: (e) {
          if (e is ConfirmationRequired) e.respond(false);
        },
      );
      expect(tool.callCount, 0);
      expect(provider.requests, hasLength(1));
    });

    test('Matcher wirft: Modell antwortet', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('Okay.')]);
      final tool = flashlight();
      final h = Harness(
        primary: a,
        tools: [tool],
        fastPath: _Match('Taschenlampe an', fail: true),
      );
      final events = await h.run('Taschenlampe an');
      expect(tool.callCount, 0);
      expect(provider.requests, hasLength(1));
      expect((terminal(events) as AgentDone).finalText, 'Okay.');
    });

    test(
      'kein Treffer: Modell antwortet, Matcher bekommt Text und Sprache',
      () async {
        final (a, provider) = scripted('a', [ScriptedTurn.text('Hallo.')]);
        final match = _Match('Taschenlampe an');
        final h = Harness(primary: a, tools: [flashlight()], fastPath: match);
        await h.run('Wie spät ist es?', language: 'de-DE');
        expect(provider.requests, hasLength(1));
        expect(match.asked, [('Wie spät ist es?', 'de-DE')]);
      },
    );

    test('Sprache fehlt: Oberflächensprache', () async {
      final (a, _) = scripted('a', [ScriptedTurn.text('x')]);
      final match = _Match('nichts');
      final h = Harness(primary: a, tools: [flashlight()], fastPath: match);
      await h.run('hallo', interfaceLanguage: 'fr');
      expect(match.asked.single.$2, 'fr');
    });

    test('ohne Schnellweg (null): Modell wie bisher', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'flashlight__set')]),
        ScriptedTurn.text('unnötig'),
      ]);
      final h = Harness(primary: a, tools: [flashlight()]);
      await h.run('Taschenlampe an');
      expect(provider.requests, hasLength(1));
    });

    test('Tool nicht im Katalog: Modell, nichts läuft', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('Okay.')]);
      final h = Harness(
        primary: a,
        tools: [flashlight()],
        fastPath: _Match('Taschenlampe an', tool: 'ha__call'),
      );
      await h.run('Taschenlampe an');
      expect(provider.requests, hasLength(1));
      expect(h.conversation.messages.whereType<Message>().length, 2);
    });

    test('Satz-Schlüssel nicht deklariert: Modell übernimmt', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('Okay.')]);
      final h = Harness(
        primary: a,
        tools: [flashlight(keys: const {})],
        fastPath: _Match('Taschenlampe an'),
      );
      final events = await h.run('Taschenlampe an');
      expect(provider.requests, hasLength(1));
      expect((terminal(events) as AgentDone).fixed, isFalse);
    });

    test(
      'Katalog des Ziels ohne das Tool (Datenschutzstufe): Modell',
      () async {
        final (a, provider) = scripted('a', [ScriptedTurn.text('Okay.')]);
        final tool = flashlight();
        final h = Harness(
          primary: a,
          tools: [tool],
          catalogFor: (_) => FakeToolCatalog(const []),
          fastPath: _Match('Taschenlampe an'),
        );
        await h.run('Taschenlampe an');
        expect(tool.callCount, 0);
        expect(provider.requests, hasLength(1));
      },
    );

    test('Katalog je Ziel enthält das Tool: Schnellweg', () async {
      final (a, provider) = scripted('a', const []);
      final tool = flashlight();
      final h = Harness(
        primary: a,
        tools: [tool],
        catalogFor: (_) => FakeToolCatalog([tool]),
        fastPath: _Match('Taschenlampe an'),
      );
      final events = await h.run('Taschenlampe an');
      expect(provider.requests, isEmpty);
      expect((terminal(events) as AgentDone).finalText, _sentence);
    });

    test('„nochmal mit“ (Wiederholung): kein Schnellweg', () async {
      final (a, _) = scripted('a', [ScriptedTurn.text('erste')]);
      final (b, providerB) = scripted('b', [ScriptedTurn.text('zweite')]);
      final match = _Match('Taschenlampe an');
      final tool = flashlight();
      final h = Harness(
        primary: a,
        chain: [b],
        tools: [tool],
        fastPath: match,
        history: [Message.user('früher'), Message.assistantText('Antwort')],
      );
      final events = await h.run('Taschenlampe an', requestEscalation: true);
      expect(match.asked, isEmpty);
      expect(tool.callCount, 0);
      expect(providerB.requests, hasLength(1));
      expect(terminal(events), isA<AgentDone>());
    });

    test('Auslöser für ein Ziel im Text: kein Schnellweg', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('Okay.')]);
      final match = _Match('Taschenlampe an');
      final h = Harness(
        primary: a,
        resolver: _Stripping(a),
        tools: [flashlight()],
        fastPath: match,
      );
      await h.run('Taschenlampe an');
      expect(match.asked, isEmpty);
      expect(provider.requests, hasLength(1));
    });

    test('Bilder: kein Schnellweg', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('Ein Bild.')]);
      final match = _Match('Taschenlampe an');
      final h = Harness(primary: a, tools: [flashlight()], fastPath: match);
      await h.run(
        'Taschenlampe an',
        images: [
          ImageBlock(mediaType: 'image/png', bytes: [1, 2, 3]),
        ],
      );
      expect(match.asked, isEmpty);
      expect(provider.requests, hasLength(1));
    });

    test('Sprache mit unsicherer Erkennung (< 0,5): Modell', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('Okay.')]);
      final match = _Match('Taschenlampe an');
      final tool = flashlight();
      final h = Harness(primary: a, tools: [tool], fastPath: match);
      await h.run(
        'Taschenlampe an',
        source: InputSource.voice,
        sttConfidence: 0.49,
      );
      expect(match.asked, isEmpty);
      expect(tool.callCount, 0);
      expect(provider.requests, hasLength(1));
    });

    test(
      'Sprache mit Erkennung genau 0,5 und fehlender Wert: Schnellweg',
      () async {
        for (final conf in <double?>[0.5, 0.97, null]) {
          final (a, provider) = scripted('a', const []);
          final h = Harness(
            primary: a,
            tools: [flashlight()],
            fastPath: _Match('Taschenlampe an'),
          );
          final events = await h.run(
            'Taschenlampe an',
            source: InputSource.voice,
            sttConfidence: conf,
          );
          expect(provider.requests, isEmpty, reason: '$conf');
          expect((terminal(events) as AgentDone).fixed, isTrue);
        }
      },
    );

    test(
      'zweiter Auftrag nach Schnellweg: Verlauf bleibt im Kontext',
      () async {
        final (a, provider) = scripted('a', [ScriptedTurn.text('Gern.')]);
        final h = Harness(
          primary: a,
          tools: [flashlight()],
          fastPath: _Match('Taschenlampe an'),
        );
        await h.run('Taschenlampe an');
        await h.run('Danke');
        expect(provider.requests, hasLength(1));
        final texts = provider.requests.single.messages.map((m) => m.text);
        expect(texts, contains(_sentence));
        expect(texts.last, 'Danke');
      },
    );
  });
}
