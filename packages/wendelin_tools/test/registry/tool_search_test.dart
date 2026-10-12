import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

final _cal = FakeIntegration(id: 'cal', displayName: 'Kalender', tools: []);
final _shop = FakeIntegration(id: 'shop', displayName: 'Einkauf', tools: []);

CatalogEntry _e(Integration i, String name, String description) =>
    (integration: i, tool: FakeTool(name: name, description: description));

final _candidates = [
  _e(_cal, 'cal__create', 'Termin anlegen'),
  _e(_cal, 'cal__delete', 'Termin löschen'),
  _e(_cal, 'cal__list', 'Termine auflisten'),
  _e(_shop, 'shop__add', 'Artikel auf die Einkaufsliste setzen'),
];

ToolContext _ctx() => ToolContext(
  sessionId: 's',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

void main() {
  late List<(String, List<String>)> unlocked;
  late ToolSearchTool search;

  setUp(() {
    unlocked = [];
    search = ToolSearchTool(
      candidates: _candidates,
      unlock: (s, names) => unlocked.add((s, names)),
      maxResults: 2,
    );
  });

  test('Eigenschaften', () {
    expect(search.name, 'tools__search');
    expect(Tool.isValidToolName(search.name), isTrue);
    expect(search.risk, RiskLevel.read);
    expect(search.describeForConfirmation(const {}), 'Tools suchen');
    expect(search.categories, {'cal': 'Kalender', 'shop': 'Einkauf'});
  });

  test('Trefferzahl entscheidet, dann Name; maxResults', () {
    expect(
      [for (final t in search.search('Termin löschen')) t.name],
      ['cal__delete', 'cal__create'],
    );
  });

  test('Groß-/Kleinschreibung egal, Integrationsname zählt', () {
    expect([for (final t in search.search('EINKAUF')) t.name], ['shop__add']);
  });

  test('Kategorie filtert; ohne Stichwort alle der Kategorie', () {
    expect(
      [for (final t in search.search('', category: 'shop')) t.name],
      ['shop__add'],
    );
    expect(search.search('Artikel', category: 'cal'), isEmpty);
  });

  test('execute liefert Specs als JSON und schaltet frei', () async {
    final o = await search.execute({'query': 'Einkaufsliste'}, _ctx());
    final json = jsonDecode(o.text) as Map<String, Object?>;
    final tools = json['tools']! as List;
    expect(tools.single, {
      'name': 'shop__add',
      'description': 'Artikel auf die Einkaufsliste setzen',
      'input_schema': {'type': 'object'},
    });
    expect(o.summary, '1 Tools freigeschaltet');
    expect(unlocked.single.$1, 's');
    expect(unlocked.single.$2, ['shop__add']);
  });

  test('keine Treffer: Hinweis', () async {
    final o = await search.execute({'query': 'Spotify'}, _ctx());
    expect(o.isError, isFalse);
    expect(o.text, contains('hinweis'));
    expect(o.summary, 'Keine Tools gefunden');
  });

  test('weder query noch category: Fehler', () async {
    final o = await search.execute({'query': '  '}, _ctx());
    expect(o.isError, isTrue);
    expect(unlocked, isEmpty);
  });

  test('Schema validiert Kategorie', () {
    expect(
      const ArgumentValidator().validate({
        'category': 'nix',
      }, search.inputSchema),
      contains('erlaubt sind nur'),
    );
    expect(
      const ArgumentValidator().validate({
        'query': 'a',
        'category': 'cal',
      }, search.inputSchema),
      isNull,
    );
  });
}
