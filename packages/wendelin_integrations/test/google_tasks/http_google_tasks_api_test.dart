import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Synthetic answers in the shape of the Google Tasks API (no real data).
const _canary = 'canary-access-9f3a';

Matcher _port(PortErrorKind kind) => throwsA(
  isA<PortException>()
      .having((e) => e.kind, 'kind', kind)
      .having(
        (e) => e.message,
        'message',
        allOf(isNot(contains(_canary)), isNot(contains('Geheim'))),
      ),
);

void main() {
  late List<http.Request> requests;
  late List<String> log;
  late DateTime now;

  HttpGoogleTasksApi api(http.Response Function(http.Request r) handler) {
    requests = [];
    log = [];
    return HttpGoogleTasksApi(
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

  test('Listen: Bearer, Basis-URL, Paginierung nextPageToken', () async {
    final a = api((r) {
      if (r.url.queryParameters['pageToken'] == null) {
        return json({
          'items': [
            {'id': 'a', 'title': 'Meine Aufgaben'},
          ],
          'nextPageToken': 'p2',
        });
      }
      return json({
        'items': [
          {'id': 'b', 'title': 'Arbeit'},
        ],
      });
    });
    final lists = await a.taskLists(_canary);
    expect(lists.map((l) => l.title), ['Meine Aufgaben', 'Arbeit']);
    expect(requests, hasLength(2));
    expect(
      requests.first.url.toString(),
      startsWith('https://tasks.googleapis.com/tasks/v1/users/@me/lists'),
    );
    expect(requests.last.url.queryParameters['pageToken'], 'p2');
    expect(requests.first.headers['Authorization'], 'Bearer $_canary');
  });

  test('Aufgaben: nur offene, Fälligkeit als Datum, ohne items leer', () async {
    final a = api(
      (r) => json({
        'items': [
          {
            'id': 't1',
            'title': 'Steuer',
            'status': 'needsAction',
            'due': '2026-10-20T00:00:00.000Z',
          },
          {'id': 't2', 'title': 'Alt', 'status': 'completed'},
          {'id': 't3', 'title': 'Ohne Datum', 'status': 'needsAction'},
        ],
      }),
    );
    final tasks = await a.tasks('x', 'L1');
    expect(tasks.map((t) => t.title), ['Steuer', 'Ohne Datum']);
    expect(tasks.first.due, '2026-10-20');
    expect(tasks.last.due, isNull);
    expect(requests.single.url.queryParameters['showCompleted'], 'false');
    expect(requests.single.url.path, '/tasks/v1/lists/L1/tasks');
    final empty = api((r) => json({'kind': 'tasks#tasks'}));
    expect(await empty.tasks('x', 'L1'), isEmpty);
  });

  test('Anlegen sendet Titel und Datum als RFC 3339', () async {
    final a = api(
      (r) =>
          json({'id': 'n1', 'title': 'Neu', 'due': '2026-10-20T00:00:00.000Z'}),
    );
    final t = await a.addTask('x', 'L1', title: 'Neu', due: '2026-10-20');
    expect(t.due, '2026-10-20');
    expect(requests.single.method, 'POST');
    expect(jsonDecode(requests.single.body), {
      'title': 'Neu',
      'due': '2026-10-20T00:00:00.000Z',
    });
    await a.addTask('x', 'L1', title: 'Ohne');
    expect(jsonDecode(requests.last.body), {'title': 'Ohne'});
  });

  test('Erledigen, Wiederöffnen (completed: null), Löschen', () async {
    final a = api(
      (r) => r.method == 'DELETE' ? http.Response('', 204) : json({'id': 't'}),
    );
    await a.setCompleted('x', 'L1', 't', completed: true);
    expect(requests.last.method, 'PATCH');
    expect(jsonDecode(requests.last.body), {'status': 'completed'});
    await a.setCompleted('x', 'L1', 't', completed: false);
    expect(jsonDecode(requests.last.body), {
      'status': 'needsAction',
      'completed': null,
    });
    await a.deleteTask('x', 'L1', 't');
    expect(requests.last.method, 'DELETE');
  });

  test('Fehlerabbildung ohne Token, Body oder Titel in Meldungen', () async {
    final cases = {
      401: PortErrorKind.permissionDenied,
      403: PortErrorKind.permissionDenied,
      404: PortErrorKind.notFound,
      400: PortErrorKind.rejected,
      500: PortErrorKind.unavailable,
      503: PortErrorKind.unavailable,
      418: PortErrorKind.failed,
    };
    for (final e in cases.entries) {
      final a = api((r) => json({'error': 'Geheimtitel'}, e.key));
      await expectLater(
        a.tasks(_canary, 'L'),
        _port(e.value),
        reason: '${e.key}',
      );
    }
  });

  test('404 beim Anlegen nennt die Liste', () async {
    final a = api((r) => json({}, 404));
    await expectLater(
      a.addTask('x', 'L', title: 'T'),
      throwsA(
        isA<PortException>().having((e) => e.message, 'm', contains('Liste')),
      ),
    );
  });

  test('Netz weg, Zeitüberschreitung, kaputte Antwort', () async {
    final down = HttpGoogleTasksApi(
      client: MockClient((r) async => throw const SocketException('weg')),
    );
    await expectLater(down.taskLists('x'), _port(PortErrorKind.unavailable));
    final slow = HttpGoogleTasksApi(
      client: MockClient((r) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(slow.taskLists('x'), _port(PortErrorKind.unavailable));
    for (final body in [
      '<html>',
      '[]',
      '{"items":5}',
      '{"items":[{"id":""}]}',
      '{"nextPageToken":3}',
    ]) {
      final a = api((r) => http.Response(body, 200));
      await expectLater(
        a.taskLists('x'),
        _port(PortErrorKind.failed),
        reason: body,
      );
    }
  });

  test('429 sperrt bis Retry-After, danach wieder frei', () async {
    var n = 0;
    final a = api((r) {
      n++;
      return n == 1
          ? http.Response('', 429, headers: {'retry-after': '30'})
          : json({'items': <Object?>[]});
    });
    await expectLater(a.taskLists('x'), _port(PortErrorKind.unavailable));
    await expectLater(a.taskLists('x'), _port(PortErrorKind.unavailable));
    expect(requests, hasLength(1), reason: 'gesperrt: kein zweiter Aufruf');
    now = now.add(const Duration(seconds: 31));
    expect(await a.taskLists('x'), isEmpty);
  });

  test('Log: nur Operation und Status, keine Titel, Token, IDs', () async {
    final a = api((r) => json({'id': 'secret-id', 'title': 'Geheimtitel'}));
    await a.addTask(_canary, 'L-secret', title: 'Geheimtitel');
    final text = log.join('\n');
    expect(text, contains('add → 200'));
    for (final s in [_canary, 'Geheimtitel', 'secret-id', 'L-secret']) {
      expect(text, isNot(contains(s)));
    }
  });
}

class _Clock implements Clock {
  _Clock(this._now);
  final DateTime Function() _now;
  @override
  DateTime now() => _now();
}
