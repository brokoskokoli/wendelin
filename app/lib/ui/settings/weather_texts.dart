/// All German texts of the weather settings in one place (WP79 moves them
/// into the localization system).
abstract final class WeatherTexts {
  /// Row on the integration page.
  static const setupTitle = 'Wetterdienst und Heimatort';

  /// Detail of that row.
  static const setupDetail = 'Dienst wählen, Ort für „Wetter hier“ festlegen';

  /// Screen title.
  static const title = 'Wetter und Meer';

  /// Intro text.
  static const intro =
      'Alle Wetterdienste sind kostenlos und brauchen keinen Schlüssel. '
      'Meeresdaten (Wellen, Wassertemperatur) kommen immer von Open-Meteo.';

  /// Label of the home place field.
  static const homeLabel = 'Heimatort, z. B. Kiel';

  /// Help below the field.
  static const homeHelp =
      'Wird genutzt, wenn du keinen Ort nennst und der Standort nicht '
      'bekannt ist. Leer lassen = kein Heimatort.';

  /// Home place not found.
  static String notFound(String name) => 'Ort „$name“ nicht gefunden.';

  /// Search failed.
  static const searchFailed = 'Ortssuche nicht erreichbar, später erneut.';

  /// Save button.
  static const save = 'Speichern';

  /// Accessibility label of the selected service.
  static const selected = 'gewählt';
}
