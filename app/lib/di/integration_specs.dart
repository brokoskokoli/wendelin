import 'package:http/http.dart' as http;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../platform/platform_ports.dart';

/// What an integration needs to be built.
final class IntegrationDeps {
  /// Creates the dependencies.
  const IntegrationDeps({
    required this.ports,
    required this.device,
    required this.httpClient,
  });

  /// Device ports (real or demo).
  final PlatformPorts ports;

  /// Locale and time zone.
  final DeviceInfo device;

  /// Shared HTTP client (web fetch).
  final http.Client httpClient;
}

/// Registration of one integration in the app: how to build it, how to
/// ask for its permission when the user enables it, and what to do when a
/// session ends.
///
/// This is the extension point for further integrations (e.g. WP12 lists):
/// add a spec to [builtInIntegrationSpecs] (and a port to [PlatformPorts]
/// if it needs device access). Registry, activation, session end and the
/// settings list pick it up from there.
final class IntegrationSpec {
  /// Creates a spec.
  const IntegrationSpec({
    required this.id,
    required this.create,
    this.requestPermission,
    this.onSessionEnd,
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
    onSessionEnd: (i) => (i as CalendarIntegration).clearCache(),
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
    // Without a configured search service only `web__fetch` is offered;
    // WP09 adds the service setup.
    create: (d) => WebIntegration(fetcher: WebFetcher(client: d.httpClient)),
  ),
];
