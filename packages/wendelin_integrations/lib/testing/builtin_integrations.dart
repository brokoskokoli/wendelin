/// The built-in integrations wired to fakes, each with the trust
/// classification (WP41, fail-closed) of its own tools. Tests that walk "all
/// integrations" (schemas, trust table) take this list, so a new integration
/// adds one entry here and no line in those tests.
library;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../alarm.dart';
import '../bring.dart';
import '../calendar.dart';
import '../clipboard.dart';
import '../fakes.dart';
import '../flashlight.dart';
import '../home_assistant.dart';
import '../lists.dart';
import '../memory.dart';
import '../obsidian.dart';
import '../spotify.dart';
import '../weather.dart';
import '../web.dart';

/// An integration plus, per tool name, whether the tool is a
/// `TrustedContentSource` (successful result contains only own data).
final class IntegrationFixture {
  /// Creates a fixture.
  const IntegrationFixture(this.integration, this.trusted);

  /// The integration wired to fakes.
  final Integration integration;

  /// Tool name -> result is trusted. Must list exactly the integration's tools.
  final Map<String, bool> trusted;
}

/// Every built-in integration with fakes, in a stable order. Add a new
/// integration here (one entry) together with its trust classification.
List<IntegrationFixture> builtInIntegrationsWithFakes() => [
  IntegrationFixture(CalendarIntegration(FakeCalendarPort()), {
    'calendar__list_calendars': false,
    'calendar__list_events': false,
    'calendar__find_free_slots': false,
    'calendar__update_event': false,
    'calendar__delete_event': false,
    'calendar__create_event': true,
  }),
  IntegrationFixture(ClipboardIntegration(FakeClipboardPort()), {
    'clipboard__read': false,
    'clipboard__write': true,
  }),
  IntegrationFixture(FlashlightIntegration(FakeTorchPort()), {
    'flashlight__on': true,
    'flashlight__off': true,
    'flashlight__toggle': true,
  }),
  IntegrationFixture(AlarmsIntegration(FakeAlarmPort()), {
    'alarms__list': false,
    'alarms__set_alarm': true,
    'alarms__set_timer': true,
  }),
  IntegrationFixture(MemoryIntegration(FakeMemoryStore()), {
    'memory__search': false,
    'memory__save': true,
    'memory__forget': true,
  }),
  IntegrationFixture(
    ListsIntegration(FakeListFilePort(), definitions: () => []),
    {
      'lists__list_lists': false,
      'lists__get_items': false,
      'lists__complete_item': false,
      'lists__remove_item': false,
      'lists__clear_completed': false,
      'lists__add_items': true,
    },
  ),
  IntegrationFixture(
    TasksIntegration(FakeListFilePort(), definitions: () => []),
    {'tasks__add': true, 'tasks__list': false, 'tasks__complete': false},
  ),
  IntegrationFixture(
    ObsidianIntegration(
      FakeVaultPort(),
      FakeNoteIndex(),
      settings: () => const ObsidianSettings(),
    ),
    {
      'obsidian__search_notes': false,
      'obsidian__read_note': false,
      'obsidian__list_folder': false,
      'obsidian__open_note': false,
      'obsidian__create_note': false,
      'obsidian__append_to_note': false,
      'obsidian__append_daily_note': false,
      'obsidian__replace_section': false,
    },
  ),
  IntegrationFixture(
    WebIntegration(
      searchBackend: FakeWebSearchBackend(),
      fetcher: WebFetcher(
        client: MockClient((_) async => http.Response('', 200)),
      ),
    ),
    {'web__search': false, 'web__fetch': false},
  ),
  IntegrationFixture(BringIntegration(FakeBringApi(), FakeBringSecrets()), {
    'bring__list_lists': false,
    'bring__get_items': false,
    'bring__add_items': false,
    'bring__remove_item': false,
    'bring__complete_item': false,
  }),
  IntegrationFixture(
    HaIntegration(FakeHaApi(), FakeHaSecrets(), FakeHaEntityStore()),
    {
      'ha__list_entities': false,
      'ha__state': false,
      'ha__call': false,
      'ha__call_secure': false,
    },
  ),
  IntegrationFixture(
    SpotifyIntegration(FakeSpotifyApi(), FakeSpotifySecrets()),
    {
      'spotify__search': false,
      'spotify__now_playing': false,
      'spotify__play': false,
      'spotify__pause': false,
      'spotify__queue_add': false,
      'spotify__next': true,
      'spotify__previous': true,
    },
  ),
  IntegrationFixture(
    WeatherIntegration(
      service: FakeWeatherService(),
      marine: FakeMarineService(),
      geocoder: FakeGeocoder(const []),
    ),
    {'weather__forecast': false, 'weather__marine': false},
  ),
];
