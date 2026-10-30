# WP180 – Zentrale Audio-Aufnahme und Ringpuffer im Dienst (ADR 0024, K145)

**Zuordnung:** Vorgabe Maintainer 2026-10-29.

## Problemstellung
Bislang versuchte die Flutter-App über `package:record` (`RecordAudioInput`) ein eigenes `AudioRecord` (`VOICE_RECOGNITION`) zu öffnen, während im Hintergrund bereits der `WakeWordService` in Kotlin ein `AudioRecord` hielt.
Auf echten Android-Geräten (insb. Android 10+ / EMUI) führt dies dazu, dass:
1. Parallele Aufnahmen von Android abgewiesen oder stummgeschaltet werden (nur Nullen geliefert).
2. Beim Sprecher- und Weckwort-Einlernen (`SpeakerEnrollScreen`, `WakeEnrollScreen`) kein Ton ankommt oder die Spracherkennung blockiert ist.
3. Bei der Übergabe vom Weckwort an die Spracherkennung das Mikrofon gestoppt und neu gestartet werden musste, wodurch trotz aufwändiger Handoff-Überbrückung (`bridgeWakeTail`) bei schnellem Sprechen Audio verloren ging.

## Anforderungen des Maintainers
1. **Zentrale Stelle für Audioaufnahmen:**
   - Das Hardware-Mikrofon wird an einer zentralen Stelle (im Dienst / Kotlin) geführt.
   - Solange Wendelin läuft und niemand anderes das Mikrofon beansprucht (kein Anruf, keine Dritt-App), nimmt diese zentrale Stelle durchgehend auf.
2. **Zentraler Ringpuffer:**
   - Der Dienst legt einen fortlaufenden Ringpuffer mit mindestens 5–6 Sekunden Historie an.
   - Alle erfassten Audiodaten rollen fortlaufend durch diesen Puffer.
3. **Multi-Subscriber-Zugriff:**
   - Alle Instanzen und Konsumenten greifen auf diese zentrale Stelle zu und erhalten die benötigten Abschnitte:
     - **Weckwort-Erkennung:** lauscht kontinuierlich am zentralen Stream.
     - **Sprachbefehl / STT:** Nach Weckwort-Treffer oder Dialogstart stoppt das Mikrofon nicht mehr; die Pipeline erhält den Pre-Roll + das unmittelbar danach gesprochene Kommando aus dem Puffer und der Stream läuft lückenlos weiter.
     - **Sprecher- und Weckwort-Einlernen:** `WakeEnrollScreen` und `SpeakerEnrollScreen` fordern Audio von der zentralen Quelle an, statt ein eigenes `AudioRecord` zu erzwingen.
     - **Barge-In:** greift auf dieselbe zentrale Quelle zu.
4. **Pausierung bei Konflikten:**
   - Kommt ein Telefonat rein oder fordert eine andere App das Mikrofon an, pausiert der Dienst die Aufnahme und setzt sie nach Ende des Konflikts automatisch fort.
5. **Entfall fragiler Handoff-Logik:**
   - Da das Mikrofon beim Wechsel nicht mehr stoppt oder neu startet, entfällt der Bedarf an komplexen Heuristiken zur Überbrückung von Mikrofonlücken.

## Abnahmekriterien
- [ ] Zentrale Audioquelle in Kotlin (`WakeWordService` / `MicAudioSource`): hält das `AudioRecord` und füttert einen fortlaufenden Ringpuffer (≥ 5–6 s).
- [ ] Kanal-Anbindung an Flutter (`CentralAudioInput` / Service-Audio-Port): `audioInputProvider` greift unter Android auf die zentrale Quelle zu.
- [ ] Bei Weckwort-Treffer läuft die Aufnahme unterbrechungsfrei weiter (kein `stopMic()` / Neueröffnen nötig); Vorlauf und folgendes Kommando werden aus dem Ringpuffer geliefert.
- [ ] Sprecher-Einlernen (`SpeakerEnrollScreen`) und Weckwort-Einlernen (`WakeEnrollScreen`) können Audiodaten zuverlässig von der zentralen Quelle beziehen, ohne dass Mikrofon-Kollisionen auftreten.
- [ ] Automatisches Pausieren und Fortsetzen bei externen Konflikten (Anruf / Fremdaufnahme) über `WakeConflictWatcher`.
- [ ] Unit-Tests für Kotlin-Ringpuffer/Abonnenten und Dart-Audio-Input.
- [ ] Mindestens 85 % Testabdeckung der geänderten/neuen Logik.
- [ ] Keine Verletzung der Architekturgrenzen (`tool/check_deps.dart`).
- [ ] Gate `--changed` lokal grün, CI grün.
- [ ] Review durch Reviewer-Agent (Urteil FREIGABE in `../james-wt/reviews/wp180-review.md`).
