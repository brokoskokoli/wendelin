import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin/app.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/platform_ports.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/fakes.dart';

import 'fake_microphone.dart';
import 'fake_speech_models.dart';

/// Fixed „now“ of the tests: Tuesday, 13 Oct 2026, 08:12 local time.
final testNow = DateTime(2026, 10, 13, 8, 12);

/// Fakes and overrides for app tests: in-memory database and secrets,
/// fake ports, fixed clock, optional scripted provider.
final class TestEnv {
  /// Creates the environment.
  TestEnv({
    this.providerConfig,
    this.providerConfigError,
    this.demo = false,
    this.realDemoPorts = false,
    this.llmFactory,
    this.storedProfiles = false,
    this.extraOverrides = const [],
    StartupSettings? startup,
    this._storage,
    Set<String> enabled = const {
      'calendar',
      'clipboard',
      'alarms',
      'memory',
      'web',
    },
  }) : startup =
           startup ??
           StartupSettings(enabledIntegrations: enabled, demoMode: demo);

  /// Further overrides (e.g. the exporter).
  final List<Override> extraOverrides;

  /// Reads the provider configuration from the stored profiles (with
  /// [llmFactory]) instead of [providerConfig].
  final bool storedProfiles;

  /// Clock of all components.
  final clock = FixedClock(testNow);

  /// Local database.
  late final WendelinStorage storage =
      _storage ?? openInMemoryStorage(clock: clock);
  final WendelinStorage? _storage;

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

  /// List files (handle → content).
  final listFiles = FakeListFilePort();

  /// Speech model downloads (WP17).
  final speechModels = FakeSpeechModelService();

  /// Microphone (permission granted unless a test changes it).
  final microphone = FakePcmRecorder();

  /// System speech output.
  final systemTts = FakeTextToSpeech();

  /// Offline speech output (sherpa-onnx).
  final sherpaTts = FakeTextToSpeech();

  /// Obsidian vault (used once a vault is chosen in the settings).
  final vault = FakeVaultPort();

  /// Obsidian search index.
  final notes = FakeNoteIndex();

  /// Builds the adapter for stored profiles; `null` = real adapters.
  final LlmProviderFactory? llmFactory;

  /// Calendar permission requests.
  int permissionRequests = 0;

  /// Settings at start.
  final StartupSettings startup;

  /// Provider configuration (`null` = none set up, unless [demo]).
  final ProviderConfig? providerConfig;

  /// Loading the provider configuration fails with this, if set.
  final Object? providerConfigError;

  /// Demo mode.
  final bool demo;

  /// Uses the app's own in-memory demo ports instead of this environment's.
  final bool realDemoPorts;

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
    devicePortsProvider.overrideWith(
      (ref) => PlatformPorts(
        calendar: calendar,
        clipboard: clipboard,
        alarms: alarms,
        memory: memory,
        requestCalendarPermission: ports.requestCalendarPermission,
        lists: ListsPorts(
          port: listFiles,
          definitions: () => ref.read(listDefinitionsProvider),
        ),
        obsidian: ObsidianPorts(
          vault: vault,
          index: notes,
          hasVault: () => ref.read(obsidianPrefsProvider).hasVault,
          settings: () =>
              obsidianSettingsOf(ref.read(obsidianPrefsProvider), 'de'),
        ),
      ),
    ),
    if (llmFactory case final f?)
      llmProviderFactoryProvider.overrideWithValue(f),
    if (!realDemoPorts) demoPortsProvider.overrideWithValue(ports),
    deviceInfoProvider.overrideWithValue(
      const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
    ),
    if (!storedProfiles)
      storedProviderConfigProvider.overrideWith(
        (ref) async => providerConfigError == null
            ? providerConfig
            : throw providerConfigError!,
      ),
    speechModelServiceProvider.overrideWith((ref) async => speechModels),
    microphoneProvider.overrideWithValue(microphone),
    systemTtsProvider.overrideWithValue(systemTts),
    sherpaTtsProvider.overrideWithValue(sherpaTts),
    ...extraOverrides,
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
  bool Function(UserInput)? isPrivate,
}) => ProviderConfig(
  primary: ProviderTarget(
    profileId: id,
    modelId: 'claude-haiku-4-5',
    provider: provider,
    privacy: privacy,
  ),
  chain: chain,
  names: {id: name, ...names},
  isPrivate: isPrivate,
);

/// „Zahnarzt Dr. Weber“, Do 15.10.2026 08:30–09:15 (Berlin), in „privat“.
CalendarEventDraft zahnarztDraft() => CalendarEventDraft(
  calendarId: 'privat',
  title: 'Zahnarzt Dr. Weber',
  start: DateTime.utc(2026, 10, 15, 6, 30),
  end: DateTime.utc(2026, 10, 15, 7, 15),
  timeZone: 'Europe/Berlin',
);

/// Tool call block with JSON arguments.
ToolCallBlock call(String id, String name, String argumentsJson) =>
    ToolCallBlock(id: id, name: name, argumentsJson: argumentsJson);
