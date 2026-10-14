@Tags(['live'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

// Live-Durchlauf Routing (WP29): „Claude, sag nur OK“ geht über die Regel
// „Starkes Modell“ (Präfix „Claude“) an das Claude-Profil (echter
// Anthropic-Adapter, kleinstes Modell Haiku, ein Aufruf). Das Standardprofil
// ist ein Fake, der nie antworten darf. Key nur aus der Umgebung, nie
// ausgeben. Start (im Verzeichnis evals/):
//   set -a; . ~/.wendelin-live.env; set +a
//   dart test test/live/routing_live_test.dart -t live --run-skipped

void main() {
  test('„Claude, sag nur OK“ wird an das Claude-Profil geroutet', () async {
    final profile = EvalProfile.parse(
      File('profiles/claude-haiku.json').readAsStringSync(),
    );
    final variable = profile.apiKeyVariable;
    final key = variable == null ? null : Platform.environment[variable];
    if (key == null || key.trim().isEmpty) {
      markTestSkipped('$variable fehlt');
      return;
    }
    final claude = ProviderFactory.create(
      profile.profile,
      (_) async => key,
      catalog: profile.catalog,
    );
    final standard = FakeLlmProvider(const []);
    final p = profile.profile;
    final time = EvalTime.parse(defaultNow, defaultTimeZone);
    final clock = FixedClock(time.instant);
    final resolver = RuleBasedProviderResolver(
      rules: RuleSet(
        rules: [
          RoutingRule(
            id: 'stark',
            name: 'Starkes Modell',
            condition: PrefixCondition(['Claude']),
            target: RouteTarget(profileId: p.id, modelId: p.defaultModel),
            stripTrigger: true,
          ),
        ],
        defaultTarget: const RouteTarget(
          profileId: 'standard',
          modelId: 'fake',
        ),
      ),
      profiles: [
        RoutingProfile(
          id: p.id,
          name: p.name,
          privacy: p.privacy,
          defaultModel: p.defaultModel,
          provider: claude,
        ),
        RoutingProfile(
          id: 'standard',
          name: 'Standard (Fake)',
          privacy: PrivacyLevel.local,
          defaultModel: 'fake',
          provider: standard,
        ),
      ],
      clock: clock,
      network: FixedNetworkStatus(),
    );
    final catalog = ToolRegistry().catalogFor(
      PrivacyLevel.standard,
      sessionId: 'routing-live',
    );
    final agent = AgentRunner(
      resolver: resolver,
      contextBuilder: ContextBuilder(
        config: const AgentConfig(),
        clock: clock,
        device: DeviceInfo(locale: 'de-DE', timeZone: time.timeZone),
        catalog: catalog,
      ),
      invoker: ToolExecutor(catalog: catalog),
      clock: clock,
      sessionId: 'routing-live',
      costEstimator: profile.costEstimator,
    );
    Routed? routed;
    var cost = 0;
    var answer = '';
    await for (final e in agent.run(UserInput(text: 'Claude, sag nur OK'))) {
      switch (e) {
        case Routed():
          routed = e;
        case UsageReported(:final costMicros):
          cost += costMicros ?? 0;
        case AgentDone(:final finalText):
          answer = finalText;
        case AgentFailed():
          fail('Lauf gescheitert: $e');
        case _:
      }
    }
    // ignore: avoid_print
    print(
      'Routing live: ${routed?.profileId}/${routed?.modelId} '
      '(${routed?.reason}), Kosten $cost µUSD, Antwort: $answer',
    );
    expect(routed?.profileId, p.id);
    expect(routed?.reason, 'Starkes Modell');
    expect(standard.requests, isEmpty);
    expect(answer.toUpperCase(), contains('OK'));
  });
}
