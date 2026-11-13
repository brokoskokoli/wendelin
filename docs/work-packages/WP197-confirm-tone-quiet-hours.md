# WP197 – Bestätigungston beachtet die Ruhezeiten des Stationsmodus

**Zuordnung:** Entscheidung Maintainer 2026-11-13 (Folgefrage aus WP195). Laut Konzept gilt in den Ruhezeiten des Stationsmodus „kein Bestätigungston“. Heute spielt der Ton beim Weckwort-Treffer trotzdem. Der Stopp-Ton aus WP195 hält die Ruhezeit bereits ein.
**Konzept:** keine Änderung (Abschnitt Stationsmodus, „Ruhezeiten … kein Bestätigungston“).

## Befund
- `app/lib/voice/wake/wake_pre_roll.dart:41` spielt den Ton bei `tone && !continues`, ohne die Ruhezeit zu prüfen.
- `_stationQuiet(ref)` (`wake_pre_roll.dart` ~66) prüft die Ruhezeit bereits für `playStopTone`.

## Inhalt
- Der Bestätigungston beim Weckwort-Treffer fällt weg, solange `_stationQuiet` zutrifft. `muteMicSamples` folgt wie bisher dem tatsächlich gespielten Ton: Ohne Ton wird nichts stummgeschaltet.
- Die Prüfung steht an einer Stelle (gemeinsame Funktion für beide Töne).

## Abnahmekriterien
- [ ] Test: Station aktiv und Ruhezeit ergibt keinen Bestätigungston und `muteMicSamples == 0`. Außerhalb der Ruhezeit oder ohne Station spielt der Ton wie bisher.
- [ ] Mutationsbeleg für die Ruhezeit-Prüfung beim Bestätigungston.
- [ ] Gerätetest-Zeile in `docs/testing/m5/wp195.md` bzw. ein neuer kurzer Block `wp197.md`.

## Nicht im Paket
- Ruhezeiten außerhalb des Stationsmodus.
