import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late FakeMapsLauncherPort launcher;
  late MapsIntegration integration;
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> run(
    String name, [
    Map<String, Object?> args = const {},
  ]) => tool(name).execute(args, ctx());

  setUp(() {
    launcher = FakeMapsLauncherPort();
    integration = MapsIntegration(launcher);
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
      tool('maps__search_place').describeForConfirmation({}),
      'In Google Maps suchen',
    );
  });
}
