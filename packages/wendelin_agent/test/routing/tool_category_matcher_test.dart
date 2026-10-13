import 'package:test/test.dart';
import 'package:wendelin_agent/testing.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

void main() {
  toolCategoryMatcherContract(
    'KeywordToolCategoryMatcher',
    KeywordToolCategoryMatcher.new,
    category: 'obsidian.edit',
    needs: 'Schreib meine Notiz zum Urlaub um',
  );

  group('FakeToolCategoryMatcher', () {
    toolCategoryMatcherContract(
      'FakeToolCategoryMatcher',
      () => _TextAwareFake(FakeToolCategoryMatcher({'obsidian.edit'})),
      category: 'obsidian.edit',
      needs: 'Notiz',
    );

    test('records questions and matches bare integrations', () {
      final m = FakeToolCategoryMatcher({'calendar.read'});
      expect(m.matches(RoutingText('Hi!'), 'calendar'), isTrue);
      expect(m.matches(RoutingText('Hi!'), 'calendar.read'), isTrue);
      expect(m.matches(RoutingText('Hi!'), 'calendar.edit'), isFalse);
      expect(m.asked.first, ('hi', 'calendar'));
    });
  });

  group('keyword lists', () {
    final m = KeywordToolCategoryMatcher();
    final cases = <(String, String, bool)>[
      ('Schreib meine Notiz zum Projekt um', 'obsidian.edit', true),
      ('Ergänze die Notizen von gestern', 'obsidian.edit', true),
      ('Lies mir die Notiz vor', 'obsidian.edit', false),
      ('Lies mir die Notiz vor', 'obsidian.read', true),
      ('Lies mir die Notiz vor', 'obsidian', true),
      ('Réécris ma note', 'obsidian.edit', true),
      ('Montre-moi mes notes', 'obsidian.read', true),
      ('Rewrite my journal entry', 'obsidian.edit', true),
      ('Was steht im Kalender morgen?', 'calendar.read', true),
      ('Trag einen Termin ein', 'calendar.edit', true),
      ('Add a meeting tomorrow', 'calendar.edit', true),
      ('Merk dir, dass ich Tee mag', 'memory', true),
      ('Weck mich um sieben', 'alarm', true),
      ('Setz Milch auf die Einkaufsliste', 'lists', true),
      ('Wie spät ist es?', 'obsidian', false),
      ('Schreib meine Notiz um', 'obsidian.delete', false),
      ('Schreib meine Notiz um', 'bring', false),
    ];
    for (final (text, category, expected) in cases) {
      test('„$text“ needs $category → $expected', () {
        expect(m.matches(RoutingText(text), category), expected);
      });
    }

    test('custom lists replace the defaults', () {
      final custom = KeywordToolCategoryMatcher(
        topics: {
          'bring': ['bring', 'einkauf', ''],
        },
        verbs: {
          'edit': ['setz'],
        },
      );
      expect(
        custom.matches(RoutingText('Setz Milch auf Bring'), 'bring.edit'),
        isTrue,
      );
      expect(custom.matches(RoutingText('Notiz'), 'obsidian'), isFalse);
      expect(custom.matches(RoutingText('Einkauf'), 'bring.read'), isFalse);
    });
  });
}

/// The fake ignores the text; the contract expects unrelated text to need
/// nothing, so this wrapper answers false for texts without „notiz“.
final class _TextAwareFake implements ToolCategoryMatcher {
  _TextAwareFake(this.inner);
  final FakeToolCategoryMatcher inner;

  @override
  bool matches(RoutingText text, String category) =>
      text.normalized.contains('notiz') && inner.matches(text, category);
}
