import 'package:wendelin_core/wendelin_core.dart';

import 'maps_tools.dart';

/// Waze as a second navigation app. It has no tools of its own: it adds
/// the app option to `maps__navigate` (the same tool instance as in
/// `MapsIntegration`). Works over the installed app only (no key, no
/// account); the app registry keeps it inactive while Waze is missing
/// (`KnownApps.waze`).
final class WazeIntegration implements Integration {
  /// Creates the integration.
  WazeIntegration(this.navigate);

  /// `maps__navigate`, shared with `MapsIntegration`.
  final MapsNavigateTool navigate;

  @override
  String get id => 'waze';

  @override
  String get displayName => 'Waze';

  @override
  String get iconId => 'maps';

  @override
  Set<AppPlatform> get platforms => const {AppPlatform.android};

  /// The tool only opens the app; no position goes into a result.
  @override
  bool get sensitive => false;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [];

  @override
  Future<SetupState> setupState() async => SetupState(missingSteps: const []);

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[navigate]);
}
