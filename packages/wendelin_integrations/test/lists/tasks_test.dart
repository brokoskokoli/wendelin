import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/src/lists/task_format.dart'
    show taskMarkers;
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

// Heute im Standardkontext: 2026-10-13.
const _aufgaben =
    '---\r\ntags: [aufgaben]\r\n---\r\n'
    '# Aufgaben\r\n'
    'Freitext bleibt.\r\n'
    '- [ ] Steuer abgeben ⏫ 📅 2026-10-20\r\n'
    '- [ ] Zahnarzt anrufen 📅 2026-10-13 ⏰ 09:30\r\n'
    '- [ ] Paket abholen 🔼 📅 2026-10-10 🔁 every week\r\n'
    '- [ ] Irgendwann aufräumen #haus\r\n'
    '- [x] Miete ✅ 2026-10-01 📅 2026-10-01\r\n'
    '\r\n'
    'Ende ohne Umbruch';

void main() {
  late FakeListFilePort port;
  late List<ListDefinition> defs;
  late TasksIntegration integration;

  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> run(String name, Map<String, Object?> args) =>
      tool(name).execute(args, ctx());
  Map<String, Object?> data(ToolOutcome o) => jsonDecode(
    o.text.startsWith(listDataNotice)
        ? o.text.substring(listDataNotice.length)
        : o.text,
  ) as Map<String, Object?>;
  Future<String> file() => port.read('aufgaben.md');

  setUp(() {
    port = FakeListFilePort(
      files: {'aufgaben.md': _aufgaben, 'einkaufen.md': '- [ ] Milch\n'},
    );
    defs = [
      ListDefinition(
        id: 'a',
        name: 'Aufgaben',
        target: 'aufgaben.md',
        taskDefault: true,
      ),
      ListDefinition(id: 'e', name: 'Einkaufen', target: 'einkaufen.md'),
    ];
    integration = TasksIntegration(port, definitions: () => defs);
  });

  test('Integration: Metadaten, Risiken, Einrichtung', () async {
    expect(integration.id, 'tasks');
    expect(
      {for (final t in integration.tools) t.name: t.risk},
      {
        'tasks__add': RiskLevel.write,
        'tasks__list': RiskLevel.read,
        'tasks__complete': RiskLevel.write,
      },
    );
    expect((await integration.setupState()).complete, isTrue);
    defs = [];
    expect((await integration.setupState()).missingSteps, [
      ListsIntegration.defineStep,
    ]);
    expect((await run('tasks__list', {})).isError, isTrue);
  });

  group('Format', () {
    test('Parser erkennt Fälligkeit, Zeit, Priorität, Erledigt', () {
      final i = TaskInfo.parse('Steuer ⏫ 📅 2026-10-20 ⏰ 14:30 ✅ 2026-10-21');
      expect(i.title, 'Steuer');
      expect(i.due, localDate('2026-10-20'));
      expect(i.minutes, 14 * 60 + 30);
      expect(i.priority, TaskPriority.high);
      expect(i.completed, localDate('2026-10-21'));
    });

    test('ohne Metadaten und ungültige Werte', () {
      final plain = TaskInfo.parse('Milch holen');
      expect(plain.title, 'Milch holen');
      expect(plain.due, isNull);
      expect(plain.priority, isNull);
      // Ungültiges Datum / Zeit ohne Datum zählen nicht als Fälligkeit.
      expect(TaskInfo.parse('x 📅 2026-02-31').due, isNull);
      expect(TaskInfo.parse('x ⏰ 10:00').minutes, isNull);
      expect(TaskInfo.parse('x 📅 2026-10-20 ⏰ 25:00').minutes, isNull);
    });

    test('Uhrzeitgrenzen', () {
      int? m(String t) => TaskInfo.parse('x ⏰ $t 📅 2026-10-20').minutes;
      expect(m('00:00'), 0);
      expect(m('23:59'), 23 * 60 + 59);
      expect(m('24:00'), isNull);
      expect(m('10:60'), isNull);
    });

    test('Parser liest beide Reihenfolgen von Zeit und Fälligkeit', () {
      for (final t in [
        'Z ⏰ 14:30 ⏫ 📅 2026-10-20',
        'Z ⏫ 📅 2026-10-20 ⏰ 14:30',
      ]) {
        final i = TaskInfo.parse(t);
        expect(i.title, 'Z', reason: t);
        expect(i.minutes, 14 * 60 + 30, reason: t);
        expect(i.due, localDate('2026-10-20'), reason: t);
        expect(i.priority, TaskPriority.high, reason: t);
      }
    });

    test('Prioritäts-IDs', () {
      expect(
        {for (final p in TaskPriority.values) p.id: TaskPriority.byId(p.id)},
        {
          'highest': TaskPriority.highest,
          'high': TaskPriority.high,
          'medium': TaskPriority.medium,
          'low': TaskPriority.low,
          'lowest': TaskPriority.lowest,
        },
      );
      expect(TaskPriority.byId('normal'), isNull);
    });

    test('Writer: Reihenfolge Zeit, Priorität, Datum', () {
      expect(composeTask('A'), 'A');
      expect(
        composeTask(
          'A',
          due: localDate('2026-10-20'),
          minutes: 8 * 60 + 5,
          priority: TaskPriority.lowest,
        ),
        'A ⏰ 08:05 ⏬ 📅 2026-10-20',
      );
      // Zeit ohne Datum wird nicht geschrieben.
      expect(composeTask('A', minutes: 60), 'A');
    });

    test('Rundreise: Schreiben und Parsen ergibt dieselben Werte', () {
      for (final p in [null, ...TaskPriority.values]) {
        final text = composeTask(
          'Titel mit Text',
          due: localDate('2026-12-01'),
          minutes: 23 * 60 + 59,
          priority: p,
        );
        final i = TaskInfo.parse(text);
        expect(i.title, 'Titel mit Text');
        expect(i.due, localDate('2026-12-01'));
        expect(i.minutes, 23 * 60 + 59);
        expect(i.priority, p);
      }
    });
  });

  group('tasks__add', () {
    test(
      'legt Aufgabe in der Standardliste an, Rest bleibt zeichengenau',
      () async {
        final o = await run('tasks__add', {
          'title': 'Auto waschen',
          'due': '2026-10-22T08:00',
          'priority': 'High',
        });
        expect(data(o)['added'], ['Auto waschen ⏰ 08:00 ⏫ 📅 2026-10-22']);
        expect(
          await file(),
          _aufgaben.replaceFirst(
            '- [x] Miete ✅ 2026-10-01 📅 2026-10-01\r\n',
            '- [x] Miete ✅ 2026-10-01 📅 2026-10-01\r\n'
                '- [ ] Auto waschen ⏰ 08:00 ⏫ 📅 2026-10-22\r\n',
          ),
        );
      },
    );

    test('Undo entfernt genau die Zeile', () async {
      final o = await run('tasks__add', {'title': 'Neu', 'due': '2026-10-14'});
      expect(await file(), contains('- [ ] Neu 📅 2026-10-14'));
      await o.undo!();
      expect(await file(), _aufgaben);
    });

    test('ohne Fälligkeit; benannte Liste', () async {
      await run('tasks__add', {'title': 'Eier', 'list': 'Einkaufen'});
      expect(await port.read('einkaufen.md'), '- [ ] Milch\n- [ ] Eier\n');
    });

    test('Duplikat wird übersprungen', () async {
      final o = await run('tasks__add', {
        'title': 'Irgendwann aufräumen #haus',
      });
      expect(data(o)['added'], isEmpty);
      expect(await file(), _aufgaben);
    });

    test('ohne Standard bei mehreren Listen: nachfragen', () async {
      defs = [
        for (final d in defs)
          ListDefinition(id: d.id, name: d.name, target: d.target),
      ];
      final o = await run('tasks__add', {'title': 'X'});
      expect(o.isError, isTrue);
      expect(o.text, contains('Standard-Aufgabenliste'));
      expect(await file(), _aufgaben);
    });

    test('einzige Liste ist Standard', () async {
      defs = [
        ListDefinition(id: 'e', name: 'Einkaufen', target: 'einkaufen.md'),
      ];
      await run('tasks__add', {'title': 'X'});
      expect(await port.read('einkaufen.md'), '- [ ] Milch\n- [ ] X\n');
    });

    test('Zeitzone in due: klare Fehlermeldung', () async {
      final o = await run('tasks__add', {
        'title': 'X',
        'due': '2026-10-20T14:30+02:00',
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('Zeitzone'));
      expect(await file(), _aufgaben);
    });

    test('Aufgaben-Marken im Titel werden abgelehnt', () async {
      // Fixed list: removing a marker from taskMarkers must fail here.
      const markers = [
        '📅', '⏳', '🛫', '➕', '✅', '❌', '🔁', '⏰', //
        '🔺', '⏫', '🔼', '🔽', '⏬',
      ];
      expect(taskMarkers.toSet(), markers.toSet());
      for (final m in markers) {
        final o = await run('tasks__add', {'title': 'Steuer $m 2026-10-20'});
        expect(o.isError, isTrue, reason: m);
        expect(o.text, contains('Marke'), reason: m);
      }
      expect(await file(), _aufgaben);
    });

    test('ungültige Argumente', () async {
      for (final args in [
        {'title': 'X', 'due': 'morgen'},
        {'title': 'X', 'priority': 'dringend'},
        {'title': 'a\nb'},
        {'title': 'a\rb'},
        {'title': 'X', 'due': '2026-10-20T14:30Z'},
        {'title': 'X', 'due': '2026-10-20T14:30+02:00'},
        <String, Object?>{},
      ]) {
        expect(
          (await run('tasks__add', args)).isError,
          isTrue,
          reason: '$args',
        );
      }
    });
  });

  group('tasks__list', () {
    List<String> titles(ToolOutcome o) => [
      for (final t in data(o)['tasks'] as List)
        (t as Map<String, Object?>)['title']! as String,
    ];

    test('all: offene Aufgaben nach Fälligkeit, ohne Datum zuletzt', () async {
      final o = await run('tasks__list', {'list': 'Aufgaben'});
      expect(titles(o), [
        'Paket abholen 🔁 every week',
        'Zahnarzt anrufen',
        'Steuer abgeben',
        'Irgendwann aufräumen #haus',
      ]);
      final first = (data(o)['tasks'] as List).first as Map;
      expect(first['overdue'], true);
      expect(first['priority'], 'medium');
      expect(o.text, startsWith(listDataNotice));
    });

    test('today, overdue und include_done', () async {
      expect(titles(await run('tasks__list', {'filter': 'today'})), [
        'Zahnarzt anrufen',
      ]);
      final t = data(await run('tasks__list', {'filter': 'today'}));
      expect(((t['tasks'] as List).single as Map)['time'], '09:30');
      expect(titles(await run('tasks__list', {'filter': 'overdue'})), [
        'Paket abholen 🔁 every week',
      ]);
      expect(
        titles(await run('tasks__list', {'include_done': true})),
        contains('Miete'),
      );
    });

    test('ohne Liste: alle Listen', () async {
      expect(titles(await run('tasks__list', {})), contains('Milch'));
    });

    test('Lesefehler einer Liste: Fehler je Liste, andere bleiben', () async {
      // Erste gelesene Liste schlägt fehl.
      port.failNext('read');
      var o = data(await run('tasks__list', {}));
      expect(o['errors'], [
        {'list': 'Aufgaben', 'error': 'Simulierter Fehler'},
      ]);
      expect(titles(await run('tasks__list', {})), contains('Steuer abgeben'));
      // Zweite gelesene Liste schlägt fehl.
      defs = defs.reversed.toList();
      port.failNext('read');
      o = data(await run('tasks__list', {}));
      expect(o['errors'], [
        {'list': 'Einkaufen', 'error': 'Simulierter Fehler'},
      ]);
      expect([
        for (final t in o['tasks'] as List) (t as Map)['title'],
      ], contains('Steuer abgeben'));
      // Ohne Fehler kein errors-Feld.
      expect(data(await run('tasks__list', {})).containsKey('errors'), isFalse);
    });

    test('Sortierung bei gleichem Datum: Uhrzeit, dann Priorität', () async {
      port.files['s.md'] =
          '- [ ] normal 📅 2026-10-20\n'
          '- [ ] low 🔽 📅 2026-10-20\n'
          '- [ ] lowest ⏬ 📅 2026-10-20\n'
          '- [ ] medium 🔼 📅 2026-10-20\n'
          '- [ ] high ⏫ 📅 2026-10-20\n'
          '- [ ] highest 🔺 📅 2026-10-20\n'
          '- [ ] spät ⏰ 15:00 ⏫ 📅 2026-10-20\n'
          '- [ ] früh ⏰ 08:00 🔽 📅 2026-10-20\n'
          '- [ ] alt ⏫ 📅 2026-10-20 ⏰ 09:00\n';
      defs = [ListDefinition(id: 's', name: 'S', target: 's.md')];
      expect(titles(await run('tasks__list', {})), [
        'früh',
        'alt',
        'spät',
        'highest',
        'high',
        'medium',
        'normal',
        'low',
        'lowest',
      ]);
    });

    test('erledigte Aufgaben sind nie überfällig', () async {
      final all =
          (data(await run('tasks__list', {'include_done': true}))['tasks']
                  as List)
              .cast<Map<String, Object?>>();
      final miete = all.singleWhere((t) => t['title'] == 'Miete');
      expect(miete['done'], true);
      expect(miete.containsKey('overdue'), isFalse);
      expect(
        titles(
          await run('tasks__list', {'filter': 'overdue', 'include_done': true}),
        ),
        ['Paket abholen 🔁 every week'],
      );
    });

    test('eingerückte Unteraufgabe und leere Datei', () async {
      port.files['u.md'] = '- [ ] Haupt\n  - [ ] Unter 📅 2026-10-13\n';
      port.files['leer.md'] = '';
      defs = [
        ListDefinition(id: 'u', name: 'U', target: 'u.md'),
        ListDefinition(id: 'l', name: 'Leer', target: 'leer.md'),
      ];
      final o = await run('tasks__list', {});
      expect(titles(o), ['Unter', 'Haupt']);
      expect(
        data(await run('tasks__list', {'list': 'Leer'}))['tasks'],
        isEmpty,
      );
      expect(
        (await run('tasks__complete', {'title': 'Unter', 'list': 'U'})).isError,
        isFalse,
      );
      expect(
        await port.read('u.md'),
        '- [ ] Haupt\n  - [x] Unter 📅 2026-10-13 ✅ 2026-10-13\n',
      );
      expect(
        (await run('tasks__complete', {'title': 'X', 'list': 'Leer'})).isError,
        isTrue,
      );
    });

    test('ungültiger Filter', () async {
      expect((await run('tasks__list', {'filter': 'morgen'})).isError, isTrue);
    });
  });

  group('tasks__complete', () {
    test('hakt ab, setzt ✅ Datum, Rest unverändert', () async {
      final o = await run('tasks__complete', {'title': 'Steuer'});
      expect(data(o)['completed'], 'Steuer abgeben');
      expect(
        await file(),
        _aufgaben.replaceFirst(
          '- [ ] Steuer abgeben ⏫ 📅 2026-10-20',
          '- [x] Steuer abgeben ⏫ 📅 2026-10-20 ✅ 2026-10-13',
        ),
      );
    });

    test('Undo stellt die Zeile genau wieder her', () async {
      final o = await run('tasks__complete', {'title': 'Zahnarzt'});
      expect(await file(), contains('- [x] Zahnarzt anrufen'));
      await o.undo!();
      expect(await file(), _aufgaben);
    });

    test('Undo bei geänderter Zeile schlägt fehl, ohne zu schreiben', () async {
      final o = await run('tasks__complete', {'title': 'Zahnarzt'});
      final changed = (await file()).replaceAll('Zahnarzt anrufen', 'Arzt');
      await port.write('aufgaben.md', changed);
      await expectLater(o.undo!(), throwsA(isA<PortException>()));
      expect(await file(), changed);
    });

    test('schon erledigt; nicht gefunden', () async {
      final o = await run('tasks__complete', {'title': 'Miete'});
      expect(data(o)['already_done'], 'Miete');
      expect(await file(), _aufgaben);
      expect(
        (await run('tasks__complete', {'title': 'Segelboot'})).isError,
        isTrue,
      );
    });

    test('Treffer über den Titel, nicht über Datum/Emoji', () async {
      // „2026“ steht im Datum mehrerer Zeilen, aber nur in einem Titel.
      port.files['aufgaben.md'] =
          '- [ ] Bericht 2026 ⏫ 📅 2025-12-01\n- [ ] Anderes 📅 2026-10-20\n';
      final o = await run('tasks__complete', {'title': '2026'});
      expect(data(o)['completed'], 'Bericht 2026');
      expect(
        await file(),
        '- [x] Bericht 2026 ⏫ 📅 2025-12-01 ✅ 2026-10-13\n'
        '- [ ] Anderes 📅 2026-10-20\n',
      );
    });

    test('mehrdeutiger Treffer: Rückfrage, nichts geschrieben', () async {
      port.files['aufgaben.md'] =
          '- [ ] Steuer Bund 📅 2026-10-20\n- [ ] Steuer Land\n';
      final before = await file();
      final o = await run('tasks__complete', {'title': 'Steuer'});
      expect(o.isError, isTrue);
      expect(o.text, contains('Mehrdeutig'));
      expect(await file(), before);
    });

    test('vorhandenes ✅ wird nicht verdoppelt', () async {
      port.files['aufgaben.md'] = '- [ ] Alt ✅ 2026-10-01\n';
      await run('tasks__complete', {'title': 'Alt'});
      expect(await file(), '- [x] Alt ✅ 2026-10-01\n');
    });
  });
}

LocalDate localDate(String iso) => LocalDate(
  int.parse(iso.substring(0, 4)),
  int.parse(iso.substring(5, 7)),
  int.parse(iso.substring(8, 10)),
);
