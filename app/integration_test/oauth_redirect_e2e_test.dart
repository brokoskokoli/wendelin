// Gerätetest (WP27): Rückleitungspfad der OAuth-Anmeldung in Kotlin
// (`AuthChannel.kt`, `OAuthRedirectActivity`).
//
// Läuft über `tool/e2e_mcp.sh` (nur Emulator). Der Test öffnet eine
// Anmeldeseite mit `state=e2e-richtig` im Browser; das Skript startet
// währenddessen per `adb shell am start -d` erst eine Rückleitung mit
// falschem state (muss ignoriert werden, die Anmeldung wartet weiter) und
// dann die richtige.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/channel_authorization_browser.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Rückleitung: falscher state wird ignoriert, richtiger kommt an',
    (tester) async {
      const browser = ChannelAuthorizationBrowser();
      if (!await browser.isAvailable()) {
        markTestSkipped('Kein Browser auf dem Gerät');
        return;
      }
      final back = await browser
          .authorize(
            Uri.parse('https://example.invalid/authorize?state=e2e-richtig'),
            mcpRedirectUri,
          )
          .timeout(const Duration(seconds: 90));
      expect(back.queryParameters['state'], 'e2e-richtig');
      expect(back.queryParameters['code'], 'e2e-code');
    },
  );
}
