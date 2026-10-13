# WP17 – Sprach-Plattform Android (`app/lib/platform/voice/`)

Abhängig von: WP15. Konzept-Bezug: „Sprach-Pipeline“, „Bausteine → Audio“, K7.

## Inhalt
- `sherpa_onnx` (FFI): Silero VAD und Whisper (`base`, `small`) als Implementierungen von `VoiceActivityDetector`/`SpeechToText`; Sprache automatisch oder fest (de/fr/en); Konfidenz aus dem Modell oder heuristisch.
- `record` für 16-kHz-Mono-PCM als `AudioInput`; Mikrofon-Berechtigung erst beim ersten Sprechen bzw. Aktivieren, mit Erklärung.
- `flutter_tts` als System-TTS (`isAvailable` = Engine vorhanden), sherpa-onnx-TTS (VITS/Piper-Stimmen de/fr/en) als Fallback (K7); Auswahl über `TtsSelector`.
- `ModelStore` im App-Verzeichnis; Download-UI (Onboarding-Schritt „Spracherkennung laden“, Einstellungen → Sprache: Modellgröße, Sprache, TTS-Stimme/Tempo).
- Prüfen: keine Google-Play-Abhängigkeiten in den Plugins (check_deps + dex-Prüfung).
- **STT-Qualität**: Fixtures aus kurzen Sätzen (de/fr/en, je ≥ 10), erzeugt z. B. mit macOS `say` + Konvertierung nach 16 kHz WAV (Skript in `tool/`), plus Platz für eigene Aufnahmen des Maintainers; Test/Skript misst Wortfehlerrate pro Modellgröße (läuft lokal auf macOS über sherpa_onnx-Desktop-Bindings, in CI optional).

## Abnahmekriterien
- [ ] Implementierungen bestehen die Contract-Suites aus WP15 (Mock-Kanal bzw. Desktop-FFI, wo möglich).
- [ ] WER-Report für base/small auf den Fixtures (Zahlen im PR).
- [ ] Modell-Download mit Fortschritt/Abbruch/Prüfsumme in der UI, Widget-Tests.
- [ ] `flutter build apk --debug`, APK ohne GMS; APK-Größe dokumentiert (Modelle nicht enthalten).
