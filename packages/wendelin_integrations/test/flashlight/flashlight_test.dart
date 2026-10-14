import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late FakeTorchPort port;
  late FlashlightIntegration integration;
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);

  setUp(() {
    port = FakeTorchPort();
    integration = FlashlightIntegration(port);
  });

  test('Integration: Metadaten, Risiko write ohne Bestätigung', () async {
    expect(integration.id, 'flashlight');
    expect(integration.displayName, 'Taschenlampe');
    expect(integration.sensitive, isFalse);
    expect(integration.platforms, {AppPlatform.android});
    expect(await integration.checkAvailability(), Availability.yes);
    expect(integration.setup, isEmpty);
    expect(
      {for (final t in integration.tools) t.name: t.risk},
      {
        'flashlight__on': RiskLevel.write,
        'flashlight__off': RiskLevel.write,
        'flashlight__toggle': RiskLevel.write,
      },
    );
    for (final t in integration.tools) {
      expect(t, isA<TrustedContentSource>());
    }
  });

  test('on: schaltet ein, Undo schaltet zurück aus', () async {
    final o = await tool('flashlight__on').execute({}, ctx());
    expect(o.isError, isFalse);
    expect(o.summary, 'Taschenlampe an');
    expect(port.on, isTrue);
    await o.undo!();
    expect(port.on, isFalse);
  });

  test('off: schaltet aus, Undo schaltet wieder ein', () async {
    port.on = true;
    final o = await tool('flashlight__off').execute({}, ctx());
    expect(o.summary, 'Taschenlampe aus');
    expect(port.on, isFalse);
    await o.undo!();
    expect(port.on, isTrue);
  });

  test('toggle: kehrt um (auch wenn die Systemkachel umschaltete)', () async {
    var o = await tool('flashlight__toggle').execute({}, ctx());
    expect(port.on, isTrue);
    expect(o.summary, 'Taschenlampe an');
    port.on = false; // Systemkachel
    o = await tool('flashlight__toggle').execute({}, ctx());
    expect(port.on, isTrue);
    o = await tool('flashlight__toggle').execute({}, ctx());
    expect(port.on, isFalse);
    await o.undo!();
    expect(port.on, isTrue);
  });

  test('schon im Zielzustand: kein Schalten, kein Undo', () async {
    port.on = true;
    final o = await tool('flashlight__on').execute({}, ctx());
    expect(o.isError, isFalse);
    expect(o.undo, isNull);
    expect(port.methodCalls, isNot(contains('set')));
  });

  test('keine LED: Tool-Fehler mit Text', () async {
    port.available = false;
    for (final t in integration.tools) {
      final o = await t.execute({}, ctx());
      expect(o.isError, isTrue);
      expect(o.text, contains('keine Taschenlampe'));
    }
  });

  test('Kamera belegt oder Thermik-Sperre: Fehlertext statt Absturz', () async {
    port.failNext(
      'set',
      const PortException(
        PortErrorKind.unavailable,
        'Die Kamera wird gerade benutzt.',
      ),
    );
    final o = await tool('flashlight__on').execute({}, ctx());
    expect(o.isError, isTrue);
    expect(o.text, contains('Kamera'));
    expect(port.on, isFalse);
  });
}
