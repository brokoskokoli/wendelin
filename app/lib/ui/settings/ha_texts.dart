/// German texts of the Home Assistant settings (one place for the
/// localization of WP79).
abstract final class HaTexts {
  /// Page title.
  static const title = 'Home Assistant';

  /// Intro under the title.
  static const intro =
      'Wendelin steuert deine freigegebenen Geräte über die Schnittstelle '
      'deines Home Assistant. Nur im Heimnetz oder über Tailscale. '
      'Adresse und Token bleiben im sicheren Speicher des Geräts.';

  /// Label of the address field.
  static const addressLabel = 'Adresse';

  /// Hint in the address field.
  static const addressHint = 'http://homeassistant.local:8123';

  /// Label of the token field.
  static const tokenLabel = 'Long-Lived Access Token';

  /// Helper under the token field.
  static const tokenHelp =
      'In Home Assistant: Profil → Sicherheit → Langlebige Zugriffstokens.';

  /// Note about the address rules.
  static const httpNote =
      'Unverschlüsseltes http ist nur im Heimnetz, über Tailscale '
      '(100.x, *.ts.net) und bei *.local erlaubt, sonst nur https. Über '
      'Tailscale wird nichts automatisch gefunden: Adresse von Hand eingeben.';

  /// Button: search the Wi-Fi.
  static const search = 'Im WLAN suchen';

  /// Button while searching.
  static const searching = 'Suche …';

  /// Nothing found.
  static const nothingFound =
      'Nichts gefunden. Adresse von Hand eingeben (bei Tailscale nötig).';

  /// Heading of the found servers.
  static const found = 'Gefunden';

  /// Button: connect.
  static const connect = 'Verbinden';

  /// Button while connecting.
  static const connecting = 'Verbinde …';

  /// Missing input.
  static const inputMissing = 'Bitte Adresse und Token eingeben.';

  /// Row: connected.
  static const connected = 'Verbunden';

  /// Button: disconnect.
  static const disconnect = 'Trennen';

  /// Confirm title of disconnecting.
  static const disconnectTitle = 'Home Assistant trennen?';

  /// Confirm text of disconnecting.
  static const disconnectMessage =
      'Adresse, Token und die Auswahl der Geräte werden vom Gerät gelöscht.';

  /// Heading of the device list.
  static const devices = 'Geräte freigeben';

  /// Explanation of the device list.
  static const devicesHelp =
      'Nur die gewählten Geräte kennt Wendelin. Schlösser, Alarmanlagen und '
      'Tore fragen immer vorher nach.';

  /// Search field of the device list.
  static const filter = 'Geräte filtern';

  /// Button: reload devices.
  static const reload = 'Geräte neu laden';

  /// Room name for devices without a room.
  static const noRoom = 'Ohne Raum';

  /// Hint when the device list is empty.
  static const noDevices = 'Keine Geräte gefunden.';

  /// Summary of approved devices.
  static String approved(int n) =>
      n == 1 ? '1 Gerät freigegeben' : '$n Geräte freigegeben';

  /// Retry button in the error state.
  static const retry = 'Erneut versuchen';

  /// Retry succeeded.
  static const reachable = 'Home Assistant ist erreichbar.';

  /// Error state title.
  static const errorTitle = 'Fehler – nicht erreichbar';
}
