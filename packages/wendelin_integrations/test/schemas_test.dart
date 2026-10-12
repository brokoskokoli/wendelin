// Abnahme: Tool-Namen gültig, Schemas mit `required` und Beschreibungen,
// die ein kleines Modell versteht (kurz, Beispiele für Zeitformate).
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  final integrations = <Integration>[
    CalendarIntegration(FakeCalendarPort()),
    ClipboardIntegration(FakeClipboardPort()),
    AlarmsIntegration(FakeAlarmPort()),
    MemoryIntegration(FakeMemoryStore()),
    WebIntegration(
      searchBackend: FakeWebSearchBackend(),
      fetcher: WebFetcher(
        client: MockClient((_) async => http.Response('', 200)),
      ),
    ),
  ];
  final tools = [for (final i in integrations) ...i.tools];

  test('alle Tools der WP-Liste sind vorhanden', () {
    expect(tools.map((t) => t.name).toSet(), {
      'calendar__list_calendars',
      'calendar__list_events',
      'calendar__find_free_slots',
      'calendar__create_event',
      'calendar__update_event',
      'calendar__delete_event',
      'clipboard__read',
      'clipboard__write',
      'alarms__set_alarm',
      'alarms__set_timer',
      'alarms__list',
      'memory__save',
      'memory__search',
      'memory__forget',
      'web__search',
      'web__fetch',
    });
    expect(tools.map((t) => t.name).toSet(), hasLength(tools.length));
  });

  for (final i in integrations) {
    for (final t in i.tools) {
      group(t.name, () {
        test('Name gültig und mit Präfix der Integration', () {
          expect(Tool.isValidToolName(t.name), isTrue);
          expect(t.name, startsWith('${i.id}__'));
          expect(t.spec.name, t.name);
        });

        test('Schema: object, properties, required ⊆ properties, '
            'jede Eigenschaft mit Typ und Beschreibung', () {
          final s = t.inputSchema;
          expect(s['type'], 'object');
          final props = s['properties']! as Map<String, Object?>;
          final required = s['required']! as List<Object?>;
          expect(props.keys, containsAll(required));
          for (final MapEntry(:key, :value) in props.entries) {
            final p = value! as Map<String, Object?>;
            expect(
              p['type'],
              isIn(['string', 'integer', 'boolean', 'array']),
              reason: key,
            );
            expect(p['description'], isA<String>(), reason: key);
            expect(
              (p['description']! as String).length,
              lessThan(160),
              reason: key,
            );
          }
        });

        test('Beschreibung kurz und vorhanden', () {
          expect(t.description.length, inInclusiveRange(30, 320));
        });

        test('Bestätigungstext wirft nie, auch bei Unsinn', () {
          for (final args in [
            <String, Object?>{},
            {
              'start': 5,
              'title': 7,
              'time': <Object?>[],
              'query': null,
              'url': 'x',
            },
          ]) {
            expect(t.describeForConfirmation(args), isNotEmpty);
          }
        });
      });
    }
  }

  test('Zeit-Tools nennen ein Beispiel im ISO- bzw. HH:MM-Format', () {
    final iso = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');
    for (final t in tools) {
      final text = '${t.description} ${t.inputSchema}';
      if (t.inputSchema.toString().contains('start')) {
        expect(text, matches(iso), reason: t.name);
      }
    }
    final alarm = tools.singleWhere((t) => t.name == 'alarms__set_alarm');
    expect(alarm.description, contains('"07:30"'));
  });
}
