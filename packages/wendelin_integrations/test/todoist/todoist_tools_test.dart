import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

TodoistTask _t(
  String id,
  String content, {
  String project = 'p-inbox',
  String? due,
  String? time,
  int prio = 1,
  bool recurring = false,
}) => TodoistTask(
  id: id,
  content: content,
  projectId: project,
  dueDate: due,
  dueTime: time,
  priority: prio,
  recurring: recurring,
);

void main() {
  late FakeTodoistApi api;
  late TodoistIntegration todoist;
  late List<String> errors;
  late int recovered;

  setUp(() {
    api = FakeTodoistApi(
      projectRows: const [
        TodoistProject(id: 'p-inbox', name: 'Eingang', inbox: true),
        TodoistProject(id: 'p-work', name: 'Arbeit'),
        TodoistProject(id: 'p-trip', name: 'Urlaub Italien'),
      ],
      tasks: [
        _t('1', 'Steuer abgeben', due: '2026-10-12', prio: 4),
        _t('2', 'Milch kaufen', due: '2026-10-13', time: '18:00'),
        _t('3', 'Bericht schreiben', project: 'p-work', due: '2026-10-20'),
        _t('4', 'Zahnarzt anrufen'),
        _t('5', 'Wäsche', recurring: true),
      ],
    );
    errors = [];
    recovered = 0;
    todoist = TodoistIntegration(
      api,
      api,
      onError: errors.add,
      onRecovered: () => recovered++,
    );
  });

  Tool tool(String name) => todoist.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> call(String name, Map<String, Object?> args) =>
      tool(name).execute(args, ctx());
  Map<String, Object?> data(ToolOutcome o) =>
      jsonDecode(o.text.substring(o.text.indexOf('{'))) as Map<String, Object?>;

  test('Tools wie tasks__*: Namen und Risiko', () {
    expect(
      {for (final t in todoist.tools) t.name: t.risk},
      {
        'todoist__add': RiskLevel.write,
        'todoist__list': RiskLevel.read,
        'todoist__complete': RiskLevel.write,
      },
    );
  });

  group('todoist__list', () {
    test(
      'alle: sortiert nach Datum, Zeit, Priorität; überfällig markiert',
      () async {
        final o = await call('todoist__list', {});
        expect(o.text, startsWith(todoistDataNotice));
        final tasks = (data(o)['tasks']! as List).cast<Map<String, Object?>>();
        expect(tasks.map((t) => t['title']), [
          'Steuer abgeben',
          'Milch kaufen',
          'Bericht schreiben',
          'Zahnarzt anrufen',
          'Wäsche',
        ]);
        expect(tasks.first, {
          'title': 'Steuer abgeben',
          'list': 'Eingang',
          'due': '2026-10-12',
          'priority': 'highest',
          'overdue': true,
        });
        expect(tasks[1]['time'], '18:00');
        expect(o.summary, '5 Aufgaben');
      },
    );

    test('Filter today, overdue, Projekt', () async {
      var o = await call('todoist__list', {'filter': 'today'});
      expect(
        ((data(o)['tasks']! as List).single as Map)['title'],
        'Milch kaufen',
      );
      o = await call('todoist__list', {'filter': 'overdue'});
      expect(
        ((data(o)['tasks']! as List).single as Map)['title'],
        'Steuer abgeben',
      );
      o = await call('todoist__list', {'list': 'Arbeit'});
      expect(((data(o)['tasks']! as List).single as Map)['list'], 'Arbeit');
    });

    test('leer, ungültiger Filter, unbekanntes Projekt', () async {
      api.open.clear();
      final o = await call('todoist__list', {});
      expect(data(o)['tasks'], isEmpty);
      expect((await call('todoist__list', {'filter': 'x'})).isError, isTrue);
      final e = await call('todoist__list', {'list': 'Strand'});
      expect(e.isError, isTrue);
      expect(e.text, contains('Eingang'));
    });
  });

  group('todoist__add', () {
    test(
      'Inbox ist Standard; due und priority kommen an; Undo löscht',
      () async {
        final o = await call('todoist__add', {
          'title': 'Steuer 2',
          'due': '2026-10-20T14:30',
          'priority': 'high',
        });
        expect(o.isError, isFalse);
        final added = api.open.last;
        expect(added.projectId, 'p-inbox');
        expect(added.dueDate, '2026-10-20');
        expect(added.dueTime, '14:30');
        expect(added.priority, 3);
        expect(data(o), {
          'list': 'Eingang',
          'added': 'Steuer 2',
          'due': '2026-10-20',
          'time': '14:30',
          'priority': 'high',
        });
        await o.undo!.run();
        expect(api.open.any((t) => t.content == 'Steuer 2'), isFalse);
      },
    );

    test('natürliche Sprache geht unverändert als due_string', () async {
      final spy = _SpyApi(api);
      final t = TodoistIntegration(spy, api);
      await t.tools.first.execute({
        'title': 'Anrufen',
        'due': 'morgen 9 Uhr',
      }, ctx());
      expect(spy.lastDue, 'morgen 9 Uhr');
    });

    test(
      'Projekt „Arbeit“: ganzes Wort wird zurückgefragt, genau nicht',
      () async {
        final o = await call('todoist__add', {'title': 'X', 'list': 'Arbeit'});
        expect(api.open.last.projectId, 'p-work');
        expect(o.isError, isFalse);
        final q = await call('todoist__add', {'title': 'Y', 'list': 'Urlaub'});
        expect(q.isError, isTrue);
        expect(q.text, contains('Urlaub Italien'));
        expect(api.open.any((t) => t.content == 'Y'), isFalse);
      },
    );

    test('Ungültiges: Zeilenumbruch, Offset, Priorität', () async {
      for (final a in [
        {'title': 'a\nb'},
        {'title': 'a', 'due': '2026-10-20T14:30+02:00'},
        {'title': 'a', 'priority': 'wow'},
      ]) {
        expect((await call('todoist__add', a)).isError, isTrue);
      }
      expect(api.calls, isNot(contains('add')));
    });
  });

  group('todoist__complete', () {
    test('erledigt, Undo öffnet wieder', () async {
      final o = await call('todoist__complete', {'title': 'Milch'});
      expect(o.isError, isFalse);
      expect(api.done.keys, ['2']);
      expect(o.summary, 'Todoist: Milch kaufen erledigt');
      await o.undo!.run();
      expect(api.done, isEmpty);
      expect(api.open.any((t) => t.id == '2'), isTrue);
    });

    test('wiederkehrend wird gemeldet', () async {
      final o = await call('todoist__complete', {'title': 'Wäsche'});
      expect(data(o)['recurring'], isTrue);
    });

    test('nicht gefunden, mehrdeutig', () async {
      var o = await call('todoist__complete', {'title': 'Nichts'});
      expect(o.isError, isTrue);
      api.open.add(_t('6', 'Milch holen', project: 'p-work'));
      o = await call('todoist__complete', {'title': 'Milch'});
      expect(o.isError, isTrue);
      expect(o.text, contains('Mehrdeutig'));
      o = await call('todoist__complete', {'title': 'Milch', 'list': 'Arbeit'});
      expect(o.isError, isFalse);
      expect(api.done.keys, ['6']);
    });
  });

  group('Sitzung und Fehlerzustand', () {
    test('ohne Token: nicht eingerichtet, kein Fehlerzustand', () async {
      api.storedToken = null;
      expect((await todoist.setupState()).missingSteps, [
        TodoistIntegration.tokenStep,
      ]);
      final o = await call('todoist__list', {});
      expect(o.isError, isTrue);
      expect(errors, isEmpty);
      expect(api.calls, isEmpty);
    });

    test('Token abgelehnt: onError, Hinweis; danach Erholung', () async {
      api.storedToken = 'falsch';
      final o = await call('todoist__list', {});
      expect(o.isError, isTrue);
      expect(o.text, contains(todoistPausedHint));
      expect(o.text, isNot(contains('falsch')));
      expect(errors, hasLength(1));
      api.storedToken = FakeTodoistApi.validToken;
      expect(await todoist.reconnect(), isNull);
      expect(recovered, 1);
    });

    test('Netz weg: nur der Aufruf scheitert', () async {
      api.failWith = const PortException(
        PortErrorKind.unavailable,
        'Todoist ist nicht erreichbar',
      );
      final o = await call('todoist__list', {});
      expect(o.text, contains(todoistRetryHint));
      expect(errors, isEmpty);
      expect(await todoist.reconnect(), contains('nicht erreichbar'));
    });
  });
}

class _SpyApi implements TodoistApi {
  _SpyApi(this.inner);
  final FakeTodoistApi inner;
  String? lastDue;

  @override
  Future<TodoistTask> addTask(
    String token, {
    required String content,
    String? projectId,
    String? dueString,
    int? priority,
  }) {
    lastDue = dueString;
    return inner.addTask(token, content: content, projectId: projectId);
  }

  @override
  Future<List<TodoistProject>> projects(String token) => inner.projects(token);
  @override
  Future<List<TodoistTask>> tasks(String token, {String? projectId}) =>
      inner.tasks(token, projectId: projectId);
  @override
  Future<void> closeTask(String token, String id) => inner.closeTask(token, id);
  @override
  Future<void> reopenTask(String token, String id) =>
      inner.reopenTask(token, id);
  @override
  Future<void> deleteTask(String token, String id) =>
      inner.deleteTask(token, id);
}
