import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Wednesday, 14 October 2026, 10:00 (local).
final wednesday10 = DateTime(2026, 10, 14, 10);

const phalaSmall = RouteTarget(profileId: 'phala', modelId: 'glm-small');
const phalaLarge = RouteTarget(profileId: 'phala', modelId: 'glm-large');
const claudeOpus = RouteTarget(profileId: 'claude', modelId: 'claude-opus');
const claudeSonnet = RouteTarget(profileId: 'claude', modelId: 'claude-sonnet');
const ollama = RouteTarget(profileId: 'ollama', modelId: 'llama');
const mistral = RouteTarget(profileId: 'mistral', modelId: 'mistral-small');

/// Profiles of the concept example, each with its own fake adapter.
List<RoutingProfile> conceptProfiles({
  Set<String> disabled = const {},
  Set<String> unbuildable = const {},
}) => [
  for (final (id, name, privacy, model, aliases) in [
    ('phala', 'Phala GLM klein', PrivacyLevel.tee, 'glm-small', <String>[]),
    (
      'claude',
      'Claude API',
      PrivacyLevel.standard,
      'claude-sonnet',
      ['Sonnet'],
    ),
    ('ollama', 'Ollama Homeserver', PrivacyLevel.local, 'llama', <String>[]),
    ('mistral', 'Mistral', PrivacyLevel.eu, 'mistral-small', <String>[]),
  ])
    RoutingProfile(
      id: id,
      name: name,
      privacy: privacy,
      defaultModel: model,
      enabled: !disabled.contains(id),
      provider: unbuildable.contains(id) ? null : FakeLlmProvider(const []),
      aliases: aliases,
    ),
];

/// The example rules of the concept („Routing und Eskalation“) plus a
/// disabled one.
RuleSet conceptRules({Map<String, List<RouteTarget>>? chains}) => RuleSet(
  rules: [
    RoutingRule(
      id: 'strong',
      name: 'Starkes Modell',
      condition: PrefixCondition(['Claude', 'Fable']),
      target: claudeOpus,
      stripTrigger: true,
    ),
    RoutingRule(
      id: 'private',
      name: 'Privat',
      condition: PrivacyCondition(),
      target: phalaSmall,
    ),
    RoutingRule(
      id: 'offline',
      name: 'Offline',
      condition: const NetworkCondition(NetworkState.offline),
      target: ollama,
    ),
    RoutingRule(
      id: 'notes',
      name: 'Notizen umschreiben',
      condition: const NeedsToolCondition('obsidian.edit'),
      target: claudeSonnet,
    ),
    RoutingRule(
      id: 'think',
      name: 'Gründlich',
      enabled: false,
      condition: KeywordCondition(['denk gründlich nach', 'think hard']),
      target: claudeOpus,
    ),
  ],
  defaultTarget: phalaSmall,
  chains:
      chains ??
      {
        'phala': [phalaLarge, claudeSonnet, claudeOpus],
        'claude': [claudeOpus],
      },
);

/// A context for [text] with fake clock and network.
RoutingContext ctxFor(
  String text, {
  NetworkState network = NetworkState.online,
  DateTime? now,
  ToolCategoryMatcher? matcher,
  String? language,
  double? sttConfidence,
  List<ImageBlock> images = const [],
}) => RoutingContext(
  input: UserInput(
    text: text,
    language: language,
    sttConfidence: sttConfidence,
    images: images,
  ),
  now: now ?? wednesday10,
  network: network,
  matcher: matcher ?? FakeToolCategoryMatcher(),
);

/// A resolver over the concept rules with fake clock and network.
RuleBasedProviderResolver conceptResolver({
  RuleSet? rules,
  List<RoutingProfile>? profiles,
  FixedNetworkStatus? network,
  FixedClock? clock,
  ToolCategoryMatcher? matcher,
}) => RuleBasedProviderResolver(
  rules: rules ?? conceptRules(),
  profiles: profiles ?? conceptProfiles(),
  clock: clock ?? FixedClock(wednesday10),
  network: network ?? FixedNetworkStatus(),
  matcher: matcher,
);
