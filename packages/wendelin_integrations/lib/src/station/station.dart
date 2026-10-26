import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';

/// Starts the station mode (WP99): a full-screen clock and info display over
/// the lock screen. Must pass `stationPortContract`.
abstract interface class StationPort {
  /// Whether the device shows the lock screen right now.
  Future<bool> isLocked();

  /// Opens the station. The mode ends only by the button „Beenden“ after
  /// unlocking; there is no counterpart to this call on purpose (K62/K63).
  Future<void> start();
}

/// Station integration: only `station__start`. No tool ends the mode, and
/// the integration does not run while the device is locked (spec flag).
final class StationIntegration implements Integration {
  /// Creates the integration on [port].
  StationIntegration(this.port);

  /// Device side.
  final StationPort port;

  @override
  String get id => 'station';

  @override
  String get displayName => 'Stationsmodus';

  @override
  String get iconId => 'station';

  @override
  Set<AppPlatform> get platforms => const {AppPlatform.android};

  /// The tool carries no personal data.
  @override
  bool get sensitive => false;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [];

  @override
  Future<SetupState> setupState() async => SetupState();

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    StationStartTool(port),
  ]);
}

/// `station__start` (write): opens the station mode on an unlocked device.
final class StationStartTool extends IntegrationTool
    implements TrustedContentSource, FixedConfirmationTool, NoNetworkTarget {
  /// Creates the tool.
  const StationStartTool(this.port);

  /// Device side.
  final StationPort port;

  @override
  String get name => 'station__start';

  @override
  String get description =>
      'Start the station mode (clock, date, weather and next appointments '
      'full screen while the phone charges). It cannot be ended by voice.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Set<String> get confirmationKeys => const {'station.started'};

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    if (await port.isLocked()) {
      throw const PortException(
        PortErrorKind.unavailable,
        'Der Stationsmodus startet nur bei entsperrtem Telefon.',
      );
    }
    await port.start();
    return ToolOutcome.text(
      'Der Stationsmodus ist an. Beenden geht nur am Bildschirm nach dem '
      'Entsperren.',
      summary: 'Stationsmodus gestartet',
      fixed: const ConfirmationSentence('station.started'),
    );
  }

  @override
  String describe(ToolArgs args) => 'Stationsmodus starten';

  @override
  String get fallbackDescription => describe(const ToolArgs({}));
}
