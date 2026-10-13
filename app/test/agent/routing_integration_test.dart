import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/routing.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/test_env.dart';
import 'agent_controller_test.dart' show waitFor;

const _secret = 'GEHEIMER-TESTSCHLUESSEL-NICHT-LOGGEN';

ProviderProfile _profile(String id, String name, PrivacyLevel privacy) =>
    ProviderProfile(
      id: id,
      name: name,
      type: ProviderType.anthropic,
      defaultModel: '$id-standard',
      privacy: privacy,
      authMethod: ApiKeyAuth('provider.$id.apiKey'),
    );

/// The concept's example: „Claude, …“ goes to Claude (prefix removed for
/// the model), „privat“ marks the request private, everything else goes to
/// the default (Phala, TEE) with the chain Phala → Claude.
RuleSet _rules() => RuleSet(
  rules: [
    RoutingRule(
      id: 'stark',
      name: 'Starkes Modell',
      condition: PrefixCondition(['Claude', 'Fable']),
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
  chains: {
    'phala': [const RouteTarget(profileId: 'claude', modelId: 'claude-sonnet')],
  },
);

void main() {
  late Map<String, FakeLlmProvider> llm;
  late TestEnv env;
  late ProviderContainer c;

  Future<void> setUpEnv({
    required List<ScriptedTurn> phala,
    required List<ScriptedTurn> claude,
  }) async {
    llm = {'phala': FakeLlmProvider(phala), 'claude': FakeLlmProvider(claude)};
    env = TestEnv(storedProfiles: true, llmFactory: (p, _) => llm[p.id]!);
    await env.secrets.write('provider.claude.apiKey', _secret);
    await env.storage.providerProfiles.save(
      _profile('phala', 'Phala GLM', PrivacyLevel.tee),
    );
    await env.storage.providerProfiles.save(
      _profile('claude', 'Claude API', PrivacyLevel.standard),
    );
    await env.storage.providerProfiles.setDefault('phala');
    await env.storage.settings.set(RoutingSettings.rules, _rules());
    c = env.container();
    addTearDown(c.dispose);
  }

  Future<ConversationState> send(String text) async {
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send(text);
    await controller.idle;
    await c.read(auditRecorderProvider).flush();
    return c.read(agentControllerProvider);
  }

  test('„Claude, wie spät ist es?“ läuft über das Claude-Profil', () async {
    await setUpEnv(
      phala: const [],
      claude: [ScriptedTurn.text('Es ist 8:12 Uhr.')],
    );
    final s = await send('Claude, wie spät ist es?');

    // Präfix nur für das Modell entfernt, Modell der Regel.
    final request = llm['claude']!.requests.single;
    expect(request.model, 'claude-opus');
    expect(request.messages.last.text, 'wie spät ist es?');
    expect(llm['phala']!.requests, isEmpty);

    // Im Verlauf bleibt der Satz vollständig.
    final sessionId = c.read(sessionManagerProvider).currentId!;
    final stored = await env.storage.conversations.messages(sessionId);
    expect(stored.first.message.text, 'Claude, wie spät ist es?');
    expect(
      s.entries.whereType<UserEntry>().single.text,
      'Claude, wie spät ist es?',
    );

    // Regel im ProviderChip, Routing-Entscheidung im Audit-Log ohne Secret.
    expect(s.activeProfileId, 'claude');
    expect(s.activeRule, 'Starkes Modell');
    final routing = await env.storage.audit.query(
      const AuditFilter(kinds: {AuditKind.routing}),
    );
    expect(routing.single.payload, {
      'profileId': 'claude',
      'modelId': 'claude-opus',
      'reason': 'Starkes Modell',
    });
    final everything = jsonEncode([
      for (final e in await env.storage.audit.query()) e.payload,
    ]);
    expect(everything, isNot(contains(_secret)));
  });

  test('Satz ohne Präfix geht an den Standard', () async {
    await setUpEnv(
      phala: [ScriptedTurn.text('Kurz nach acht.')],
      claude: const [],
    );
    final s = await send('Wie spät ist es?');
    expect(llm['phala']!.requests.single.model, 'glm-klein');
    expect(
      llm['phala']!.requests.single.messages.last.text,
      'Wie spät ist es?',
    );
    expect(llm['claude']!.requests, isEmpty);
    expect(s.activeRule, isNull);
    final routing = await env.storage.audit.query(
      const AuditFilter(kinds: {AuditKind.routing}),
    );
    expect(routing.single.payload['reason'], RuleSet.defaultReason);
    expect(s.privateSince, isNull);
  });

  test('„privat“ setzt die Untergrenze: Eskalation darunter fragt nach, '
      'die Unterhaltung bleibt privat', () async {
    await setUpEnv(
      phala: [
        ScriptedTurn.error(const RateLimitException('voll')),
        ScriptedTurn.error(const RateLimitException('voll')),
      ],
      claude: [ScriptedTurn.text('Erledigt.')],
    );
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send('Privat: erinnere mich an den Arzttermin');
    final asking = await waitFor(c, (s) => s.pending != null);
    final q = asking.pending! as EscalationQuestion;
    expect(q.fromName, 'Phala GLM');
    expect(q.toName, 'Claude API');
    expect(llm['claude']!.requests, isEmpty, reason: 'erst nach Zustimmung');
    // Die Anfrage ist schon mit Untergrenze gespeichert: Hinweis „privat“.
    final private = await waitFor(c, (s) => s.privateSince != null);
    expect(private.privateSince, testNow);
    expect(private.privateByRequest, isTrue);

    controller.answer(approved: false);
    await controller.idle;
    expect(llm['claude']!.requests, isEmpty, reason: '„Nein“ gilt');
    expect(c.read(agentControllerProvider).privateSince, testNow);

    // „Neues Gespräch“ beendet den privaten Zustand.
    await controller.newTopic();
    expect(c.read(agentControllerProvider).privateSince, isNull);
  });

  group('Gedächtnis je Ziel (Review WP26)', () {
    /// A memory entry; sensitive integrations (memory) only for TEE and
    /// better, as the user set it in „Datenschutz“.
    Future<void> remember() async {
      await c
          .read(toolPrefsProvider.notifier)
          .set(const ToolPrefs(sensitiveMinimum: PrivacyLevel.tee));
      await env.storage.memory.save(
        'Mag Tee mit Pfefferminz',
        category: StoredMemoryCategory.preference,
        source: 'user',
      );
    }

    test('Standard-Ziel bekommt kein Gedächtnis, TEE-Ziel schon und die '
        'Unterhaltung wird vertraulich', () async {
      await setUpEnv(
        phala: [ScriptedTurn.text('Pfefferminz.')],
        claude: [ScriptedTurn.text('Weiß ich nicht.')],
      );
      await remember();
      var s = await send('Claude, welchen Tee mag ich?');
      expect(
        llm['claude']!.requests.single.systemPrompt,
        isNot(contains('Pfefferminz')),
      );
      expect(s.privateSince, isNull);

      await c.read(agentControllerProvider.notifier).newTopic();
      s = await send('Welchen Tee mag ich?');
      expect(
        llm['phala']!.requests.single.systemPrompt,
        contains('Pfefferminz'),
      );
      final ready = await waitFor(c, (s) => s.privateSince != null);
      expect(ready.privateByRequest, isFalse, reason: 'nur Gedächtnis');
    });

    test('Sitzungsende setzt „Unterhaltung privat“ zurück', () async {
      await setUpEnv(
        phala: [ScriptedTurn.text('Pfefferminz.')],
        claude: const [],
      );
      await remember();
      await send('Welchen Tee mag ich?');
      await waitFor(c, (s) => s.privateSince != null);
      c.read(sessionManagerProvider).end();
      expect(c.read(agentControllerProvider).privateSince, isNull);
      expect(c.read(agentControllerProvider).privateByRequest, isFalse);
    });
  });
}
