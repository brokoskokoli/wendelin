# WP115 – Große Modelle streamend entpacken, erkannte Sprache loggen (`app/`)

**Zuordnung:** M5-Nachtest (Gerätetest 2026-10-20, T20-P.1, T20-V).

## Befund
- Parakeet v3 (487 MB) lädt, Entpacken scheitert zweimal mit „Das Archiv ist zu groß oder beschädigt und wurde nicht entpackt.“ Vermutung: `app/lib/platform/voice/tar_bz2.dart` hält Archiv und Tar komplett im Speicher, der Decoder wirft (Speicher oder `maxOutputSize`), `on Object` verdeckt die Ursache. Im Log steht nichts.
- Einmal wurde die falsche Sprache erkannt; die erkannte Sprache steht nicht im Log.

## Inhalt
1. Entpacken streamend (Datei → bz2 → tar → Dateien), Speicher unabhängig von der Archivgröße; Grenzen gegen Zip-Bomben bleiben (Gesamtgröße, Pfade außerhalb des Ziels), aber passend zu den Katalog-Größen. Platzprüfung vorab mit klarer Meldung.
2. Fehler beim Laden/Entpacken im Log (`Wendelin/voice`, Art des Fehlers, Größen, ohne Pfade mit Nutzerdaten).
3. Erkannte Sprache je Äußerung loggen (Sprache, Konfidenz, Quelle; kein Inhalt).

## Abnahmekriterien
- [ ] Test mit großem synthetischem Archiv (Speicher begrenzt bzw. Streaming nachgewiesen), Tests für Pfad-Ausbruch und Größenlimit (Mutationsbeleg).
- [ ] Gerätetest-Datei `docs/testing/m5/wp115.md` (Parakeet v3 laden).
- [ ] Gate `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Berührt `app/lib/platform/voice/` (Modell-Laden) und den STT-Adapter für das Log, nicht den Sprach-Controller. Parallel zu WP112, WP113, WP116.
