import 'package:wendelin_core/wendelin_core.dart';

import '../src/web/web_search_backend.dart';
import 'fake_failures.dart';

/// Scripted [WebSearchBackend]: returns the first `count` of [results]
/// (or throws [error]) and records every query.
final class FakeWebSearchBackend with FakeFailures implements WebSearchBackend {
  /// Creates the fake.
  FakeWebSearchBackend({this.results = const [], this.error});

  /// Results returned for every query.
  List<WebSearchResult> results;

  /// If set, every search throws it (after argument checks).
  Object? error;

  /// Queries received, in order.
  final List<String> queries = [];

  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake-Suche';

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int count = 5,
    String? language,
    CancelToken? cancel,
  }) async {
    checkSearchArgs(query, count);
    cancel?.throwIfCancelled();
    enter('search');
    queries.add(query);
    if (error != null) throw error!;
    return results.take(count).toList();
  }
}
