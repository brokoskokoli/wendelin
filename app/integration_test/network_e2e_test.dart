// Gerätetest (WP26): Netzstatus über den Kotlin-Kanal `NetworkChannel.kt`
// (ConnectivityManager, ohne Play-Dienste) für die Routing-Bedingung
// `network`.
//
// Nur auf dem Emulator, mit explizitem Serial, z. B.:
//   flutter test integration_test/network_e2e_test.dart -d emulator-5554 \
//     --dart-define=NETWORK_EXPECT=online
// Mit Flugmodus (`adb -s emulator-5554 shell cmd connectivity
// airplane-mode enable`) und NETWORK_EXPECT=offline greift die Regel
// „Offline“. Ohne NETWORK_EXPECT wird nur geprüft, dass der Kanal antwortet.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/channel_network_status.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

const _expect = String.fromEnvironment('NETWORK_EXPECT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('Kanal liefert den Netzstatus, Regel „Offline“ folgt ihm', () async {
    final status = ChannelNetworkStatus();
    await status.start();
    addTearDown(status.dispose);
    final expected = ChannelNetworkStatus.parse(_expect);
    if (expected != null) {
      expect(status.current, expected);
    } else {
      // Emulator mit Netz: online oder (Mobilfunk) getaktet.
      expect(status.current, isNot(NetworkState.offline));
    }
    const rule = NetworkCondition(NetworkState.offline);
    final match = rule.evaluate(
      RoutingContext(
        input: UserInput(text: 'Wie wird das Wetter?'),
        now: DateTime.now(),
        network: status.current,
        matcher: KeywordToolCategoryMatcher(),
      ),
    );
    expect(match != null, status.current == NetworkState.offline);
  });
}
