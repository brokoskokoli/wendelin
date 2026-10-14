// Gerätetest (WP29, DoD M3): Routing „Claude, …“ → Claude-Profil.
//
// Die echte App auf dem Emulator (Kanäle, Registry, Routing-Regeln aus dem
// Speicher, Audit-Log), aber ohne Netz: Beide Profile („Standard“ und
// „Claude“) antworten mit einem Skript-Provider; geprüft wird, welches
// Profil die Anfrage bekommt. Die Regel „Starkes Modell“ (Präfix „Claude“)
// ist so eingerichtet wie in der Routing-Seite der Einstellungen.
//
// Läuft über `tool/e2e_android.sh` (nur Emulator).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/routing.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';

ProviderProfile _profile(String id, String name, PrivacyLevel privacy) =>
    ProviderProfile(
      id: id,
      name: name,
      type: ProviderType.anthropic,
      defaultModel: '$id-modell',
      privacy: privacy,
      authMethod: ApiKeyAuth('provider.$id.apiKey'),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('„Claude, wie spät ist es?“ geht an das Claude-Profil, der '
      'Satz ohne Präfix an das Standardprofil (Audit-Log)', (tester) async {
    final llm = {
      'standard': FakeLlmProvider([ScriptedTurn.text('Kurz nach acht.')]),
      'claude': FakeLlmProvider([ScriptedTurn.text('Es ist 8 Uhr.')]),
    };
    final app = E2eApp(
      extraOverrides: [
        llmProviderFactoryProvider.overrideWithValue((p, _) => llm[p.id]!),
      ],
    );
    final profiles = app.storage.providerProfiles;
    await profiles.save(_profile('standard', 'Standard', PrivacyLevel.local));
    await profiles.save(
      _profile('claude', 'Claude API', PrivacyLevel.standard),
    );
    await profiles.setDefault('standard');
    await app.storage.settings.set(
      RoutingSettings.rules,
      RuleSet(
        rules: [
          RoutingRule(
            id: 'stark',
            name: 'Starkes Modell',
            condition: PrefixCondition(['Claude']),
            target: const RouteTarget(
              profileId: 'claude',
              modelId: 'claude-modell',
            ),
            stripTrigger: true,
          ),
        ],
        defaultTarget: const RouteTarget(
          profileId: 'standard',
          modelId: 'standard-modell',
        ),
      ),
    );
    await app.pump(tester);

    await send(tester, 'Claude, wie spät ist es?');
    await pumpUntil(tester, find.textContaining('Es ist 8 Uhr.'));
    await waitIdle(tester);
    expect(llm['claude']!.requests, hasLength(1));
    expect(
      llm['claude']!.requests.single.messages.last.text,
      'wie spät ist es?',
    );
    expect(llm['standard']!.requests, isEmpty);

    await send(tester, 'Wie spät ist es?');
    await pumpUntil(tester, find.textContaining('Kurz nach acht.'));
    await waitIdle(tester);
    expect(llm['standard']!.requests, hasLength(1));
    expect(llm['claude']!.requests, hasLength(1));

    final routing = await app.storage.audit.query(
      const AuditFilter(kinds: {AuditKind.routing}),
    );
    final decisions = [
      for (final e in routing.reversed)
        '${e.payload['profileId']} · ${e.payload['reason']}',
    ];
    // ignore: avoid_print
    print('Routing-Audit: $decisions');
    expect(decisions, ['claude · Starkes Modell', 'standard · Standard']);
  });
}
