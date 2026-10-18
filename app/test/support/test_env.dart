import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin/app.dart';
import 'package:wendelin/di/app_requirements.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/platform/channel_notifier.dart';
import 'package:wendelin/platform/platform_ports.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/fakes.dart';

import 'env/core_overrides.dart';
import 'env/integration_overrides.dart';
import 'env/provider_overrides.dart';
import 'env/voice_overrides.dart';
import 'fake_microphone.dart';

/// The M2 key `routing.escalationChain`. The app no longer reads it (K28);
/// tests store values under it to see that they have no effect.
final legacyEscalationChain = SettingKey<Object>(
  'routing.escalationChain',
  encode: (v) => v,
  decode: (json) => json!,
);

/// Fixed „now“ of the tests: Tuesday, 13 Oct 2026, 08:12 local time.
final testNow = DateTime(2026, 10, 13, 8, 12);

/// Fakes and overrides for app tests: in-memory database and secrets,
/// fake ports, fixed clock, optional scripted provider.
final class TestEnv {
  /// Creates the environment.
  TestEnv({
    this.providerConfig,
    this.providerConfigError,
    this.attestationCryptoError,
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

  /// Flashlight.
  final torch = FakeTorchPort();

  /// Alarms.
  final alarms = FakeAlarmPort();

  /// Memory.
  final memory = FakeMemoryStore();

  /// Installed apps (all known apps unless a test removes one).
  final apps = FakeAppPresencePort(
    installed: [for (final app in KnownApps.all) app.androidPackage],
  );

  /// List files (handle → content).
  final listFiles = FakeListFilePort();

  /// Speech model downloads (WP17).
  final speechModels = FakeSpeechModelService();

  /// Microphone (permission granted unless a test changes it).
  final microphone = FakePcmRecorder();

  /// System speech output.
  final systemTts = FakeTextToSpeech();

  /// Offline speech output (sherpa-onnx).
  var sherpaTts = FakeTextToSpeech();

  /// Obsidian vault (used once a vault is chosen in the settings).
  final vault = FakeVaultPort();

  /// Obsidian search index.
  final notes = FakeNoteIndex();

  /// Bring! account (no request ever goes to the real API in tests).
  final bring = FakeBringApi();

  /// Home Assistant (no request ever goes to a real instance in tests).
  final ha = FakeHaApi();

  /// Instances the mDNS search finds.
  final haDiscovery = FakeHaDiscovery();

  /// Spotify account, login browser and app launcher (WP84).
  final spotify = FakeSpotifyApi();

  /// Login page of Spotify: answers the redirect at once.
  final spotifyBrowser = FakeSpotifyAuthBrowser();

  /// Wakes the Spotify app.
  final spotifyLauncher = FakeSpotifyLauncher();

  /// Texts shared with other apps (package, text).
  final shared = <(String, String)>[];

  /// Connectivity for the routing condition `network`.
  final network = FixedNetworkStatus();

  /// System notifications (failed GPU check): the texts shown.
  final notifier = RecordingNotifier();

  /// Builds the adapter for stored profiles; `null` = real adapters.
  final LlmProviderFactory? llmFactory;

  /// Calendar permission requests.
  int permissionRequests = 0;

  /// Settings at start.
  final StartupSettings startup;

  /// Provider configuration (`null` = none set up, unless [demo]).
  final ProviderConfig? providerConfig;

  /// Loading the TEE check module fails with this, if set.
  final Object? attestationCryptoError;

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
    apps: apps,
    torch: torch,
    requestCalendarPermission: () async {
      permissionRequests++;
      return calendar.permissionGranted = true;
    },
  );

  /// Overrides for a `ProviderScope`/`ProviderContainer`, built per area
  /// (`env/`).
  List<Override> get overrides => [
    ...coreOverrides(this),
    ...withIntegrations(this),
    ...withProviders(this),
    ...withVoice(this),
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
  List<ProviderTarget> others = const [],
  Map<String, String> names = const {},
  bool Function(UserInput)? isPrivate,
}) => ProviderConfig(
  primary: ProviderTarget(
    profileId: id,
    modelId: 'claude-haiku-4-5',
    provider: provider,
    privacy: privacy,
    name: name,
  ),
  others: others,
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

/// [AttestationNotifier] that records the notifications.
final class RecordingNotifier implements AttestationNotifier {
  /// Notifications shown, as (title, text).
  final shown = <(String, String)>[];

  /// Whether the permission is granted.
  bool granted = true;

  /// Number of permission requests.
  int permissionRequests = 0;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted = true;
  }

  /// What the next [takeLaunchTarget] returns (once).
  String? launchTarget;

  @override
  Future<String?> takeLaunchTarget() async {
    final t = launchTarget;
    launchTarget = null;
    return t;
  }

  @override
  Future<bool> show({required String title, required String text}) async {
    if (!granted) return false;
    shown.add((title, text));
    return true;
  }
}
