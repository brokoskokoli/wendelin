import 'package:timezone/timezone.dart' as tz;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/time.dart' show timeZoneLocation;
import '../common/tool_args.dart';
import 'weather_model.dart';
import 'weather_service.dart';
import 'weather_text.dart';

/// Weather and sea state: `weather__forecast`, `weather__marine` (both
/// read). The place comes from the question, else from the current location
/// ([location], WP86), else from the home place ([home]).
final class WeatherIntegration implements Integration {
  /// Creates the integration.
  WeatherIntegration({
    required this.service,
    required this.marine,
    required this.geocoder,
    this.home,
    this.location,
  });

  /// Id of the setup step for the home place.
  static const homeStep = 'home_place';

  /// Forecast service chosen in the settings.
  final WeatherService service;

  /// Sea state service.
  final MarineService marine;

  /// Place name to coordinates.
  final Geocoder geocoder;

  /// Fallback place from the settings.
  final Place? home;

  /// Current location, if a location integration provides it.
  final WeatherLocationPort? location;

  @override
  String get id => 'weather';

  @override
  String get displayName => 'Wetter und Meer';

  @override
  String get iconId => 'weather';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  @override
  bool get sensitive => false;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: homeStep,
      kind: SetupStepKind.config,
      label: 'Heimatort und Wetterdienst wählen',
      optional: true,
    ),
  ];

  @override
  Future<SetupState> setupState() async =>
      SetupState(missingSteps: [if (home == null) homeStep]);

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    WeatherForecastTool(this),
    WeatherMarineTool(this),
  ]);

  /// The place for a question: [name] if given, else current, else home.
  Future<Place> resolvePlace(String? name, ToolContext ctx) async {
    if (name != null && name.trim().isNotEmpty) {
      final found = await geocoder.find(
        name,
        language: ctx.locale.split('-').first,
        cancel: ctx.cancel,
      );
      if (found == null) {
        throw PortException(
          PortErrorKind.notFound,
          'Ort „${ellipsize(name.trim(), 40)}“ nicht gefunden',
        );
      }
      return found;
    }
    Place? here;
    try {
      here = await location?.currentPlace(
        cancel: ctx.cancel,
        level: ctx.privacyLevel,
      );
    } on PortException {
      // Permission revoked or no fix: fall back to the home place.
      here = null;
    }
    if (here != null) return here;
    if (home != null) return home!;
    throw const PortException(
      PortErrorKind.notFound,
      'Kein Ort bekannt: nach dem Ort fragen oder in den Einstellungen '
      '(Wetter und Meer) einen Heimatort festlegen',
    );
  }

  WeatherRequest _request(Place place, ToolContext ctx, int days, int hours) {
    tz.Location zone;
    try {
      zone = timeZoneLocation(place.timeZone ?? ctx.timeZone);
    } on InvalidArgumentsException {
      zone = timeZoneLocation(ctx.timeZone);
    }
    return WeatherRequest(
      place: place,
      zone: zone,
      now: ctx.clock.now(),
      days: days,
      hours: hours,
      cancel: ctx.cancel,
    );
  }
}

const _placeProperty = {
  'type': 'string',
  'description':
      'Place name, e.g. "Hamburg". Leave out for the current location or the '
      'home place.',
};

/// `weather__forecast` (read).
final class WeatherForecastTool extends IntegrationTool {
  /// Creates the tool.
  const WeatherForecastTool(this.integration);

  /// Owner.
  final WeatherIntegration integration;

  @override
  String get name => 'weather__forecast';

  @override
  String get description =>
      'Weather now, hourly and for the next days: temperature, rain, wind. '
      'Example: place "Kiel", days 2, hours 6 for "Wie wird das Wetter in '
      'Kiel heute Nachmittag?". Without place the current location or the '
      'home place is used.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'place': _placeProperty,
      'days': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 7,
        'description': 'Days from today (default 2: today and tomorrow).',
      },
      'hours': {
        'type': 'integer',
        'minimum': 0,
        'maximum': 24,
        'description': 'Hourly outlook for the next hours (default 0).',
      },
    },
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final days = args.optInt('days', min: 1, max: 7) ?? 2;
    final hours = args.optInt('hours', min: 0, max: 24) ?? 0;
    try {
      final place = await integration.resolvePlace(
        args.optString('place'),
        ctx,
      );
      final request = integration._request(place, ctx, days, hours);
      final report = await integration.service.forecast(request);
      return ToolOutcome.text(
        describeForecast(report, request),
        summary: 'Wetter: ${ellipsize(place.name, 40)}',
      );
    } on CancelledException {
      return ToolOutcome.cancelled();
    }
  }

  @override
  String describe(ToolArgs args) =>
      'Wetter abfragen: ${args.optString('place') ?? 'aktueller Ort'}';

  @override
  String get fallbackDescription => 'Wetter abfragen';
}

/// `weather__marine` (read).
final class WeatherMarineTool extends IntegrationTool {
  /// Creates the tool.
  const WeatherMarineTool(this.integration);

  /// Owner.
  final WeatherIntegration integration;

  @override
  String get name => 'weather__marine';

  @override
  String get description =>
      'Sea state: wave height, swell, period, water temperature (Open-Meteo '
      'Marine). Example: place "Palma". Only for places at the sea.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'place': _placeProperty,
      'days': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 7,
        'description': 'Days from today (default 2).',
      },
    },
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final days = args.optInt('days', min: 1, max: 7) ?? 2;
    try {
      final place = await integration.resolvePlace(
        args.optString('place'),
        ctx,
      );
      final request = integration._request(place, ctx, days, 0);
      final report = await integration.marine.marine(request);
      return ToolOutcome.text(
        describeMarine(report, request),
        summary: 'Meer: ${ellipsize(place.name, 40)}',
      );
    } on CancelledException {
      return ToolOutcome.cancelled();
    }
  }

  @override
  String describe(ToolArgs args) =>
      'Seegang abfragen: ${args.optString('place') ?? 'aktueller Ort'}';

  @override
  String get fallbackDescription => 'Seegang abfragen';
}
