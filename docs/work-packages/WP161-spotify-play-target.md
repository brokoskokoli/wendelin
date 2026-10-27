# WP161 – Spotify: „spielt“, aber nirgends Musik

**Zuordnung:** Gerätetest des Maintainers vom 2026-10-27 (rc10).

## Befund (Dev-Log Handy, 18:51–18:52)
- Anfrage „Spotify mit einer Evening-Chill-Playlist“. `spotify__play` (query, playlist) → „findet nichts“; `spotify__search` (playlist) → leer; Suche ohne Art → Titel; das Modell spielt ein Album per URI. `spotify__play` antwortet nach 740 ms `ok` („Spielt: …“), das Modell sagt „Die Wiedergabe läuft.“
- Auf dem Handy lief nichts: Spotify-App im Hintergrund, von MIUI eingefroren (GreezeManager), Mediensitzung `state=NONE`. Die App wurde nicht geweckt.
- Ursache im Code (Vermutung, zu belegen): `SpotifySession.playbackCommand` (`packages/wendelin_integrations/lib/src/spotify/spotify_session.dart:119-131`) schickt zuerst ohne `device_id`; nur bei 404 `NO_ACTIVE_DEVICE` sucht es ein Gerät bzw. weckt die App. Hält Spotify ein anderes oder ein eingefrorenes Gerät für aktiv, kommt 204, und der Befehl geht dorthin oder verpufft. Das Tool prüft danach nicht, ob und wo etwas läuft.

## Inhalt
- Ursache belegen (Fake-API-Tests für: aktives Fremdgerät, eingefrorenes Handy-Gerät, kein Gerät; ggf. Dev-Log-Zeilen `spotify-device`/`spotify-verify` ohne Titel/Tokens).
- Nach `play` den Zustand prüfen (`GET /me/player`: `is_playing`, Gerät). Läuft nichts: Spotify-App wecken, das Handy-Gerät gezielt wählen (`device_id`, ggf. Transfer), erneut prüfen; scheitert es, ehrliche Fehlermeldung statt „Spielt“.
- Zielgerät: Standard das Handy, auf dem Wendelin läuft (wenn die Spotify-App installiert ist); ein anderes Gerät nur, wenn der Nutzer es nennt oder dort schon Musik läuft. Mit dem Maintainer klären (Buttons, Empfehlung).
- Antwort nennt das Gerät, wenn es nicht das Handy ist.
- Erfolglose Suche nach einer Playlist: ehrlich sagen und Ersatz anbieten bzw. kennzeichnen, statt still ein beliebiges Album zu spielen (Tool-Ergebnistext/Beschreibung).
- Wecken auf MIUI/HyperOS (eingefrorene App) am Handy prüfen lassen; der Intent `spotify:` startet die App ggf. nicht in den Vordergrund.

## Abnahmekriterien
- [ ] Je Fehlerfall ein Test, der vor dem Fix rot ist (Mutationsbeleg).
- [ ] `spotify__play` meldet nur dann Erfolg, wenn danach Wiedergabe bestätigt ist (oder sagt klar, dass es nicht prüfen konnte).
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp161.md` (Spotify im Hintergrund/eingefroren, anderes Gerät aktiv, Playlist nicht gefunden).
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- WP160 läuft (HA, Sicherheitsstufen, Werkzeug-Einstellungen). Keine gemeinsamen Dateien erwartet; l10n nur eigene Schlüssel.
- Log-Auszug: `../james-wt/handoff/wp161-phone-log-2026-10-27.txt` (nicht ins Repo).
