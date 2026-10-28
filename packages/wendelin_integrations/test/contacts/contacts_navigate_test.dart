// WP164 C: contacts__navigate – Status statt Adresse, gleiche App-Wahl wie
// maps__navigate, fester Satz bei ok.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

const _home = 'Musterstraße 1, 12345 Musterstadt';
const _work = 'Werkstraße 3, 54321 Beispielstadt';

void main() {
  late FakeContactsPort book;
  late FakeMapsLauncherPort launcher;
  late FakeNavigationApps apps;
  late ContactsNavigateTool nav;

  Future<ToolOutcome> run(Map<String, Object?> args) =>
      nav.execute(args, ctx());

  /// Everything a result may show to the model, the user or a log.
  String shown(ToolOutcome o) => '${o.text}|${o.summary}|${o.fixed?.params}';

  void expectNoAddress(ToolOutcome o) {
    final s = shown(o);
    for (final a in ['Musterstra', 'Werkstra', '12345', '54321', 'Beispiel']) {
      expect(s, isNot(contains(a)));
    }
  }

  setUp(() {
    book = FakeContactsPort(
      contacts: const [
        ContactEntry(
          name: 'Anna Meier',
          phones: [ContactPhone('0170 1')],
          addresses: [ContactAddress(_home, label: 'Privat')],
        ),
        ContactEntry(
          name: 'Ben Weber',
          phones: [ContactPhone('0172 3')],
          addresses: [
            ContactAddress(_home, label: 'Privat'),
            ContactAddress(_work, label: 'Arbeit'),
          ],
        ),
        ContactEntry(name: 'Carla Keller', phones: [ContactPhone('0173 4')]),
        ContactEntry(
          name: 'Dora Lang',
          phones: [ContactPhone('0174 5')],
          addresses: [ContactAddress('Hauptstr. 1\n80331 Stadt')],
        ),
        ContactEntry(
          name: 'Erik Roth',
          phones: [ContactPhone('0175 6')],
          addresses: [ContactAddress(_home), ContactAddress(_work)],
        ),
        ContactEntry(name: 'Anna Berg', phones: [ContactPhone('0176 7')]),
      ],
    );
    launcher = FakeMapsLauncherPort();
    apps = FakeNavigationApps();
    nav = ContactsNavigateTool(
      ContactsFinder(book),
      NavigationStarter(launcher, apps),
    );
  });

  test('Metadaten: write, nur entsperrt, fester Satz, Schema', () {
    expect(nav.name, 'contacts__navigate');
    expect(nav.risk, RiskLevel.write);
    expect(nav, isA<WorksOnlyUnlocked>());
    expect(nav, isA<FixedConfirmationTool>());
    expect(nav.inputSchema['required'], ['name']);
    final props = nav.inputSchema['properties']! as Map<String, Object?>;
    expect(props.keys, containsAll(['name', 'address_label', 'app']));
  });

  test(
    'ok: Launcher bekommt genau die Adresse, fester Satz, kein Modelltext',
    () async {
      final o = await run({'name': 'Anna Meier'});
      expect(o.isError, isFalse, reason: o.text);
      expect(json(o), {'status': 'ok'});
      final launch = launcher.launched.single;
      expect(launch.package, googleMapsPackage);
      expect(Uri.decodeComponent(launch.uri.toString()), contains('q=$_home'));
      expectFixed(
        o,
        nav,
        'navigation.started',
        de: 'Navigation zu Anna Meier gestartet.',
      );
      expect(
        renderConfirmation(o.fixed!, 'en'),
        'Navigation to Anna Meier started.',
      );
      expect(
        renderConfirmation(o.fixed!, 'fr'),
        'Navigation vers Anna Meier lancée.',
      );
      expectNoAddress(o);
      // Nur die Adresse wurde aus dem Adressbuch geholt.
      expect(book.requested, [
        {ContactField.address},
      ]);
    },
  );

  test('Zeilenumbruch der Adresse wird zu ", "', () async {
    await run({'name': 'Dora Lang'});
    expect(
      Uri.decodeComponent(launcher.launched.single.uri.toString()),
      contains('q=Hauptstr. 1, 80331 Stadt'),
    );
  });

  test('app waze: Waze-Intent mit der Adresse', () async {
    final o = await run({'name': 'Anna Meier', 'app': 'waze'});
    expect(json(o)['status'], 'ok');
    expect(launcher.launched.single.package, wazePackage);
    expect(
      Uri.decodeComponent(launcher.launched.single.uri.toString()),
      contains(_home),
    );
  });

  test('Einstellung Navigations-App gilt ohne app', () async {
    apps.preferred = NavigationApp.waze;
    await run({'name': 'Anna Meier'});
    expect(launcher.launched.single.package, wazePackage);
  });

  test('no_contact', () async {
    final o = await run({'name': 'Zacharias'});
    expect(json(o), {'status': 'no_contact'});
    expect(launcher.launched, isEmpty);
    expect(o.fixed, isNull);
  });

  test('no_address: Kontakt ohne Adresse', () async {
    final o = await run({'name': 'Carla Keller'});
    expect(json(o), {'status': 'no_address'});
    expect(launcher.launched, isEmpty);
    expect(o.fixed, isNull);
  });

  test('no_address: Adresse nur aus Leerraum oder zu lang', () async {
    book.contacts = [
      const ContactEntry(
        name: 'Fritz',
        phones: [ContactPhone('1')],
        addresses: [ContactAddress('  \n ')],
      ),
      ContactEntry(
        name: 'Gerda',
        phones: const [ContactPhone('2')],
        addresses: [ContactAddress('x' * 201)],
      ),
    ];
    for (final n in ['Fritz', 'Gerda']) {
      expect(json(await run({'name': n})), {'status': 'no_address'});
    }
    expect(launcher.launched, isEmpty);
  });

  test('choice_needed bei mehreren Kontakten: nur Namen', () async {
    final o = await run({'name': 'Anna'});
    // „Anna“ ist ein Teiltreffer auf zwei Kontakte.
    expect(json(o), {
      'status': 'choice_needed',
      'contacts': ['Anna Meier', 'Anna Berg'],
    });
    expectNoAddress(o);
    expect(launcher.launched, isEmpty);
    expect(o.fixed, isNull);
  });

  test('choice_needed bei mehreren Adressen: nur Bezeichnungen', () async {
    final o = await run({'name': 'Ben Weber'});
    expect(json(o), {
      'status': 'choice_needed',
      'address_labels': ['Privat', 'Arbeit'],
    });
    expectNoAddress(o);
    expect(launcher.launched, isEmpty);
  });

  test(
    'address_label wählt die Adresse (Groß-/Kleinschreibung egal)',
    () async {
      final o = await run({'name': 'Ben Weber', 'address_label': 'arbeit'});
      expect(json(o), {'status': 'ok'});
      expect(
        Uri.decodeComponent(launcher.launched.single.uri.toString()),
        contains(_work),
      );
      expect(
        Uri.decodeComponent(launcher.launched.single.uri.toString()),
        isNot(contains('Musterstra')),
      );
    },
  );

  test('unbekanntes address_label: erneut Auswahl, kein Start', () async {
    final o = await run({'name': 'Ben Weber', 'address_label': 'Urlaub'});
    expect(json(o)['status'], 'choice_needed');
    expect(launcher.launched, isEmpty);
  });

  test('Adressen ohne Bezeichnung heißen Adresse 1, Adresse 2', () async {
    final first = await run({'name': 'Erik Roth'});
    expect(json(first)['address_labels'], ['Adresse 1', 'Adresse 2']);
    final o = await run({'name': 'Erik Roth', 'address_label': 'Adresse 2'});
    expect(json(o)['status'], 'ok');
    expect(
      Uri.decodeComponent(launcher.launched.single.uri.toString()),
      contains(_work),
    );
  });

  group('app_unavailable', () {
    test('keine App aktiv', () async {
      apps.active = {};
      final o = await run({'name': 'Anna Meier'});
      expect(json(o), {'status': 'app_unavailable'});
      expect(launcher.launched, isEmpty);
      expectNoAddress(o);
    });

    test('gewählte App nicht installiert: nie die andere', () async {
      apps.installed.remove(NavigationApp.waze);
      final o = await run({'name': 'Anna Meier', 'app': 'waze'});
      expect(json(o), {'status': 'app_unavailable'});
      expect(launcher.launched, isEmpty);
    });

    test('Start schlägt fehl: nur Status, keine Fehlermeldung', () async {
      launcher.failNext(
        'launch',
        const PortException(PortErrorKind.failed, 'Fehler bei $_home'),
      );
      final o = await run({'name': 'Anna Meier'});
      expect(json(o), {'status': 'app_unavailable'});
      expectNoAddress(o);
      expect(o.fixed, isNull);
    });
  });

  test('Kontakte-Berechtigung fehlt: Fehler ohne Adresse', () async {
    book.permission = false;
    final o = await run({'name': 'Anna Meier'});
    expect(o.isError, isTrue);
    expectNoAddress(o);
    expect(launcher.launched, isEmpty);
  });

  test('ungültige Argumente: Fehler ohne Start', () async {
    expect((await run({'name': '  '})).isError, isTrue);
    expect((await run({})).isError, isTrue);
    expect((await run({'name': 'Anna Meier', 'app': 'osm'})).isError, isTrue);
    expect(launcher.launched, isEmpty);
  });

  test('Verfügbarkeit folgt den aktiven Navigations-Apps', () {
    expect(nav.offered, isTrue);
    apps.active = {NavigationApp.waze};
    expect(nav.offered, isTrue);
    apps.active = {};
    expect(nav.offered, isFalse);
  });

  test('Schema nennt nur aktive Apps', () {
    apps.active = {NavigationApp.waze};
    final props = nav.inputSchema['properties']! as Map<String, Object?>;
    expect((props['app']! as Map)['enum'], ['waze']);
  });

  test('Audit und Beschreibung ohne Adresse', () async {
    final redacted = await nav.redactedArguments({
      'name': 'Anna Meier',
      'address_label': 'Privat',
    }, ctx());
    expect(jsonDecode(redacted), {'contact': 'Anna Meier'});
    expect(
      nav.describeForConfirmation({'name': 'Anna Meier'}),
      'Navigation zu Anna Meier starten',
    );
    expect(nav.describeForConfirmation({}), nav.fallbackDescription);
  });

  test('ContactsIntegration: Tool nur mit Navigation', () {
    final without = ContactsIntegration(book, FakePhonePort());
    expect(without.tools.map((t) => t.name), isNot(contains(nav.name)));
    final with_ = ContactsIntegration(
      book,
      FakePhonePort(),
      navigation: NavigationStarter(launcher, apps),
    );
    final t = with_.tools.singleWhere((t) => t.name == nav.name);
    expect(t is TrustedContentSource, isTrue);
  });

  test('contacts__find nennt contacts__navigate und rät von address ab', () {
    final d = ContactsFindTool(ContactsFinder(book)).description;
    expect(d, contains('contacts__navigate'));
    expect(d, isNot(contains('maps__navigate')));
  });
}
