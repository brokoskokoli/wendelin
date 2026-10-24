# WP140 – Einlernen mit Inhaltsprüfung, unsichere Erkennung verwerfen, Ja/Nein robuster

**Zuordnung:** Gerätetest des Maintainers 2026-10-23 mit APK v0.1.0-rc1 (Log nur Zählungen): (1) Beim Einlernen wurden Klicklaute als „Wendelin“ angenommen. (2) Im Gesprächsmodus kam Erkanntes mit Sicherheit 0,18 bei der KI an, sie antwortete auf etwas, das nicht gesagt wurde. (3) Ein „Ja“ bei der Rückfrage (sichere Aktion) wurde zweimal hintereinander als unklar gewertet, danach blieb nur noch Tippen. Entscheidung Maintainer: alle drei Punkte umsetzen.

## Ist-Stand
- Einlernen: `app/lib/voice/wake/utterance_capture.dart:117-139` nimmt jede Aufnahme an, die ≥ 0,25 s etwa viermal über dem Grundrauschen liegt (`minSpeech`, `minPeak`). Ob „Wendelin“ gesagt wurde, prüft niemand. `wake_enroller.dart:254-270` speichert jede angenommene Aufnahme als Vorlage.
- Erkennungssicherheit: `transcript.confidence` geht in die Pipeline (`packages/wendelin_voice/lib/src/pipeline/voice_pipeline.dart:300`, `:636`), eine Mindestschwelle gibt es nur im Schnellweg (WP135, < 0,5 → Modell). Der normale Weg zum Modell schickt auch sehr unsichere Ergebnisse weiter.
- Ja/Nein: `packages/wendelin_voice/lib/src/text/yes_no.dart`, Auswertung in `app/lib/voice/voice_confirmation.dart` (`confirm-unclear`).

## Inhalt
### A. Einlernen prüft den Inhalt
- Jede Aufnahme zusätzlich prüfen. Annehmen nur, wenn eine der beiden Prüfungen besteht, und dabei wählen, was am Gerät zuverlässig und schnell genug ist (beide messen):
  - (a) die eingestellte Spracherkennung (Parakeet bzw. Whisper; Hotword „Wendelin“, wo verfügbar) erkennt „Wendelin“ bzw. „Hey Wendelin“ (Wortstamm, Erkennungsvarianten wie „Wendlin“), oder
  - (b) bei vorhandenem Klassifikator dessen Wert über einer Mindestgrenze.
- Zusätzlich die Konsistenz prüfen: Liegt eine Vorlage im zentrierten Raum (WP134) weit unter dem Median der übrigen, gilt sie als Ausreißer und wird verworfen bzw. neu aufgenommen.
- Abgelehnte Aufnahmen bekommen einen klaren Hinweis („Nicht als ‚Wendelin‘ erkannt – bitte noch einmal“). Die Zahl der abgelehnten Aufnahmen bleibt sichtbar.
- Bestehende Vorlagen: beim nächsten Start einmal gegen die übrigen prüfen. Ausreißer werden entfernt, ist danach zu wenig übrig, kommt der Hinweis „Neu einlernen“.
- Test mit Fixtures (Klick, Klopfen, Räuspern, Stille, Rauschen, ein anderes Wort): wird abgelehnt; „Wendelin“-Aufnahmen werden angenommen. Mutationsbeleg.

### B. Unsichere Erkennung verwerfen
- Im Gesprächsmodus (Folgefrage ohne Tastendruck bzw. ohne Wake Word) und nach Barge-in: Liegt die Erkennungssicherheit unter der Schwelle (Vorschlag 0,5, an echten Läufen prüfen), geht nichts an das Modell. Die App zeigt bzw. sagt kurz „Nicht verstanden“ (oder bleibt still und hört weiter, je nach Lage, begründen) und loggt `stt-reject reason=low-conf conf=…` (ohne Text).
- Bei Push-to-Talk eine niedrigere Schwelle oder Nachfrage statt stillem Verwerfen, weil der Nutzer bewusst gesprochen hat; begründen.
- Prüfen, woher die 0,18 kam: Echo der eigenen Sprachausgabe (Audio-Quelle, AEC, Nachlauf nach `answer-complete`) oder Raumgeräusch. Ist es Echo, den Nachlauf bzw. das Mikrofon-Fenster beheben.
- Tests: niedrige Sicherheit → kein Modellaufruf (Mutationsbeleg); hohe → normal.

### C. Ja/Nein bei Rückfragen robuster
- Ursache für zweimal `confirm-unclear` klären: Was liefert Parakeet bei kurzem „Ja“ bzw. „Jo“, „Jawohl“, „Ja, mach“? Auf den echten Aufnahmen bzw. synthetisch messen, ob Wörter fehlen, ob die Normalisierung (Satzzeichen, Großschreibung) greift oder ob das Audio zu kurz bzw. abgeschnitten ist (`confirm-listen-end ms`, Vorlauf).
- Wortliste und Normalisierung ergänzen. Für kurze Antworten ggf. Hotwords bzw. Kontext („ja“, „nein“) im Erkenner. Die strenge Bestätigung für sichere Aktionen (Schloss, Garage) bleibt streng: Nur eindeutige Zustimmung zählt, „nein“ oder Unklares bricht ab.
- Test mit typischen Varianten de/en/fr.

## Abnahmekriterien
- [ ] A, B, C mit Tests und Mutationsbelegen; Zahlen (Ablehnungsquote echter „Wendelin“-Aufnahmen, abgelehnte Störgeräusche, Rechenzeit je Prüfung am Emulator) im Bericht, plausibel geprüft.
- [ ] E2E auf dem Emulator: Einlernen mit Störgeräusch wird abgelehnt; Gesprächsmodus mit leiser Störung ruft das Modell nicht auf; „Ja“ bestätigt.
- [ ] Gate `--changed`, CI grün, Review FREIGABE; Gerätetest-Block ins laufende Protokoll; Konzeptabweichungen gemeldet.

## Parallel-Hinweise
- WP137 rechnet nur in `tool/train_wake_word/` und `docs/notes/`, keine Überschneidung. Bis auf Weiteres auf `main` basieren (cbe8d319 ist Stand).
