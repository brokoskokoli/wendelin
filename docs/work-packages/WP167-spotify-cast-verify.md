# WP167 – Spotify: Chromecast wird nach dem Befehl als „kommt nichts an“ gewertet

**Zuordnung:** Gerätetest des Maintainers mit rc12 (2026-10-28), Folge von WP166.

## Befund (Dev-Log Handy, 14:21–14:22)
- Chromecast spielte. „Spiel <Künstler>“ → `spotify-device target="active" via="playback" devices=5`: Das spielende Gerät wurde richtig erkannt, der Befehl ging hin.
- Danach `spotify-verify result="stalled" via="api" attempts=3` (≈ 3 s, `verifyInterval` 1 s, `SpotifySession.verifyAttempts`) → `fallback=true` → Handy.
- Maintainer: Der Chromecast hat den neuen Titel kurz angespielt, bevor das Handy übernahm. Die Prüfung ist für Cast-Geräte zu kurz bzw. zu streng.
- Vermutung (zu belegen): Nach einem neuen Kontext meldet die Web-API für Cast-Geräte `progress_ms` verzögert bzw. springt zurück (alter Titel → 0). `SpotifyPlaybackVerifier.check` (`spotify_playback_verifier.dart:~95-106`) wertet einen kleineren Fortschritt als „stalled“ und braucht zwei wachsende Lesungen in 3 s.
- Log-Auszug: `../james-wt/handoff/wp167-phone-log-2026-10-28.txt` (nicht ins Repo, enthält einen Gerätenamen).

## Entscheidung Maintainer (2026-10-28)
- Für Fremdgeräte (nicht das Handy) länger prüfen, bis etwa 10 s.
- Bleibt die Bestätigung aus, **nicht** aufs Handy ausweichen, sondern auf dem Fremdgerät bleiben und ehrlich sagen: „Ich habe es an <Gerät> geschickt, konnte es aber nicht bestätigen.“ (Tote Geräte filtert schon der Vorab-Check aus WP166, `_playingElsewhere`.)
- Ausweichen aufs Handy nur noch, wenn der Befehl am Fremdgerät mit einem Fehler für ein totes Gerät scheitert (404/5xx wie bisher).

## Inhalt
- Ursache belegen (Fake-API mit Cast-typischem Verlauf: Fortschritt zuerst alt, dann 0, dann verzögert wachsend).
- Verifier: Rücksprung des Fortschritts nach dem Befehl als Neustart werten (nicht als „stalled“), für Fremdgeräte längeres Fenster (Parameter, Standard ~10 s), Handy unverändert.
- `_playOnActive` (`spotify_session_devices.dart`): bei `stalled`/`idle` nach Ablauf kein Ausweichen mehr; Ergebnis `confirmed=false`, Text wie oben. Tool-Ergebnistext und Beschreibung entsprechend.
- `docs/testing/m5/wp166.md` C1/C4 anpassen.
- Konzept: K129 ist noch offen; Abweichung melden.

## Abnahmekriterien
- [ ] Test mit Cast-Verlauf (vorher rot, Mutationsbeleg); Test „Fremdgerät unbestätigt → bleibt dort, ehrlicher Satz, kein Handy“; Test „toter Fehler beim Befehl → Handy“.
- [ ] Antwortzeit beim Handy unverändert (Test ohne zusätzliche Wartezeit).
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Läuft allein, nur Spotify-Dateien.
