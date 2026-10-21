// WP122: every template key a tool may use exists in all languages, and
// every tool with fixed confirmations is covered by this check.
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _clientId = '0123456789abcdef0123456789abcdef';

/// Every integration that has tools with fixed confirmations, built with
/// fakes.
List<Integration> _integrations() {
  final todoistApi = FakeTodoistApi();
  final googleApi = FakeGoogleTasksApi();
  final bringApi = FakeBringApi();
  final files = FakeListFilePort(files: {'l.md': ''});
  final definitions = [
    ListDefinition(
      id: 'a',
      name: 'Aufgaben',
      target: 'l.md',
      taskDefault: true,
    ),
  ];
  return [
    FlashlightIntegration(FakeTorchPort()),
    AlarmsIntegration(FakeAlarmPort()),
    StationIntegration(FakeStationPort()),
    MemoryIntegration(FakeMemoryStore()),
    ContactsIntegration(FakeContactsPort(), FakePhonePort()),
    CalendarIntegration(FakeCalendarPort()),
    MediaIntegration(FakeMediaControlPort(), FakeAppPresencePort()),
    ListsIntegration(files, definitions: () => definitions),
    TasksIntegration(files, definitions: () => definitions),
    BringIntegration(bringApi, FakeBringSecrets()),
    TodoistIntegration(todoistApi, todoistApi),
    GoogleTasksIntegration(googleApi, googleApi, googleApi),
    SpotifyIntegration(
      FakeSpotifyApi(),
      FakeSpotifySecrets(storedClientId: _clientId),
      launcher: FakeSpotifyLauncher(),
    ),
    HaIntegration(
      FakeHaApi(),
      FakeHaSecrets(const HaEndpoint(url: 'http://10.0.0.2:8123', token: 't')),
      FakeHaEntityStore(const []),
    ),
    ObsidianIntegration(
      FakeVaultPort(),
      FakeNoteIndex(),
      settings: () => const ObsidianSettings(vaultName: 'V'),
    ),
  ];
}

void main() {
  final tools = [
    for (final i in _integrations())
      for (final t in i.tools)
        if (t is FixedConfirmationTool) t,
  ];

  test('alle Tools mit festen Sätzen sind erfasst', () {
    expect(
      {for (final t in tools) t.name},
      {
        'flashlight__on',
        'flashlight__off',
        'flashlight__toggle',
        'alarms__set_alarm',
        'alarms__set_timer',
        'station__start',
        'memory__save',
        'sms__compose',
        'phone__call',
        'calendar__create_event',
        'media__play',
        'media__pause',
        'media__next',
        'media__previous',
        'lists__add_items',
        'lists__complete_item',
        'tasks__add',
        'tasks__complete',
        'bring__add_items',
        'bring__complete_item',
        'todoist__add',
        'todoist__complete',
        'gtasks__add',
        'gtasks__complete',
        'spotify__play',
        'spotify__pause',
        'spotify__next',
        'spotify__previous',
        'ha__call',
        'obsidian__create_note',
        'obsidian__append_to_note',
        'obsidian__append_daily_note',
      },
    );
  });

  group('Schlüssel in allen Sprachen', () {
    for (final t in tools) {
      test(t.name, () {
        final keys = (t as FixedConfirmationTool).confirmationKeys;
        expect(keys, isNotEmpty);
        for (final entry in confirmationLanguages.entries) {
          for (final key in keys) {
            expect(
              entry.value.templates,
              contains(key),
              reason: '${t.name}: „$key“ fehlt in ${entry.key}',
            );
          }
        }
      });
    }
  });
}
