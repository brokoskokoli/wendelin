import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin/app.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/platform/platform_ports.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Fixed „now“ of the tests: Tuesday, 13 Oct 2026, 08:12 local time.
final testNow = DateTime(2026, 10, 13, 8, 12);

/// Fakes and overrides for app tests: in-memory database and secrets,
/// fake ports, fixed clock, optional scripted provider.
final class TestEnv {
  /// Creates the environment.
  TestEnv({
    this.providerConfig,
    this.demo = false,
    Set<String> enabled = const {
      'calendar',
      'clipboard',
      'alarms',
      'memory',
      'web',
    },
  }) : startup = StartupSettings(enabledIntegrations: enabled, demoMode: demo);

  /// Clock of all components.
  final clock = FixedClock(testNow);

  /// Local database.
  late final WendelinStorage storage = openInMemoryStorage(clock: clock);

  /// Secrets.
  final secrets = InMemorySecretStore();

  /// Device calendar.
  final calendar = FakeCalendarPort();

  /// Clipboard.
  final clipboard = FakeClipboardPort();

  /// Alarms.
  final alarms = FakeAlarmPort();

  /// Memory.
  final memory = FakeMemoryStore();

  /// Calendar permission requests.
  int permissionRequests = 0;

  /// Settings at start.
  final StartupSettings startup;

  /// Provider configuration (`null` = none set up, unless [demo]).
  final ProviderConfig? providerConfig;

  /// Demo mode.
  final bool demo;

  /// The device ports.
  late final ports = PlatformPorts(
    calendar: calendar,
    clipboard: clipboard,
    alarms: alarms,
    memory: memory,
    requestCalendarPermission: () async {
      permissionRequests++;
      return calendar.permissionGranted = true;
    },
  );

  /// Overrides for a `ProviderScope`/`ProviderContainer`.
  List<Override> get overrides => [
    clockProvider.overrideWithValue(clock),
    storageProvider.overrideWithValue(storage),
    secretStoreProvider.overrideWithValue(secrets),
    startupProvider.overrideWithValue(startup),
    devicePortsProvider.overrideWithValue(ports),
    deviceInfoProvider.overrideWithValue(
      const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
    ),
    if (!demo)
      providerConfigProvider.overrideWith((ref) async => providerConfig),
  ];

  /// A container with [overrides].
  ProviderContainer container() =>
      ProviderContainer(overrides: overrides, retry: (_, _) => null);

  /// The app in a `ProviderScope`.
  Widget app({Widget? home}) => ProviderScope(
    overrides: overrides,
    retry: (_, _) => null,
    child: home == null ? const WendelinApp() : WendelinApp(home: home),
  );
}

/// A configuration with one scripted target.
ProviderConfig scripted(
  FakeLlmProvider provider, {
  String id = 'claude',
  String name = 'Claude Haiku',
  PrivacyLevel privacy = PrivacyLevel.standard,
  List<ProviderTarget> chain = const [],
  Map<String, String> names = const {},
}) => ProviderConfig(
  primary: ProviderTarget(
    profileId: id,
    modelId: 'claude-haiku-4-5',
    provider: provider,
    privacy: privacy,
  ),
  chain: chain,
  names: {id: name, ...names},
);

/// Tool call block with JSON arguments.
ToolCallBlock call(String id, String name, String argumentsJson) =>
    ToolCallBlock(id: id, name: name, argumentsJson: argumentsJson);
