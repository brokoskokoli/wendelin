// Gerätetest (WP25): App-Erkennung über den Kotlin-Kanal `AppsChannel.kt`.
//
// Läuft über `tool/e2e_app_presence.sh` (nur Emulator). Das Skript
// installiert Attrappen-APKs und übergibt die Erwartung als
// `--dart-define=APPS_EXPECT=<paket>=<0|1>,…`, abgeglichen mit
// `pm list packages`: Ein installiertes, in `<queries>` deklariertes Paket
// ist sichtbar; ein installiertes, nicht deklariertes ist es nicht
// (Paket-Sichtbarkeit ab Android 11).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/app_requirements.dart';
import 'package:wendelin/platform/channel_app_presence_port.dart';
import 'package:wendelin_core/testing.dart';

const _expect = String.fromEnvironment('APPS_EXPECT');

Map<String, bool> _expectations() => {
  for (final entry in _expect.split(',').where((e) => e.isNotEmpty))
    entry.split('=')[0]: entry.split('=')[1] == '1',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const port = ChannelAppPresencePort();

  test('Kanal: Ergebnis wie erwartet (pm list packages, <queries>)', () async {
    final expected = _expectations();
    expect(expected, isNotEmpty, reason: 'APPS_EXPECT fehlt');
    for (final MapEntry(key: pkg, value: installed) in expected.entries) {
      expect(await port.isInstalled(pkg), installed, reason: pkg);
    }
  });

  test('Pflicht-App über den echten Kanal: Integration verfügbar oder '
      'nicht', () async {
    final expected = _expectations();
    const app = KnownApps.obsidian;
    final installed = expected[app.androidPackage];
    if (installed == null) return;
    final guard = AppRequirementGuard(
      FakeIntegration(id: 'needs_obsidian', tools: const []),
      app,
      InstalledApps(port),
    );
    final availability = await guard.checkAvailability();
    expect(availability.available, installed);
    if (!installed) {
      expect(availability.reason, appMissingReason);
      expect(availability.storeUrl, app.storeUrl);
    }
  });
}
