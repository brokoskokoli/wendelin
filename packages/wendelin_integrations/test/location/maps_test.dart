import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late FakeMapsLauncherPort launcher;
  late FakeNavigationApps apps;
  late MapsIntegration integration;
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> run(
    String name, [
    Map<String, Object?> args = const {},
  ]) => tool(name).execute(args, ctx());

  setUp(() {
    launcher = FakeMapsLauncherPort();
    apps = FakeNavigationApps();
    integration = MapsIntegration(launcher, MapsNavigateTool(launcher, apps));
  });

  test('Metadaten, Risiken, Vertrauen, keine route_info', () async {
    expect(integration.id, 'maps');
    expect(integration.sensitive, isFalse);
    expect(await integration.checkAvailability(), Availability.yes);
    expect(
      {for (final t in integration.tools) t.name: t.risk},
      {'maps__navigate': RiskLevel.write, 'maps__search_place': RiskLevel.read},
    );
    expect(integration.tools.every((t) => t is TrustedContentSource), isTrue);
    expect((await integration.setupState()).missingSteps, isEmpty);
  });

  test('maps__navigate: Intent an Google Maps', () async {
    final o = await run('maps__navigate', {
      'destination': 'Flughafen',
      'mode': 'transit',
    });
    expect(o.isError, isFalse, reason: o.text);
    expect(launcher.launched.single.package, googleMapsPackage);
    expect(launcher.launched.single.uri.host, 'www.google.com');
    expect(launcher.launched.single.uri.queryParameters, {
      'api': '1',
      'destination': 'Flughafen',
      'travelmode': 'transit',
    });
    expect(o.summary, isNot(contains('Flughafen')));
  });

  group('maps__navigate mit Waze (WP164 B)', () {
    Future<ToolOutcome> nav([Map<String, Object?> extra = const {}]) =>
        run('maps__navigate', {'destination': 'Café Müller & Söhne', ...extra});

    test('Waze-URI: kodierte Sonderzeichen, Umlaute, Paket com.waze', () async {
      final o = await nav({'app': 'waze'});
      expect(o.isError, isFalse, reason: o.text);
      expect(o.text, 'Waze ist geöffnet.');
      final l = launcher.launched.single;
      expect(l.package, 'com.waze');
      expect(
        l.uri.toString(),
        'https://waze.com/ul?q=Caf%C3%A9%20M%C3%BCller%20%26%20S%C3%B6hne'
        '&navigate=yes',
      );
      expect(l.uri.queryParameters, {
        'q': 'Café Müller & Söhne',
        'navigate': 'yes',
      });
    });

    test('Standard ohne Einstellung: Google Maps, sonst Waze', () async {
      expect((await nav()).text, 'Google Maps ist geöffnet.');
      apps.active = {NavigationApp.waze};
      expect((await nav()).text, 'Waze ist geöffnet.');
      expect(launcher.launched.last.package, 'com.waze');
    });

    test('Einstellung gilt ohne app, app im Aufruf schlägt sie', () async {
      apps.preferred = NavigationApp.waze;
      expect((await nav()).text, 'Waze ist geöffnet.');
      expect(
        (await nav({'app': 'google_maps'})).text,
        'Google Maps ist geöffnet.',
      );
    });

    test(
      'Gewählte App fehlt oder aus: Fehler, kein Wechsel zur anderen',
      () async {
        apps.active = {NavigationApp.googleMaps};
        final off = await nav({'app': 'waze'});
        expect(off.isError, isTrue);
        expect(off.text, contains('Waze'));
        apps.active = {...NavigationApp.values};
        apps.installed.remove(NavigationApp.waze);
        final missing = await nav({'app': 'waze'});
        expect(missing.isError, isTrue);
        apps.preferred = NavigationApp.waze;
        expect((await nav()).isError, isTrue);
        apps.active = {};
        apps.preferred = null;
        expect((await nav()).isError, isTrue);
        apps.active = {...NavigationApp.values};
        apps.failNext('isInstalled');
        expect((await nav({'app': 'google_maps'})).isError, isTrue);
        expect(launcher.launched, isEmpty);
      },
    );

    test('Waze nur mit dem Auto, unbekannte App wird abgelehnt', () async {
      expect((await nav({'app': 'waze', 'mode': 'walking'})).isError, isTrue);
      expect((await nav({'app': 'osmand'})).isError, isTrue);
      expect(launcher.launched, isEmpty);
    });

    test('Schema bietet nur aktive Apps an', () {
      List<Object?> offered() =>
          ((tool('maps__navigate').inputSchema['properties']! as Map)['app']
                  as Map)['enum']!
              as List<Object?>;
      expect(offered(), ['google_maps', 'waze']);
      apps.active = {NavigationApp.waze};
      expect(offered(), ['waze']);
    });

    test('Waze-Integration teilt das Tool, hat keine eigenen', () {
      final waze = WazeIntegration(integration.tools.first as MapsNavigateTool);
      expect(waze.id, 'waze');
      expect(waze.tools.single, same(integration.tools.first));
    });
  });

  test('maps__search_place: Suche öffnen, Maps fehlt = Fehlertext', () async {
    final o = await run('maps__search_place', {'query': 'Apotheke'});
    expect(o.isError, isFalse);
    expect(launcher.launched.single.uri.queryParameters['query'], 'Apotheke');
    launcher.missing.add(googleMapsPackage);
    final bad = await run('maps__search_place', {'query': 'Apotheke'});
    expect(bad.isError, isTrue);
  });

  test('Argumente werden geprüft', () async {
    expect((await run('maps__navigate')).isError, isTrue);
    expect((await run('maps__search_place')).isError, isTrue);
    expect(
      (await run('maps__navigate', {'destination': 'X', 'mode': 'x'})).isError,
      isTrue,
    );
    expect(launcher.launched, isEmpty);
    expect(
      tool('maps__navigate').describeForConfirmation({}),
      'Navigation starten',
    );
    expect(
      tool('maps__search_place').describeForConfirmation({}),
      'In Google Maps suchen',
    );
  });
}
