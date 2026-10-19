import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'helpers.dart';

/// Alle Aufgaben-Tools (lokal, Todoist, Google Tasks): kein Titel und kein
/// freier Text im Audit, auch nicht in Bestätigungszeile 1.
void main() {
  late List<Tool> tools;

  setUp(() {
    final todoist = FakeTodoistApi();
    final google = FakeGoogleTasksApi();
    tools = [
      ...TasksIntegration(
        FakeListFilePort(files: {'a.md': '- [ ] Geheimtitel-77\n'}),
        definitions: () => [
          ListDefinition(
            id: 'a',
            name: 'Aufgaben',
            target: 'a.md',
            taskDefault: true,
          ),
        ],
      ).tools,
      ...TodoistIntegration(
        todoist,
        todoist,
        onError: (_, _) {},
        onRecovered: () {},
      ).tools,
      ...GoogleTasksIntegration(
        google,
        google,
        google,
        onError: (_, _) {},
        onRecovered: () {},
      ).tools,
    ];
  });

  test('Schreibende Aufgaben-Tools mit Titel: Audit ohne Titel', () async {
    final writers = tools.where((t) => t.risk == RiskLevel.write).toList();
    expect(
      writers.map((t) => t.name),
      containsAll([
        'tasks__add',
        'tasks__complete',
        'todoist__add',
        'todoist__complete',
        'gtasks__add',
        'gtasks__complete',
      ]),
    );
    for (final t in writers) {
      final raw = {
        'title': 'Geheimtitel-77',
        'notes': 'Geheimnotiz-5',
        'list': 'Arbeit',
      };
      final a = await t.auditArguments(jsonEncode(raw), raw, ctx());
      expect(a, isNot(contains('Geheim')), reason: t.name);
      expect(jsonDecode(a), {'list': 'Arbeit'}, reason: t.name);
      final d = t.describeForConfirmation({'title': 'Geheimtitel-77'});
      expect(
        d.split('\n').first,
        isNot(contains('Geheimtitel')),
        reason: t.name,
      );
      expect(d, contains('Geheimtitel-77'), reason: t.name);
    }
  });
}
