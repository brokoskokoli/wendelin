// Gerätetest (WP86): Standort und Karten über die Kotlin-Kanäle, ohne LLM.
//
// Nur auf einem Emulator (`tool/e2e_android.sh integration_test/location_e2e_test.dart`).
// Das Skript erteilt die Standort-Berechtigung (`pm grant`) und setzt die
// Position per `adb emu geo fix`; der Test prüft Position und Tool-Ergebnis.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/channel_app_presence_port.dart';
import 'package:wendelin/platform/channel_location_port.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Polls [ok] for up to a minute (the script grants and positions in the
/// background; there is no event to wait for).
Future<void> _until(Future<bool> Function() ok, String reason) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!await ok()) {
    if (DateTime.now().isAfter(end)) fail(reason);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const port = ChannelLocationPort();
  const launcher = ChannelMapsLauncherPort();
  const apps = ChannelAppPresencePort();
  final integration = LocationIntegration(port, launcher, apps);
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);
  final ctx = ToolContext(
    sessionId: 's',
    clock: FixedClock(DateTime(2026, 1, 1)),
    locale: 'de-DE',
    timeZone: 'Europe/Berlin',
  );

  test('Standort: Position vom Host, Tool nennt Ort oder Koordinaten', () async {
    // Das Skript erteilt ACCESS_FINE/COARSE_LOCATION und setzt die Position
    // (`adb emu geo fix 10.0 53.55`, Hamburg).
    // Das Skript erteilt im Hintergrund, sobald die App installiert ist.
    await _until(
      port.hasPermission,
      'Standort-Berechtigung fehlt (tool/e2e_android.sh erteilt sie)',
    );
    expect((await integration.setupState()).missingSteps, isEmpty);
    GeoFix? fix;
    await _until(() async {
      try {
        fix = await port.current();
      } on Object {
        return false; // noch keine Position
      }
      return (fix!.latitude - 53.55).abs() < 0.05;
    }, 'Position vom Host (adb emu geo fix) kam nicht an');
    expect(fix!.latitude, closeTo(53.55, 0.05));
    expect(fix!.longitude, closeTo(10.0, 0.05));
    final out = await tool('location__current').execute({}, ctx);
    expect(out.isError, isFalse, reason: out.text);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Karten: ohne Google Maps kein Absturz', () async {
    final google = await apps.isInstalled('com.google.android.apps.maps');
    // ignore: avoid_print
    print('LOC_E2E googleMaps=$google');
    final out = await tool(
      'location__navigate_to',
    ).execute({'destination': 'Hamburg Hauptbahnhof'}, ctx);
    // ignore: avoid_print
    print('LOC_E2E navigate error=${out.isError} text=${out.text}');
    if (out.isError) expect(out.text, contains('Karten-App'));
  });
}
