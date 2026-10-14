# WP67 – Jeder Assistenten-Aufruf beginnt ein neues Gespräch (`app/`)

Bezug: Gerätetest Maintainer 2026-10-15: Nach einem Gespräch über Glocken wurde der Assistent neu gestartet und knüpfte wieder an die Glocken an. Das soll nicht so sein.

## Inhalt
- Jeder neue Aufruf des Assistenten-Overlays (Assistenten-Taste/Geste, Wake Word, Kachel, gesperrter Bildschirm) startet mit leerem Gesprächsverlauf; das Modell bekommt nichts aus dem vorigen Overlay-Gespräch (Gedächtnis-Einträge nach den bestehenden Regeln bleiben erlaubt).
- Innerhalb eines Overlay-Aufrufs (Gesprächsmodus, Folgefragen, Barge-in) bleibt der Verlauf erhalten.
- Das Hauptfenster der App (Chat) behält sein Verhalten („Neues Gespräch“-Knopf, K18 c); Overlay-Gespräche verdrängen den App-Chat nicht. Prüfen und im Bericht festhalten, ob Overlay und App-Chat heute denselben Verlauf teilen; falls ja, trennen. Abgeschlossene Overlay-Gespräche dürfen im Verlauf/Archiv auftauchen, wenn es das gibt.
- Datenschutz-Untergrenze/Taint (K13 d) wird mit dem neuen Gespräch zurückgesetzt.

## Abnahmekriterien
- [ ] Tests: zwei aufeinanderfolgende Overlay-Aufrufe → der zweite Request enthält keine Nachrichten des ersten; Folgefrage im selben Aufruf enthält den Verlauf; App-Chat unverändert.
- [ ] Emulator (separater E2E-Agent): zwei Aufrufe nacheinander, zweiter ohne Bezug.
- [ ] Gate grün.
