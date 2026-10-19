import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'home_assistant.dart';
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

/// Rooms (areas) and entity names of the Home Assistant entities the user
/// approved (WP103). Names only: no states, ids or values.
final class HaNameHintSource implements HintTermSource {
  /// Creates the source over [entities] (the approved ones).
  const HaNameHintSource(this.entities);

  /// The approved entities (local store, no network).
  final Future<List<HaEntity>> Function() entities;

  @override
  Future<List<HintTerm>> terms() async => [
    for (final e in await entities()) ...[
      if (e.area != null) HintTerm(e.area!, HintTermKind.room),
      HintTerm(e.name, HintTermKind.entity),
    ],
  ];
}

/// Port for contact names (WP85 delivers the real source later): display
/// names only, no numbers, addresses or notes.
typedef ContactNames = Future<List<String>> Function();

/// The contact names; the default is empty until WP85 overrides it.
final contactNamesProvider = Provider<ContactNames>(
  (ref) =>
      () async => const [],
);

/// [HintTermSource] over [ContactNames].
final class ContactNameHintSource implements HintTermSource {
  /// Creates the source.
  const ContactNameHintSource(this.names);

  /// Where the display names come from.
  final ContactNames names;

  @override
  Future<List<HintTerm>> terms() async => [
    for (final n in await names()) HintTerm(n, HintTermKind.contact),
  ];
}

/// The approved Home Assistant entities (local store, no network). The
/// settings screen invalidates it when the approval changes, so the hint
/// names follow (Befund 7).
final haApprovedEntitiesProvider = FutureProvider<List<HaEntity>>(
  (ref) => ref.watch(haStoreProvider).load(),
);

/// The sources of the recognizer hint (names only, nothing leaves the
/// device): the assistant, lists, approved Home Assistant rooms and
/// entities, and contacts through the port of WP85 (empty until then). The
/// only agent name is „Wendelin“ (the app has no further named agents).
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
    HaNameHintSource(() => ref.read(haApprovedEntitiesProvider.future)),
    ContactNameHintSource(() => ref.read(contactNamesProvider)()),
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
  // Rebuild when the list settings, the approved Home Assistant entities or
  // the contact source change (a new [ContactNames] from WP85 = new names).
  ref.watch(listDefinitionsProvider);
  await ref.watch(haApprovedEntitiesProvider.future);
  ref.watch(contactNamesProvider);
  return collectHintTerms(ref.watch(hintTermSourcesProvider));
});
