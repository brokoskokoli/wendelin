import 'package:test/test.dart';

import '../src/routing/routing_text.dart';
import '../src/routing/tool_category_matcher.dart';

/// Contract every [ToolCategoryMatcher] must fulfil. [create] returns a
/// matcher for which a request containing [needs] needs `[category]` (and
/// thus the bare integration of it).
void toolCategoryMatcherContract(
  String name,
  ToolCategoryMatcher Function() create, {
  required String category,
  required String needs,
  String unrelated = 'Wie spät ist es?',
}) {
  group('ToolCategoryMatcher contract: $name', () {
    final integration = category.split('.').first;

    test('matches the category and its integration', () {
      final m = create();
      expect(m.matches(RoutingText(needs), category), isTrue);
      expect(m.matches(RoutingText(needs), integration), isTrue);
    });

    test('unknown categories never match', () {
      final m = create();
      expect(m.matches(RoutingText(needs), 'unbekannt'), isFalse);
      expect(m.matches(RoutingText(needs), 'unbekannt.edit'), isFalse);
    });

    test('is deterministic and ignores case and punctuation', () {
      final m = create();
      final a = m.matches(RoutingText(needs), category);
      final b = m.matches(RoutingText('${needs.toUpperCase()}!!'), category);
      expect(b, a);
    });

    test('empty text needs nothing', () {
      final m = create();
      expect(m.matches(RoutingText(''), category), isFalse);
      expect(m.matches(RoutingText(unrelated), category), isFalse);
    });
  });
}
