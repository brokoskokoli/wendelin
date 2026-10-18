import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/test_env.dart';

/// Provider only the probe integration depends on.
final _probeGreetingProvider = Provider<String>((ref) => 'hallo');

/// A new integration as a spec in its own file would be: its own provider
/// (via [IntegrationSpec.prepare]), no change to `IntegrationDeps`.
final _probeSpec = IntegrationSpec(
  id: 'probe',
  prepare: (ref) => ref.watch(_probeGreetingProvider),
  isSupported: (d) => d.extra<String>('probe') != null,
  create: (d) => FakeIntegration(
    id: 'probe',
    displayName: d.extra<String>('probe')!,
    tools: [FakeTool(name: 'probe__ping', risk: RiskLevel.read)],
  ),
);

void main() {
  test('Reihenfolge der eingebauten Integrationen (UI und Tool-Katalog)', () {
    expect(
      [for (final s in builtInIntegrationSpecs) s.id],
      [
        'calendar',
        'clipboard',
        'alarms',
        'flashlight',
        'memory',
        'web',
        'obsidian',
        'bring',
        'lists',
        'ha',
      ],
    );
  });

  test('Probe: neue Integration braucht nur die Registry-Zeile', () {
    final env = TestEnv(enabled: const {'probe'});
    final c = ProviderContainer(
      overrides: [
        ...env.overrides,
        // The one shared line: `probeSpec` in `integrations/registry.dart`.
        integrationSpecsProvider.overrideWithValue([
          ...builtInIntegrationSpecs,
          _probeSpec,
        ]),
        _probeGreetingProvider.overrideWithValue('probe-welt'),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    final integrations = c.read(integrationsProvider);
    expect(integrations['probe']!.displayName, 'probe-welt');
    expect(integrations.keys.last, 'probe');
    expect(
      c.read(toolRegistryProvider).integrations.map((i) => i.id),
      contains('probe'),
    );
  });

  test('ohne prepare-Wert ist die Probe nicht unterstützt', () {
    final spec = IntegrationSpec(
      id: 'probe',
      isSupported: (d) => d.extra<String>('probe') != null,
      create: (_) => throw StateError('nicht gebaut'),
    );
    final env = TestEnv();
    final c = ProviderContainer(
      overrides: [
        ...env.overrides,
        integrationSpecsProvider.overrideWithValue([spec]),
      ],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    expect(c.read(integrationsProvider), isEmpty);
  });
}
