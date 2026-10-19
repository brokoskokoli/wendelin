@Tags(['live'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Live-Test gegen die echte Tasks API, nur mit eigenem Testkonto:
//   set -a; . ~/.wendelin-live.env; set +a; dart test -t live --run-skipped \
//     test/google_tasks/google_tasks_live_test.dart
// Aus GOOGLE_TASKS_CLIENT_ID, GOOGLE_TASKS_CLIENT_SECRET und
// GOOGLE_TASKS_REFRESH_TOKEN (einmalig über die App-Anmeldung gewonnen),
// nie ausgeben. Legt eine Testaufgabe in der ersten Liste an, erledigt sie,
// öffnet sie wieder und löscht sie.

void main() {
  final env = Platform.environment;
  final id = env['GOOGLE_TASKS_CLIENT_ID'] ?? '';
  final secret = env['GOOGLE_TASKS_CLIENT_SECRET'] ?? '';
  final refresh = env['GOOGLE_TASKS_REFRESH_TOKEN'] ?? '';
  final skip = id.isEmpty || secret.isEmpty || refresh.isEmpty
      ? 'GOOGLE_TASKS_CLIENT_ID/_CLIENT_SECRET/_REFRESH_TOKEN nicht gesetzt'
      : null;

  test('Refresh, Listen, Aufgabe anlegen, abhaken, öffnen, löschen', () async {
    final set = await HttpGoogleOAuthApi().refresh(
      GoogleClient(id: id, secret: secret),
      refresh,
    );
    final token = set.access.token;
    final api = HttpGoogleTasksApi();
    final lists = await api.taskLists(token);
    expect(lists, isNotEmpty);
    final t = await api.addTask(
      token,
      lists.first.id,
      title: 'Wendelin Livetest',
      due: '2026-12-24',
    );
    expect(t.due, '2026-12-24');
    try {
      await api.setCompleted(token, t.listId, t.id, completed: true);
      expect(
        (await api.tasks(token, t.listId)).any((x) => x.id == t.id),
        isFalse,
      );
      await api.setCompleted(token, t.listId, t.id, completed: false);
      expect(
        (await api.tasks(token, t.listId)).any((x) => x.id == t.id),
        isTrue,
      );
    } finally {
      await api.deleteTask(token, t.listId, t.id);
    }
  }, skip: skip);
}
