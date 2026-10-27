import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/tool_args.dart';
import '../location/location_port.dart';
import '../location/location_tools.dart';
import '../location/maps_intents.dart';

/// `maps__navigate` (write): navigation in Google Maps.
final class MapsNavigateTool extends IntegrationTool
    implements TrustedContentSource, NoNetworkTarget, WorksOnlyUnlocked {
  /// Creates the tool.
  const MapsNavigateTool(this.launcher);

  /// Starts map apps.
  final MapsLauncherPort launcher;

  @override
  String get name => 'maps__navigate';

  @override
  String get description =>
      'Start navigation to a destination in Google Maps (turn-by-turn for '
      'car, walking and bicycle; the route page for public transport).';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{
      'destination': destinationProperty,
      'mode': modeProperty,
    },
    'required': <String>['destination'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final destination = requireDestination(args);
    final mode = readMode(args);
    await launcher.launch(
      MapsIntents.navigate(destination, mode: mode, googleMaps: true),
    );
    return ToolOutcome.text(
      'Google Maps ist geöffnet.',
      summary: 'Navigation gestartet',
    );
  }

  // The audit log stores confirmation texts: no destination in it.
  @override
  String describe(ToolArgs args) => 'Navigation in Google Maps starten';

  @override
  String get fallbackDescription => 'Navigation in Google Maps starten';
}

/// `maps__search_place` (read): opens a search in Google Maps. The result
/// is only visible on screen, the model gets no place data back.
final class MapsSearchPlaceTool extends IntegrationTool
    implements TrustedContentSource, NoNetworkTarget, WorksOnlyUnlocked {
  /// Creates the tool.
  const MapsSearchPlaceTool(this.launcher);

  /// Starts map apps.
  final MapsLauncherPort launcher;

  @override
  String get name => 'maps__search_place';

  @override
  String get description =>
      'Open a search in Google Maps for a place, business or category '
      '(e.g. "pharmacy nearby"). The results are shown on the phone; you '
      'get no place data back.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{
      'query': {
        'type': 'string',
        'description': 'What to search for: place, address or category.',
        'maxLength': 200,
      },
    },
    'required': <String>['query'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final query = args.requireString('query');
    if (query.length > 200) {
      throw const InvalidArgumentsException('„query“ ist zu lang');
    }
    await launcher.launch(MapsIntents.search(query, googleMaps: true));
    return ToolOutcome.text(
      'Die Suche läuft in Google Maps; die Treffer sind auf dem Display '
      'zu sehen.',
      summary: 'Suche in Google Maps geöffnet',
    );
  }

  @override
  String describe(ToolArgs args) => 'In Google Maps suchen';

  @override
  String get fallbackDescription => 'In Google Maps suchen';
}
