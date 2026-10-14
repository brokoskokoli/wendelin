// Gerätetest (WP48): Taschenlampe über den Kotlin-Kanal `TorchChannel.kt`.
//
// Nur auf einem Emulator ausführen (`flutter test integration_test/torch_e2e_test.dart
// -d emulator-xxxx`). Der Test passt sich dem Gerät an: Mit Blitz-LED wird
// geschaltet und der Zustand geprüft, ohne LED muss das Tool einen sauberen
// Fehlertext liefern. Die Ausgabe nennt den Fall.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/channel_torch_port.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const port = ChannelTorchPort();
  final integration = FlashlightIntegration(port);
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);
  final ctx = ToolContext(
    sessionId: 's',
    clock: FixedClock(DateTime(2026, 1, 1)),
    locale: 'de-DE',
    timeZone: 'Europe/Berlin',
  );

  test('Kanal und Tools: mit LED schalten, ohne LED sauberer Fehler', () async {
    final led = await port.isAvailable();
    // ignore: avoid_print
    print('TORCH_E2E led=$led');
    if (led) {
      final on = await tool('flashlight__on').execute({}, ctx);
      expect(on.isError, isFalse, reason: on.text);
      expect(await port.state(), isTrue);
      final off = await tool('flashlight__toggle').execute({}, ctx);
      expect(off.isError, isFalse, reason: off.text);
      expect(await port.state(), isFalse);
    } else {
      for (final name in ['flashlight__on', 'flashlight__off']) {
        final o = await tool(name).execute({}, ctx);
        expect(o.isError, isTrue);
        expect(o.text, contains('keine Taschenlampe'));
      }
    }
  });
}
