import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Synthetic answers in the shape of the Todoist API v1 (no real data).
const _canary = 'canary-token-9f3a';

Matcher _port(PortErrorKind kind) => throwsA(
  isA<PortException>()
      .having((e) => e.kind, 'kind', kind)
      .having(
        (e) => e.message,
        'message',
        allOf(isNot(contains(_canary)), isNot(contains('Geheim'))),
      ),
);

Map<String, Object?> _task(String id, String content, {Object? due}) => {
  'id': id,
  'content': content,
  'project_id': 'p1',
  'priority': 3,
  'checked': false,
  'due': due,
};

void main() {
  late List<http.BaseRequest> requests;
  late List<String> log;
  late DateTime now;

  HttpTodoistApi api(http.Response Function(http.Request r) handler) {
    requests = [];
    log = [];
    return HttpTodoistApi(
      client: MockClient((r) async {
        requests.add(r);
        return handler(r);
      }),
      clock: _Clock(() => now),
      log: log.add,
    );
  }

  setUp(() => now = DateTime.utc(2026, 10, 13, 12));

  http.Response json(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('Projekte: Bearer-Token, Basis-URL v1, Inbox erkannt', () async {
    final a = api(
      (r) => json({
        'results': [
          {'id': 'p0', 'name': 'Eingang', 'inbox_project': true},
          {'id': 'p1', 'name': 'Arbeit'},
        ],
        'next_cursor': null,
      }),
    );
    final projects = await a.projects(_canary);
    expect(projects, [
      const TodoistProject(id: 'p0', name: 'Eingang', inbox: true),
      const TodoistProject(id: 'p1', name: 'Arbeit'),
    ]);
    final r = requests.single;
    expect(r.method, 'GET');
    expect(r.url.path, '/api/v1/projects');
    expect(r.headers['Authorization'], 'Bearer $_canary');
    expect(log.join(), isNot(contains(_canary)));
  });

  test('Paginierung folgt next_cursor bis zum Ende', () async {
    final a = api((r) {
      final cursor = r.url.queryParameters['cursor'];
      return switch (cursor) {
        null => json({
          'results': [_task('1', 'Eins')],
          'next_cursor': 'c2',
        }),
        'c2' => json({
          'results': [_task('2', 'Zwei')],
          'next_cursor': 'c3',
        }),
        _ => json({
          'results': [_task('3', 'Drei')],
          'next_cursor': null,
        }),
      };
    });
    final tasks = await a.tasks(_canary, projectId: 'p1');
    expect(tasks.map((t) => t.content), ['Eins', 'Zwei', 'Drei']);
    expect(requests.map((r) => r.url.queryParameters['project_id']), [
      'p1',
      'p1',
      'p1',
    ]);
    expect(requests.last.url.queryParameters['cursor'], 'c3');
  });

  test('Endlos-Cursor bricht nach maxPages ab', () async {
    final a = api(
      (r) => json({
        'results': [_task('1', 'Eins')],
        'next_cursor': 'again',
      }),
    );
    final tasks = await a.tasks(_canary);
    expect(tasks, hasLength(HttpTodoistApi.maxPages));
  });

  test('leere Liste', () async {
    final a = api((r) => json({'results': <Object?>[], 'next_cursor': null}));
    expect(await a.tasks(_canary), isEmpty);
  });

  test(
    'Fälligkeit: Datum, schwebende Zeit, feste Zone, Wiederholung',
    () async {
      final a = api(
        (r) => json({
          'results': [
            _task('1', 'a', due: {'date': '2026-10-20', 'is_recurring': false}),
            _task(
              '2',
              'b',
              due: {'date': '2026-10-20T14:30:00', 'is_recurring': true},
            ),
            _task(
              '3',
              'c',
              due: {
                'date': '2026-10-20T12:30:00Z',
                'timezone': 'Europe/Berlin',
                'is_recurring': false,
              },
            ),
          ],
        }),
      );
      final t = await a.tasks(_canary);
      expect([t[0].dueDate, t[0].dueTime], ['2026-10-20', null]);
      expect(
        [t[1].dueDate, t[1].dueTime, t[1].recurring],
        ['2026-10-20', '14:30', true],
      );
      expect([t[2].dueDate, t[2].dueTime], ['2026-10-20', '14:30']);
      expect(t[0].priority, 3);
    },
  );

  test('Aufgabe anlegen: JSON-Body mit due_string', () async {
    final a = api((r) => json(_task('9', 'Steuer')));
    final t = await a.addTask(
      _canary,
      content: 'Steuer',
      projectId: 'p1',
      dueString: 'tomorrow 9am',
      priority: 4,
    );
    expect(t.id, '9');
    final r = requests.single as http.Request;
    expect(r.method, 'POST');
    expect(r.url.path, '/api/v1/tasks');
    expect(jsonDecode(r.body), {
      'content': 'Steuer',
      'project_id': 'p1',
      'due_string': 'tomorrow 9am',
      'priority': 4,
    });
    expect(log.join(), isNot(contains('Steuer')));
  });

  test('close, reopen, delete: Pfade und Methoden', () async {
    final a = api((r) => http.Response('', 204));
    await a.closeTask(_canary, '7');
    await a.reopenTask(_canary, '7');
    await a.deleteTask(_canary, '7');
    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'POST /api/v1/tasks/7/close',
      'POST /api/v1/tasks/7/reopen',
      'DELETE /api/v1/tasks/7',
    ]);
  });

  group('Fehler', () {
    test('401 und 403: permissionDenied ohne Token im Text', () async {
      for (final s in [401, 403]) {
        final a = api((r) => http.Response('Geheim $_canary', s));
        await expectLater(
          a.projects(_canary),
          _port(PortErrorKind.permissionDenied),
        );
      }
    });

    test('404: notFound', () async {
      final a = api((r) => http.Response('{}', 404));
      await expectLater(
        a.closeTask(_canary, '1'),
        _port(PortErrorKind.notFound),
      );
    });

    test('400: rejected (Fälligkeit nicht verständlich)', () async {
      final a = api((r) => http.Response('Geheim', 400));
      await expectLater(
        a.addTask(_canary, content: 'x', dueString: 'blub'),
        _port(PortErrorKind.rejected),
      );
    });

    test('Netzfehler und Zeitüberschreitung: unavailable', () async {
      final a = HttpTodoistApi(
        client: MockClient((r) async => throw const SocketException('weg')),
      );
      await expectLater(a.projects(_canary), _port(PortErrorKind.unavailable));
    });

    test('5xx: unavailable; 418: failed; HTML statt JSON: failed', () async {
      await expectLater(
        api((r) => http.Response('', 503)).projects(_canary),
        _port(PortErrorKind.unavailable),
      );
      await expectLater(
        api((r) => http.Response('', 418)).projects(_canary),
        _port(PortErrorKind.failed),
      );
      await expectLater(
        api((r) => http.Response('<html>', 200)).projects(_canary),
        _port(PortErrorKind.failed),
      );
      await expectLater(
        api(
          (r) => json({
            'results': [
              {'id': 1},
            ],
          }),
        ).projects(_canary),
        _port(PortErrorKind.failed),
      );
    });

    test('429 sperrt bis Retry-After, danach wieder offen', () async {
      var calls = 0;
      final a = api((r) {
        calls++;
        return calls == 1
            ? http.Response('', 429, headers: {'retry-after': '30'})
            : json({'results': <Object?>[]});
      });
      await expectLater(a.projects(_canary), _port(PortErrorKind.unavailable));
      await expectLater(a.projects(_canary), _port(PortErrorKind.unavailable));
      expect(calls, 1);
      now = now.add(const Duration(seconds: 31));
      expect(await a.projects(_canary), isEmpty);
    });
  });
}

class _Clock implements Clock {
  _Clock(this._now);
  final DateTime Function() _now;
  @override
  DateTime now() => _now();
}
