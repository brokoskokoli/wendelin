import 'package:wendelin_core/wendelin_core.dart';

import '../common/app_presence.dart';
import '../weather/weather_service.dart';
import 'location_port.dart';
import 'location_tools.dart';

/// Location and navigation: `location__current`, `location__navigate_to`,
/// `location__distance_to`.
final class LocationIntegration implements Integration {
  /// Creates the integration. [geocoder] resolves place names for
  /// `location__distance_to` (optional).
  LocationIntegration(this.port, this.launcher, this.apps, {this.geocoder});

  /// The device position.
  final LocationPort port;

  /// Starts map apps.
  final MapsLauncherPort launcher;

  /// Installed-app check (Google Maps).
  final AppPresencePort apps;

  /// Place search for `location__distance_to`.
  final Geocoder? geocoder;

  /// Id of the permission setup step.
  static const permissionStep = 'location_permission';

  @override
  String get id => 'location';

  @override
  String get displayName => 'Standort';

  @override
  String get iconId => 'location';

  @override
  Set<AppPlatform> get platforms => const {AppPlatform.android};

  /// Where the user is, is personal; the tools are only sent to providers
  /// meeting the privacy level.
  @override
  bool get sensitive => true;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: permissionStep,
      kind: SetupStepKind.permission,
      label: 'Standortzugriff erlauben',
    ),
  ];

  @override
  Future<SetupState> setupState() async => SetupState(
    missingSteps: [if (!await port.hasPermission()) permissionStep],
  );

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    LocationCurrentTool(port),
    LocationNavigateToTool(launcher, apps),
    LocationDistanceToTool(port, geocoder),
  ]);
}
