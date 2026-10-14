import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/agent_factory.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/routing.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/test_env.dart';

ProviderProfile _profile(
  String id, {
  PrivacyLevel privacy = PrivacyLevel.standard,
  ProviderType type = ProviderType.anthropic,
}) => ProviderProfile(
  id: id,
  name: 'Profil $id',
  type: privacy == PrivacyLevel.tee ? ProviderType.openaiCompatible : type,
  defaultModel: 'model-$id',
  privacy: privacy,
  authMethod: ApiKeyAuth('provider.$id'),
  // „TEE“ counts only for profiles the app attests.
  baseUrl: privacy == PrivacyLevel.tee ? 'https://api.redpill.ai/v1' : null,
  options: privacy == PrivacyLevel.tee
      ? const {'attestation': 'phala'}
      : const {},
);

/// Storage as M2 left it: profiles, a default profile and the global
/// escalation chain (`routing.escalationChain`, ignored now), no rules yet.
Future<WendelinStorage> _m2Storage({
  required List<ProviderProfile> profiles,
  required String defaultId,
  List<String> chain = const [],
}) async {
  final storage = openInMemoryStorage(clock: FixedClock(testNow));
  for (final p in profiles) {
    await storage.providerProfiles.save(p);
  }
  await storage.providerProfiles.setDefault(defaultId);
  await storage.settings.set(legacyEscalationChain, chain);
  return storage;
}

void main() {
  final providers = <String, FakeLlmProvider>{};
  Future<ProviderConfig?> load(
    WendelinStorage storage, {
    NetworkStatus? network,
  }) => loadProviderConfig(
    storage: storage,
    secrets: InMemorySecretStore(),
    catalog: ModelCatalog.builtIn(),
    create: (p, _) => switch (p.type) {
      // Like a profile without base URL: cannot be built.
      ProviderType.openaiCompatible when p.baseUrl == null =>
        throw ArgumentError('baseUrl'),
      _ => providers.putIfAbsent(p.id, () => FakeLlmProvider(const [])),
    },
    clock: FixedClock(testNow),
    network: network,
  );

  group('Migration der M2-Einstellungen', () {
    test('die alte globale Kette hat keine Wirkung (K28), Verhalten wie '
        'DefaultProviderResolver ohne Kette', () async {
      final storage = await _m2Storage(
        profiles: [
          _profile('local', privacy: PrivacyLevel.local),
          _profile('cloud'),
          _profile('kaputt', type: ProviderType.openaiCompatible),
        ],
        defaultId: 'local',
        chain: ['local', 'weg', 'kaputt', 'cloud'],
      );
      final config = (await load(storage))!;

      final rules = (await storage.settings.get(RoutingSettings.rules))!;
      expect(rules, config.routing!.rules, reason: 'einmalig gespeichert');
      expect(rules.defaultTarget.profileId, 'local');
      expect(rules.rules.map((r) => r.id), [privateRuleId]);
      expect(config.primary.profileId, 'local');
      expect(config.chain.map((t) => t.profileId), ['cloud']);
      expect(config.nameOf('cloud'), 'Profil cloud');
      expect(config.lowestPrivacy, PrivacyLevel.standard);

      // Vergleich mit dem M2-Resolver (privat = Schlüsselwort „privat“).
      final m2 = DefaultProviderResolver(
        config.primary,
        isPrivate: (i) => i.text.toLowerCase().contains('privat'),
      );
      final m3 = config.resolver();
      expect(m3, isA<RuleBasedProviderResolver>());
      for (final text in [
        'Wie spät ist es?',
        'Privat: wie geht es Anna?',
        'Das bleibt bitte privat.',
      ]) {
        final input = UserInput(text: text);
        final a = m2.resolve(input);
        final b = m3.resolve(input);
        expect(b.profileId, a.profileId, reason: text);
        expect(b.modelId, a.modelId, reason: text);
        expect(b.privacyFloor, a.privacyFloor, reason: text);
        // Nothing follows on its own, whatever the old chain said.
        expect(m2.escalate(a, EscalationReason.userRequested), isNull);
        expect(m3.escalate(b, EscalationReason.userRequested), isNull);
      }
    });

    test('Privat-Regel zielt auf den Standard, wenn er TEE oder lokal ist', () {
      final def = _profile('phala', privacy: PrivacyLevel.tee);
      final rule = privatePresetRule([_profile('a'), def], def);
      expect(rule.id, privateRuleId);
      expect(rule.enabled, isTrue);
      expect(rule.isPrivate, isTrue);
      expect(rule.target.profileId, 'phala');
      expect(rule.condition, PrivacyCondition());
    });

    test('sonst auf das erste Profil ab TEE', () {
      final def = _profile('cloud');
      final rule = privatePresetRule([
        def,
        _profile('eu', privacy: PrivacyLevel.eu),
        _profile('ollama', privacy: PrivacyLevel.local),
        _profile('phala', privacy: PrivacyLevel.tee),
      ], def);
      expect(rule.enabled, isTrue);
      expect(
        rule.target,
        const RouteTarget(profileId: 'ollama', modelId: 'model-ollama'),
      );
    });

    test('ohne Profil ab TEE: ausgeschaltet, mit Hinweis', () async {
      final storage = await _m2Storage(
        profiles: [
          _profile('cloud'),
          _profile('eu', privacy: PrivacyLevel.eu),
        ],
        defaultId: 'cloud',
      );
      final rules = (await loadRuleSet(storage))!;
      final privat = rules.rules.single;
      expect(privat.enabled, isFalse);
      expect(privat.target.profileId, 'cloud');
      final issues = RoutingState(
        rules: rules,
        profiles: await storage.providerProfiles.list(),
      ).issues;
      expect(issues.single.kind, RuleSetIssueKind.privacyTargetTooWeak);
      // Ausgeschaltet: „privat“ ändert nichts am Ziel (wie in M2).
      final config = (await load(storage))!;
      final r = config.resolver().resolve(UserInput(text: 'privat: x'));
      expect(r.profileId, 'cloud');
      expect(r.privacyFloor, isNull);
    });

    test('ohne Standardprofil: kein Regelsatz, nichts gespeichert', () async {
      final storage = openInMemoryStorage();
      await storage.providerProfiles.save(_profile('a'));
      expect(await loadRuleSet(storage), isNull);
      expect(await load(storage), isNull);
      expect(await storage.settings.get(RoutingSettings.rules), isNull);
    });
  });

  group('loadRuleSet', () {
    test('migriert nur einmal, folgt danach dem Standardprofil', () async {
      final storage = await _m2Storage(
        profiles: [_profile('a'), _profile('b')],
        defaultId: 'a',
        chain: ['b'],
      );
      final first = (await loadRuleSet(storage))!;
      await storage.settings.set(legacyEscalationChain, ['x']);
      expect(await loadRuleSet(storage), first, reason: 'keine 2. Migration');

      await storage.providerProfiles.setDefault('b');
      final moved = (await loadRuleSet(storage))!;
      expect(
        moved.defaultTarget,
        const RouteTarget(profileId: 'b', modelId: 'model-b'),
      );
      expect(await storage.settings.get(RoutingSettings.rules), moved);
    });

    test('unlesbarer Regelsatz: Fehler statt stiller Standard', () async {
      final storage = await _m2Storage(
        profiles: [_profile('a')],
        defaultId: 'a',
      );
      await storage.settings.set(SettingKey.json('routing.rules'), {
        'schemaVersion': 99,
      });
      await expectLater(loadRuleSet(storage), throwsFormatException);
      await expectLater(load(storage), throwsFormatException);
    });

    test('nicht baubares Standardprofil wirft', () async {
      final storage = await _m2Storage(
        profiles: [_profile('x', type: ProviderType.openaiCompatible)],
        defaultId: 'x',
      );
      await expectLater(load(storage), throwsArgumentError);
    });
  });

  test(
    'neues Standardmodell eines Profils: Ziele mit dem alten folgen',
    () async {
      final storage = await _m2Storage(
        profiles: [_profile('a'), _profile('b')],
        defaultId: 'a',
        chain: ['b'],
      );
      final rules = (await loadRuleSet(storage))!;
      await storage.settings.set(
        RoutingSettings.rules,
        rules.copyWith(
          rules: [
            RoutingRule(
              id: 'x',
              name: 'X',
              condition: KeywordCondition(['x']),
              target: const RouteTarget(profileId: 'a', modelId: 'model-a'),
            ),
            RoutingRule(
              id: 'y',
              name: 'Y',
              condition: KeywordCondition(['y']),
              target: const RouteTarget(profileId: 'a', modelId: 'gewaehlt'),
            ),
          ],
        ),
      );
      await followDefaultModel(
        storage,
        profileId: 'a',
        from: 'model-a',
        to: 'neu',
      );
      await followDefaultModel(
        storage,
        profileId: 'b',
        from: 'model-b',
        to: 'model-b',
      );
      final now = (await storage.settings.get(RoutingSettings.rules))!;
      expect(now.defaultTarget.modelId, 'neu');
      expect(now.rules.map((r) => r.target.modelId), ['neu', 'gewaehlt']);
    },
  );

  test('Regel „offline“ greift mit dem Netzstatus des Ports', () async {
    final storage = await _m2Storage(
      profiles: [
        _profile('cloud'),
        _profile('ollama', privacy: PrivacyLevel.local),
      ],
      defaultId: 'cloud',
    );
    final rules = (await loadRuleSet(storage))!;
    await storage.settings.set(
      RoutingSettings.rules,
      rules.copyWith(
        rules: [
          RoutingRule(
            id: 'offline',
            name: 'Offline',
            condition: const NetworkCondition(NetworkState.offline),
            target: const RouteTarget(
              profileId: 'ollama',
              modelId: 'model-ollama',
            ),
          ),
        ],
      ),
    );
    final network = FixedNetworkStatus();
    final config = (await load(storage, network: network))!;
    final input = UserInput(text: 'Wie wird das Wetter?');
    expect(config.resolver().resolve(input).profileId, 'cloud');
    network.current = NetworkState.offline;
    final offline = config.resolver().resolve(input);
    expect(offline.profileId, 'ollama');
    expect(offline.reason, 'Offline');
  });

  test('Standardziel nutzt das Modell der Regeln, nicht nur das des '
      'Profils', () async {
    final storage = await _m2Storage(profiles: [_profile('a')], defaultId: 'a');
    final rules = (await loadRuleSet(storage))!;
    await storage.settings.set(
      RoutingSettings.rules,
      rules.copyWith(
        defaultTarget: const RouteTarget(profileId: 'a', modelId: 'gross'),
      ),
    );
    final config = (await load(storage))!;
    expect(config.primary.modelId, 'gross');
    expect(
      config.resolver().resolve(UserInput(text: 'hallo')).modelId,
      'gross',
    );
  });

  test('Hinweis auf die Regel „Privat“ nur, wenn sie aktiv wird', () async {
    final on = await _m2Storage(
      profiles: [
        _profile('a'),
        _profile('p', privacy: PrivacyLevel.tee),
      ],
      defaultId: 'a',
    );
    await loadRuleSet(on);
    expect(
      await on.settings.get(RoutingSettings.privateRuleNotice),
      'Profil p',
    );
    final off = await _m2Storage(profiles: [_profile('a')], defaultId: 'a');
    await loadRuleSet(off);
    expect(await off.settings.get(RoutingSettings.privateRuleNotice), isNull);
  });

  test('memoryFloorOf: niedrigste Stufe mit memory__search', () {
    final memory = FakeToolCatalog([FakeTool(name: 'memory__search')]);
    final none = FakeToolCatalog(const []);
    ToolCatalog Function(PrivacyLevel) from(PrivacyLevel min) =>
        (level) => level.isAtLeast(min) ? memory : none;
    expect(memoryFloorOf(from(PrivacyLevel.standard)), isNull);
    expect(memoryFloorOf(from(PrivacyLevel.eu)), PrivacyLevel.eu);
    expect(memoryFloorOf(from(PrivacyLevel.tee)), PrivacyLevel.tee);
    expect(memoryFloorOf(from(PrivacyLevel.local)), PrivacyLevel.local);
    expect(memoryFloorOf((_) => none), PrivacyLevel.tee);
  });

  test('ProviderConfig ohne Regeln bleibt beim DefaultProviderResolver', () {
    final config = ProviderConfig.demo(FixedClock(testNow));
    expect(config.routing, isNull);
    expect(config.resolver(), isA<DefaultProviderResolver>());
  });
}
