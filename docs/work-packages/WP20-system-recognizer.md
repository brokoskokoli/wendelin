# WP20 – Lokale System-Spracherkennung (RecognitionService mit Whisper)

Abhängig von: WP17, WP18. Konzept-Bezug: K7 (ohne Google-Dienste), „Sprach-Pipeline → STT“.

Android verlangt für die Assistenten-Rolle einen `RecognitionService`. Bisher ist das ein Platzhalter, der Fehler liefert; solange Wendelin Assistent ist, funktioniert die System-Spracheingabe anderer Apps nicht. Ziel: Der Dienst erkennt Sprache lokal mit Whisper (sherpa-onnx) und Silero VAD – damit wird Wendelin auf Geräten ohne Google zur nutzbaren Offline-Spracherkennung für alle Apps.

## Inhalt
- `RecognitionService` (Kotlin) nimmt Audio selbst auf (oder über die vorhandene Aufnahme-Schicht), Endpointing wie die Pipeline (VAD, 800 ms Stille, max. 30 s), liefert `onReadyForSpeech`, `onBeginningOfSpeech`, `onRmsChanged`, `onEndOfSpeech`, `onResults` (und `onPartialResults` falls möglich), Fehlercodes korrekt (`ERROR_NO_MATCH`, `ERROR_SPEECH_TIMEOUT`, `ERROR_INSUFFICIENT_PERMISSIONS`, `ERROR_CLIENT`).
- Sprache aus `EXTRA_LANGUAGE` (de/fr/en), sonst App-Einstellung; Modell aus der App-Einstellung; ohne geladenes Modell sauber `ERROR_CLIENT`/Hinweis.
- Whisper läuft nativ oder über eine Headless-Flutter-Engine/Isolate – Architekturentscheidung als ADR (Speicher, Startzeit, Gleichzeitigkeit mit der App-Pipeline).
- Weiterhin nur aktiv, wenn Wendelin die Assistenten-Rolle hält (WP18), plus optionale Einstellung „Als Spracherkennung für andere Apps anbieten“.
- Kein Audio verlässt das Gerät; keine Speicherung der Aufnahmen.

## Abnahmekriterien
- [ ] Emulator-Test: eine Test-App bzw. Instrumentationstest ruft `SpeechRecognizer` mit einer eingespeisten WAV-Datei auf und bekommt das erwartete Ergebnis.
- [ ] Fehlerpfade getestet (keine Berechtigung, kein Modell, Stille, Abbruch).
- [ ] Gate grün, APK GMS-frei.
