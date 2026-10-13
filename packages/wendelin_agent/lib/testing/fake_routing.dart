import '../src/routing/routing_context.dart';
import '../src/routing/routing_text.dart';
import '../src/routing/tool_category_matcher.dart';

/// [ToolCategoryMatcher] for tests: a request needs a category if it is in
/// [categories] (exact or as the integration of a `<integration>.<kind>`
/// entry), regardless of the text. Records every question in [asked].
final class FakeToolCategoryMatcher implements ToolCategoryMatcher {
  /// Creates the matcher; [categories] are copied.
  FakeToolCategoryMatcher([Set<String> categories = const {}])
    : categories = Set.unmodifiable(categories);

  /// Categories every request needs.
  final Set<String> categories;

  /// `(normalized text, category)` of every call.
  final List<(String, String)> asked = [];

  @override
  bool matches(RoutingText text, String category) {
    asked.add((text.normalized, category));
    return categories.contains(category) ||
        categories.any((c) => c.startsWith('$category.'));
  }
}

/// [NetworkStatus] with a settable [current] state.
final class FixedNetworkStatus implements NetworkStatus {
  /// Creates the status.
  FixedNetworkStatus([this.current = NetworkState.online]);

  @override
  NetworkState current;
}
