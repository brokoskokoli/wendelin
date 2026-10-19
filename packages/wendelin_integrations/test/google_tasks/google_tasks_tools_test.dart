import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

GoogleTask _t(
  String id,
  String title, {
  String list = 'l-default',
  String? due,
}) => GoogleTask(id: id, listId: list, title: title, due: due);

void main() {
  late FakeGoogleTasksApi api;
  late GoogleTasksIntegration g;
  late List<String> errors;
  late int recovered;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 10, 13, 12);
    api = FakeGoogleTasksApi(
      tasks: [
        _t('1', 'Steuer abgeben', due: '2026-10-12'),
        _t('2', 'Milch kaufen', due: '2026-10-13'),
        _t('3', 'Bericht schreiben', list: 'l-work', due: '2026-10-20'),
        _t('4', 'Zahnarzt anrufen'),
      ],
    )..now = () => now;
    errors = [];
    recovered = 0;
    g = GoogleTasksIntegration(
      api,
      api,
      api,
      onError: errors.add,
      onRecovered: () => recovered++,
      clock: _Clock(() => now),
    );
  });

  Tool tool(String name) => g.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> call(String name, Map<String, Object?> args) =>
      tool(name).execute(args, ctx());
  Map<String, Object?> data(ToolOutcome o) =>
      jsonDecode(o.text.substring(o.text.indexOf('{'))) as Map<String, Object?>;

  test('Tools wie tasks__*: Namen und Risiko', () {
    expect(
      {for (final t in g.tools) t.name: t.risk},
      {
        'gtasks__add': RiskLevel.write,
        'gtasks__list': RiskLevel.read,
        'gtasks__complete': RiskLevel.write,
      },
    );
  });

  group('gtasks__list', () {
    test('alle Listen, nach Datum sortiert, überfällig markiert', () async {
      final o = await call('gtasks__list', {});
      expect(o.text, startsWith(googleTasksDataNotice));
      final tasks = (data(o)['tasks']! as List).cast<Map<String, Object?>>();
      expect(tasks.map((t) => t['title']), [
        'Steuer abgeben',
        'Milch kaufen',
        'Bericht schreiben',
        'Zahnarzt anrufen',
      ]);
      expect(tasks.first, {
        'title': 'Steuer abgeben',
        'list': 'Meine Aufgaben',
        'due': '2026-10-12',
        'overdue': true,
      });
      expect(o.summary, '4 Aufgaben');
    });

    test('Filter und Liste; Fehler', () async {
      var o = await call('gtasks__list', {'filter': 'today'});
      expect(
        ((data(o)['tasks']! as List).single as Map)['title'],
        'Milch kaufen',
      );
      o = await call('gtasks__list', {'filter': 'overdue'});
      expect(
        ((data(o)['tasks']! as List).single as Map)['title'],
        'Steuer abgeben',
      );
      o = await call('gtasks__list', {'list': 'Arbeit'});
      expect(((data(o)['tasks']! as List).single as Map)['list'], 'Arbeit');
      expect((await call('gtasks__list', {'filter': 'x'})).isError, isTrue);
      final e = await call('gtasks__list', {'list': 'Strand'});
      expect(e.isError, isTrue);
      expect(e.text, contains('Meine Aufgaben'));
    });
  });

  group('gtasks__add', () {
    test(
      'Standardliste, Datum lokal aufgelöst, Uhrzeit weg; Undo löscht',
      () async {
        final o = await call('gtasks__add', {
          'title': 'Anrufen',
          'due': 'morgen 9 Uhr',
        });
        expect(o.isError, isFalse);
        final added = api.open.last;
        expect(added.listId, 'l-default');
        expect(added.due, '2026-10-14');
        expect(data(o)['note'], contains('Uhrzeit'));
        await o.undo!.run();
        expect(api.open.any((t) => t.title == 'Anrufen'), isFalse);
      },
    );

    test(
      'ISO-Datum, Liste „Arbeit“ (ganzes Wort wird zurückgefragt)',
      () async {
        final q = await call('gtasks__add', {'title': 'X', 'list': 'Arbeit'});
        expect(q.isError, isFalse, reason: 'exakter Name');
        expect(api.open.last.listId, 'l-work');
        final o = await call('gtasks__add', {
          'title': 'Y',
          'due': '2026-10-20',
        });
        expect(data(o), {
          'list': 'Meine Aufgaben',
          'added': 'Y',
          'due': '2026-10-20',
        });
      },
    );

    test('Ungültiges legt nichts an', () async {
      for (final a in [
        {'title': 'a\nb'},
        {'title': 'a', 'due': 'irgendwann'},
        {'title': 'a' * 501},
      ]) {
        expect((await call('gtasks__add', a)).isError, isTrue);
      }
      expect(api.calls, isNot(contains('add')));
    });
  });

  group('gtasks__complete', () {
    test('erledigt, Undo setzt wieder offen', () async {
      final o = await call('gtasks__complete', {'title': 'Milch'});
      expect(o.isError, isFalse);
      expect(api.done.keys, ['2']);
      expect(o.summary, 'Google Tasks: Milch kaufen erledigt');
      await o.undo!.run();
      expect(api.done, isEmpty);
      expect(api.open.any((t) => t.id == '2'), isTrue);
    });

    test('nicht gefunden, mehrdeutig, Liste engt ein', () async {
      var o = await call('gtasks__complete', {'title': 'Nichts'});
      expect(o.isError, isTrue);
      api.open.add(_t('6', 'Milch holen', list: 'l-work'));
      o = await call('gtasks__complete', {'title': 'Milch'});
      expect(o.isError, isTrue);
      expect(o.text, contains('Mehrdeutig'));
      o = await call('gtasks__complete', {'title': 'Milch', 'list': 'Arbeit'});
      expect(o.isError, isFalse);
      expect(api.done.keys, ['6']);
    });
  });

  group('Sitzung und Fehlerzustand', () {
    test('nicht eingerichtet: kein Fehlerzustand, kein Aufruf', () async {
      api.storedRefresh = null;
      expect((await g.setupState()).missingSteps, [
        GoogleTasksIntegration.loginStep,
      ]);
      final o = await call('gtasks__list', {});
      expect(o.isError, isTrue);
      expect(errors, isEmpty);
      expect(api.calls, isEmpty);
    });

    test('Access-Token wird gecacht und vor Ablauf erneuert', () async {
      await call('gtasks__list', {});
      await call('gtasks__list', {});
      expect(api.calls.where((c) => c == 'refresh'), hasLength(1));
      now = now.add(const Duration(hours: 2));
      await call('gtasks__list', {});
      expect(api.calls.where((c) => c == 'refresh'), hasLength(2));
    });

    test('401 erneuert genau einmal und wiederholt den Aufruf', () async {
      await call('gtasks__list', {});
      api.calls.clear();
      api.rejectNext = 1;
      final o = await call('gtasks__list', {});
      expect(o.isError, isFalse);
      expect(api.calls.where((c) => c == 'refresh'), hasLength(1));
    });

    test('Refresh abgelehnt: Token gelöscht, pausiert, Hinweis', () async {
      api.storedRefresh = 'widerrufen';
      final o = await call('gtasks__list', {});
      expect(o.isError, isTrue);
      expect(o.text, contains(googleTasksPausedHint));
      expect(o.text, isNot(contains('widerrufen"')));
      expect(errors, hasLength(1));
      expect(api.storedRefresh, isNull);
      expect(api.storedClient, isNotNull, reason: 'Client bleibt');
    });

    test('401 nach erfolgreichem Refresh: pausiert, Login bleibt', () async {
      api.rejectNext = 5;
      final o = await call('gtasks__list', {});
      expect(o.isError, isTrue);
      expect(errors, hasLength(1));
      expect(api.storedRefresh, FakeGoogleTasksApi.validRefresh);
      api.rejectNext = 0;
      expect(await g.reconnect(), isNull);
      expect(recovered, 1);
    });

    test('Netz weg: nur der Aufruf scheitert', () async {
      api.failWith = const PortException(
        PortErrorKind.unavailable,
        'Google Tasks ist nicht erreichbar',
      );
      final o = await call('gtasks__list', {});
      expect(o.text, contains(googleTasksRetryHint));
      expect(errors, isEmpty);
      expect(await g.reconnect(), contains('nicht erreichbar'));
    });

    test('Refresh-Netzfehler löscht das Token nicht', () async {
      api.refreshFailWith = const PortException(
        PortErrorKind.unavailable,
        'Google ist nicht erreichbar',
      );
      final o = await call('gtasks__list', {});
      expect(o.isError, isTrue);
      expect(api.storedRefresh, isNotNull);
      expect(errors, isEmpty);
    });
  });

  group('Fälligkeit lokal aufgelöst (Dienstag 2026-10-13)', () {
    final today = LocalDate(2026, 10, 13);
    String r(String s) => resolveGoogleDue(s, today).date.toIso();

    test('Wörter, Wochentage, Abstände, deutsches Datum', () {
      expect(r('heute'), '2026-10-13');
      expect(r('Tomorrow'), '2026-10-14');
      expect(r('übermorgen'), '2026-10-15');
      expect(r('in 3 Tagen'), '2026-10-16');
      expect(r('in 2 weeks'), '2026-10-27');
      expect(r('nächste Woche'), '2026-10-20');
      expect(r('Freitag'), '2026-10-16');
      expect(r('am Dienstag'), '2026-10-20');
      expect(r('next monday'), '2026-10-19');
      expect(r('20.10.'), '2026-10-20');
      expect(r('1.10.'), '2027-10-01');
      expect(r('5.11.2026'), '2026-11-05');
      expect(r('2026-10-20T14:30'), '2026-10-20');
      expect(resolveGoogleDue('2026-10-20T14:30', today).timeDropped, isTrue);
      expect(resolveGoogleDue('Freitag um 9 Uhr', today).timeDropped, isTrue);
      expect(r('Freitag 14:30'), '2026-10-16');
    });

    test('Unverständliches und ungültige Tage werfen', () {
      for (final s in ['irgendwann', '31.2.', '', 'Frühling']) {
        expect(
          () => resolveGoogleDue(s, today),
          throwsA(isA<InvalidArgumentsException>()),
        );
      }
    });
  });

  test('Canary: Aufgabentitel stehen in keiner Fehlermeldung', () async {
    api.failWith = const PortException(
      PortErrorKind.failed,
      'Google Tasks: unerwartete Antwort (Format geändert?)',
    );
    final o = await call('gtasks__add', {'title': 'Geheimtitel-77'});
    expect(o.text, isNot(contains('Geheimtitel-77')));
    expect(
      const GoogleTask(
        id: 'i',
        listId: 'l',
        title: 'Geheimtitel-77',
      ).toString(),
      isNot(contains('Geheimtitel')),
    );
    expect(
      const GoogleClient(id: 'idX', secret: 'secretX').toString(),
      isNot(anyOf(contains('idX'), contains('secretX'))),
    );
  });
}

final class _Clock implements Clock {
  _Clock(this._now);
  final DateTime Function() _now;
  @override
  DateTime now() => _now();
}
