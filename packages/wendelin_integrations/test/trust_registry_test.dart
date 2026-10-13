// WP41 (fail-closed): every shipped tool is classified on purpose. Only a
// tool whose successful result contains nothing but own data (a confirmation
// of what was just set or saved) is a TrustedContentSource; everything else
// switches the invisible `<spoken>` text off. A new tool that is not in the
// table turns this test red.
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'http_tools/support.dart' as http_support;

/// Tool name -> result is trusted (own data only).
const _trusted = <String, bool>{
  // Reading foreign or stored text.
  'calendar__list_calendars': false,
  'calendar__list_events': false, // invitations from third parties
  'calendar__find_free_slots': false,
  'clipboard__read': false,
  'alarms__list': false,
  'memory__search': false,
  'web__search': false,
  'web__fetch': false,
  'lists__list_lists': false,
  'lists__get_items': false,
  'obsidian__search_notes': false,
  'obsidian__read_note': false,
  'obsidian__list_folder': false,
  'obsidian__open_note': false,
  'bring__list_lists': false,
  'bring__get_items': false,
  // Writes that echo stored or foreign text.
  'calendar__update_event': false,
  'calendar__delete_event': false,
  'lists__complete_item': false,
  'lists__remove_item': false,
  'lists__clear_completed': false,
  'obsidian__create_note': false,
  'obsidian__append_to_note': false,
  'obsidian__append_daily_note': false,
  'obsidian__replace_section': false,
  'bring__add_items': false,
  'bring__remove_item': false,
  'bring__complete_item': false,
  // Confirmations of what the user just asked for.
  'calendar__create_event': true,
  'clipboard__write': true,
  'alarms__set_alarm': true,
  'alarms__set_timer': true,
  'memory__save': true,
  'memory__forget': true,
  'lists__add_items': true,
};

void main() {
  final integrations = <Integration>[
    CalendarIntegration(FakeCalendarPort()),
    ClipboardIntegration(FakeClipboardPort()),
    AlarmsIntegration(FakeAlarmPort()),
    MemoryIntegration(FakeMemoryStore()),
    ListsIntegration(FakeListFilePort(), definitions: () => []),
    ObsidianIntegration(
      FakeVaultPort(),
      FakeNoteIndex(),
      settings: () => const ObsidianSettings(),
    ),
    WebIntegration(
      searchBackend: FakeWebSearchBackend(),
      fetcher: WebFetcher(
        client: MockClient((_) async => http.Response('', 200)),
      ),
    ),
    BringIntegration(FakeBringApi(), FakeBringSecrets()),
  ];
  final tools = [for (final i in integrations) ...i.tools];

  test('jedes ausgelieferte Tool steht in der Tabelle und stimmt', () {
    expect(tools.map((t) => t.name).toSet(), _trusted.keys.toSet());
    for (final t in tools) {
      expect(
        t is TrustedContentSource,
        _trusted[t.name],
        reason: '${t.name}: Einstufung (vertrauenswürdig) weicht ab',
      );
    }
  });

  test('HTTP-Tools sind nie vertrauenswürdig', () {
    final h = http_support.mockRunner((_) async => http.Response('', 200));
    final tool = HttpTool(http_support.def(), h.runner);
    expect(tool, isNot(isA<TrustedContentSource>()));
  });
}
