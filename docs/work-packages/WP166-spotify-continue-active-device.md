# WP166 – Spotify: läuft schon etwas, dort weiterspielen statt aufs Handy wechseln

**Zuordnung:** Gerätetest des Maintainers mit rc11 (2026-10-28). Korrigiert die Zielgerät-Regel aus WP161 (K129, noch offen).

## Befund (Maintainer)
- Spotify spielt mit rc11 zuverlässig, aber immer auf dem Handy. Lief gerade Musik auf dem Chromecast und der Maintainer sagte „spiel das“, stoppte der Chromecast und das Handy spielte.
- Die Regel „immer aufs Handy“ war ein Missverständnis (Maintainer 2026-10-28, sinngemäß): „Wenn ich gerade eine Wiedergabe neu starte und es nirgendwo was läuft, dann bitte auf meinem Gerät starten. Ansonsten die Wiedergabe immer auf dem Gerät starten, wo gerade schon was läuft. Auf dem Chromecast soll er das dann auf dem Chromecast spielen.“

## Gewollte Regel
1. Nennt der Nutzer ein Gerät ausdrücklich: dort (wie WP161).
2. Sonst: Spielt gerade auf dem Konto ein Gerät tatsächlich (`GET /me/player`: `is_playing == true`, Gerät nicht eingeschränkt): dort spielen.
3. Sonst (nichts läuft, nur pausiert oder kein aktives Gerät): auf dem Handy, App wecken (wie WP161).

## Risiko aus WP161
Der ursprüngliche Fehler war ein totes, für Spotify noch „aktives“ Connect-Gerät, auf dem nichts lief. Möglich, dass Spotify dort sogar `is_playing` meldete. Deshalb: Nach dem Befehl auf einem fremden Gerät die Wiedergabe wie in WP161 prüfen (Fortschritt wächst über die Web-API). Läuft dort nach der Prüfzeit nichts, auf das Handy ausweichen und das in der Antwort sagen („Auf <Gerät> kam nichts an, ich spiele auf dem Handy.“). Prüfen, ob `progress_ms`/`timestamp` vor dem Befehl schon zeigt, dass das Gerät tot ist (Fortschritt steht trotz `is_playing`), und es dann gleich überspringen.

## Inhalt
- Zielwahl in `SpotifySession` (`packages/wendelin_integrations/lib/src/spotify/spotify_session.dart`, `_choose`, ab Z. ~175/258) nach der Regel oben; Log `spotify-device target="active|phone|named"` (ohne Gerätenamen).
- Antwort nennt das Gerät, wenn es nicht das Handy ist (wie bisher).
- Tool-Beschreibung von `spotify__play` anpassen (Modell soll nicht „auf dem Handy“ behaupten).
- `docs/testing/m5/wp161.md` C2 anpassen bzw. neue Anleitung `docs/testing/m5/wp166.md` (Chromecast läuft → dort; Chromecast pausiert → Handy; totes aktives Gerät → Ausweichen aufs Handy mit Hinweis; benanntes Gerät).
- Konzept: K129 ist noch offen; die Abweichung melden, der Orchestrator passt K129 an.

## Abnahmekriterien
- [ ] Fake-API-Tests: aktives spielendes Fremdgerät → dort; pausiertes Fremdgerät → Handy; nichts aktiv → Handy; spielendes, aber totes Gerät (Fortschritt wächst nicht) → Handy mit Hinweis; benanntes Gerät → dort. Je Fall Mutationsbeleg.
- [ ] `spotify__play` meldet weiter nur bei bestätigter Wiedergabe Erfolg.
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Läuft allein. Nur Spotify-Dateien, keine gemeinsamen Dateien erwartet.
