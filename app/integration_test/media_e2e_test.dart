// Gerätetest (WP90): Mediensteuerung über den Kotlin-Kanal `MediaChannel.kt`.
//
// Nur auf einem Emulator ausführen. Der Test passt sich an: Ohne
// Benachrichtigungszugriff prüft er Fehlertext und Medientasten-Fallback,
// mit Zugriff und einem laufenden Test-Player (siehe docs/testing/m5-device.md)
// pausiert, spult und spielt er. Zugriff vorher geben:
//   adb -s emulator-xxxx shell cmd notification allow_listener \
//     app.wendelin/app.wendelin.MediaListenerService
// Die Ausgabe nennt den Fall (`MEDIA_E2E access=… session=…`).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/channel_app_presence_port.dart';
import 'package:wendelin/platform/channel_media_control_port.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const port = ChannelMediaControlPort();
  final integration = MediaIntegration(port, const ChannelAppPresencePort());
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);
  final ctx = ToolContext(
    sessionId: 's',
    clock: FixedClock(DateTime(2026, 1, 1)),
    locale: 'de-DE',
    timeZone: 'Europe/Berlin',
  );

  test('Kanal und Tools: Zugriff, Session, Fallback', () async {
    final access = await port.hasSessionAccess();
    final session = access ? await port.nowPlaying() : null;
    // ignore: avoid_print
    print('MEDIA_E2E access=$access session=${session?.packageName}');
    if (!access) {
      final np = await tool('media__now_playing').execute({}, ctx);
      expect(np.isError, isTrue);
      expect(np.text, contains('Benachrichtigungszugriff'));
      // Medientaste ohne Zugriff: kein Fehler, auch wenn niemand zuhört.
      final pause = await tool('media__pause').execute({}, ctx);
      expect(pause.isError, isFalse, reason: pause.text);
    } else if (session == null) {
      final np = await tool('media__now_playing').execute({}, ctx);
      expect(np.isError, isFalse);
      expect(np.text, contains('läuft nichts'));
    } else {
      final np = await tool('media__now_playing').execute({}, ctx);
      expect(np.isError, isFalse, reason: np.text);
      final pause = await tool('media__pause').execute({}, ctx);
      expect(pause.isError, isFalse, reason: pause.text);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect((await port.nowPlaying())!.playing, isFalse);
      if (session.positionMs != null) {
        final seek = await tool('media__seek').execute({'seconds': 5}, ctx);
        expect(seek.isError, isFalse, reason: seek.text);
        await pause.undo?.run();
      }
    }
    // Audible ist im Emulator nicht installiert.
    final audible = await tool('media__open_audible').execute({}, ctx);
    expect(audible.isError, isTrue);
    expect(audible.text, contains('nicht installiert'));
  });
}
