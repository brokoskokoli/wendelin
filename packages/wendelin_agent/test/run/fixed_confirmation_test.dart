// WP122: fixed confirmation sentences end a request without a second model
// call.

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';
import 'parallel_receipt_test.dart' show PerCallVerifying, PolicyInvoker;

FakeTool flashlight({
  ToolOutcome? outcome,
  Set<String> keys = const {'flashlight.on'},
  RiskLevel risk = RiskLevel.write,
  bool undo = false,
}) => FakeTool(
  name: 'flashlight__set',
  risk: risk,
  withUndo: undo,
  confirmationKeys: keys,
  outcome:
      outcome ??
      ToolOutcome.text(
        'ok',
        fixed: const ConfirmationSentence('flashlight.on'),
      ),
);

FakeTool bring(List<String> items) => FakeTool(
  name: 'bring__add_items',
  risk: RiskLevel.write,
  confirmationKeys: const {'list.added'},
  outcome: ToolOutcome.text(
    'ok',
    fixed: ConfirmationSentence('list.added', {
      'items': items,
      'list': 'Einkauf',
    }),
  ),
);

void main() {
  group('feste Sätze', () {
    test('Taschenlampe an: ein Modellaufruf, Satz im Verlauf', () async {
      final c1 = call('c1', 'flashlight__set', '{"on":true}');
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([c1], text: 'Mach ich. '),
        ScriptedTurn.text('wird nie gebraucht'),
      ]);
      final logged = <(String, String)>[];
      final h = Harness(
        primary: a,
        tools: [flashlight()],
        onFixedConfirmation: (s, t) => logged.add((s, t)),
      );
      final events = await h.run('Licht an', language: 'de-DE');

      expect(provider.requests, hasLength(1));
      const sentence = 'Die Taschenlampe ist an.';
      expect(streamedText(events), 'Mach ich. $sentence');
      expect(events.whereType<AgentTextReset>(), isEmpty);
      final done = terminal(events) as AgentDone;
      expect(done.finalText, sentence);
      expect(done.stopReason, StopReason.endTurn);
      expect(done.fixed, isTrue);
      expect(logged, [('s1', 'flashlight__set')]);
      expect(h.conversation.messages, [
        Message.user('Licht an'),
        Message.assistant([const TextBlock('Mach ich. '), c1]),
        Message.toolResults([
          ToolResultBlock(callId: 'c1', content: const [TextBlock('ok')]),
        ]),
        Message.assistantText(sentence),
      ]);
    });

    test('Fehler des Tools: Modell antwortet (zwei Aufrufe)', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'flashlight__set')]),
        ScriptedTurn.text('Das ging nicht.'),
      ]);
      final logged = <String>[];
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
        onFixedConfirmation: (_, t) => logged.add(t),
      );
      final events = await h.run('Licht an');
      expect(provider.requests, hasLength(2));
      expect((terminal(events) as AgentDone).finalText, 'Das ging nicht.');
      expect((terminal(events) as AgentDone).fixed, isFalse);
      expect(logged, isEmpty);
    });

    test('Lese-Tool ohne Vorlage: zwei Aufrufe', () async {
      final read = FakeTool(
        name: 'weather__get',
        outcome: ToolOutcome.text('12 Grad'),
      );
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'weather__get')]),
        ScriptedTurn.text('Es hat 12 Grad.'),
      ]);
      final h = Harness(primary: a, tools: [read]);
      final events = await h.run('Wetter?');
      expect(provider.requests, hasLength(2));
      expect((terminal(events) as AgentDone).finalText, 'Es hat 12 Grad.');
    });

    test('Tool ohne deklarierten Schlüssel: Modell antwortet', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'flashlight__set')]),
        ScriptedTurn.text('Licht ist an.'),
      ]);
      final h = Harness(
        primary: a,
        tools: [flashlight(keys: const {})],
      );
      final events = await h.run('Licht an');
      expect(provider.requests, hasLength(2));
      expect((terminal(events) as AgentDone).finalText, 'Licht ist an.');
    });

    test(
      'Satz mit anderem Schlüssel als deklariert: Modell antwortet',
      () async {
        final (a, provider) = scripted('a', [
          ScriptedTurn.toolCalls([call('c1', 'flashlight__set')]),
          ScriptedTurn.text('Okay.'),
        ]);
        final h = Harness(
          primary: a,
          tools: [
            flashlight(keys: const {'flashlight.off'}),
          ],
        );
        await h.run('Licht an');
        expect(provider.requests, hasLength(2));
      },
    );

    test('abgelehnte Bestätigung: Modell antwortet', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'flashlight__set')]),
        ScriptedTurn.text('Gut, nicht.'),
      ]);
      final tool = flashlight(risk: RiskLevel.external);
      final h = Harness(primary: a, tools: [tool]);
      final events = await h.run(
        'Licht an',
        onEvent: (e) {
          if (e is ConfirmationRequired) e.respond(false);
        },
      );
      expect(tool.callCount, 0);
      expect(provider.requests, hasLength(2));
      expect((terminal(events) as AgentDone).finalText, 'Gut, nicht.');
    });

    test(
      'gemischte Runde mit einem Call ohne Satz: Modell antwortet',
      () async {
        final read = FakeTool(name: 'weather__get');
        final (a, provider) = scripted('a', [
          ScriptedTurn.toolCalls([
            call('c1', 'flashlight__set'),
            call('c2', 'weather__get'),
          ]),
          ScriptedTurn.text('Licht an, 12 Grad.'),
        ]);
        final h = Harness(primary: a, tools: [flashlight(), read]);
        await h.run('Licht an und Wetter');
        expect(provider.requests, hasLength(2));
      },
    );

    test(
      'wiederholter Call (nicht erneut ausgeführt): Modell antwortet',
      () async {
        final read = FakeTool(name: 'weather__get');
        final light = flashlight();
        final (a, provider) = scripted('a', [
          // Round 1 is mixed (model answers), round 2 repeats the light call.
          ScriptedTurn.toolCalls([
            call('c1', 'flashlight__set'),
            call('c2', 'weather__get'),
          ]),
          ScriptedTurn.toolCalls([call('c1', 'flashlight__set')]),
          ScriptedTurn.text('Ist an.'),
        ]);
        final h = Harness(primary: a, tools: [light, read]);
        await h.run('Licht an');
        expect(light.callCount, 1, reason: 'zweiter Call nicht ausgeführt');
        expect(provider.requests, hasLength(3));
      },
    );

    test('unbekannte Sprache: Modell antwortet', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'flashlight__set')]),
        ScriptedTurn.text('La linterna está encendida.'),
      ]);
      final h = Harness(primary: a, tools: [flashlight()]);
      await h.run('Linterna', language: 'es');
      expect(provider.requests, hasLength(2));
    });

    test('zwei feste Calls: Sätze aneinander, ein Aufruf', () async {
      final off = FakeTool(
        name: 'media__command',
        risk: RiskLevel.write,
        confirmationKeys: const {'media.pause'},
        outcome: ToolOutcome.text(
          'ok',
          fixed: const ConfirmationSentence('media.pause'),
        ),
      );
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([
          call('c1', 'flashlight__set'),
          call('c2', 'media__command'),
        ]),
      ]);
      final h = Harness(primary: a, tools: [flashlight(), off]);
      final events = await h.run('Licht an und Pause');
      expect(provider.requests, hasLength(1));
      expect(
        (terminal(events) as AgentDone).finalText,
        'Die Taschenlampe ist an. Die Wiedergabe ist pausiert.',
      );
    });

    final expected = {
      'de-DE': 'Ich habe Milch, Eier und Brot auf die Liste Einkauf gesetzt.',
      'en-US': 'I added Milch, Eier and Brot to the list Einkauf.',
      'fr-FR': 'J’ai ajouté Milch, Eier et Brot à la liste Einkauf.',
    };
    for (final MapEntry(key: lang, value: text) in expected.entries) {
      test('Bring mit drei Artikeln ($lang)', () async {
        final (a, provider) = scripted('a', [
          ScriptedTurn.toolCalls([call('c1', 'bring__add_items')]),
        ]);
        final h = Harness(
          primary: a,
          tools: [
            bring(['Milch', 'Eier', 'Brot']),
          ],
        );
        final events = await h.run('Setz auf die Liste', language: lang);
        expect(provider.requests, hasLength(1));
        expect((terminal(events) as AgentDone).finalText, text);
      });
    }

    for (final (language, interface, text) in [
      (null, 'en', 'I added Milch, Eier and Brot to the list Einkauf.'),
      ('fr', 'en', 'J’ai ajouté Milch, Eier et Brot à la liste Einkauf.'),
    ]) {
      test('Sprache $language, Oberfläche $interface', () async {
        final (a, _) = scripted('a', [
          ScriptedTurn.toolCalls([call('c1', 'bring__add_items')]),
        ]);
        final h = Harness(
          primary: a,
          tools: [
            bring(['Milch', 'Eier', 'Brot']),
          ],
        );
        final events = await h.run(
          'Setz auf die Liste',
          language: language,
          interfaceLanguage: interface,
        );
        expect((terminal(events) as AgentDone).finalText, text);
      });
    }

    test('Folgefrage sieht den Satz im Verlauf', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'bring__add_items')]),
        ScriptedTurn.text('Und noch Butter?'),
      ]);
      final h = Harness(
        primary: a,
        tools: [
          bring(['Milch', 'Eier', 'Brot']),
        ],
      );
      await h.run('Milch, Eier, Brot');
      await h.run('und noch Butter');
      expect(provider.requests, hasLength(2));
      final texts = provider.requests[1].messages.map((m) => m.text).toList();
      expect(texts, contains(contains('auf die Liste Einkauf gesetzt')));
      expect(
        provider.requests[1].messages.last,
        Message.user('und noch Butter'),
      );
    });
  });

  group('feste Sätze mit Quittung (TEE)', () {
    late PerCallVerifying provider;
    late FakeTool tool;
    late Harness h;
    late List<AgentEvent> events;

    void start(FakeAsync async, List<ScriptedTurn> turns) {
      tool = flashlight(undo: true);
      provider = PerCallVerifying(FakeLlmProvider(turns), 3);
      final tools = [tool];
      h = Harness(
        invoker: PolicyInvoker(FakeToolInvoker(FakeToolCatalog(tools))),
        primary: ProviderTarget(
          profileId: 'tee',
          modelId: 'm',
          provider: provider,
          privacy: PrivacyLevel.tee,
        ),
        tools: tools,
      );
      events = [];
      h.runner.run(UserInput(text: 'Licht an')).listen(events.add);
      async.flushMicrotasks();
    }

    final toolTurn = ScriptedTurn.toolCalls([call('c1', 'flashlight__set')]);

    test('grün: ein Aufruf, kein Überlappungsaufruf', () {
      fakeAsync((async) {
        start(async, [toolTurn, ScriptedTurn.text('unnötig')]);
        expect(provider.inner.requests, hasLength(1));
        expect(events.last, isNot(isA<AgentDone>()), reason: 'wartet');
        provider.settle(0, AttestationStatus.green);
        async.flushMicrotasks();
        final done = events.last as AgentDone;
        expect(done.finalText, 'Die Taschenlampe ist an.');
        expect(provider.inner.requests, hasLength(1));
        expect(tool.undoCount, 0);
      });
    });

    test('rot: Undo, Modell antwortet, kein fester Satz', () {
      fakeAsync((async) {
        start(async, [toolTurn, ScriptedTurn.text('Zurückgenommen.')]);
        provider.settle(0, AttestationStatus.red);
        async.flushMicrotasks();
        expect(tool.undoCount, 1);
        expect(provider.inner.requests, hasLength(2));
        expect(streamedText(events), isNot(contains('Taschenlampe ist an')));
      });
    });
  });
}
