import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

const _hamburg = GeoFix(latitude: 53.5511, longitude: 9.9937);

void main() {
  late FakeLocationPort port;
  late FakeMapsLauncherPort launcher;
  late FakeAppPresencePort apps;
  late FakeGeocoder geocoder;
  late LocationIntegration integration;
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> run(
    String name, [
    Map<String, Object?> args = const {},
  ]) => tool(name).execute(args, ctx());

  setUp(() {
    port = FakeLocationPort();
    launcher = FakeMapsLauncherPort();
    apps = FakeAppPresencePort(installed: [googleMapsPackage]);
    geocoder = FakeGeocoder([
      const Place(name: 'Berlin', latitude: 52.52, longitude: 13.405),
    ]);
    integration = LocationIntegration(port, launcher, apps, geocoder: geocoder);
  });

  group('Intent-Bau', () {
    test('Google Maps: Navigation je Modus', () {
      final car = MapsIntents.navigate(
        'Marienplatz 1, München',
        googleMaps: true,
      );
      expect(
        car.uri.toString(),
        'google.navigation:q=Marienplatz%201%2C%20M%C3%BCnchen&mode=d',
      );
      expect(car.package, googleMapsPackage);
      expect(
        MapsIntents.navigate(
          'X',
          mode: TravelMode.walking,
          googleMaps: true,
        ).uri.toString(),
        'google.navigation:q=X&mode=w',
      );
      expect(
        MapsIntents.navigate(
          'X',
          mode: TravelMode.bicycling,
          googleMaps: true,
        ).uri.toString(),
        'google.navigation:q=X&mode=b',
      );
      final transit = MapsIntents.navigate(
        'A&B',
        mode: TravelMode.transit,
        googleMaps: true,
      );
      expect(
        transit.uri.toString(),
        'https://www.google.com/maps/dir/?api=1&destination=A%26B'
        '&travelmode=transit',
      );
    });

    test('ohne Google Maps: geo-Query ohne Paket', () {
      final l = MapsIntents.navigate('Café Ü', googleMaps: false);
      expect(l.uri.scheme, 'geo');
      expect(l.uri.toString(), 'geo:0,0?q=Caf%C3%A9%20%C3%9C');
      expect(l.package, isNull);
      final s = MapsIntents.search('Apotheke', googleMaps: false);
      expect(s.uri.toString(), 'geo:0,0?q=Apotheke');
    });

    test('Suche in Google Maps', () {
      final s = MapsIntents.search('Apotheke in der Nähe', googleMaps: true);
      expect(
        s.uri.toString(),
        'https://www.google.com/maps/search/?api=1'
        '&query=Apotheke%20in%20der%20N%C3%A4he',
      );
      expect(s.package, googleMapsPackage);
    });

    test('TravelMode.parse', () {
      expect(TravelMode.parse('walking'), TravelMode.walking);
      expect(TravelMode.parse('flying'), isNull);
    });
  });

  group('Entfernung', () {
    test('Haversine: Hamburg–Berlin etwa 255 km', () {
      final m = haversineMeters(53.5511, 9.9937, 52.52, 13.405);
      expect(m, closeTo(255000, 3000));
      expect(haversineMeters(1, 2, 1, 2), 0);
    });

    test('Formatierung gerundet mit „ca.“', () {
      expect(formatDistance(4), 'unter 10 m');
      expect(formatDistance(454), 'ca. 450 m');
      expect(formatDistance(3449), 'ca. 3,4 km');
      expect(formatDistance(254600), 'ca. 255 km');
    });
  });

  group('location__current', () {
    test('mit Ortsname: nur der Name, keine Koordinaten', () async {
      final o = await run('location__current');
      expect(o.isError, isFalse);
      expect(json(o)['place'], 'Hamburg');
      expect(json(o).containsKey('latitude'), isFalse);
      expect(json(o)['accuracy_m'], 10);
      expect(o.summary, 'Standort ermittelt');
    });

    test('ohne Ortsname: auf drei Stellen gerundete Koordinaten', () async {
      port.fix = const GeoFix(latitude: 53.55119, longitude: 9.99375);
      final o = await run('location__current');
      expect(json(o)['latitude'], '53.551');
      expect(json(o)['longitude'], '9.994');
      expect(o.text, isNot(contains('53.55119')));
      expect(o.summary, isNot(contains('53')));
    });

    test('Berechtigung verweigert: klare Meldung', () async {
      port.permission = false;
      final o = await run('location__current');
      expect(o.isError, isTrue);
      expect(o.text, contains('Standort'));
    });

    test('kein Fix: Fehler ohne Koordinaten', () async {
      port.fix = null;
      final o = await run('location__current');
      expect(o.isError, isTrue);
      expect(o.text, contains('Standort'));
    });
  });

  group('location__navigate_to', () {
    test('mit Google Maps: Navigationsintent an Maps', () async {
      final o = await run('location__navigate_to', {
        'destination': 'Hauptbahnhof',
        'mode': 'walking',
      });
      expect(o.isError, isFalse, reason: o.text);
      expect(launcher.launched.single.package, googleMapsPackage);
      expect(
        launcher.launched.single.uri.toString(),
        'google.navigation:q=Hauptbahnhof&mode=w',
      );
      expect(o.summary, isNot(contains('Hauptbahnhof')));
    });

    test('ohne Google Maps: geo-Intent', () async {
      apps.uninstall(googleMapsPackage);
      final o = await run('location__navigate_to', {
        'destination': 'Hauptbahnhof',
      });
      expect(o.isError, isFalse);
      expect(launcher.launched.single.uri.scheme, 'geo');
      expect(launcher.launched.single.package, isNull);
    });

    test('Maps gemeldet, aber nicht startbar: Rückfall auf geo', () async {
      launcher.missing.add(googleMapsPackage);
      final o = await run('location__navigate_to', {'destination': 'X'});
      expect(o.isError, isFalse);
      expect(launcher.launched.single.uri.scheme, 'geo');
    });

    test('Abfrage der Apps schlägt fehl: wie nicht installiert', () async {
      apps.failNext('isInstalled');
      final o = await run('location__navigate_to', {'destination': 'X'});
      expect(o.isError, isFalse);
      expect(launcher.launched.single.uri.scheme, 'geo');
    });

    test('keine passende App: klare Meldung', () async {
      apps.uninstall(googleMapsPackage);
      launcher.anyApp = false;
      final o = await run('location__navigate_to', {'destination': 'X'});
      expect(o.isError, isTrue);
      expect(o.text, contains('Keine Karten-App'));
      expect(launcher.launched, isEmpty);
    });

    test('anderer Fehler wird nicht verschluckt', () async {
      launcher.failNext(
        'launch',
        const PortException(PortErrorKind.failed, 'kaputt'),
      );
      final o = await run('location__navigate_to', {'destination': 'X'});
      expect(o.isError, isTrue);
      expect(o.text, 'kaputt');
    });

    test('Argumente: Ziel Pflicht, Modus geprüft', () async {
      expect((await run('location__navigate_to')).isError, isTrue);
      expect(
        (await run('location__navigate_to', {
          'destination': 'X',
          'mode': 'flying',
        })).isError,
        isTrue,
      );
      expect(launcher.launched, isEmpty);
    });

    test('Bestätigungstext ohne Ziel (Audit)', () {
      expect(
        tool('location__navigate_to')
            .describeForConfirmation({'destination': 'Praxis Dr. Muster'}),
        isNot(contains('Muster')),
      );
    });
  });

  group('location__distance_to', () {
    test('Ortsname über den Geocoder', () async {
      port.fix = _hamburg;
      final o = await run('location__distance_to', {'destination': 'Berlin'});
      expect(o.isError, isFalse, reason: o.text);
      expect(json(o)['distance'], 'ca. 255 km');
      expect(json(o)['to'], 'Berlin');
      expect(json(o)['kind'], contains('Luftlinie'));
      expect(o.text, isNot(contains('53.55')));
      expect(geocoder.asked, ['Berlin']);
      // Die Zusammenfassung (Verlauf, Zusammenfassungen an Anbieter) nennt
      // keine Entfernung.
      expect(o.summary, 'Entfernung berechnet');
    });

    test('Geocoder bekommt das Abbruch-Token', () async {
      final cancel = CancelToken();
      await tool('location__distance_to').execute({
        'destination': 'Berlin',
      }, ctxAt(DateTime.utc(2026), cancel: cancel));
      expect(geocoder.lastCancel, same(cancel));
    });

    test('Koordinaten ohne Geocoder', () async {
      integration = LocationIntegration(port, launcher, apps);
      final o = await run('location__distance_to', {
        'destination': '53.5511, 10.0037',
      });
      expect(json(o)['distance'], 'ca. 660 m');
    });

    test('unbekannter Ort, fehlende Angaben, kein Geocoder', () async {
      expect(
        (await run('location__distance_to', {'destination': 'Nirgendwo'})).text,
        contains('nicht gefunden'),
      );
      expect((await run('location__distance_to')).isError, isTrue);
      expect(
        (await run('location__distance_to', {'destination': '100.0,0.0'})).text,
        contains('außerhalb'),
      );
      integration = LocationIntegration(port, launcher, apps);
      expect(
        (await run('location__distance_to', {'destination': 'Berlin'})).isError,
        isTrue,
      );
    });

    test('Berechtigung verweigert', () async {
      port.permission = false;
      final o = await run('location__distance_to', {'destination': 'Berlin'});
      expect(o.isError, isTrue);
      expect(o.text, contains('Standort'));
    });
  });

  test('Metadaten, Risiken, Einrichtung', () async {
    expect(integration.id, 'location');
    expect(integration.sensitive, isTrue);
    expect(integration.platforms, {AppPlatform.android});
    expect(
      {for (final t in integration.tools) t.name: t.risk},
      {
        'location__current': RiskLevel.read,
        'location__navigate_to': RiskLevel.write,
        'location__distance_to': RiskLevel.read,
      },
    );
    expect(integration.tools.whereType<TrustedContentSource>(), hasLength(3));
    expect((await integration.setupState()).missingSteps, isEmpty);
    port.permission = false;
    expect((await integration.setupState()).missingSteps, [
      LocationIntegration.permissionStep,
    ]);
  });

  group('Wetter-Anbindung', () {
    test('Position als Ort, ohne Namen „Aktueller Standort“', () async {
      final w = LocationWeatherPort(port);
      expect((await w.currentPlace())!.name, 'Hamburg');
      port.fix = _hamburg;
      expect((await w.currentPlace())!.name, 'Aktueller Standort');
    });

    test('ohne Berechtigung oder Fix: null statt Fehler', () async {
      final w = LocationWeatherPort(port);
      port.permission = false;
      expect(await w.currentPlace(), isNull);
      port.permission = true;
      port.fix = null;
      expect(await w.currentPlace(), isNull);
    });

    test('ohne Berechtigung wird die Position nicht gelesen', () async {
      final w = LocationWeatherPort(port);
      port.permission = false;
      await w.currentPlace();
      expect(port.methodCalls, isNot(contains('current')));
    });

    test('Koordinaten auf zwei Nachkommastellen gerundet', () async {
      final w = LocationWeatherPort(port);
      port.fix = const GeoFix(latitude: 53.55119, longitude: 9.99371);
      final p = (await w.currentPlace())!;
      expect(p.latitude, 53.55);
      expect(p.longitude, 9.99);
    });

    test('ohne Fix nach der Frist: null (Heimatort)', () {
      fakeAsync((async) {
        final w = LocationWeatherPort(_HangingPort());
        var done = false;
        Place? result = const Place(name: 'x', latitude: 0, longitude: 0);
        w.currentPlace().then((p) {
          done = true;
          result = p;
        });
        async.elapse(const Duration(seconds: 7));
        expect(done, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(done, isTrue);
        expect(result, isNull);
      });
    });

    test('Abbruch beendet die Suche sofort mit null', () {
      fakeAsync((async) {
        final w = LocationWeatherPort(_HangingPort());
        final cancel = CancelToken();
        var done = false;
        w.currentPlace(cancel: cancel).then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isFalse);
        cancel.cancel();
        async.flushMicrotasks();
        expect(done, isTrue);
      });
    });
  });
}

/// A port whose fix never arrives.
final class _HangingPort implements LocationPort {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<GeoFix> current() => Completer<GeoFix>().future;
}
