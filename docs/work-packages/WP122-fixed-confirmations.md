# WP122 – Feste Bestätigungssätze statt zweitem Modellaufruf

**Zuordnung:** M6, Entscheid Maintainer 2026-10-21: „Standardformulierung für die Dinge, die gemacht worden sind … ‚das und das ist jetzt auf der Einkaufsliste‘, ‚Taschenlampe an‘, ‚SMS versendet‘ … da muss ja die KI nicht für fragen.“

## Inhalt
- Heute: Modell ruft ein Tool → App führt aus → **zweiter Modellaufruf** nur für den Antwortsatz. Neu: Für eindeutige Aktionen bildet die App den Satz selbst aus einer festen Vorlage und beendet die Anfrage ohne zweiten Aufruf (spart ~1 s und Kosten).
- **Wann:** Alle Tool-Aufrufe der Modellantwort sind erfolgreich **und** jedes Tool hat eine Bestätigungsvorlage. Sonst (Fehler, Rückfrage, Lese-Tool, Tool ohne Vorlage, Bestätigung abgelehnt, Mehrschritt mit Folgeaufruf nötig) wie bisher zum Modell.
- **Welche Tools:** Schreibende/ausführende Aktionen mit klarem Ergebnis, z. B. Taschenlampe an/aus, Wecker/Timer gestellt, Bring/Listen/Aufgaben hinzugefügt/erledigt („Milch, Eier und Brot stehen jetzt auf der Einkaufsliste“), SMS/Nachricht gesendet, Anruf gestartet, Termin angelegt (mit Datum/Uhrzeit), Notiz gespeichert, Gedächtnis gespeichert, Spotify/Medien Play/Pause/Weiter, HA schalten, Station starten. Lese-Tools (Wetter, Kalender lesen, Suche, Web, nächster Wecker) bleiben beim Modell. Liste im Paket-Bericht.
- **Vorlagen:** je Tool im Tool selbst bzw. an einer Stelle je Integration, Texte in de/en/fr über die vorhandene Übersetzung (ARB oder Text-Dateien je Sprache wie die Wortlisten aus WP119), Platzhalter aus dem Tool-Ergebnis (nicht aus den Modell-Argumenten, wo das Ergebnis genauer ist, z. B. Name der Liste, „schon vorhanden“). Aufzählungen sprachrichtig („A, B und C“). Mehrere Tools in einer Antwort → Sätze aneinander.
- **Verlauf:** Der feste Satz landet als Antwort des Assistenten im Gesprächsverlauf, damit Folgefragen („und noch Butter“) normal funktionieren. Anzeige im Chat wie eine normale Antwort.
- Hatte die erste Modellantwort schon eigenen Text, wird er mit ausgegeben bzw. verdrängt (Wahl begründen, kein Doppel „Mach ich. Taschenlampe ist an.“ nötig).
- Datenschutz: Sätze enthalten nur, was ohnehin in der Antwort stünde; nichts davon in Logs (nur `confirm=fixed tool=<name>`).

## Abnahmekriterien
- [ ] Test mit Fake-Provider: „Taschenlampe an“ → genau **ein** Modellaufruf, Antwort aus der Vorlage; Fehlerfall und Lese-Tool → zwei Aufrufe (Mutationsbeleg).
- [ ] Bring mit drei Artikeln → „…, … und … stehen jetzt auf …“ in de/en/fr (Test); Folgefrage nutzt den Verlauf (Test).
- [ ] Test: jede Vorlage gibt es in jeder Sprache (wie Wortlisten-Test in WP119).
- [ ] Evals gegen Fake-Provider grün (Erwartungen ggf. angepasst, Liste im Bericht); `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE; Gerätetest `docs/testing/m5/wp122.md`.

## Parallel-Hinweise
- WP120 läuft gleichzeitig (Latenz-Log in Agent-Schleife/Adaptern, TTS-Vorlauf). Konfliktpunkt `packages/wendelin_agent/lib/src/agent_runner.dart`: kleine, abgegrenzte Einschübe; vor dem Abschluss `origin/main` mergen. WP121 berührt nur tool/ und docs/notes.
