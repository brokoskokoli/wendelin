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

## Nachtrag (2026-10-14, Stand nach WP44/WP51/WP53/WP56/WP58/WP60)
Dieser Nachtrag geht dem Text oben vor, wo sie sich widersprechen.
- **Erkennung:** keine sherpa-KWS. Stufe 1 = openWakeWord-Merkmalskette aus WP60 (`wakeFeaturesFactoryProvider`, `app/lib/di/wake_providers.dart`, `ort_session.dart`, `wake_feature_chain.dart`) + `CandidateWakeEngine` aus `packages/wendelin_voice/lib/src/wake/` mit den persönlichen Vorlagen aller eingelernten Sprecher (`WakeTemplateStore`, je Sprecher eigene Schwelle) und optional dem WP58-Modell. Stufe 2 = Whisper-Nachprüfung (`wake_verifier.dart`), nur wenn `wakeVerifyProvider` an ist (Standard an).
- **Whisper im Dienst:** abweichend von „kein Whisper im Dienst“ läuft die Nachprüfung im Dienst: Whisper (kleinstes installiertes Modell) wird erst beim ersten Kandidaten geladen und nach ~60 s ohne Kandidat wieder freigegeben. Das Speicherziel < 200 MB (K14 c) gilt für den Ruhezustand ohne geladenes Whisper; den Spitzenwert mit Whisper im Bericht nennen. Kein Agent im Dienst.
- **Ohne Einlernen kein Dienst:** Ist kein Sprecher eingelernt und kein WP58-Modell aktiv, lässt sich Wake Word nicht einschalten (Hinweis mit Weg zu „Wendelin lernt deine Stimme“).
- **Voraussetzung Assistentenrolle** (Entscheidung Maintainer 5): ohne Rolle ist der Schalter gesperrt, mit Erklärung und Knopf zur Rollen-Auswahl (vorhandener Weg aus WP38/WP56).
- **Bedingung:** Standard „nur beim Laden“, wählbar „immer“ (Entscheidung Maintainer 7). „Nur beim Laden“: Dienst startet/stoppt über Lade-Ereignisse (`ACTION_POWER_CONNECTED/DISCONNECTED`, dynamisch registriert aus dem `VoiceInteractionService`; kein `BOOT_COMPLETED`).
- **Mikrofon-Übergabe:** Bei einem Treffer gibt der Dienst das Mikrofon frei, bevor das Overlay aufnimmt; Pre-Roll geht mit (`TriggerEvent.preRoll`). Regel aus WP51: im Folgefenster nimmt die App mit `VOICE_RECOGNITION` auf. `bargeInDetectorProvider` ist heute null – WP50 verdrahtet den Barge-in-Detektor (`wake_word_barge_in.dart`) mit derselben Merkmalskette, sofern der Gesprächsmodus an ist; sonst bleibt er null.
- **Gesperrtes Gerät:** Treffer bei Sperre → Overlay mit `TriggerKind.wakeWord` auf dem WP53-Pfad (nur Taschenlampe).
- **Akku-Hinweise:** Bausteine aus WP56 wiederverwenden (Akku-Optimierung, Hersteller-Checkliste, App-Info), nicht neu bauen.
- **Diagnose:** zusätzlich `wake-cand` und `wake-verify ok|no|skip` (ohne Text), Zähler Kandidaten/h und bestätigt/h in `wake-alive`.
- **Schnitt:** Teil a (Dienst, Engine-Verdrahtung, Kotlin, Emulator-Kriterien) und Teil b (Einstellungsseite, Erklärdialog, Onboarding-Schritt) als zwei Review-Einheiten auf eigenen Branches (`wp/50a-wake-service`, danach `wp/50b-wake-settings`). Die Seite „Wake Word“ aus WP60 (`app/lib/ui/settings/wake/wake_word_screen.dart`) wird in b erweitert, nicht ersetzt.
- **Emulator-Kriterium angepasst:** eingespeiste WAV mit synthetischer Stimme, vorher mit derselben Stimme eingelernt (wie `wake_enroll_e2e_test.dart`); 10/10 gilt für Stufe 1, Stufe 2 bei synthetischen Stimmen nur berichten (WP44: 42 %).

## Umsetzung Teil a (2026-10-14, Branch `wp/50a-wake-service`)
Dienst, Engine-Verdrahtung, Startwege, Konflikte, Barge-in, Kotlin-Hilfsklassen mit JVM-Test, Manifest-Prüfung und ADR 0013 sind umgesetzt (`docs/adr/0013-wake-word-dienst.md`, Karte in `docs/ARCHITECTURE.md`). Gerätetest: `app/integration_test/wake_service_e2e_test.dart` (Aufträge `role` und `wake-loop` in `tool/e2e_android.sh`). Offen für Teil b: Einstellungsseite, Erklärdialog, Onboarding-Schritt auf `wakeServiceProvider` (`app/lib/di/wake_service.dart`) und `WakePlatform.status()`.
