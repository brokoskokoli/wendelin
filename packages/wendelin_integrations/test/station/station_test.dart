import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late FakeStationPort port;
  late StationIntegration integration;

  setUp(() {
    port = FakeStationPort();
    integration = StationIntegration(port);
  });

  stationPortContract(FakeStationPort.new);

  test('Metadaten: Android, nicht sensibel, immer verfügbar', () async {
    expect(integration.id, 'station');
    expect(integration.sensitive, isFalse);
    expect(integration.platforms, {AppPlatform.android});
    expect(await integration.checkAvailability(), Availability.yes);
  });

  test('es gibt nur den Start, kein Tool beendet den Modus', () {
    expect([for (final t in integration.tools) t.name], ['station__start']);
    expect(integration.tools.single.risk, RiskLevel.write);
  });

  test('entsperrt: startet die Station', () async {
    final out = await integration.tools.single.execute({}, ctx());
    expect(out.isError, isFalse);
    expect(port.starts, 1);
  });

  test('gesperrt: startet nicht und meldet es', () async {
    port.locked = true;
    final out = await integration.tools.single.execute({}, ctx());
    expect(out.isError, isTrue);
    expect(port.starts, 0);
  });

  test('feste Bestätigung beim Start; gesperrt ohne Satz', () async {
    final t = integration.tools.single;
    expectFixed(
      await t.execute({}, ctx()),
      t,
      'station.started',
      de: 'Der Stationsmodus ist an.',
    );
    port.locked = true;
    final o = await t.execute({}, ctx());
    expect(o.isError, isTrue);
    expect(o.fixed, isNull);
  });
}
