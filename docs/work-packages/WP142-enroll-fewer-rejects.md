# WP142 – Einlernen: weniger echte Rufe ablehnen

**Zuordnung:** Folgepunkt WP140 (K114), Entscheidung Maintainer 2026-10-24. Die Inhaltsprüfung aus WP140 hält Störgeräusche draußen (0/480 über den Erkennerweg), lehnt auf den echten Aufnahmen aber 29/120 echte Rufe ab (ruhig 2/60). 6 der 29 Ablehnungen sind „Hey Wendelin“-Rufe, bei denen die Aufnahme nach 440 ms Pause endet. Im E2E verwirft die Ausreißer-Prüfung 1 von 15 Einlern-Aufnahmen.

## Ziel
Im ruhigen Raum fast keine Ablehnung, insgesamt < 10 % abgelehnte echte Rufe; Störgeräusche weiterhin abgelehnt (gleiche Störer-Menge wie WP140: Klick, Klopfen, Räuspern, Stille, Rauschen, andere Wörter).

## Inhalt
1. **Pause bei „Hey Wendelin“:** Die Aufnahme beim Einlernen endet erst nach 0,8–1,0 s Stille (statt 0,44 s), aber höchstens bei der bisherigen Gesamtlänge (`utterance_capture.dart`). An den echten Rufen messen, welche Pause die Abschnitte vermeidet, ohne Nachlauf einzufangen.
2. **Pegel angleichen:** Leise bzw. ferne Aufnahmen vor der Inhaltsprüfung auf einen Zielpegel normalisieren (Spitze bzw. RMS, Begrenzung gegen Übersteuerung).
3. **Unscharfe Wortprüfung:** Erkennungsvarianten wie „Wendlin“, „Wendeline“, „Wändelin“, „Wendolin“, „Wendelien“ annehmen (Liste aus den echten Transkripten der abgelehnten Rufe ableiten, plus begrenzte Edit-Distanz zum Wortstamm), ohne dass Störer durchrutschen.
4. **Beide Wege kombinieren:** Annehmen, wenn der Erkenner **oder** der Klassifikator „Wendelin“ meldet, falls ein Modell installiert ist. Die Klassifikator-Grenze an den Störern messen; in WP140 ließ 0,9 5/410 Störer durch, deshalb die Kombination nur so wählen, dass die Störer-Quote nicht steigt.
5. **Ausreißer-Grenze nachmessen** (d < −0,2 aus WP140) an echten Vorlagensätzen; im E2E darf keine gute Aufnahme mehr verworfen werden.
6. **Rückmeldung je Ablehnung:** konkret „zu leise – näher ans Handy“, „nicht als ‚Wendelin‘ erkannt“, „zu kurz“, de/en/fr.

## Abnahmekriterien
- [ ] Messung auf denselben echten Rufen und Störern wie WP140, vorher/nachher je Bedingung (ruhig/leise/fern, W/HW), Intervalle, plausibel geprüft; Huawei und handy2 sind dieselbe Sitzung (gepaart zählen).
- [ ] Tests mit Mutationsbelegen; E2E Einlernen auf dem Emulator ohne verworfene gute Aufnahme, Störgeräusch abgelehnt.
- [ ] Gate `--changed`, CI grün, Review FREIGABE, Gerätetest-Block ins laufende Protokoll.

## Parallel-Hinweise
- WP137 rechnet nur in `tool/train_wake_word/` und `docs/notes/`. Keine anderen App-Pakete laufen.
