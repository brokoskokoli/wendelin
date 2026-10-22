# WP135 – Smart Home schneller: Geräteliste, Synonyme, feste Bestätigung, Schnellweg, Rollo ohne Rückfrage

**Zuordnung:** K108 (zu K53, K57, K89, WP91, WP119, WP122). Testbefund und Entscheidung Maintainer 2026-10-22: Licht/Rollo schalten braucht 4–6 Schritte und dauert zu lange; „Lampe“ klappt nicht, „Licht“ schon. Umfang A–E wie unten; Nutzungsstatistik nicht.

## Ist-Stand (Code-Analyse 2026-10-22)
- Bestfall 1 Modellaufruf + `ha__call` + feste Bestätigung (WP122, `packages/wendelin_agent/lib/src/run/fixed_answer.dart:50-104`); ha-Tools werden per Themenwort vorab freigeschaltet (`tool_registry.dart:186-219`, `topic_words/de.dart:39-43`).
- Keine Geräteliste im Prompt; `ha__call` beschreibt nur „Gerät wie gesagt oder Entity-Id aus ha__list_entities“ (`ha_call_tools.dart:143-148`) → häufig Extra-Runde `ha__list_entities`.
- `HaContext.resolve` (`ha_context.dart:55-84`) nutzt nur Wort-/Stammgleichheit (`common/matching.dart:95-103`): „Lampe“ trifft „Licht Wohnzimmer“ nicht → notFound → weitere Runden.
- Feste Bestätigung nur für einfaches turn_on/turn_off (`ha_call_tools.dart:249-257`); Rollo, Position, Helligkeit, Temperatur → zweiter Modellaufruf.
- `cover` (inkl. Rollläden) läuft immer über `ha__call_secure` mit Bestätigung.
- `HaEntityStore.load()` liest bei jedem resolve aus dem SecretStore (`app/lib/di/home_assistant.dart:55-61`); je `ha__call` GET state + POST service.

## Inhalt
0. **Erst messen:** Ablauf eines echten Laufs aus dem Debug-Log des Maintainers (Anzahl Modell-/Tool-Aufrufe, Dauer je Schritt) für „Licht … aus“, „Lampe … an“, „Rollo … runter“, „Rollo … auf 50 %“; bei Abweichung zur Analyse oben den Grund klären. Danach dieselbe Messung als Vorher/Nachher (Eval mit Fake-Provider zählt Aufrufe).
- **A Geräteliste:** Ist `ha` vorab freigeschaltet, bekommt das Modell die freigegebenen Geräte kompakt (Name, Raum, Typ; Datenschutzfilter K10 und `sensitive` gelten). Begrenzung bei vielen Geräten (z. B. nach Raum/Typ aus der Anfrage filtern). Store im Speicher halten (Invalidierung bei Änderung); Abgleich von Namen/Räumen mit Home Assistant beim App-Start bzw. höchstens einmal täglich, Fehler ohne Wirkung auf Aufrufe.
- **B Synonyme/Typ:** je Sprache Wortliste Gerätetyp → Domain (Lampe, Leuchte, Licht, Birne → light; Rollo, Rollladen, Jalousie, Markise → cover; Steckdose → switch; Heizung, Thermostat → climate). `resolve` nutzt Raum + Typ, wenn der Name nicht passt („Lampe Wohnzimmer“ → einziges Licht im Wohnzimmer); mehrere Treffer bleiben „Mehrdeutig“.
- **B2 Aktions-Synonyme (Maintainer 2026-10-22):** je Sprache auch für Aktionen, inkl. Umgangssprache und Varianten der Spracherkennung, nicht nur 1:1 übersetzt. Beispiele de: öffnen ← rauf, hoch, auf, aufmachen, öffnen, hochfahren; schließen ← runter, herunter, zu, zumachen, schließen, runterlassen, runterfahren; stoppen ← stopp, anhalten, halt; an ← an, ein, anmachen, einschalten, anschalten; aus ← aus, ausmachen, ausschalten, abschalten; heller/dunkler, Prozent („auf 50 %“, „halb“ = 50 %). Auch Erkennungsfehler wie „Rolle“ für „Rollo“. Gleiche Liste für B, D und die Wortliste der Vorauswahl; ein Test prüft, dass jede Sprache jede Aktion abdeckt.
- **C Feste Bestätigung** für cover öffnen/schließen/stoppen/Position, Licht mit Helligkeit, Klima-Temperatur, mit Werten aus dem Ergebnis („Rollo Wohnzimmer auf 50 %“), de/en/fr; Fehler oder rote Belegprüfung → wie bisher Modell.
- **D Schnellweg ohne KI:** einfache Sätze (Gerät/Raum/Typ + an/aus/rauf/runter/stopp/Prozent) werden lokal erkannt und direkt ausgeführt, mit fester Bestätigung und Undo wie `ha__call`. Nur bei eindeutigem Gerät und eindeutiger Aktion; sonst normaler Weg. Nie für Schloss, Alarm, Garage/Tor oder „Immer bestätigen“-Geräte. Abschaltbar in den Einstellungen (Standard an). Erscheint im Verlauf wie ein normaler Aufruf.
- **E Rollo ohne Rückfrage:** je Gerät der Domain cover mit Geräteklasse shutter/blind/awning/curtain eine Option „ohne Rückfrage“ (Standard aus); dann läuft es über `ha__call` mit Undo. Garage/Tor/Tür (garage, gate, door) bleiben immer mit Bestätigung; Geräteklasse fehlt → mit Bestätigung. Sperrbildschirm-Regeln (WP92) unverändert.

## Abnahmekriterien
- [ ] Vorher/Nachher-Messung (Log + Eval): „Licht/Lampe … aus“ 0 Modellaufrufe über D bzw. höchstens 1 ohne D; „Rollo … auf 50 %“ ohne zweiten Modellaufruf. Zahlen auf Plausibilität geprüft.
- [ ] Tests: Synonym-Auflösung, Mehrdeutigkeit, Schnellweg lehnt Unsicheres und sichere Domains ab (Mutationsbelege), Option E nur für die genannten Geräteklassen, Garage bleibt mit Bestätigung.
- [ ] Texte de/en/fr, Wortlisten je Sprache getrennt (wie WP119), Doku im README der Integration.
- [ ] Gate `--changed`, CI grün, Review FREIGABE (Schwerpunkt Sicherheit D/E), E2E mit Fake-HA, Gerätetest-Block ins laufende Protokoll.

## Parallel-Hinweise
- Berührt `wendelin_integrations/home_assistant`, `wendelin_agent` (Schnellweg vor dem Modellaufruf, Prompt), `wendelin_core/topic_words`, App-Einstellungen HA. Keine Wake-Dateien → parallel zu WP129/WP133/WP134 möglich.
