# WP155 – Entwicklermodus: Weckwort-Archiv für Training

**Zuordnung:** Wunsch des Maintainers vom 2026-10-26. Baut auf WP148 (Entwicklermodus, `DevClips`, `packages/wendelin_voice/lib/src/dev/dev_clips.dart`, `app/lib/voice/dev_audio.dart`) auf. Ziel: über Wochen echte Beispiele sammeln – erkannte, verworfene und knapp verfehlte Weckwörter –, die der Maintainer später anhört und als Trainingsdaten freigibt (Prüfseite folgt als eigener Auftrag).

## Ist-Stand
- WP148 schreibt `wake-cand`/`wake-verify`/`barge-cand`/`barge-verify`/`rec` nach `dev-audio/` und löscht beim Start alles älter als 1 Tag bzw. über der Obergrenze. Für Trainingsdaten ist das zu kurzlebig, und Fälle unter der Kandidatenschwelle (knapp verfehlt) fehlen ganz.

## Inhalt
- **Eigenes Verzeichnis** `dev-audio/wake-archive/` (per `adb pull` abrufbar, kein Upload). Nur bei eingeschaltetem Entwicklermodus; ohne Modus wird nichts gesammelt.
- **Was gespeichert wird** (je Fall ein WAV mit ±2 s um den Treffer plus eine JSON-Zeile mit Metadaten):
  - jeder Weckwort-Kandidat im Ruhezustand, angenommen **und** verworfen (direkt ≥ 0,999, Band mit Prüfung, Prüfung abgelehnt),
  - jeder Barge-in-Kandidat (angenommen, abgelehnt, wegen `busy` verworfen),
  - **knapp verfehlte** Fälle: Stufe-1-Score über einer Sammelschwelle unter der Kandidatenschwelle (Vorschlag 0,5; im Paket an Zahlen begründen, Rate pro Stunde im Bericht), damit auch nicht erkannte Weckwörter dabei sind,
  - zusätzlich der Prüf-Ausschnitt, falls es eine Prüfung gab.
- **Metadaten** (`index.jsonl`, eine Zeile je Fall): Zeit, Dateiname(n), Quelle (`idle`/`barge`), Stufe-1-Score/Ähnlichkeit, Schwellen, Prüfer (`b`/`hw2`) und Ergebnis, Parakeet-Text und lp (nur Entwicklermodus), Modus (Gesprächston/`mic mode`), App-Version, Ergebnis gesamt (`accepted`/`rejected`/`dropped`/`near-miss`). Feld `label` leer (für die spätere Prüfseite).
- **Aufbewahrung:** keine 1-Tage-Löschung für das Archiv; eigene Obergrenze (Vorschlag 1 GB, älteste zuerst raus, Zahl im Paket begründen). In den Entwickler-Einstellungen: Anzahl/Größe des Archivs und „Archiv löschen“ (mit Rückfrage).
- **Doku:** Abrufweg und Format in `docs/testing/m5/wp155.md` (wie ziehen, wie `index.jsonl` lesen), Datenschutz-Abschnitt aus WP148 ergänzen.

## Zusatz aus dem Projekt-Review (2026-10-26, Entscheidung Maintainer)
- **Ausschalten:** Beim Ausschalten des Entwicklermodus werden die kurzlebigen Dev-Aufnahmen (`dev-audio/` ohne Archiv) sofort gelöscht (`app/lib/voice/dev_audio.dart:19,135-140`, `app_language_screen.dart:51-52`). Das Weckwort-Archiv bleibt; beim Ausschalten fragt die App einmal, ob es mitgelöscht werden soll.
- **Schwärzung:** `packages/wendelin_storage/lib/src/redaction.dart:65-78,111-115` kennt die Schlüssel `pin`, `otp`, `code`, `state` nicht; Werkzeugargumente als JSON (`{"pin":"1234"}`) und URLs mit `?code=` erscheinen im Dev-Log (`dev_agent_log.dart:57-59`). Schlüssel ergänzen, Tests für JSON und Query-Parameter, dazu die WP148-Folgepunkte („PIN – 1234“, Überschwärzung „TAN 123456. Danke“).

## Abnahmekriterien
- [ ] Ausschalten löscht Dev-Aufnahmen, Archiv nur nach Rückfrage (Tests).
- [ ] Schwärzung für `pin`/`otp`/`code`/`state` in JSON und Query (Tests mit Mutationsbeleg).
- [ ] Ohne Entwicklermodus: kein Archiv, keine Zeile (Test, Mutationsbeleg).
- [ ] Mit Modus: je Fallart (angenommen, abgelehnt, busy, near-miss, Barge-in) genau ein Eintrag mit WAV und `index.jsonl`-Zeile (Tests mit Fake-Erkennung).
- [ ] Archiv übersteht den Neustart (keine 1-Tage-Löschung), Obergrenze greift (Test).
- [ ] Schreiben blockiert den Sprachpfad nie, Fehler beim Schreiben ändern nichts am Ergebnis (Test).
- [ ] E2E auf dem Emulator: Weckwort-WAV abspielen, Archiv per `adb pull` holen, Einträge passen zum Log.
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Nicht im Paket
- Die Prüfseite zum Anhören und Markieren (eigener Auftrag später) und das Training selbst.

## Parallel-Hinweise
- Berührt `wake_barge_in.dart` und den Wake-Pfad: nach WP151 starten.
