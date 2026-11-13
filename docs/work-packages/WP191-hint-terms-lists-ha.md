# WP191 – Hinweisbegriffe: Listen und Home Assistant sicher drin, Gerätesynonyme, höhere Obergrenze

**Zuordnung:** Wunsch Maintainer 2026-11-13. Manche Listennamen werden nicht sauber erkannt. Listen und Home-Assistant-Geräte sollen sicher als Hinweisbegriffe (Hotwords) an die Spracherkennung gehen, dazu Synonyme je Gerätetyp, alles mit dem bisherigen niedrigen Bonus.
**Konzept:** K150 (offen).

## Befund (Code, 2026-11-13)
- Quellen: `app/lib/di/hint_term_providers.dart:107`, nämlich „Wendelin“, Listen (Name und Aliase), freigegebene HA-Entitäten (Area und Name) und Kontakte.
- `sanitizeHintTerms` (`packages/wendelin_voice/lib/src/recognizer/hint_terms.dart:82`) sortiert nach `HintTermKind`, Kontakte zuerst, und schneidet bei `maxTerms = 64` ab (`:52`). Bei mehr als etwa 60 Kontakten fallen Listen und Geräte ganz heraus. Das ist die vermutete Ursache und muss belegt werden.
- Hotwords wirken nur bei `SttEngine.nemoTransducer` (Parakeet, `speech_model.dart:203`). Der Bonus bleibt bei 1.0 (`defaultHotwordsScore`, WP146).

## Inhalt
- **Teil A, Belegen:** Ein Test zeigt, dass Listen und HA bei vielen Kontakten heute herausfallen. Ein Debug-Log nennt nur Zahlen je Art (keine Namen), also wie viele Begriffe je Art angekommen sind.
- **Teil B, Obergrenze anheben** (Entscheidung Maintainer). Die Messung läuft wie in `docs/notes/hotword-bias-2026-10-25.md` (`tool/voice_quality_measure.py hotword-bias`, Bonus 1.0): Einfügungsrate, WER und Dekodierzeit bei 64, 128, 200 und 300 Begriffen. Gewählt wird der größte Wert ohne messbare Fehleinfügungen und mit vertretbarer Dekodierzeit. Das Ergebnis kommt als Nachtrag in die Notiz. Die Reihenfolge wird so geändert, dass bei Erreichen der Grenze Kontakte zuerst wegfallen: Agent → Liste → Raum → Entität → Synonym → Kontakt.
- **Teil C, Synonyme je Domain** für freigegebene Entitäten. Neuer `HintTermKind.synonym` oder Teil von `entity`, Wahl im Paket. Eine feste Tabelle je Sprache (de/en/fr), z. B. `light` → Lampe, Licht; `cover` → Rollo, Rollladen, Jalousie; `switch` → Schalter, Steckdose; `climate` → Heizung, Thermostat; `fan` → Ventilator; `media_player` → Fernseher, Lautsprecher; `lock` → Schloss. Nur Domains, die unter den freigegebenen Entitäten vorkommen. Die Tabelle steht an einer Stelle und ist leicht erweiterbar.
- Datenschutz wie bisher: nur Namen, nichts verlässt das Gerät, nichts im Log.

## Abnahmekriterien
- [ ] Test: 300 Kontakte plus 5 Listen plus 10 HA-Entitäten ergibt, dass alle Listen und HA-Namen samt Synonymen in den Hotwords stehen.
- [ ] Synonyme erscheinen nur für Domains vorhandener freigegebener Entitäten und folgen der App-Sprache.
- [ ] Die neue Obergrenze ist mit einer Messung belegt (Tabelle im Nachtrag). Der Bonus bleibt 1.0.
- [ ] Mutationsbeleg für Reihenfolge, Obergrenze und Synonymfilter.
- [ ] Gerät: Das Debug-Log zeigt die Anzahl je Art. Ein zuvor schlecht erkannter Listenname wird erkannt (Gerätetest-Block in `docs/testing/m5/`).

## Nicht im Paket
- Bonus ändern, Hotwords für Whisper, Listeninhalte als Begriffe.
