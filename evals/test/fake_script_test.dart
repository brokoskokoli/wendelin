import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

const _case = EvalCase(
  id: 'a',
  language: 'de',
  prompt: 'p',
  expect: Expectation(noTools: true),
);
const _other = EvalCase(
  id: 'b',
  language: 'de',
  prompt: 'p',
  expect: Expectation(noTools: true),
);

Future<List<ChatEvent>> _play(LlmProvider p) =>
    p.chat(ChatRequest(messages: [], model: 'm', maxTokens: 10)).toList();

void main() {
  final time = EvalTime.parse('2026-10-14T09:00', defaultTimeZone);

  test(
    'Platzhalter, parallele Aufrufe, Usage und abschließender Text',
    () async {
      final script = FakeScript.parse('''
cases:
  a:
    - tools:
        - tool: calendar__create_event
          args: {title: T, start: "{{+1d 10:00}}", tags: ["{{today}}"], n: 1}
        - tool: alarms__set_timer
          args: {duration_seconds: 60}
      usage: {input: 7, output: 3}
''');
      expect(script.caseIds, ['a']);
      final p = script.providerFor(_case, time);
      expect(p.remainingTurns, 2);
      final first = await _play(p);
      final calls = first
          .whereType<ToolCallComplete>()
          .map((e) => e.call)
          .toList();
      expect(calls.map((c) => c.name), [
        'calendar__create_event',
        'alarms__set_timer',
      ]);
      expect(calls.map((c) => c.id), ['call_0_0', 'call_0_1']);
      expect(jsonDecode(calls.first.argumentsJson), {
        'title': 'T',
        'start': '2026-10-15T10:00',
        'tags': ['2026-10-14'],
        'n': 1,
      });
      expect(
        first.whereType<UsageEvent>().single.usage,
        const Usage(inputTokens: 7, outputTokens: 3),
      );
      final second = await _play(p);
      expect(
        second.whereType<TextDelta>().map((e) => e.text).join(),
        'Erledigt.',
      );
    },
  );

  test('Standardantwort für Fälle ohne Skript', () async {
    final script = FakeScript.parse('cases: {}');
    final events = await _play(script.providerFor(_other, time));
    expect(
      events.whereType<TextDelta>().map((e) => e.text).join(),
      'Das weiß ich leider nicht.',
    );
    final custom = FakeScript.parse('default: [{text: Nö}]');
    final events2 = await _play(custom.providerFor(_other, time));
    expect(events2.whereType<TextDelta>().map((e) => e.text).join(), 'Nö');
  });

  test('ungültige Skripte', () {
    for (final bad in [
      '- a',
      'cases: [',
      'cases: []',
      'cases: {a: []}',
      'cases: {a: [x]}',
      'default: []',
    ]) {
      expect(() => FakeScript.parse(bad), throwsFormatException, reason: bad);
    }
    for (final bad in [
      'cases: {a: [{tool: 1}]}',
      'cases: {a: [{foo: 1}]}',
      'cases: {a: [{tools: []}]}',
      'cases: {a: [{tools: x}]}',
      'cases: {a: [{tool: t, args: {s: "{{morgen}}"}}]}',
    ]) {
      expect(
        () => FakeScript.parse(bad).providerFor(_case, time),
        throwsFormatException,
        reason: bad,
      );
    }
  });
}
