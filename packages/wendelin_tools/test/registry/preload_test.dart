import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

FakeIntegration _i(String id, {bool sensitive = false}) => FakeIntegration(
  id: id,
  sensitive: sensitive,
  tools: [
    FakeTool(name: '${id}__a', description: 'Tool a'),
    FakeTool(name: '${id}__b', description: 'Tool b'),
  ],
);

Future<ToolRegistry> _registry(
  List<FakeIntegration> all, {
  int threshold = 3,
  PrivacyLevel? sensitiveMinimum,
}) async {
  final r = ToolRegistry(
    metaToolThreshold: threshold,
    sensitiveMinimum: sensitiveMinimum,
  );
  for (final i in all) {
    await r.registerIntegration(i, enabled: true);
  }
  return r;
}

List<String> _offered(ToolRegistry r, PrivacyLevel level) => [
  for (final s in r.activeSpecsFor(level, sessionId: 's')) s.name,
];

ToolContext _ctx() => ToolContext(
  sessionId: 's',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

Future<List<String>> _search(ToolRegistry r, Map<String, Object?> args) async {
  final tool = r
      .catalogFor(PrivacyLevel.local, sessionId: 's')
      .lookup(ToolSearchTool.toolName)!;
  final o = await tool.execute(args, _ctx());
  return [
    for (final t in (jsonDecode(o.text) as Map)['tools'] as List)
      (t as Map)['name'] as String,
  ];
}

void main() {
  final all = [_i('alarms'), _i('calendar'), _i('weather'), _i('maps')];

  test('erkannte Integration: Tools vorab, tools__search bleibt', () async {
    final r = await _registry(all);
    expect(_offered(r, PrivacyLevel.local), [ToolSearchTool.toolName]);
    final ids = r.preloadForRequest(
      'Stell mir einen Wecker um 7',
      PrivacyLevel.local,
      sessionId: 's',
      languageTag: 'de-DE',
    );
    expect(ids, ['alarms']);
    expect(_offered(r, PrivacyLevel.local), [
      ToolSearchTool.toolName,
      'alarms__a',
      'alarms__b',
    ]);
  });

  test('unerkannte Anfrage: nur die Suche wie bisher', () async {
    final r = await _registry(all);
    expect(
      r.preloadForRequest(
        'Erzähl mir einen Witz',
        PrivacyLevel.local,
        sessionId: 's',
        languageTag: 'de',
      ),
      isEmpty,
    );
    expect(_offered(r, PrivacyLevel.local), [ToolSearchTool.toolName]);
  });

  test('höchstens drei Integrationen', () async {
    final r = await _registry([...all, _i('contacts')]);
    final ids = r.preloadForRequest(
      'Wecker, Kalender, Wetter, Route und Kontakt',
      PrivacyLevel.local,
      sessionId: 's',
      languageTag: 'de-DE',
    );
    expect(ids, hasLength(ToolRegistry.maxPreloaded));
    expect(_offered(r, PrivacyLevel.local), hasLength(1 + 3 * 2));
  });

  test('K10: sensitive Tools nicht für zu niedrige Stufe vorab', () async {
    final r = await _registry([
      _i('calendar', sensitive: true),
      _i('alarms'),
      _i('x'),
    ], sensitiveMinimum: PrivacyLevel.tee);
    final ids = r.preloadForRequest(
      'Was steht im Kalender, und stell einen Wecker',
      PrivacyLevel.standard,
      sessionId: 's',
      languageTag: 'de-DE',
    );
    expect(ids, ['alarms']);
    expect(
      _offered(r, PrivacyLevel.standard).any((n) => n.startsWith('calendar')),
      isFalse,
    );
    // Not even later with the higher level in the same session: it was
    // never unlocked, so the model has to search.
    expect(_offered(r, PrivacyLevel.tee), isNot(contains('calendar__a')));
  });

  test('nicht aktive Integration wird nicht vorab geladen', () async {
    final r = ToolRegistry(metaToolThreshold: 3);
    await r.registerIntegration(_i('alarms'));
    await r.registerIntegration(_i('calendar'), enabled: true);
    await r.registerIntegration(_i('weather'), enabled: true);
    expect(
      r.preloadForRequest(
        'Wecker',
        PrivacyLevel.local,
        sessionId: 's',
        languageTag: 'de',
      ),
      isEmpty,
    );
  });

  test('ohne Meta-Modus nichts zu tun', () async {
    final r = await _registry(all, threshold: 30);
    expect(
      r.preloadForRequest(
        'Wecker',
        PrivacyLevel.local,
        sessionId: 's',
        languageTag: 'de',
      ),
      isEmpty,
    );
    expect(r.unlockedTools('s'), isEmpty);
  });

  test('Freischaltung gilt nur für die eigene Sitzung', () async {
    final r = await _registry(all);
    r.preloadForRequest(
      'Wecker',
      PrivacyLevel.local,
      sessionId: 's',
      languageTag: 'de',
    );
    expect(r.unlockedTools('other'), isEmpty);
  });

  test('Vorab-Menge wird je Anfrage ersetzt, Suchtreffer bleiben', () async {
    final r = await _registry(all);
    r.preloadForRequest(
      'Wecker',
      PrivacyLevel.local,
      sessionId: 's',
      languageTag: 'de',
    );
    await _search(r, {'category': 'maps'});
    r.preloadForRequest(
      'Wie wird das Wetter?',
      PrivacyLevel.local,
      sessionId: 's',
      languageTag: 'de',
    );
    expect(r.unlockedTools('s'), {
      'weather__a',
      'weather__b',
      'maps__a',
      'maps__b',
    });
    r.preloadForRequest(
      'Erzähl einen Witz',
      PrivacyLevel.local,
      sessionId: 's',
      languageTag: 'de',
    );
    expect(r.unlockedTools('s'), {'maps__a', 'maps__b'});
  });

  test('Suche nutzt die Sprache der Anfrage, nicht des Geräts', () async {
    final r = await _registry(all);
    expect(await _search(r, {'query': 'réveille'}), isEmpty);
    r.preloadForRequest(
      'Réveille-moi à sept heures',
      PrivacyLevel.local,
      sessionId: 's',
      languageTag: 'fr',
    );
    expect(await _search(r, {'query': 'réveille'}), contains('alarms__a'));
  });
}
