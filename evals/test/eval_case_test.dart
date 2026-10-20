import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

void main() {
  group('parseCaseFile', () {
    test('liest Fall mit Aufrufen, Setup und Sprache der Datei', () {
      final cases = parseCaseFile('''
language: de
cases:
  - id: a
    category: calendar
    prompt: Trag mir morgen um 10 Tauchen ein
    note: Hinweis
    setup:
      clipboard: Hallo
      events:
        - {id: e1, title: Zahnarzt, start: "+1d 15:00"}
        - {id: e2, title: Arzt, start: "+1d 9:00", end: "+1d 10:00"}
      memory:
        - {text: Mag keinen Koriander, category: preference}
      search_results:
        - {title: T, url: "https://example.org"}
        - {title: U, url: "https://example.org/u", snippet: S}
    expect:
      calls:
        - tool: calendar__create_event
          args:
            title: {contains: Tauchen}
            start: {at: "+1d 10:00"}
        - any_of:
            - tool: [alarms__set_alarm, alarms__set_timer]
            - tool: calendar__list_events
      forbid: [calendar__delete_event]
      exact: true
      confirmed: false
      text: {contains: Tauchen}
  - id: b
    language: fr
    prompt: Merci
    pending: true
    expect:
      no_tools: true
''');
      expect(cases, hasLength(2));
      final a = cases.first;
      expect(a.id, 'a');
      expect(a.language, 'de');
      expect(a.category, 'calendar');
      expect(a.note, 'Hinweis');
      expect(a.pending, isFalse);
      expect(a.setup.clipboard, 'Hallo');
      expect(a.setup.events.map((e) => e.id), ['e1', 'e2']);
      expect(a.setup.events.first.end, isNull);
      expect(a.setup.events.last.end, '+1d 10:00');
      expect(a.setup.memory.single.category, 'preference');
      expect(a.setup.searchResults!.last.snippet, 'S');
      expect(a.expect.calls, hasLength(2));
      expect(
        a.expect.calls.first.describe(),
        'calendar__create_event(title enthält [Tauchen], start @ +1d 10:00)',
      );
      expect(a.expect.calls.last.toolNames, [
        'alarms__set_alarm',
        'alarms__set_timer',
        'calendar__list_events',
      ]);
      expect(
        a.expect.calls.last.describe(),
        'alarms__set_alarm|alarms__set_timer oder calendar__list_events',
      );
      expect(a.expect.forbid, ['calendar__delete_event']);
      expect(a.expect.exact, isTrue);
      expect(a.expect.confirmed, isFalse);
      expect(a.expect.text, isNotNull);
      final b = cases.last;
      expect(
        (b.language, b.pending, b.expect.noTools, b.category),
        ('fr', true, true, 'misc'),
      );
      expect(b.setup.searchResults, isNull);
    });

    final invalid = <String, String>{
      'kein Objekt': '- a',
      'ohne cases': 'language: de',
      'YAML-Fehler': 'cases: [',
      'unbekanntes Feld': 'cases: [{id: a, language: de, prompt: p, expect: {no_tools: true}, foo: 1}]',
      'ohne Sprache': 'cases: [{id: a, prompt: p, expect: {no_tools: true}}]',
      'ohne id': 'language: de\ncases: [{prompt: p, expect: {no_tools: true}}]',
      'ohne prompt': 'language: de\ncases: [{id: a, expect: {no_tools: true}}]',
      'ohne expect': 'language: de\ncases: [{id: a, prompt: p}]',
      'leeres expect': 'language: de\ncases: [{id: a, prompt: p, expect: {}}]',
      'no_tools und calls': 'language: de\ncases: [{id: a, prompt: p, expect: {no_tools: true, calls: [{tool: x}]}}]',
      'calls keine Liste':
          'language: de\ncases: [{id: a, prompt: p, expect: {calls: x}}]',
      'pending kein bool': 'language: de\ncases: [{id: a, prompt: p, pending: ja, expect: {no_tools: true}}]',
      'no_tools kein bool':
          'language: de\ncases: [{id: a, prompt: p, expect: {no_tools: ja}}]',
      'forbid falsch': 'language: de\ncases: [{id: a, prompt: p, expect: {no_tools: true, forbid: [1]}}]',
      'any_of leer': 'language: de\ncases: [{id: a, prompt: p, expect: {calls: [{any_of: []}]}}]',
      'any_of mit tool': 'language: de\ncases: [{id: a, prompt: p, expect: {calls: [{any_of: [{tool: x}], tool: y}]}}]',
      'tool leer': 'language: de\ncases: [{id: a, prompt: p, expect: {calls: [{tool: []}]}}]',
      'falsches Prädikat': 'language: de\ncases: [{id: a, prompt: p, expect: {calls: [{tool: x, args: {a: {foo: 1}}}]}}]',
      'Setup-Liste': 'language: de\ncases: [{id: a, prompt: p, setup: {events: x}, expect: {no_tools: true}}]',
      'Kategorie': 'language: de\ncases: [{id: a, prompt: p, setup: {memory: [{text: t, category: geheim}]}, expect: {no_tools: true}}]',
      'Event ohne Titel': 'language: de\ncases: [{id: a, prompt: p, setup: {events: [{id: e, start: today}]}, expect: {no_tools: true}}]',
    };
    for (final MapEntry(key: name, value: yaml) in invalid.entries) {
      test('ungültig: $name', () {
        expect(
          () => parseCaseFile(yaml, source: 'x.yaml'),
          throwsFormatException,
        );
      });
    }

    test('expect darf nur aus forbid bestehen; Backends M5 sind erlaubt', () {
      final c = parseCaseFile(
        'language: de\ncases: [{id: a, prompt: p, '
        'setup: {backends: [gtasks, spotify, weather, station, notes]}, '
        'expect: {forbid: [memory__save]}}]',
      ).single;
      expect(c.expect.forbid, ['memory__save']);
      expect(c.expect.calls, isEmpty);
      expect(c.setup.backends, {
        'gtasks',
        'spotify',
        'weather',
        'station',
        'notes',
      });
    });

    test('Fehlermeldung nennt Datei und Fall', () {
      expect(
        () => parseCaseFile(
          'language: de\ncases: [{id: kaputt, prompt: p, expect: {}}]',
          source: 'de.yaml',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('de.yaml#1'), contains('kaputt')),
          ),
        ),
      );
    });
  });

  group('matches', () {
    const c = EvalCase(
      id: 'de-cal-tauchen',
      language: 'de',
      category: 'calendar',
      prompt: 'p',
      expect: Expectation(noTools: true),
    );
    test('Filter', () {
      expect(c.matches(null), isTrue);
      expect(c.matches(' '), isTrue);
      expect(c.matches('tauchen'), isTrue);
      expect(c.matches('de'), isTrue);
      expect(c.matches('fr,calendar'), isTrue);
      expect(c.matches('fr, ,alarms'), isFalse);
      expect(c.matches('en'), isFalse); // nicht Teil von „tauchen“
      expect(c.matches('chen'), isTrue);
    });
  });

  group('loadCases', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('evals_cases'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('liest *.yaml sortiert, meldet doppelte Ids', () {
      File('${dir.path}/b.yaml').writeAsStringSync(
        'language: en\ncases: [{id: b, prompt: p, expect: {no_tools: true}}]',
      );
      File('${dir.path}/a.yml').writeAsStringSync(
        'language: de\ncases: [{id: a, prompt: p, expect: {no_tools: true}}]',
      );
      File('${dir.path}/readme.txt').writeAsStringSync('x');
      expect(loadCases(dir).map((c) => c.id), ['a', 'b']);
      File('${dir.path}/c.yaml').writeAsStringSync(
        'language: de\ncases: [{id: a, prompt: p, expect: {no_tools: true}}]',
      );
      expect(() => loadCases(dir), throwsFormatException);
    });

    test('fehlendes Verzeichnis', () {
      expect(
        () => loadCases(Directory('${dir.path}/nix')),
        throwsFormatException,
      );
    });
  });
}
