# WP172 – Overlay schließt sich nach dem Zuhören ohne Antwort, Weckwort wieder bereit

**Zuordnung:** Wunsch des Maintainers vom 2026-10-28 (Gerätetest v0.1.0).

## Wunsch (sinngemäß)
„Wenn man mit dem Weckwort etwas aufruft, der Assistent antwortet und fertig ist, und ich in den ~5 Sekunden nichts antworte, dann hört er auf zuzuhören – dann soll das Fenster auch wieder zugehen und nicht stehen bleiben. Aktuell kann ich ihn dann auch nicht wieder aufrufen.“
Entscheidung Maintainer: **immer** schließen, egal ob per Weckwort, Taste oder Geste geöffnet.

Präzisierung Maintainer (2026-10-28): „Allgemein kann das Fenster sich immer schließen, wenn es aufhört zuzuhören.“ Das gilt auch, wenn nach dem Weckwort gar nichts gesagt wird: Zuhören endet ohne Äußerung → Fenster zu.

## Inhalt
- Nach Ende des Folge-Zuhörens ohne Äußerung (Gesprächsmodus) bzw. nach der Antwort ohne Gesprächsmodus schließt das Overlay selbst (`overlay-close by=idle` im Log). Nicht schließen, solange der Nutzer interagiert (Tippen, Tastatur, offene Rückfrage/Bestätigung, Entsperr-Abfrage aus WP153/WP163, laufende Wiedergabe der Antwort).
- Ursache „kann ihn nicht wieder aufrufen“ belegen: Weckwort pausiert, solange das Overlay offen ist? Nach dem Schließen muss das Weckwort sofort wieder lauschen (`wake-start`/Resume im Log), und Taste/Geste müssen ein neues Overlay öffnen.
- Einstellung nötig? Nur wenn die Sitzung es mit dem Maintainer so klärt (Standard: an).
- Gerätetest-Anleitung `docs/testing/m5/wp172.md`.

## Abnahmekriterien
- [ ] Tests: Folge-Zuhören endet ohne Äußerung → Overlay zu (vorher rot, Mutationsbeleg); Rückfrage/Bestätigung offen → bleibt offen; danach Weckwort wieder aktiv.
- [ ] E2E auf dem Emulator: Anfrage, Antwort, Stille → Overlay zu → erneuter Aufruf möglich.
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- WP171 (Weckwort-Prüfung) läuft gleichzeitig, berührt `wake_host.dart`/`device_wake_parts.dart`; hier nur das Wiederaufnehmen nach dem Schließen, kleine Diffs.
