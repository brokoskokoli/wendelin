import 'package:wendelin_core/wendelin_core.dart';

import '../location/location_port.dart';
import 'maps_tools.dart';
import 'waze_integration.dart';

/// Google Maps adapter: `maps__navigate`, `maps__search_place`. Works over
/// the installed app only (no API key); the app registry keeps it inactive
/// while Google Maps is missing (`KnownApps.googleMaps`).
///
/// `maps__route_info` (distance and duration of a route) is left out: it
/// needs the Directions API and with it an API key.
final class MapsIntegration implements Integration {
  /// Creates the integration.
  MapsIntegration(this.launcher, this.navigate);

  /// Starts map apps.
  final MapsLauncherPort launcher;

  /// `maps__navigate`; the same instance as in [WazeIntegration], so the
  /// registry offers it once while either integration is on.
  final MapsNavigateTool navigate;

  @override
  String get id => 'maps';

  @override
  String get displayName => 'Google Maps';

  @override
  String get iconId => 'maps';

  @override
  Set<AppPlatform> get platforms => const {AppPlatform.android};

  /// The tools only open the app; no position or place goes into a result.
  @override
  bool get sensitive => false;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [];

  @override
  Future<SetupState> setupState() async => SetupState(missingSteps: const []);

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    navigate,
    MapsSearchPlaceTool(launcher),
  ]);
}
