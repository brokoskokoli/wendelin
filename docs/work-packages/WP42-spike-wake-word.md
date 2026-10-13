# WP42 – Spike Wake Word und Audio (Messung, Entscheidung)

Abhängig von: – (sofort startbar). Ergebnis: Notiz `docs/notes/wake-word-spike-<datum>.md` mit Messwerten und Entscheidungen. Produktivcode kommt nicht auf `main`; wiederverwendbare Messskripte unter `tool/` sind erlaubt. Grundlage: `M4.md`, Recherche 1–3.

## Fragen und Messungen

1. **Genauigkeit „Wendelin“ mit sherpa-onnx KWS.** Getestet wird `sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20` (chunk-8 und chunk-16, int8) gegen `gigaspeech-3.3M` (BPE). Schlüsselwort-Varianten: `V EH1 N D AH0 L IY2 N`, `W EH1 N D AH0 L IH0 N`, `V EH1 N D AH0 L IH0 N` und weitere aus den Messungen. Je Zeile werden Boost (`:`) und Schwelle (`#`) variiert.
   - Positivsatz: synthetische Aufnahmen (sherpa-TTS Thorsten de, eigene Stimme per Systemstimme), dazu 20–30 Aufnahmen des Maintainers (Frage 6 in `M4.md`), mit und ohne Raumhall/Rauschen (Mischung per Skript).
   - Negativsatz: deutsche Sprache ohne das Wort (STT-Fixtures aus `app/test/fixtures/stt/`, gemeinfreie Hörbücher/Podcasts mit Lizenz-Notiz), ähnliche Wörter („Wendeltreppe“, „Wendel“, „Vanille“, „Benjamin“).
   - Kennzahlen: Trefferquote, Falschauslösungen je Stunde Audio, Latenz Wortende → Treffer.
2. **CPU und Akku.** Echtzeitfaktor und CPU-Zeit je Stunde auf dem Emulator (`top`/`dumpsys cpuinfo`, Release-Build). Auf dem Gerät misst der Maintainer (Prüfliste).
3. **Ort der Erkennung.** Verglichen werden (a) eine eigene schlanke Flutter-Engine `wakeWordMain` mit dem vorhandenen `sherpa_onnx`-Plugin (FFI, wie `recognizerMain`, ADR 0008) und (b) Kotlin mit sherpa-onnx-JNI (zusätzliche native Bibliothek, APK-Zuwachs). Gemessen werden PSS des Prozesses im Hintergrund (Ziel K14 c < 200 MB), APK-Zuwachs und Startzeit. Entscheidung mit Begründung.
4. **Start des Dienstes.** Auf dem Emulator (Ziel-API wie die App):
   - Foreground Service Typ `microphone` aus der sichtbaren App: Aufnahme läuft, auch nach `KEYCODE_SLEEP` (Bildschirm aus) und `dumpsys deviceidle force-idle` (Doze). Ist ein `PARTIAL_WAKE_LOCK` nötig?
   - Start aus `WendelinVoiceInteractionService.onReady()` nach einem Emulator-Neustart: Bekommt der Dienst Mikrofon-Zugriff (kein „can not have … microphone access“ im Logcat)?
   - Gegenprobe ohne Assistentenrolle: Start aus dem Hintergrund scheitert. Die Benachrichtigungsaktion „Wieder einschalten“ funktioniert.
   - `BOOT_COMPLETED`: bestätigen, dass der Start scheitert (`ForegroundServiceStartNotAllowedException`), damit niemand diesen Weg einbaut.
5. **Übergabe ans Overlay.** Der Treffer ruft `showSession` des laufenden `VoiceInteractionService` auf. Gemessen wird die Zeit vom Treffer bis zum ersten Overlay-Audio-Frame, und ob der Pre-Roll (300 ms) samt Folgeaudio lückenlos ankommt. Mikrofon: Variante „Dienst gibt `AudioRecord` frei, Overlay öffnet neu“ gegen „Dienst reicht Frames weiter“ (gleicher Prozess).
6. **AEC.** Emulator: nur Verfügbarkeit (`AcousticEchoCanceler.isAvailable`) und ob `VOICE_COMMUNICATION` die Whisper-WER verändert (`tool/stt_measure.sh` mit eingespeisten WAVs). Gerät: Messplan für den Maintainer. Die TTS läuft laut, „Stopp“ wird gesagt, gezählt werden Treffer und Selbstauslösungen, einmal mit `VOICE_RECOGNITION` und einmal mit `VOICE_COMMUNICATION` + AEC, TTS über `USAGE_ASSISTANT` bzw. `USAGE_VOICE_COMMUNICATION`.
7. **Modelllizenz** der KWS-Modelldateien (Hugging Face/Release) festhalten.

## Entscheidungen, die das Ergebnis festlegt
- Modell, Varianten, Standard-Schwelle und Empfindlichkeitsstufen (z. B. 3 Stufen → Schwelle).
- Ob die zweite Stufe (Whisper-Bestätigung im Overlay) nötig ist.
- Ort der Erkennung (a oder b) und Mikrofonübergabe.
- Startwege des Dienstes, die WP50 umsetzt. Wenn der Weg über den `VoiceInteractionService` trägt, auch „nur beim Laden“.
- Audioquelle für Barge-in (ADR-0015-Vorlage für WP51).
- Plan B (eigenes openWakeWord-Modell mit deutscher Piper-Stimme) nur, wenn die Trefferquote unter 80 % oder die Falschauslösungen über 2/h liegen. Dann folgt ein eigenes Folgepaket.

## Abnahmekriterien
- [ ] Notiz mit Tabellen (Variante × Schwelle → Trefferquote, Falschauslösungen/h, Latenz), CPU/PSS-Werten, APK-Zuwachs und den Ergebnissen der Startwege, jeweils mit Befehl/Skript zur Wiederholung.
- [ ] Messskript (z. B. `tool/kws_measure.sh` oder Dart-CLI) läuft ohne Gerät gegen WAV-Ordner und gibt die Kennzahlen aus.
- [ ] Emulator-Nachweise nur auf `Wendelin_AOSP_35` mit explizitem Serial (Logcat-Auszüge ohne Inhalte).
- [ ] Liste der Entscheidungen oben, als Vorlage für ADR 0013 und ADR 0015.
- [ ] Abweichungen vom Konzept als Liste im Bericht.

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] Mit der Spike-APK (Debug, eigener Build) 30× „Wendelin“ aus 1 m und 3 m, ruhig und mit Radio. Treffer notieren.
- [ ] 8 h Alltag mit laufendem Dienst: Falschauslösungen (Zähler in der Benachrichtigung bzw. Logzeile `wake-hit`) und Akku in % (Einstellungen → Akku → App).
- [ ] HyperOS: Läuft der Dienst nach 30 min Bildschirm aus noch (Logzeile `wake-alive` je 5 min)? Einmal ohne und einmal mit Autostart/„Keine Einschränkungen“.
- [ ] AEC-Messplan aus Frage 6 durchführen.
