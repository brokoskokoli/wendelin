import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'preferences.dart';

/// Names from the list settings: list names and their aliases (WP103).
/// Names only, never list entries.
final class ListNameHintSource implements HintTermSource {
  /// Creates the source over [names].
  const ListNameHintSource(this.names);

  /// Names and aliases of the user's lists.
  final Iterable<String> Function() names;

  @override
  Future<List<HintTerm>> terms() async => [
    for (final n in names()) HintTerm(n, HintTermKind.list),
  ];
}

/// The sources of the recognizer hint (names only, nothing leaves the
/// device). More sources (Home Assistant rooms and entities, agents,
/// contacts through the port of WP85) join here.
final hintTermSourcesProvider = Provider<List<HintTermSource>>(
  (ref) => [
    const _Fixed([HintTerm('Wendelin', HintTermKind.agent)]),
    ListNameHintSource(
      () => [
        for (final l in ref.read(listDefinitionsProvider)) ...[
          l.name,
          ...l.aliases,
        ],
      ],
    ),
  ],
);

final class _Fixed implements HintTermSource {
  const _Fixed(this._terms);

  final List<HintTerm> _terms;

  @override
  Future<List<HintTerm>> terms() async => _terms;
}

/// The cleaned hint names (limited, deduplicated); a change rebuilds the
/// recognizer of a model that takes hotwords.
final hintTermsProvider = FutureProvider<List<String>>((ref) async {
  // Rebuild when the list settings change.
  ref.watch(listDefinitionsProvider);
  return collectHintTerms(ref.watch(hintTermSourcesProvider));
});
