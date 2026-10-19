import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'core_providers.dart';
import 'home_assistant.dart';
import 'integration_providers.dart';
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

/// Port for contact names: display names only, no numbers, addresses or
/// notes.
typedef ContactNames = Future<List<String>> Function();

/// The contact names for the recognizer hint (WP85), read from the contacts
/// port. Empty unless the contacts integration is on (or in demo mode) and
/// the address book may be read; a failing port yields no names. The names
/// stay on the device: they go to the local recognizer only, never to a
/// provider, the log or the audit. Switching the integration rebuilds it;
/// the app invalidates [hintTermsProvider] on resume (permission dialog,
/// changed address book).
final contactNamesProvider = Provider<ContactNames>((ref) {
  final on =
      ref.watch(demoModeProvider) ||
      ref.watch(enabledIntegrationsProvider).contains('contacts');
  if (!on) return () async => const [];
  return () async {
    try {
      final port = ref.read(platformPortsProvider).contacts;
      if (port == null || !await port.hasPermission()) return const [];
      return [
        for (final c in await port.all())
          if (c.name.trim().isNotEmpty) c.name.trim(),
      ];
    } on Object {
      return const [];
    }
  };
});

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
///
/// A failing store (platform channel) yields an empty list: the hint names
/// then go without Home Assistant, the recognizer still starts.
final haApprovedEntitiesProvider = FutureProvider<List<HaEntity>>((ref) async {
  try {
    return await ref.watch(haStoreProvider).load();
  } on Object {
    return const [];
  }
});

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
