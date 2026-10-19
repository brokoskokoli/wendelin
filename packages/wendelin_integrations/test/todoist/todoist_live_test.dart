@Tags(['live'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Live-Test gegen die echte Todoist-API v1, nur mit eigenem Testkonto:
//   set -a; . ~/.wendelin-live.env; set +a; dart test -t live --run-skipped \
//     test/todoist/todoist_live_test.dart
// Token nur aus TODOIST_API_TOKEN, nie ausgeben. Legt eine Testaufgabe im
// Eingang an, erledigt sie, öffnet sie wieder und löscht sie.

void main() {
  final token = Platform.environment['TODOIST_API_TOKEN'] ?? '';
  final skip = token.isEmpty ? 'TODOIST_API_TOKEN nicht gesetzt' : null;

  test('Projekte, Aufgabe anlegen, abhaken, öffnen, löschen', () async {
    final api = HttpTodoistApi();
    final projects = await api.projects(token);
    expect(projects, isNotEmpty);
    final inbox = projects.firstWhere(
      (p) => p.inbox,
      orElse: () => projects.first,
    );
    final t = await api.addTask(
      token,
      content: 'Wendelin Livetest',
      projectId: inbox.id,
      dueString: 'tomorrow 9am',
    );
    try {
      expect(t.dueDate, isNotNull);
      expect(
        (await api.tasks(token, projectId: inbox.id)).map((e) => e.id),
        contains(t.id),
      );
      await api.closeTask(token, t.id);
      await api.reopenTask(token, t.id);
    } finally {
      await api.deleteTask(token, t.id);
    }
    expect((await api.tasks(token)).map((e) => e.id), isNot(contains(t.id)));
  }, skip: skip);
}
