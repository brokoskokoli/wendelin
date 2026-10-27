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

## Ziel und Prüfung von `spotify__play` (WP161)

Ziel ist immer das Handy, nicht „das gerade aktive Gerät“ (das kann ein toter Rechner sein, der Befehle annimmt und nichts spielt). `SpotifySession.startPlayback` wählt das Gerät in dieser Reihenfolge: ein vom Nutzer genannter Gerätename (Parameter `device`, nur auf ausdrücklichen Wunsch); sonst das Handy, erkannt am gemerkten Gerät, an den Namen aus `SpotifyHostDevice` (App: Gerätename, Marktname und Modell über den Apps-Kanal `deviceNames`) oder am einzigen Gerät vom Typ `Smartphone`. Bei mehreren Smartphones ohne Namenstreffer gilt das Handy als nicht gelistet (kein Raten).

Ein 2xx auf den Befehl heißt nicht, dass etwas spielt. Darum fragt die Session danach bis zu `verifyAttempts` Mal `GET /me/player` und meldet Erfolg nur, wenn dort `is_playing` auf dem Ziel gesehen wird. Das Ziel wird an `device.id` erkannt; liefert Spotify keine Id (erlaubt bei eingeschränkten oder privaten Geräten), zählt der Gerätename (ohne Groß-/Kleinschreibung). Fehlt beides, gilt es als nicht bestätigt. Läuft auf dem Handy nichts, wird die Spotify-App genau einmal geweckt (Intent `spotify:`), auf das Gerät gewartet und der Befehl wiederholt; danach folgt ein ehrlicher Fehler statt „läuft“. `queue_add` und Pause/Weiter nutzen weiter `playbackCommand` (altes Verhalten ohne Prüfung).

Diagnose (`onDiagnostic`, App: Dev-Log `Wendelin/dev`): `spotify-device` (`target` phone/named, `via` cache/name/type, `woke`, `devices`) und `spotify-verify` (`result` playing/idle/other-device/unchecked, `attempts`). Nie Titel, URIs, Tokens oder Gerätenamen.

## Kein aktives Gerät (andere Befehle)

Pause, Weiter, Zurück und `queue_add` gehen über `SpotifySession.playbackCommand`: Ist kein Gerät aktiv, nimmt es ein bekanntes Gerät; gibt es keins und der Befehl startet Musik (`queue_add`), weckt es die Spotify-App per `SpotifyAppLauncher` und fragt bis zu `wakeAttempts` Mal im Abstand `wakeInterval` nach dem Gerät. Das App Remote SDK wird nicht benutzt: Es braucht eine Registrierung der App bei Spotify und eine proprietäre AAR (Lizenz „Spotify Developer Terms“, nicht Open Source), und der Intent genügt.

## Fehlertexte

Kein Premium (403 `PREMIUM_REQUIRED`), kein Gerät (404 `NO_ACTIVE_DEVICE`), nicht angemeldet bzw. Anmeldung abgelaufen (401 nach Erneuerung), sonstige 403 mit Hinweis auf „User Management“, 429 mit Sperre bis `Retry-After`. Die Meldungen enthalten nie Tokens oder Antworttexte.

## Hinweise

- Titel, Künstler und Playlistnamen sind fremde Daten: Die Ergebnisse tragen `spotifyDataNotice`, URIs werden gegen `spotifyUriPattern` geprüft.
- Die Tools liefern höchstens 5 Treffer je Art (3 bei Suche über alle Arten). Bei Playlists fragt die API mit `limit=10` ab und kürzt danach: Spotify füllt `playlists.items` mit `null` für ausgeblendete Playlists und zählt sie gegen `limit`; mit `limit=5` konnte die Seite nur aus `null` bestehen (Ergebnis „nichts gefunden“). Ursache am Gerät nicht live bestätigt, siehe `docs/testing/m5/wp161.md`.
- Ohne Treffer sagt `spotify__play` ehrlich „nichts gefunden, nichts abgespielt“ und bietet höchstens eine Alternative an; es spielt nie still etwas anderes.
- Prüfpunkte für das Gerät: `docs/testing/m5/README.md`.
