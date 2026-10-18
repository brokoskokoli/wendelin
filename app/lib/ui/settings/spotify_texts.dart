/// German texts of the Spotify settings page, in one place (WP79 moves them
/// to the localization files).
abstract final class SpotifyTexts {
  /// Page title.
  static const title = 'Spotify';

  /// Intro under the title.
  static const intro =
      'Wendelin steuert Spotify über die offizielle Schnittstelle. Dafür '
      'braucht es ein Spotify-Premium-Konto und eine eigene (kostenlose) '
      'Entwickler-App von dir. Client-ID und Anmeldung bleiben im sicheren '
      'Speicher des Geräts.';

  /// Heading of the guide.
  static const guideTitle = 'Entwickler-App anlegen';

  /// Steps of the guide; `{redirect}` is replaced by the redirect address.
  static const guideSteps = [
    '1. Auf developer.spotify.com/dashboard mit dem Spotify-Konto anmelden '
        'und „Create app“ wählen.',
    '2. Name und Beschreibung frei wählen. Als „Redirect URI“ genau diese '
        'Adresse eintragen: {redirect}',
    '3. Bei „Which API/SDKs are you planning to use?“ „Web API“ ankreuzen '
        'und speichern.',
    '4. Unter „Settings“ die „Client ID“ kopieren und unten eintragen. Im '
        'Entwicklungsmodus muss das eigene Konto unter „User Management“ '
        'stehen.',
  ];

  /// Label of the copy button for the redirect address.
  static const copyRedirect = 'Adresse kopieren';

  /// Hint after copying.
  static const copied = 'Adresse kopiert.';

  /// Label of the Client-ID field.
  static const clientIdLabel = 'Client-ID';

  /// Error when the field is empty.
  static const clientIdMissing = 'Bitte die Client-ID eintragen.';

  /// Sign-in button.
  static const signIn = 'Bei Spotify anmelden';

  /// Sign-in button while busy.
  static const signingIn = 'Anmelden …';

  /// Sign-out button.
  static const signOut = 'Abmelden';

  /// Confirmation title of the sign-out.
  static const signOutTitle = 'Von Spotify abmelden?';

  /// Confirmation text of the sign-out.
  static const signOutMessage =
      'Client-ID und Anmeldung werden vom Gerät gelöscht.';

  /// Row title when signed in.
  static const signedIn = 'Angemeldet';

  /// Row title when failed.
  static const failed =
      'Fehler – Anmeldung abgelaufen oder Spotify nicht '
      'erreichbar';

  /// Retry button.
  static const retry = 'Erneut versuchen';

  /// Retry button while busy.
  static const retrying = 'Prüfe …';

  /// Hint after a successful retry.
  static const reconnected = 'Spotify ist wieder erreichbar.';

  /// Title of the app section.
  static const appTitle = 'Spotify-App';

  /// Explanation of the app section.
  static const appNote =
      'Die Spotify-App wird gebraucht, damit Wendelin auf diesem Handy '
      'abspielen kann: Läuft sie nicht, startet Wendelin sie. Auf anderen '
      'Geräten (Lautsprecher, Computer) spielt Wendelin auch ohne sie.';
}
