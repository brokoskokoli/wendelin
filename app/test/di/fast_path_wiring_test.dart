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

final class _Coffee implements FastPath {
  @override
  Future<FastPathCall?> match(String text, {required String? language}) async =>
      text == 'Kaffeemaschine an'
      ? const FastPathCall(tool: 'smart__set', arguments: {'on': true})
      : null;
}

FakeIntegration _i(String id, {bool sensitive = false}) => FakeIntegration(
  id: id,
  sensitive: sensitive,
  tools: [
    FakeTool(
      name: '${id}__set',
      confirmationKeys: const {'flashlight.on'},
      outcome: ToolOutcome.text(
        'ok',
        fixed: const ConfirmationSentence('flashlight.on'),
      ),
    ),
    FakeTool(name: '${id}__b'),
  ],
);

/// WP135 D: the fast path does not depend on the tool preselection (topic
/// words): in meta-tool mode a tool the request does not name is still
/// callable, so „Kaffeemaschine an“ works without a type word.
void main() {
  Future<(List<AgentEvent>, FakeLlmProvider)> run(
    String text, {
    required PrivacyLevel level,
    FastPath? fastPath,
    bool smartEnabled = true,
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
    for (final i in [_i('alarms'), _i('weather'), _i('maps')]) {
      await registry.registerIntegration(i, enabled: true);
    }
    await registry.registerIntegration(
      _i('smart', sensitive: true),
      enabled: smartEnabled,
    );
    addTearDown(registry.dispose);
    final provider = FakeLlmProvider([ScriptedTurn.text('Das Modell.')]);
    final factory = AgentFactory(
      registry: registry,
      storage: storage,
      policy: RiskPolicy(),
      audit: AuditRecorder(storage.audit, clock: const SystemClock()),
      clock: const SystemClock(),
      device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
      costEstimator: const FlatCostEstimator(),
      budgetGuard: FixedBudgetGuard(),
      fastPath: fastPath,
    );
    final events = await factory
        .create(
          ProviderConfig(
            primary: ProviderTarget(
              profileId: 'p',
              modelId: 'm',
              provider: provider,
              privacy: level,
            ),
          ),
          session.id,
        )
        .run(UserInput(text: text, language: 'de'))
        .toList();
    return (events, provider);
  }

  test(
    'Name ohne Typwort, Tool nicht vorausgewählt: Schnellweg, kein Modell',
    () async {
      final (events, provider) = await run(
        'Kaffeemaschine an',
        level: PrivacyLevel.tee,
        fastPath: _Coffee(),
      );
      expect(provider.requests, isEmpty);
      expect((events.last as AgentDone).fixed, isTrue);
    },
  );

  test('Standard-Ziel sieht die sensible Integration nicht: Modell', () async {
    final (events, provider) = await run(
      'Kaffeemaschine an',
      level: PrivacyLevel.standard,
      fastPath: _Coffee(),
    );
    expect(provider.requests, hasLength(1));
    expect((events.last as AgentDone).fixed, isFalse);
  });

  test('Integration abgeschaltet: Modell', () async {
    final (_, provider) = await run(
      'Kaffeemaschine an',
      level: PrivacyLevel.tee,
      fastPath: _Coffee(),
      smartEnabled: false,
    );
    expect(provider.requests, hasLength(1));
  });

  test('Schnellweg aus (null): Modell', () async {
    final (_, provider) = await run(
      'Kaffeemaschine an',
      level: PrivacyLevel.tee,
    );
    expect(provider.requests, hasLength(1));
  });
}
