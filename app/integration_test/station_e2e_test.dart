// Gerätetest WP99: Stationsmodus über dem Sperrbildschirm.
//
// 1. Start über die echte `StationPort`-Brücke (wie der Button): die Station liegt oben.
// 2. Gerät sperren (PIN nur auf dem Emulator): die Station bleibt sichtbar.
// 3. „Beenden“ tippen: die PIN-Abfrage kommt; abbrechen: die Station bleibt.
// 4. „Beenden“ und richtige PIN: die Station geht zu.
// 5. Start per Schnellkachel (`cmd statusbar click-tile`): wieder oben.
//
// Die Host-Aufträge (`station-*`) erledigt `tool/e2e_android.sh`; sie notieren
// ihre Beobachtungen in `files/e2e/station-result.txt`. Aufruf:
// `tool/e2e_android.sh integration_test/station_e2e_test.dart` auf dem
// Emulator, ohne Modelle. Die Station selbst (zweite Engine) braucht den
// Dart-Einstieg `stationMain` in dieser Datei.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/main.dart' as app show stationMain;
import 'package:wendelin/platform/channel_station_port.dart';

import 'support/voice_e2e.dart';

/// The station's Dart entrypoint (the station engine looks for it in the
/// root library, see `overlay_e2e_test.dart`).
@pragma('vm:entry-point')
Future<void> stationMain() => app.stationMain();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Station: Start per Button und Kachel, gesperrt sichtbar, '
      'Beenden verlangt die PIN', (tester) async {
    final e2e = await e2eDirectory();
    await e2e.create(recursive: true);
    final result = File('${e2e.path}/station-result.txt');
    if (result.existsSync()) result.deleteSync();
    addTearDown(() async => askHost('station-unlock'));

    Map<String, String> notes() => {
      for (final line
          in result.existsSync() ? result.readAsLinesSync() : <String>[])
        if (line.contains('='))
          line.split('=').first: line.split('=').last.trim(),
    };

    // 1. Start wie der Button im Kopf des Hauptbildschirms. Kein Widget-Baum:
    // Sobald die StationActivity die Haupt-Engine verdeckt, wird die Fläche
    // 0x0 und die Semantics-Assertion schlägt an. Dass der Button
    // `port.start` aufruft, belegt app/test/screens/main_screen_test.dart:343-352.
    const port = ChannelStationPort();
    await port.start();
    await askHost('station-check');
    // Die Station braucht einen Moment (zweite Engine).
    for (var i = 0; i < 20 && notes()['visible'] != '1'; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      await askHost('station-check');
    }
    expect(notes()['visible'], '1', reason: 'Station nach Button nicht oben');

    // 2. Sperren: die Station liegt über dem Sperrbildschirm.
    await askHost('station-lock');
    expect(notes()['locked'], '1', reason: 'Gerät nicht gesperrt');
    expect(notes()['shown_locked'], '1', reason: 'Station nicht sichtbar');

    // 3. Beenden ohne PIN (Abbruch) beendet nicht.
    await askHost('station-end-cancel');
    expect(notes()['end_tapped'], '1');
    expect(notes()['pin_asked'], '1', reason: 'keine PIN-Abfrage');
    expect(notes()['stays_after_cancel'], '1', reason: 'Station ohne PIN weg');

    // 4. Beenden mit PIN.
    await askHost('station-end-pin');
    expect(notes()['ended_after_pin'], '1', reason: 'Station blieb nach PIN');

    // 5. Start per Schnellkachel.
    await askHost('station-unlock');
    await askHost('station-tile');
    expect(notes()['tile_started'], '1', reason: 'Kachel startet nicht');

    // Aufräumen: die Station per PIN schließen, damit die Test-App wieder
    // vorn ist (bei entsperrtem Gerät harmlos).
    await askHost('station-end-pin');
  });
}
