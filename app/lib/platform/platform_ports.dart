import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../di/app_requirements.dart';
import '../di/app_settings.dart';
import '../di/preference_models.dart';
import 'android_alarm_port.dart';
import 'channel_app_presence_port.dart';
import 'channel_location_port.dart';
import 'channel_media_control_port.dart';
import 'channel_torch_port.dart';
import 'device_calendar_port.dart';
import 'flutter_clipboard_port.dart';
import 'repository_memory_port.dart';
import 'repository_note_index_port.dart';
import 'saf_list_file_port.dart';
import 'saf_vault_port.dart';

/// The device ports the built-in integrations run on.
///
/// New integrations with device access (e.g. WP12 lists with a
/// `ListFilePort`) add their port here and in [PlatformPorts.device]
/// / [PlatformPorts.demo], then register an `IntegrationSpec`.
final class PlatformPorts {
  /// Creates the bundle.
  const PlatformPorts({
    required this.calendar,
    required this.clipboard,
    required this.alarms,
    required this.memory,
    required this.apps,
    required this.torch,
    this.requestCalendarPermission,
    this.lists,
    this.obsidian,
    this.media,
    this.location,
    this.mapsLauncher,
  });

  /// Real device ports (Android): calendar channel, system clipboard,
  /// `AlarmClock` intents, memory in the local database.
  factory PlatformPorts.device(
    WendelinStorage storage, {
    required List<ListDefinition> Function() listDefinitions,
    ObsidianPrefs Function() obsidian = _noVault,
    String Function() language = _german,
  }) {
    final calendar = DeviceCalendarPort(
      preferredCalendar: () =>
          storage.settings.get(AppSettings.defaultCalendarId),
    );
    return PlatformPorts(
      calendar: calendar,
      clipboard: const FlutterClipboardPort(),
      alarms: const AndroidAlarmPort(),
      memory: RepositoryMemoryPort(storage.memory),
      apps: const ChannelAppPresencePort(),
      torch: const ChannelTorchPort(),
      media: const ChannelMediaControlPort(),
      location: const ChannelLocationPort(),
      mapsLauncher: const ChannelMapsLauncherPort(),
      requestCalendarPermission: calendar.requestPermission,
      lists: ListsPorts(port: SafListFilePort(), definitions: listDefinitions),
      obsidian: ObsidianPorts(
        vault: SafVaultPort(tree: () => obsidian().vaultUri),
        index: RepositoryNoteIndexPort(storage.notes),
        hasVault: () => obsidian().hasVault,
        settings: () => obsidianSettingsOf(obsidian(), language()),
        openUri: launchObsidianUri,
      ),
    );
  }

  static ObsidianPrefs _noVault() => const ObsidianPrefs();
  static String _german() => 'de';

  /// In-memory ports for the demo mode: nothing touches the device (all
  /// known apps count as installed).
  factory PlatformPorts.demo() => PlatformPorts(
    calendar: FakeCalendarPort(),
    clipboard: FakeClipboardPort(),
    alarms: FakeAlarmPort(),
    memory: FakeMemoryStore(),
    apps: FakeAppPresencePort(
      installed: [for (final app in KnownApps.all) app.androidPackage],
    ),
    torch: FakeTorchPort(),
    media: FakeMediaControlPort(
      snapshot: const MediaSnapshot(
        packageName: audiblePackage,
        appName: 'Audible',
        playing: true,
        title: 'Demo-Hörbuch',
        positionMs: 600000,
        durationMs: 3600000,
      ),
    ),
    location: FakeLocationPort(),
    mapsLauncher: FakeMapsLauncherPort(),
    lists: ListsPorts.demo(),
    obsidian: ObsidianPorts.demo(),
  );

  /// Device calendar.
  final CalendarPort calendar;

  /// System clipboard.
  final ClipboardPort clipboard;

  /// Alarm clock and timers.
  final AlarmPort alarms;

  /// Long-term memory.
  final MemoryStorePort memory;

  /// Which other apps are installed (app detection, WP25).
  final AppPresencePort apps;

  /// Flash LED as a flashlight.
  final TorchPort torch;

  /// Asks for calendar access; `null` if the port needs none.
  final Future<bool> Function()? requestCalendarPermission;

  /// List files and definitions; `null` = no lists on this platform.
  final ListsPorts? lists;

  /// Obsidian vault and search index; `null` = not on this platform.
  final ObsidianPorts? obsidian;

  /// Media sessions and media keys; `null` = not on this platform.
  final MediaControlPort? media;

  /// Device position (WP86); `null` = not on this platform.
  final LocationPort? location;

  /// Starts map apps (WP86); `null` = not on this platform.
  final MapsLauncherPort? mapsLauncher;
}

/// Vault, search index and settings of the Obsidian integration.
final class ObsidianPorts {
  /// Creates the bundle; one [NoteIndexer] is shared by the integration
  /// and the background index build.
  ObsidianPorts({
    required this.vault,
    required this.index,
    required this.hasVault,
    required this.settings,
    this.openUri,
  }) : indexer = NoteIndexer(vault, index);

  /// In-memory vault „Demo“ with a few notes for the demo mode.
  factory ObsidianPorts.demo() => ObsidianPorts(
    vault: FakeVaultPort(
      files: {
        'Wendelin.md': '# Wendelin\n\n## Ideen\n\n- Sprachsteuerung\n',
        'Projekte/Garten.md': '# Garten\n\n## Todo\n\n- Beet umgraben\n',
      },
    ),
    index: FakeNoteIndex(),
    hasVault: () => true,
    settings: () => const ObsidianSettings(vaultName: 'Demo'),
  );

  /// The vault (SAF tree on Android).
  final VaultPort vault;

  /// Full-text index (SQLite FTS5).
  final NoteIndexPort index;

  /// Keeps [index] in step with [vault].
  final NoteIndexer indexer;

  /// Whether a vault folder is chosen (the integration exists only then).
  final bool Function() hasVault;

  /// Current settings (vault name, daily notes, language).
  final ObsidianSettings Function() settings;

  /// Opens `obsidian://` links.
  final OpenUri? openUri;
}

/// [ObsidianSettings] from the stored [prefs] and the app [language].
ObsidianSettings obsidianSettingsOf(ObsidianPrefs prefs, String language) =>
    ObsidianSettings(
      vaultName: prefs.hasVault ? prefs.vaultName ?? 'Vault' : null,
      dailyNotes: prefs.dailyNotes,
      locale: switch (language) {
        'fr' || 'en' => language,
        _ => 'de',
      },
    );

/// Opens an `obsidian://` link in the Obsidian app (`ACTION_VIEW`).
Future<void> launchObsidianUri(Uri uri) async {
  try {
    await AndroidIntent(action: 'action_view', data: uri.toString()).launch();
  } on PlatformException {
    throw const PortException(
      PortErrorKind.unavailable,
      'Obsidian ist auf diesem Gerät nicht installiert.',
    );
  }
}

/// Opens [url] in the browser or the app that handles it (`ACTION_VIEW`),
/// e.g. the download page of a missing app.
Future<void> openExternalUrl(Uri url) async {
  try {
    await AndroidIntent(action: 'action_view', data: url.toString()).launch();
  } on PlatformException {
    throw const PortException(
      PortErrorKind.unavailable,
      'Keine App zum Öffnen der Adresse gefunden.',
    );
  } on UnsupportedError {
    throw const PortException(
      PortErrorKind.unsupported,
      'Adressen lassen sich hier nicht öffnen.',
    );
  }
}

/// File port and list definitions of the lists integration.
final class ListsPorts {
  /// Creates the bundle.
  const ListsPorts({required this.port, required this.definitions});

  /// In-memory lists „Einkaufen“ and „SmartSSH“ for the demo mode.
  factory ListsPorts.demo() {
    final definitions = [
      ListDefinition(
        id: 'einkaufen',
        name: 'Einkaufen',
        aliases: const ['Einkaufsliste'],
        target: 'demo://Listen/Einkaufen.md',
      ),
      ListDefinition(
        id: 'smartssh',
        name: 'SmartSSH',
        target: 'demo://Projekte/SmartSSH.md',
        section: 'Todo',
      ),
    ];
    return ListsPorts(
      port: FakeListFilePort(
        files: {
          'demo://Listen/Einkaufen.md':
              '# Einkaufen\n\n- [ ] Milch\n- [x] Brot\n',
          'demo://Projekte/SmartSSH.md':
              '# SmartSSH\n\n## Todo\n\n- [ ] Release-Notizen\n',
        },
      ),
      definitions: () => definitions,
    );
  }

  /// Reads and writes the Markdown files.
  final ListFilePort port;

  /// The user's lists.
  final List<ListDefinition> Function() definitions;
}
