import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// One sentence of the routing table: what the rules should do with it.
final class RoutingRow {
  /// Creates a row.
  const RoutingRow(
    this.text,
    this.expectedRule, {
    this.network = NetworkState.online,
  });

  /// The utterance.
  final String text;

  /// Name of the rule that should match (or [RuleSet.defaultReason]).
  final String expectedRule;

  /// Network state while routing.
  final NetworkState network;
}

/// Result of one row.
final class RoutingOutcome {
  /// Creates an outcome.
  const RoutingOutcome(this.row, this.rule, this.profileId, this.modelId);

  /// The row.
  final RoutingRow row;

  /// The rule that matched.
  final String rule;

  /// Chosen profile.
  final String profileId;

  /// Chosen model.
  final String modelId;

  /// Whether the matching rule is the expected one.
  bool get ok => rule == row.expectedRule;
}

const _strong = 'Starkes Modell';
const _private = 'Privat';
const _offline = 'Offline';
const _notes = 'Notizen umschreiben';
const _default = RuleSet.defaultReason;

/// The sentences of the routing table (WP21 sentence table, de/fr/en): the
/// concept's example rules, see `RuleSet` in `wendelin_agent`.
const routingRows = [
  RoutingRow('Claude, wie spät ist es?', _strong),
  RoutingRow('Fable, schreib mir ein Gedicht', _strong),
  RoutingRow('Frag mal Claude, wie spät es ist', _default),
  RoutingRow('Claudia, wie geht es dir?', _default),
  RoutingRow('Das ist privat: mein Arzttermin', _private),
  RoutingRow('Erklär mir die Privatsphäre-Einstellungen', _default),
  RoutingRow('Wie wird das Wetter?', _offline, network: NetworkState.offline),
  RoutingRow('Claude, hilf mir', _strong, network: NetworkState.offline),
  RoutingRow('Schreib meine Notiz zum Projekt um', _notes),
  RoutingRow('Wie spät ist es?', _default),
  RoutingRow('Claude, quelle heure est-il ?', _strong),
  RoutingRow("C'est privé : mon rendez-vous chez le médecin", _private),
  RoutingRow('Réécris ma note sur le projet', _notes),
  RoutingRow('Demande à Claude la météo', _default),
  RoutingRow("Claude, what's the weather like?", _strong),
  RoutingRow('This is private: my bank reminder', _private),
  RoutingRow('Rewrite my note about the trip', _notes),
  RoutingRow('Ask Claude about the weather', _default),
  RoutingRow('What time is it?', _offline, network: NetworkState.offline),
  RoutingRow('What time is it?', _default),
];

/// Routes every row with the concept rules and real condition code.
List<RoutingOutcome> runRoutingTable([List<RoutingRow> rows = routingRows]) {
  const phala = RouteTarget(profileId: 'phala', modelId: 'glm-small');
  const claude = RouteTarget(profileId: 'claude', modelId: 'claude-opus');
  const sonnet = RouteTarget(profileId: 'claude', modelId: 'claude-sonnet');
  const ollama = RouteTarget(profileId: 'ollama', modelId: 'llama');
  final rules = RuleSet(
    rules: [
      RoutingRule(
        id: 'strong',
        name: _strong,
        condition: PrefixCondition(['Claude', 'Fable']),
        target: claude,
        stripTrigger: true,
      ),
      RoutingRule(
        id: 'private',
        name: _private,
        condition: PrivacyCondition(),
        target: phala,
      ),
      RoutingRule(
        id: 'offline',
        name: _offline,
        condition: const NetworkCondition(NetworkState.offline),
        target: ollama,
      ),
      RoutingRule(
        id: 'notes',
        name: _notes,
        condition: const NeedsToolCondition('obsidian.edit'),
        target: sonnet,
      ),
    ],
    defaultTarget: phala,
  );
  RoutingProfile profile(String id, PrivacyLevel privacy, String model) =>
      RoutingProfile(
        id: id,
        name: id,
        privacy: privacy,
        defaultModel: model,
        provider: FakeLlmProvider(const []),
      );
  final profiles = [
    profile('phala', PrivacyLevel.tee, 'glm-small'),
    profile('claude', PrivacyLevel.standard, 'claude-sonnet'),
    profile('ollama', PrivacyLevel.local, 'llama'),
  ];
  return [
    for (final row in rows)
      () {
        final r = RuleBasedProviderResolver(
          rules: rules,
          profiles: profiles,
          clock: FixedClock(DateTime(2026, 10, 14, 10)),
          network: FixedNetworkStatus(row.network),
        ).resolve(UserInput(text: row.text));
        return RoutingOutcome(row, r.reason, r.profileId, r.modelId);
      }(),
  ];
}

/// The table as text: sentence, network, matching rule, target, status.
String formatRoutingTable(List<RoutingOutcome> outcomes) {
  final b = StringBuffer('Routing-Tabelle (welche Regel greift)\n');
  for (final o in outcomes) {
    final net = o.row.network == NetworkState.online
        ? ''
        : ' [${o.row.network.name}]';
    b.writeln(
      '${o.ok ? 'ok    ' : 'FALSCH'} „${o.row.text}“$net → ${o.rule} '
      '(${o.profileId}/${o.modelId})'
      '${o.ok ? '' : ', erwartet ${o.row.expectedRule}'}',
    );
  }
  final ok = outcomes.where((o) => o.ok).length;
  b.writeln('$ok/${outcomes.length} wie erwartet');
  return b.toString();
}
