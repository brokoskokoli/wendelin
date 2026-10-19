// Abnahme: Tool-Namen gültig, Schemas mit `required` und Beschreibungen,
// die ein kleines Modell versteht (kurz, Beispiele für Zeitformate).
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/all_integrations.dart';

void main() {
  // All integrations of the real registry (built from fakes by TestEnv): a
  // new integration is covered without touching this test. The container is
  // built inside the first test (needs the test zone).
  Map<String, Integration>? cache;
  Map<String, Integration> all() => cache ??= allBuiltInIntegrations();

  List<Tool> allTools() => [for (final i in all().values) ...i.tools];

  test('Tool-Namen sind eindeutig, jede Integration hat Tools', () {
    final tools = allTools();
    expect(tools.map((t) => t.name).toSet(), hasLength(tools.length));
    for (final i in all().values) {
      expect(i.tools, isNotEmpty, reason: i.id);
    }
  });

  for (final spec in builtInIntegrationSpecs) {
    group(spec.id, () {
      test('Name gültig und mit Präfix der Integration', () {
        final i = all()[spec.id]!;
        for (final t in i.tools) {
          expect(Tool.isValidToolName(t.name), isTrue, reason: t.name);
          expect(t.name, startsWith('${i.id}__'));
          expect(t.spec.name, t.name);
        }
      });

      test('Schema: object, properties, required ⊆ properties, '
          'jede Eigenschaft mit Typ und Beschreibung', () {
        for (final t in all()[spec.id]!.tools) {
          final s = t.inputSchema;
          expect(s['type'], 'object', reason: t.name);
          final props = s['properties']! as Map<String, Object?>;
          final required = s['required']! as List<Object?>;
          expect(props.keys, containsAll(required), reason: t.name);
          for (final MapEntry(:key, :value) in props.entries) {
            final p = value! as Map<String, Object?>;
            expect(
              p['type'],
              isIn(['string', 'integer', 'boolean', 'array']),
              reason: '${t.name}.$key',
            );
            expect(p['description'], isA<String>(), reason: '${t.name}.$key');
            expect(
              (p['description']! as String).length,
              lessThan(160),
              reason: '${t.name}.$key',
            );
          }
        }
      });

      test('Beschreibung kurz und vorhanden', () {
        for (final t in all()[spec.id]!.tools) {
          expect(
            t.description.length,
            inInclusiveRange(30, 320),
            reason: t.name,
          );
        }
      });

      test('Bestätigungstext wirft nie, auch bei Unsinn', () {
        for (final t in all()[spec.id]!.tools) {
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
            expect(t.describeForConfirmation(args), isNotEmpty, reason: t.name);
          }
        }
      });
    });
  }

  test('Zeit-Tools nennen ein Beispiel im ISO- bzw. HH:MM-Format', () {
    final tools = allTools();
    final iso = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');
    for (final t in tools) {
      final text = '${t.description} ${t.inputSchema}';
      // Only tools with a `start` parameter, not any description mentioning it.
      final props = t.inputSchema['properties'] as Map<String, Object?>;
      if (props.containsKey('start')) {
        expect(text, matches(iso), reason: t.name);
      }
    }
    final alarm = tools.singleWhere((t) => t.name == 'alarms__set_alarm');
    expect(alarm.description, contains('"07:30"'));
  });
}
