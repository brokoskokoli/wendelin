import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/routing.dart';
import 'package:wendelin/voice/speaker/person_storage.dart';
import 'package:wendelin/voice/speaker/speaker_storage.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'person_scope_test.dart' show testProfile;

ProviderProfile _profile(String id, String name, PrivacyLevel privacy) =>
    ProviderProfile(
      id: id,
      name: name,
      type: ProviderType.anthropic,
      defaultModel: '$id-standard',
      privacy: privacy,
      authMethod: ApiKeyAuth('provider.$id.apiKey'),
    );

/// Rules as in the concept: „Claude, …“ goes to Claude, „privat“ marks the
/// request private (target Phala), everything else to the default (Phala).
RuleSet _rules() => RuleSet(
  rules: [
    RoutingRule(
      id: 'stark',
      name: 'Starkes Modell',
      condition: PrefixCondition(['Claude']),
      target: const RouteTarget(profileId: 'claude', modelId: 'claude-opus'),
      stripTrigger: true,
    ),
    RoutingRule(
      id: 'privat',
      name: 'Privat',
      condition: PrivacyCondition(),
      target: const RouteTarget(profileId: 'phala', modelId: 'glm-klein'),
    ),
  ],
  defaultTarget: const RouteTarget(profileId: 'phala', modelId: 'glm-klein'),
);

/// The agent of a person is only another default target (WP92b): routing
/// rules, privacy and the stored global default stay as they are.
void main() {
  late Map<String, FakeLlmProvider> llm;
  late TestEnv env;
  late ProviderContainer c;

  Future<void> setUp0() async {
    llm = {
      'phala': FakeLlmProvider([
        for (var i = 0; i < 4; i++) ScriptedTurn.text('ok'),
      ]),
      'claude': FakeLlmProvider([
        for (var i = 0; i < 4; i++) ScriptedTurn.text('ok'),
      ]),
    };
    env = TestEnv(storedProfiles: true, llmFactory: (p, _) => llm[p.id]!);
    await env.secrets.write('provider.claude.apiKey', 'k');
    await env.storage.providerProfiles.save(
      _profile('phala', 'Phala GLM', PrivacyLevel.tee).copyWith(
        type: ProviderType.openaiCompatible,
        baseUrl: 'https://api.redpill.ai/v1',
        options: const {'attestation': 'phala'},
      ),
    );
    await env.storage.providerProfiles.save(
      _profile('claude', 'Claude API', PrivacyLevel.standard),
    );
    await env.storage.providerProfiles.setDefault('phala');
    await env.storage.settings.set(RoutingSettings.rules, _rules());
    await SecretSpeakerProfileStore(env.secrets)
        .save(testProfile('pa', 'Anna'));
    await SecretPersonSettingsStore(env.secrets).save(
      const PersonSettings(
        personId: 'pa',
        address: 'Anni',
        agentProfileId: 'claude',
      ),
    );
    c = env.container();
    addTearDown(c.dispose);
  }

  Future<void> ask(String text, {String? speaker}) async {
    final controller = c.read(agentControllerProvider.notifier);
    await controller
        .submit(
          UserInput(text: text, source: InputSource.voice, speakerId: speaker),
        )
        .toList();
    await controller.idle;
    await c.read(auditRecorderProvider).flush();
  }

  test('die Person landet beim eigenen Agenten, unbekannt beim Standard, '
      'der gespeicherte globale Standard bleibt', () async {
    await setUp0();
    await ask('Wie spät ist es?', speaker: 'pa');
    expect(llm['claude']!.requests.single.model, 'claude-standard');
    expect(llm['phala']!.requests, isEmpty);
    final route = await env.storage.audit.query(
      const AuditFilter(kinds: {AuditKind.routing}),
    );
    expect(route.single.payload['profileId'], 'claude');
    await ask('Neu', speaker: null);
    // Unbekannt bleibt in der Unterhaltung der Person (Entscheidung 3).
    expect(llm['claude']!.requests, hasLength(2));
    await c.read(agentControllerProvider.notifier).newTopic();
    await ask('Wie spät ist es?');
    expect(llm['phala']!.requests.single.model, 'glm-klein');
    expect((await env.storage.providerProfiles.defaultProfile())?.id, 'phala');
  });

  test('„privat“ geht trotz Personen-Agent an das Ziel der Regel', () async {
    await setUp0();
    await ask('Privat: erinnere mich an den Arzttermin', speaker: 'pa');
    expect(llm['claude']!.requests, isEmpty);
    expect(llm['phala']!.requests.single.model, 'glm-klein');
    final state = c.read(agentControllerProvider);
    expect(state.privateSince, isNotNull);
  });

  test('Routing-Regeln der Person gelten weiter („Claude, …“)', () async {
    await setUp0();
    await ask('Claude, wie spät ist es?', speaker: 'pa');
    expect(llm['claude']!.requests.single.model, 'claude-opus');
  });

  test('keine Person-Id, Anrede oder Namespace im Audit-Log', () async {
    await setUp0();
    await ask('Wie spät ist es?', speaker: 'pa');
    final all = jsonEncode([
      for (final e in await env.storage.audit.query()) e.payload,
    ]);
    expect(all, isNot(contains('p:pa')));
    expect(all, isNot(contains('Anni')));
    expect(all, isNot(contains('Anna')));
    expect(all, isNot(contains('speakerId')));
  });

  test('withDefaultProfile ändert nur das Standardziel', () async {
    await setUp0();
    final config = (await c.read(providerConfigProvider.future))!;
    final mine = config.withDefaultProfile('claude');
    expect(mine.primary.profileId, 'claude');
    expect(mine.primary.modelId, 'claude-standard');
    expect(mine.others.map((t) => t.profileId), ['phala']);
    expect(mine.lowestPrivacy, config.lowestPrivacy);
    expect(mine.routing!.rules.rules, config.routing!.rules.rules);
    expect(mine.routing!.rules.defaultTarget.profileId, 'claude');
    expect(config.primary.profileId, 'phala', reason: 'Original unverändert');
    // Unbekannt, null und der Standard selbst: dieselbe Konfiguration.
    expect(identical(config.withDefaultProfile(null), config), isTrue);
    expect(identical(config.withDefaultProfile('phala'), config), isTrue);
    expect(identical(config.withDefaultProfile('weg'), config), isTrue);
  });
}
