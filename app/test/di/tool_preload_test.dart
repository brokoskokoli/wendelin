import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/agent_factory.dart';
import 'package:wendelin/di/audit_recorder.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin_agent/testing.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

FakeIntegration _i(String id, {bool sensitive = false}) => FakeIntegration(
  id: id,
  sensitive: sensitive,
  tools: [
    FakeTool(name: '${id}__a', description: 'Tool a'),
    FakeTool(name: '${id}__b', description: 'Tool b'),
  ],
);

/// WP119: the tools of the integrations a request names are offered with the
/// first model call, without `tools__search` first.
void main() {
  late FakeLlmProvider provider;

  Future<List<String>> firstCallTools(
    String text, {
    required PrivacyLevel level,
    String? language,
  }) async {
    final storage = openInMemoryStorage();
    addTearDown(storage.close);
    final session = await storage.conversations.startNew(
      DateTime(2026, 10, 21),
    );
    final registry = ToolRegistry(
      metaToolThreshold: 3,
      sensitiveMinimum: PrivacyLevel.tee,
    );
    for (final i in [
      _i('alarms'),
      _i('weather'),
      _i('maps'),
      _i('calendar', sensitive: true),
    ]) {
      await registry.registerIntegration(i, enabled: true);
    }
    addTearDown(registry.dispose);
    provider = FakeLlmProvider([ScriptedTurn.text('ok')]);
    final factory = AgentFactory(
      registry: registry,
      storage: storage,
      policy: RiskPolicy(),
      audit: AuditRecorder(storage.audit, clock: const SystemClock()),
      clock: const SystemClock(),
      device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
      costEstimator: const FlatCostEstimator(),
      budgetGuard: FixedBudgetGuard(),
    );
    final run = factory.create(
      ProviderConfig(
        primary: ProviderTarget(
          profileId: 'p',
          modelId: 'm',
          provider: provider,
          privacy: level,
        ),
      ),
      session.id,
    );
    final events = await run
        .run(UserInput(text: text, language: language))
        .toList();
    expect(events.last, isA<AgentDone>(), reason: '$events');
    return [for (final t in provider.requests.first.tools) t.name];
  }

  test(
    '„Stell mir einen Wecker um 7“: erster Aufruf enthält alarms__*',
    () async {
      final tools = await firstCallTools(
        'Stell mir einen Wecker um 7',
        level: PrivacyLevel.local,
      );
      expect(tools, containsAll(['alarms__a', 'alarms__b']));
      expect(tools, contains(ToolSearchTool.toolName));
      expect(tools.where((n) => n.startsWith('weather')), isEmpty);
    },
  );

  test('Sprache der Anfrage zählt: französisch', () async {
    final tools = await firstCallTools(
      'Mets un réveil à sept heures',
      level: PrivacyLevel.local,
      language: 'fr',
    );
    expect(tools, contains('alarms__a'));
  });

  test('unerkannte Anfrage: nur die Suche', () async {
    final tools = await firstCallTools(
      'Erzähl mir einen Witz',
      level: PrivacyLevel.local,
    );
    expect(tools, [ToolSearchTool.toolName]);
  });

  test('Datenschutz: sensitive Tools nicht vorab für Standardstufe', () async {
    final tools = await firstCallTools(
      'Was steht im Kalender, und stell einen Wecker',
      level: PrivacyLevel.standard,
    );
    expect(tools, contains('alarms__a'));
    expect(tools.where((n) => n.startsWith('calendar')), isEmpty);
  });

  test('Datenschutz: sensitive Tools vorab für TEE', () async {
    final tools = await firstCallTools(
      'Was steht im Kalender?',
      level: PrivacyLevel.tee,
    );
    expect(tools, contains('calendar__a'));
  });
}
