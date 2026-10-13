# WP50 – Wake-Word-Dienst Android (`app/` + Kotlin)

Abhängig von: WP42 (Entscheidungen), WP44 (Kern), WP38 und WP40 gemergt. Andockpunkte: `WendelinVoiceInteractionService.kt` (`onReady`), `WendelinVoiceSessionService.kt`/`AssistantActivity.kt` (Overlay-Weg, ADR 0006), `RecognizerEngine.kt` als Vorbild für eine eigene Engine (ADR 0008), `app/lib/main.dart` (Einstiege), `app/lib/platform/voice/` (sherpa-Implementierungen), `AssistantTriggerSource` in `app/lib/platform/assistant_platform.dart`, `AndroidManifest.xml`, Einstellungen (`app/lib/ui/settings/`, `app/lib/di/preferences.dart`). Legt ADR 0013 an.

## Teil a – Dienst
- `WakeWordService` (Foreground Service, `foregroundServiceType="microphone"`, Berechtigungen `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`). Dauerhafte Benachrichtigung „Wendelin hört auf ‚Wendelin‘“ mit „Pause 1 h“ und „Aus“ (eigener, leiser Kanal).
- Erkennung nach WP42 (eigene Engine `wakeWordMain` mit `SherpaWakeWordEngine` oder nativ). Kein Whisper und kein Agent im Dienst. Speicherziel K14 c.
- Startwege: aus der sichtbaren App (Einstellung an); aus `WendelinVoiceInteractionService.onReady()` (Assistentenrolle, auch nach Neustart); aus der Benachrichtigung „Wieder einschalten“. Kein `BOOT_COMPLETED`-Start. Fehlschläge werden mit Grund geloggt (`wake-start result=…`).
- Treffer: Mikrofon pausieren, `showSession` des Assistenten-Dienstes mit `TriggerKind.wakeWord` und Pre-Roll aufrufen (Weg nach WP42). Nach dem Schließen des Overlays wird fortgesetzt. Bestätigungston optional. Bei gesperrtem Gerät folgt der Pfad aus WP53.
- Konflikte: Telefonat, fremde Aufnahme (`AudioManager.getActiveRecordingConfigurations`, Audio-Fokus) → pausieren und danach fortsetzen. Push-to-talk und Power-Taste haben Vorrang (der Dienst gibt das Mikrofon frei).
- Diagnose ohne Audio: `wake-start`, `wake-hit kw=… score=…`, `wake-pause reason=…`, `wake-alive` (alle 5 min), `wake-stop reason=…`.
- Debug-Überschreibung für Gerätetests: `WavAudioInput` als Quelle des Dienstes (`app/lib/debug/`).

## Teil b – Einstellungen und Erklärung
- Seite „Wake Word“: an/aus, Empfindlichkeit (3 Stufen), Bestätigungston, „nur beim Laden“ (falls WP42 trägt), Modell-Download (Größe), Status (läuft / pausiert / vom System beendet, mit letztem Grund).
- Vor dem Einschalten erklärt die App: dauerhafte Benachrichtigung, grüner Mikrofon-Punkt, alles bleibt auf dem Gerät, Akkuverbrauch (Messwert aus WP42). Sie fragt nach Benachrichtigungs- und Mikrofon-Berechtigung und bietet die Ausnahme von der Akku-Optimierung an (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`). Ohne Assistentenrolle folgt der Hinweis, dass nach dem Neustart erst ein Tipp nötig ist.
- Herstellerhinweis für Xiaomi/HyperOS (Erkennung über `Build.MANUFACTURER`): Autostart, „Keine Einschränkungen“, App in „Letzte“ sperren. Text-Anleitung plus Knopf zur App-Info.
- Onboarding: optionaler Schritt „Wake Word“ am Ende (ADR 0005).

## Abnahmekriterien
- [ ] Kotlin: Start-/Stopp-Logik als testbare Hilfsklasse (JVM-Test), Manifest-Prüfung in `tool/check_apk.sh` (Typ `microphone`, nicht exportiert).
- [ ] Emulator (`Wendelin_AOSP_35`, explizites Serial): Dienst an, `KEYCODE_SLEEP`, eingespeiste WAV „Wendelin, …“ → Overlay öffnet sich mit `TriggerKind.wakeWord`, der Satzanfang nach dem Wake Word wird erkannt. 10/10 Durchläufe.
- [ ] Emulator: Neustart mit Assistentenrolle → `wake-start result=ok source=vis` ohne „microphone access“-Warnung. Ohne Rolle erscheint die Benachrichtigung „Wieder einschalten“.
- [ ] Emulator: `dumpsys meminfo app.wendelin` im Hintergrund mit laufendem Dienst < 200 MB (K14 c), Wert im Bericht.
- [ ] Widget-/Golden-Tests der Einstellungsseite und des Erklärdialogs (Goldens nur auf macOS).
- [ ] Gate grün, APK baut, `tool/check_apk.sh` grün. ADR 0013 angelegt, `docs/ARCHITECTURE.md` (Einstiege, Kanäle, Datenfluss „Auslöser“) nachgeführt.

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] Bildschirm aus, 30 min liegen lassen, dann „Wendelin, wie spät ist es?“ → Overlay (nach Entsperren) bzw. Antwort. 10×, Treffer notieren.
- [ ] Neustart des Telefons ohne App zu öffnen → nach 2 min löst „Wendelin“ aus (mit Assistentenrolle).
- [ ] HyperOS mit Standard-Akkueinstellungen gegen die empfohlenen Einstellungen: Läuft der Dienst nach 2 h noch (`wake-alive`)?
- [ ] Akkuverbrauch über 8 h (Einstellungen → Akku), Falschauslösungen zählen.
- [ ] Während eines Telefonats und bei laufender Sprachmemo-App: Dienst pausiert und läuft danach weiter.
