import 'package:http/http.dart' as http;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../platform/platform_ports.dart';
import 'app_requirements.dart';

/// What an integration needs to be built.
final class IntegrationDeps {
  /// Creates the dependencies.
  const IntegrationDeps({
    required this.ports,
    required this.device,
    required this.httpClient,
    this.webSearch,
    this.bringApi,
    this.bringSecrets,
    this.reportError,
    this.clearError,
  });

  /// Device ports (real or demo).
  final PlatformPorts ports;

  /// Locale and time zone.
  final DeviceInfo device;

  /// Shared HTTP client (web fetch).
  final http.Client httpClient;

  /// Configured search service; `null` = only `web__fetch`.
  final WebSearchBackend? webSearch;

  /// Bring! API client; `null` = no Bring! (demo mode).
  final BringApi? bringApi;

  /// Where the Bring! login and session live.
  final BringSecrets? bringSecrets;

  /// Puts the integration `id` into the error state (tools paused).
  final void Function(String id, String message)? reportError;

  /// Clears the error state of the integration `id`.
  final void Function(String id)? clearError;
}

/// „Erneut versuchen“ of an integration in the error state: [label] on the
/// tile, [run] returns `null` on success or a German message.
typedef IntegrationRetry = ({
  String label,
  Future<String?> Function(Integration integration) run,
});

/// Registration of one integration in the app: how to build it, how to
/// ask for its permission when the user enables it, and what to do when a
/// session ends.
///
/// This is the extension point for further integrations (e.g. WP12 lists):
/// add a spec to [builtInIntegrationSpecs] (and a port to [PlatformPorts]
/// if it needs device access). Registry, activation, session end and the
/// settings list pick it up from there. Integrations that use another app
/// name it in [requiredApp] (and its package in `<queries>`). User-defined
/// integrations (MCP, HTTP tools) come from a `UserIntegrationSource`
/// instead (ADR 0012).
final class IntegrationSpec {
  /// Creates a spec.
  const IntegrationSpec({
    required this.id,
    required this.create,
    this.requestPermission,
    this.onSessionEnd,
    this.isSupported,
    this.permissionRationale,
    this.requiredApp,
    this.retry,
  });

  /// Integration id (must match `Integration.id`).
  final String id;

  /// Builds the integration.
  final Integration Function(IntegrationDeps deps) create;

  /// Requests the OS permission when the user enables the integration;
  /// `null` if none is needed. Returns whether it was granted.
  final Future<bool> Function(IntegrationDeps deps)? requestPermission;

  /// Called with the built integration when a session ends.
  final void Function(Integration integration)? onSessionEnd;

  /// Explanation shown before [requestPermission] asks the OS.
  final String? permissionRationale;

  /// Whether the integration can be built with [IntegrationDeps] (e.g. its
  /// port exists); `null` = always.
  final bool Function(IntegrationDeps deps)? isSupported;

  /// The app the integration uses, if any: without a needed app it is
  /// „nicht verfügbar“, an optional one only adds a hint (WP25).
  final AppRequirement? requiredApp;

  /// Action of the tile in the error state instead of „Neu anmelden“
  /// (gets the unwrapped integration).
  final IntegrationRetry? retry;
}

/// The built-in integrations of M1, in display order.
final builtInIntegrationSpecs = <IntegrationSpec>[
  IntegrationSpec(
    id: 'calendar',
    create: (d) => CalendarIntegration(
      d.ports.calendar,
      deviceTimeZone: () => d.device.timeZone,
    ),
    requestPermission: (d) async =>
        await d.ports.requestCalendarPermission?.call() ?? true,
    permissionRationale:
        'Wendelin braucht Zugriff auf deine Kalender, um Termine zu lesen, '
        'anzulegen und zu ändern. Android fragt dich gleich danach. Löschen '
        'fragt Wendelin immer vorher nach.',
  ),
  IntegrationSpec(
    id: 'clipboard',
    create: (d) => ClipboardIntegration(d.ports.clipboard),
  ),
  IntegrationSpec(
    id: 'alarms',
    create: (d) => AlarmsIntegration(d.ports.alarms),
  ),
  IntegrationSpec(
    id: 'memory',
    create: (d) => MemoryIntegration(d.ports.memory),
  ),
  IntegrationSpec(
    id: 'web',
    // Without a search service only `web__fetch` is offered (settings →
    // Web-Suche configures one).
    create: (d) => WebIntegration(
      fetcher: WebFetcher(client: d.httpClient),
      searchBackend: d.webSearch,
    ),
  ),
  IntegrationSpec(
    id: 'obsidian',
    // Device: SAF vault; until a folder is chosen (Einstellungen →
    // Obsidian) it shows „Einrichtung nötig“. Demo: in-memory vault.
    isSupported: (d) => d.ports.obsidian != null,
    // The vault is a folder; the app only opens notes (obsidian:// links).
    requiredApp: KnownApps.obsidian.optional(
      'Obsidian-App fehlt: Öffnen in Obsidian geht nicht',
    ),
    create: (d) {
      final o = d.ports.obsidian!;
      return ObsidianIntegration(
        o.vault,
        o.index,
        settings: o.settings,
        openUri: o.openUri,
        indexer: o.indexer,
      );
    },
  ),
  IntegrationSpec(
    id: 'bring',
    // Unofficial API with the user's account (Einstellungen → Bring!); the
    // app is only the fallback for sharing items when the API fails.
    isSupported: (d) => d.bringApi != null && d.bringSecrets != null,
    requiredApp: KnownApps.bring.optional(
      'Bring!-App fehlt: kein Ausweg über „Teilen“',
    ),
    create: (d) => BringIntegration(
      d.bringApi!,
      d.bringSecrets!,
      onError: (message) => d.reportError?.call('bring', '$message · pausiert'),
      onRecovered: () => d.clearError?.call('bring'),
    ),
    retry: (
      label: 'Erneut versuchen',
      run: (i) async => i is BringIntegration
          ? i.reconnect()
          : 'Bring! ist nicht eingerichtet.',
    ),
  ),
  IntegrationSpec(
    id: 'lists',
    // Device: SAF files picked in settings → Listen; demo: in memory.
    isSupported: (d) => d.ports.lists != null,
    create: (d) => ListsIntegration(
      d.ports.lists!.port,
      definitions: d.ports.lists!.definitions,
    ),
  ),
];
