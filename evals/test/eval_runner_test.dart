import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

ToolCallBlock _call(String id, String name, Map<String, Object?> args) =>
    ToolCallBlock(id: id, name: name, argumentsJson: jsonEncode(args));

EvalCase _case(String yaml) =>
    parseCaseFile('language: de\ncases:\n$yaml').single;

void main() {
  final time = EvalTime.parse('2026-10-14T09:00', defaultTimeZone);

  EvalRunner runner(List<ScriptedTurn> Function() turns) => EvalRunner(
    target: EvalTarget(
      profileId: 'fake',
      modelId: 'fake-model',
      privacy: PrivacyLevel.local,
      provider: (_) => FakeLlmProvider(turns()),
      costEstimator: const FlatCostEstimator(),
    ),
    time: time,
  );

  final tauchen = _case('''
  - id: tauchen
    prompt: Trag mir morgen um 10 Tauchen ein
    expect:
      calls:
        - tool: calendar__create_event
          args: {title: {contains: Tauchen}, start: {at: "+1d 10:00"}}
''');

  test('echte Agent-Schleife mit Fake-Ports: Termin wird angelegt', () async {
    final r = await runner(
      () => [
        ScriptedTurn.toolCalls([
          _call('c1', 'calendar__create_event', {
            'title': 'Tauchen',
            'start': '2026-10-15T10:00',
          }),
        ]),
        ScriptedTurn.text('Eingetragen.'),
      ],
    ).runCase(tauchen);
    expect(r.status, CaseStatus.passed, reason: '${r.reasons}');
    final o = r.observation;
    expect(o.calls.single.isError, isFalse);
    expect(o.calls.single.summary, contains('Tauchen'));
    expect(o.finalText, 'Eingetragen.');
    expect(o.modelCalls, 2);
    expect(o.usage, const Usage(inputTokens: 200, outputTokens: 40));
    expect(o.costMicros, 400);
    expect(o.gaveUp, isFalse);
    expect(o.escalations, isEmpty);
    expect(o.confirmations, 0);
    expect(o.latency, greaterThanOrEqualTo(Duration.zero));
  });

  test(
    'System-Prompt zeigt den festen „heute“-Zeitpunkt und alle Tools',
    () async {
      final provider = FakeLlmProvider([ScriptedTurn.text('Hallo')]);
      final r = EvalRunner(
        target: EvalTarget(
          profileId: 'fake',
          modelId: 'm',
          privacy: PrivacyLevel.local,
          provider: (_) => provider,
        ),
        time: time,
      );
      final result = await r.runCase(tauchen);
      expect(result.observation.costMicros, isNull, reason: 'ohne Preise');
      final req = provider.requests.single;
      expect(req.systemPrompt, contains('Mittwoch, 14. Oktober 2026'));
      expect(req.systemPrompt, contains('Uhrzeit: 09:00'));
      expect(req.systemPrompt, contains('Europe/Berlin'));
      expect(
        req.tools.map((t) => t.name),
        containsAll([
          'calendar__create_event',
          'clipboard__read',
          'alarms__set_timer',
          'memory__save',
          'web__search',
          'web__fetch',
        ]),
      );
    },
  );

  test('external-Löschen wird automatisch bestätigt und ausgeführt', () async {
    final c = _case('''
  - id: del
    prompt: Lösch den Zahnarzttermin morgen.
    setup:
      events: [{id: evt-z, title: Zahnarzt, start: "+1d 15:00"}]
    expect:
      calls: [{tool: calendar__delete_event, args: {event_id: evt-z}}]
      confirmed: true
''');
    final r = await runner(
      () => [
        ScriptedTurn.toolCalls([
          _call('c1', 'calendar__list_events', {
            'start': '2026-10-15',
            'end': '2026-10-16',
          }),
        ]),
        ScriptedTurn.toolCalls([
          _call('c2', 'calendar__delete_event', {'event_id': 'evt-z'}),
        ]),
        ScriptedTurn.text('Gelöscht.'),
      ],
    ).runCase(c);
    expect(r.status, CaseStatus.passed, reason: '${r.reasons}');
    expect(r.observation.confirmations, 1);
    expect(r.observation.calls.map((x) => x.isError), [false, false]);
    expect(r.observation.calls.first.summary, isNotNull);
  });

  test('Setup: Zwischenablage, Gedächtnis, Suche, Seite', () async {
    final c = _case('''
  - id: setup
    prompt: p
    setup:
      clipboard: Bahnhofstraße 12
      memory: [{text: Die Tochter von Jonas heißt Mila, category: person}]
      search_results: [{title: Mond, url: "https://example.org/mond", snippet: Vollmond am 26.}]
    expect:
      calls:
        - tool: clipboard__read
        - tool: memory__search
        - tool: web__search
        - tool: web__fetch
''');
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        _call('a', 'clipboard__read', {}),
        _call('b', 'memory__search', {'query': 'Tochter Jonas'}),
        _call('c', 'web__search', {'query': 'Vollmond'}),
        _call('d', 'web__fetch', {'url': 'https://example.org/mond'}),
      ]),
      ScriptedTurn.text('Fertig.'),
    ]);
    final r = await EvalRunner(
      target: EvalTarget(
        profileId: 'fake',
        modelId: 'm',
        privacy: PrivacyLevel.local,
        provider: (_) => provider,
      ),
      time: time,
    ).runCase(c);
    expect(r.status, CaseStatus.passed, reason: '${r.reasons}');
    expect(r.observation.calls.where((x) => x.isError), isEmpty);
    final results = provider.requests.last.messages.last.content
        .whereType<ToolResultBlock>()
        .map((b) => b.content.whereType<TextBlock>().map((t) => t.text).join())
        .toList();
    expect(results[0], contains('Bahnhofstraße 12'));
    expect(results[1], contains('Mila'));
    expect(results[2], contains('example.org/mond'));
    expect(results[3], contains('feste Seite'));
  });

  test(
    'Aufgeben: Endantwort wird markiert, es gibt keine Eskalation (K28)',
    () async {
      final r = await runner(() => [ScriptedTurn.text('Das kann ich nicht.')])
          .runCase(tauchen);
      expect(r.status, CaseStatus.failed);
      expect(r.observation.gaveUp, isTrue);
      expect(r.observation.escalations, isEmpty);
    },
  );

  test('Fehler des Providers → error', () async {
    final r = await runner(
      () => [ScriptedTurn.error(const AuthException('Key ungültig'))],
    ).runCase(tauchen);
    expect(r.status, CaseStatus.error);
    expect(r.observation.failure!.error, AgentErrorKind.provider);
    expect(r.reasons.single, contains('Zugang abgelehnt'));
    expect(r.toJson()['failure'], {'kind': 'provider', 'message': anything});
  });

  test('Ausnahme beim Aufbau → error statt Absturz', () async {
    final r = await EvalRunner(
      target: EvalTarget(
        profileId: 'x',
        modelId: 'm',
        privacy: PrivacyLevel.local,
        provider: (_) => throw StateError('kaputt'),
      ),
      time: time,
    ).runCase(tauchen);
    expect(r.status, CaseStatus.error);
    expect(r.reasons.single, contains('kaputt'));
  });

  test('runAll überspringt pending, außer includePending', () async {
    final pending = _case('''
  - id: p
    pending: true
    prompt: Was steht auf der Liste?
    expect: {no_tools: true}
''');
    final seen = <String>[];
    final r = runner(() => [ScriptedTurn.text('Nichts.')]);
    final results = await r.runAll([
      tauchen,
      pending,
    ], onResult: (x) => seen.add(x.evalCase.id));
    expect(seen, ['tauchen', 'p']);
    expect(results.map((x) => x.status), [
      CaseStatus.failed,
      CaseStatus.skipped,
    ]);
    expect(results.last.toJson(), {
      'id': 'p',
      'language': 'de',
      'category': 'misc',
      'prompt': 'Was steht auf der Liste?',
      'status': 'skipped',
      'reasons': ['pending: Integration fehlt noch'],
    });
    final all = await r.runAll([pending], includePending: true);
    expect(all.single.status, CaseStatus.passed);
  });

  test(
    'Gedächtnis kommt über den Retriever in den System-Prompt (Review #7)',
    () async {
      final c = _case('''
  - id: mem
    language: fr
    prompt: Wie heißt nochmal die Tochter von Jonas?
    setup:
      memory: [{text: Die Tochter von Jonas heißt Mila, category: person}]
    expect: {text: {contains: Mila}}
''');
      final provider = FakeLlmProvider([ScriptedTurn.text('Mila.')]);
      final r = await EvalRunner(
        target: EvalTarget(
          profileId: 'fake',
          modelId: 'm',
          privacy: PrivacyLevel.local,
          provider: (_) => provider,
        ),
        time: time,
      ).runCase(c);
      expect(r.status, CaseStatus.passed);
      final prompt = provider.requests.single.systemPrompt!;
      expect(prompt, contains('[person] Die Tochter von Jonas heißt Mila'));
      expect(prompt, contains('Gerätesprache: fr-FR'));
    },
  );

  test('localeFor', () {
    expect(EvalRunner.localeFor('de'), 'de-DE');
    expect(EvalRunner.localeFor('fr'), 'fr-FR');
    expect(EvalRunner.localeFor('en'), 'en-US');
    expect(EvalRunner.localeFor('it'), 'it-IT');
  });

  test(
    'normaler Fall ist completed, Report hat numerisches p50 (N16)',
    () async {
      final r = await runner(() => [ScriptedTurn.text('Nichts.')])
          .runCase(tauchen);
      expect(r.observation.completed, isTrue);
      final report = EvalReport(meta: const {}, results: [r]).toJson();
      final latency = (report['summary']! as Map)['latencyMs']! as Map;
      expect(latency['p50'], isA<int>());
      expect(latency['p90'], isA<int>());
    },
  );

  test('ObservedCall.toJson mit ungültigem JSON', () {
    const c = ObservedCall(
      name: 'x',
      args: null,
      rawArguments: '{',
      isError: true,
    );
    expect(c.toJson(), {'name': 'x', 'rawArguments': '{', 'isError': true});
  });
}
