# Spotify (`spotify__…`)

Wiedergabe über die offizielle Spotify Web API. Die Entscheidung zur Anmeldung und zum Aufwecken steht unten; die Einrichtungsseite liegt in `app/lib/ui/settings/spotify_screen.dart`.

| Tool | Risiko | Undo |
| --- | --- | --- |
| `spotify__search` | r | – |
| `spotify__now_playing` | r | – |
| `spotify__play` (Titel, Album, Künstler, Playlist, per Suchtext oder URI; ohne Angabe: fortsetzen) | w | pausiert bzw. spielt das vorherige Stück an derselben Stelle |
| `spotify__pause` | w | weiter abspielen |
| `spotify__next`, `spotify__previous` | w | keins (Überspringen lässt sich nicht exakt zurücknehmen) |
| `spotify__queue_add` (nur Titel) | w | keins (die Web API kann nichts aus der Warteschlange entfernen) |

## Anmeldung

OAuth 2.0 Authorization Code mit PKCE, ohne Client-Secret. Der Nutzer legt unter developer.spotify.com/dashboard eine eigene App an (Entwicklungsmodus reicht, sein Konto steht dort unter „User Management“), trägt als Redirect URI `app.wendelin://oauth/spotify` ein und gibt die Client-ID in der Einrichtung ein. `SpotifyLogin` öffnet die Anmeldung im Custom Tab (`SpotifyAuthBrowser`, in der App `ChannelAuthorizationBrowser`), prüft `state` und tauscht den Code. Scopes: `user-read-playback-state`, `user-modify-playback-state`, `user-read-currently-playing`.

Client-ID und Tokens liegen nur im `SpotifySecrets` (App: `flutter_secure_storage`, Schlüssel `spotify.*`), nie in Logs, Einstellungen oder Exporten. `SpotifySession` erneuert den Access-Token vor Ablauf bzw. bei 401 (einmal) und pausiert die Integration (Fehlerzustand), wenn der Refresh-Token abgelehnt wird.

## Kein aktives Gerät

Die Web API spielt nur auf einem Spotify-Connect-Gerät. Ist keins aktiv, nimmt `SpotifySession.playbackCommand` ein bekanntes Gerät; gibt es keins und der Befehl startet Musik (`play`, `queue_add`), weckt es die Spotify-App per `SpotifyAppLauncher` (App: Intent `spotify:`) und fragt bis zu `wakeAttempts` Mal im Abstand `wakeInterval` nach dem Gerät. Das App Remote SDK wird nicht benutzt: Es braucht eine Registrierung der App bei Spotify und eine proprietäre AAR (Lizenz „Spotify Developer Terms“, nicht Open Source), und der Intent genügt.

## Fehlertexte

Kein Premium (403 `PREMIUM_REQUIRED`), kein Gerät (404 `NO_ACTIVE_DEVICE`), nicht angemeldet bzw. Anmeldung abgelaufen (401 nach Erneuerung), sonstige 403 mit Hinweis auf „User Management“, 429 mit Sperre bis `Retry-After`. Die Meldungen enthalten nie Tokens oder Antworttexte.

## Hinweise

- Titel, Künstler und Playlistnamen sind fremde Daten: Die Ergebnisse tragen `spotifyDataNotice`, URIs werden gegen `spotifyUriPattern` geprüft.
- Die Tools fragen höchstens 5 Treffer je Art ab (3 bei Suche über alle Arten).
- Prüfpunkte für das Gerät: `docs/testing/m5/README.md`.
