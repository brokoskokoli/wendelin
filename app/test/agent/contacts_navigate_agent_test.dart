// WP164 C: „Navigiere zu <Kontakt>“ läuft über contacts__navigate. Das
// Modell bekommt nur einen Status, nie die Adresse; bei ok spricht ein
// fester Satz. Verfügbar nur mit Kontakte-Integration UND Navigations-App.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_requirements.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../screens/main_screen_test.dart' show pumpApp, pumpUntil, send;
import '../support/test_env.dart';

const _home = 'Musterstraße 1, 12345 Musterstadt';
const _work = 'Werkstraße 3, 54321 Beispielstadt';
const _addressParts = ['Musterstra', 'Werkstra', '12345', '54321'];

const _book = [
  ContactEntry(
    name: 'Anna Meier',
    phones: [ContactPhone('+49 170 1234567', label: 'Mobil')],
    addresses: [ContactAddress(_home, label: 'Privat')],
  ),
  ContactEntry(
    name: 'Ben Weber',
    phones: [ContactPhone('0172 333')],
    addresses: [
      ContactAddress(_home, label: 'Privat'),
      ContactAddress(_work, label: 'Arbeit'),
    ],
  ),
];

/// Alles, was ein Modell-Request enthält (Nachrichten, Werkzeuge).
String _everything(FakeLlmProvider p) => jsonEncode([
  for (final r in p.requests) ...[
    for (final m in r.messages)
      for (final b in m.content) b.toJson(),
    for (final t in r.tools) '${t.name}|${t.description}|${t.inputSchema}',
  ],
]);

void _expectNoAddress(FakeLlmProvider p) {
  final seen = _everything(p);
  for (final part in _addressParts) {
    expect(seen, isNot(contains(part)), reason: part);
  }
}

TestEnv _env(FakeLlmProvider provider) {
  final env = TestEnv(
    providerConfig: scripted(provider),
    startup: const StartupSettings(enabledIntegrations: {'contacts', 'maps'}),
  );
  env.contacts.contacts = _book;
  return env;
}

ToolContext _ctx() => ToolContext(
  sessionId: 's',
  clock: FixedClock(testNow),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

void main() {
  testWidgets('ok: kein Modell-Request enthält die Adresse, fester Satz', (
    tester,
  ) async {
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        call('c1', 'contacts__navigate', jsonEncode({'name': 'Anna Meier'})),
      ]),
      ScriptedTurn.text('Das Modell sollte nicht mehr antworten.'),
    ]);
    final env = _env(provider);
    await pumpApp(tester, env);
    await send(tester, 'Navigiere zu Anna Meier');
    await pumpUntil(tester, find.text('Navigation zu Anna Meier gestartet.'));

    expect(provider.requests, hasLength(1), reason: 'fester Satz, 1 Zug');
    _expectNoAddress(provider);
    // Genau diese Adresse ging an Google Maps, nur die Adresse wurde gelesen.
    final launch = env.mapsLauncher.launched.single;
    expect(launch.package, googleMapsPackage);
    expect(
      Uri.decodeComponent(launch.uri.toString()),
      startsWith('google.navigation:q=$_home'),
    );
    expect(env.contacts.requested, [
      {ContactField.address},
    ]);
  });

  testWidgets('choice_needed: Auswahl per address_label, Modell sieht nie '
      'eine Adresse', (tester) async {
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        call('c1', 'contacts__navigate', jsonEncode({'name': 'Ben Weber'})),
      ]),
      ScriptedTurn.text('Privat oder Arbeit?'),
    ]);
    final env = _env(provider);
    await pumpApp(tester, env);
    await send(tester, 'Navigiere zu Ben');
    await pumpUntil(tester, find.text('Privat oder Arbeit?'));
    expect(env.mapsLauncher.launched, isEmpty);
    final seen = _everything(provider);
    expect(seen, contains('choice_needed'));
    expect(seen, contains('Arbeit'));
    _expectNoAddress(provider);
  });

  group('Verfügbarkeit', () {
    Future<Tool?> tool(TestEnv env) async {
      final c = env.container();
      addTearDown(c.dispose);
      final registry = c.read(toolRegistryProvider);
      await registry.refresh();
      return registry
          .catalogFor(PrivacyLevel.local, sessionId: 's')
          .lookup('contacts__navigate');
    }

    for (final (enabled, offered) in <(Set<String>, bool)>[
      ({'contacts'}, false),
      ({'maps'}, false),
      ({'waze'}, false),
      ({'contacts', 'maps'}, true),
      ({'contacts', 'waze'}, true),
      ({'contacts', 'maps', 'waze'}, true),
    ]) {
      test('an: $enabled -> angeboten: $offered', () async {
        final t = await tool(TestEnv(enabled: enabled));
        expect(t != null, offered);
      });
    }

    test('Navigations-App nicht installiert: nicht angeboten', () async {
      final env = TestEnv(enabled: const {'contacts', 'maps'});
      env.apps.uninstall(KnownApps.googleMaps.androidPackage);
      expect(await tool(env), isNull);
    });

    test('Schema nennt nur aktive Apps', () async {
      final t = await tool(TestEnv(enabled: const {'contacts', 'waze'}));
      final app = (t!.inputSchema['properties']! as Map)['app']! as Map;
      expect(app['enum'], ['waze']);
    });
  });

  test('Werkzeugergebnis über die Registry: Status ohne Adresse', () async {
    final env = TestEnv(enabled: const {'contacts', 'maps'});
    env.contacts.contacts = _book;
    final c = env.container();
    addTearDown(c.dispose);
    final registry = c.read(toolRegistryProvider);
    await registry.refresh();
    final t = registry
        .catalogFor(PrivacyLevel.local, sessionId: 's')
        .lookup('contacts__navigate')!;
    final o = await t.execute({'name': 'Ben Weber'}, _ctx());
    expect(o.text, isNot(contains('Muster')));
    expect(jsonDecode(o.text), containsPair('status', 'choice_needed'));
    // Audit und Bestätigungstext: nur der Kontaktname.
    final args = {'name': 'Anna Meier', 'address_label': 'Privat'};
    final audit = await t.auditArguments(jsonEncode(args), args, _ctx());
    expect(jsonDecode(audit), {'contact': 'Anna Meier'});
    expect(t.describeForConfirmation(args), 'Navigation zu Anna Meier starten');
  });
}
