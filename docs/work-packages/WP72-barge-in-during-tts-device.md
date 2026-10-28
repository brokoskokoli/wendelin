# WP72 – Barge-in während der Sprachausgabe erkennt auf dem Gerät nichts (`app/`, `wendelin_voice`)

Bezug: Gerätetest 2026-10-15 (Testtelefon, Android 16), `ergebnisse.md` Prio 2 Nr. 2; WP64/WP64b (Emulator grün mit Fake-TTS).

## Befund
Weder „Stopp“ (gelernt) noch „Wendelin“ unterbricht, solange die App spricht. `barge-listen on=true`, `mic-start profile=speechOutput`, Android nimmt auf (AudioRecord source=7 VOICE_COMMUNICATION, 16 kHz), aber **keine** `barge-hit`- oder Kandidatenzeile. Ein `barge-hit kind=keyword-wake` kam nur in der Stille direkt nach der Ausgabe. Bei jedem Mikrofonstart `wake-conflict reason=recording`. Auf dem Emulator lief es grün, weil dort keine echte Ausgabe (Fake-TTS) und kein echtes AEC lief.

## Inhalt
- Ursache finden: Kommen während der Ausgabe überhaupt Merkmale/Scores beim Detektor an (Pegel, Fenster, Score-Maxima)? Liefert VOICE_COMMUNICATION mit Echo-Unterdrückung auf diesem Gerät stark gedämpfte/verzerrte Sprache? Passt die Schwelle (+0,05) während der Ausgabe? Wird das Mikrofon evtl. durch den Wake-Dienst (`wake-conflict reason=recording`) oder durch Audio-Fokus stummgeschaltet (`isClientSilenced`)?
- Diagnose-Logs (ohne Inhalte): während Barge-in je Sekunde Pegel (RMS) und höchster Score je Vorlagensatz, damit der Maintainer mit einem Lauf die Ursache belegen kann.
- Fix je nach Ursache, z. B. eigene Schwelle während der Ausgabe, Pegel-Normalisierung, andere Quelle (VOICE_RECOGNITION mit `AcousticEchoCanceler` explizit), Vorlagen auch aus Barge-in-Bedingungen kalibrieren. Lösungen mit Begründung, keine Raterei: wo nur das Gerät entscheiden kann, Varianten per Debug-Einstellung umschaltbar machen und im Prüfpunkt beschreiben.

## Abnahmekriterien
- [ ] Unit-Tests für die gefundene Ursache / den Fix.
- [ ] Diagnose-Logs mit Prüfanleitung in `docs/testing/m4-device.md` 11.6/11.7 (welche Zeilen, was sie bedeuten).
- [ ] Emulator (separater E2E-Agent) weiter grün.
- [ ] Gate grün.
