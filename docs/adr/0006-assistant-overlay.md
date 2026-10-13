# ADR 0006 – Standard-Assistent, Overlay, Push-to-talk, Vault-Zugriff (`app/` + Kotlin)

Status: vorgeschlagen · 2026-10-13

## Kontext
WP18 macht Wendelin zum Android-Standard-Assistenten, baut das Assistenten-Overlay laut `docs/design/screens/overlay`, schaltet Push-to-talk im Hauptbildschirm frei und gibt der Obsidian-Integration (WP16) einen SAF-Vault auf dem Gerät. Die Sprach-Plattform (sherpa-onnx, Aufnahme, TTS) entsteht parallel in WP17.

## Entscheidungen

### 1. Overlay als eigene, transparente Activity mit eigenem Flutter-Engine
`WendelinVoiceInteractionService` (leer) + `WendelinVoiceSessionService` → `WendelinVoiceSession.onShow` startet per `startAssistantActivity` die `AssistantActivity` und blendet das eigene, leere Session-Fenster aus. Die Activity ist ein `FlutterActivity` mit transparentem Hintergrund (`BackgroundMode.transparent`, `AssistantTheme`), eigener Task (`excludeFromRecents`, nicht exportiert) und dem Dart-Einstieg `assistantMain`. Flutter zeichnet das Sheet (560 von 844, höchstens 80 % der Höhe) unten; ein Tipp daneben, „Beenden“, Zurück oder das Verlassen (`onStop`) schließen es. Jeder Aufruf meldet `TriggerKind.assistant` (`AssistantTriggerSource`); ein erneuter Aufruf bei offenem Overlay kommt als `trigger` über den Kanal `app.wendelin/assistant`.

Haupt-App und Overlay können gleichzeitig laufen (zwei Engines in einem Prozess). Die Datenbank läuft deshalb mit `shareAcrossIsolates: true` über einen gemeinsamen drift-Isolate. Beide Activities erben von `WendelinActivity` und haben dieselben Kanäle (Kalender, Dateien, Vault, Assistent), weil Tools in beiden laufen. Das Overlay zeigt nur die aktuelle Anfrage (letzte Nutzernachricht und was danach kam), nie Denktext und keinen Verlauf.

### 2. Android verlangt einen Erkennungsdienst
Ohne `recognitionService` in den Metadaten lehnt Android einen `VoiceInteractionService` ab. `WendelinRecognitionService` beantwortet deshalb jede Anfrage mit `ERROR_CLIENT`. **Folge:** Ist Wendelin Standard-Assistent, setzt Android auch `voice_recognition_service` auf diesen Dienst. Apps, die die System-Spracherkennung nutzen (z. B. Spracheingabe mancher Tastaturen), bekommen dann einen Fehler. Folgearbeit: den Dienst mit dem lokalen Whisper aus WP17 betreiben.

### 3. Sperrbildschirm: erst entsperren, vorher nichts zeigen oder sprechen
Das Overlay darf über dem Sperrbildschirm erscheinen (`setShowWhenLocked`). Ist das Gerät gesperrt (`KeyguardManager.isKeyguardLocked`), startet keine Anfrage. Das Sheet zeigt nur „Gerät entsperren“ ohne Verlauf, Transkript, Tool-Karten oder Antwort, Mikrofon und Tastatur sind aus, und die App fordert `requestDismissKeyguard` an. Erst nach dem Entsperren hört Wendelin zu. Wird das Entsperren abgebrochen, bleibt es dabei, bis „Entsperren“ oder „Beenden“ getippt wird. So erreicht kein sensibler Inhalt (Kalender, Notizen, Gedächtnis) den Bildschirm oder den Lautsprecher eines gesperrten Geräts. Der Reviewer-Hinweis aus WP15 ist damit umgesetzt.

### 4. Schnittstelle zu WP17: `VoiceComponents` + `voiceComponentsProvider`
WP18 hängt nur an `VoiceComponents` (AudioInput, VAD, STT, TTS je Sprache, `VoicePipelineConfig`, optional `prepare` für die Mikrofon-Berechtigung) und an `voiceComponentsProvider` (`app/lib/voice/voice_components.dart`). Im Demo-Modus liefert er `VoiceComponents.demo()` (Fakes aus `package:wendelin_voice/fakes.dart`), auf dem Gerät bis WP17 `null` (Mikrofon aus, Hinweis „Spracherkennung noch nicht eingerichtet“). **WP17 ersetzt nur den Geräte-Zweig** durch die echten Komponenten aus `app/di/voice_providers.dart`. Push-to-talk, Overlay und Bestätigung per Stimme bleiben unverändert.

### 5. Sprache läuft über den `AgentController`
`VoiceController` betreibt die `VoicePipeline` aus WP15. Deren Agent ist `ControllerAgentRun`: `AgentController.submit(UserInput, trigger:)` führt die Anfrage wie eine getippte aus (Verlauf, Sitzung, Undo, Bestätigungs-Sheet, Kosten) und liefert zusätzlich die Ereignisse an die Pipeline (Vorlesen). Das Audit-Log der Anfrage enthält jetzt `trigger` (`pushToTalk`, `assistant`), `language` und `sttConfidence` (Konzept „Logging: Auslöser“). Ein Abbruch während des Starts (Provider-Laden, Registry) verhindert den Modellaufruf.

### 6. Push-to-talk und Abbruch
Der Mikrofon-Button startet die Pipeline. In jedem aktiven Zustand (Zuhören, Erkennen, Denken, Sprechen) bricht ein Tipp ab (Konzept: „Antippen beendet jederzeit“). Das Ende des Zuhörens bestimmt das Endpointing (VAD). Beim Zuhören heißt der Button deshalb „Zuhören abbrechen“. Läuft eine getippte Anfrage, bricht der Tipp sie ab.

### 7. Bestätigung per Stimme
Nur bei einer Sprach-Anfrage (Pipeline nicht `idle`) liest der `VoiceController` eine kurze Frage vor („Termin löschen? Ja oder nein?“, fr/en generisch), wartet das Ende vorheriger Sätze ab und nimmt eine kurze Äußerung auf (höchstens 5 s, 6 s ohne Sprache). `YesNoRecognizer` (wendelin_voice, Tabellentest de/fr/en) wertet sie aus. Erkannt werden Ja- und Nein-Wörter und -Wendungen. Verneinungen und Stoppwörter zählen als „nein“. Ist beides oder keins erkannt, oder hat die Äußerung mehr als 8 Wörter, gilt sie als unklar. Bei Unklarheit wird einmal nachgefragt, danach gilt nur noch der Tipp. Ein Tipp beendet die Aufnahme sofort. Getippte Anfragen werden nie per Stimme bestätigt. Das Sheet zeigt „Sag einfach „ja“ oder „nein““, solange eine Sprach-Anfrage läuft, sonst „Antworte per Tipp“ (ersetzt K9 c). Im Overlay erscheint die Bestätigung im selben Sheet (Zitat, Karte, Steuerleiste), und der Hinweis steht unten statt des Gesprächsmodus-Hinweises.

### 8. Gesprächsmodus erst ab M4
Unten im Overlay steht ausgegraut (Deckkraft 0,55) „Gesprächsmodus kommt mit M4 · „Stopp“ beendet“. Ist `conversationMode` an (M4), zeigt die Zeile den Entwurfstext „Hört noch 5 s zu …“.

### 9. SAF-Vault (`SafVaultPort`, `VaultChannel.kt`)
Den Vault-Ordner wählt der Nutzer über `ACTION_OPEN_DOCUMENT_TREE`, die Rechte werden mit `takePersistableUriPermission(READ|WRITE)` dauerhaft übernommen. Pfade prüft zuerst `VaultPath` in Dart. Kotlin löst sie über `DocumentsContract` Segment für Segment auf und weist `.`, `..`, `\` und NUL ab. `list` holt Name, Typ, `COLUMN_LAST_MODIFIED` und `COLUMN_SIZE` in einer Abfrage. Fehlende Ordner legt `write` an. `create` ist exklusiv: Benennt der Provider die neue Datei um, weil der Name inzwischen vergeben ist, wird sie wieder gelöscht und es kommt `exists`. Die Bytes gehen roh über den Kanal, UTF-8 wird in Dart dekodiert, eine BOM bleibt erhalten, kein gültiges UTF-8 ergibt `failed`. Jeder Aufruf hat 10 s Zeitlimit (danach `unavailable`). Verlorene Rechte ergeben `permissionDenied` mit dem Hinweis auf Einstellungen → Obsidian. Geprüft ist das mit `vaultPortContract` gegen eine Kanal-Attrappe. **Grenze:** SAF kann nicht über eine vorhandene Datei umbenennen. `write` ersetzt den Inhalt deshalb in einem Aufruf mit `wt`, nicht mit temporärer Datei und Umbenennen. Die optimistische Sperre der Integration fängt fremde Änderungen trotzdem ab.

### 10. Obsidian in der App
Einstellungen → Obsidian: Vault wählen (beim ersten Mal schaltet das die Integration ein), anderen Ordner wählen (gibt die alten Rechte frei), Vault entfernen, Tagesnotizen (Ordner, Datumsformat, Vorlage) mit Vorschau des heutigen Pfads und Index aufbauen mit Fortschritt. Die Integration gibt es auf dem Gerät erst, wenn ein Vault gewählt ist (`IntegrationSpec.isSupported`), im Demo-Modus mit dem Vault „Demo“ im Speicher. Den Suchindex baut `ObsidianIndexController` auf: nach der Wahl, beim Start (Integration an) und auf Knopfdruck. Er wiederholt `NoteIndexer.sync()`, bis `pending == 0` ist, oder bricht ab, wenn ein Lauf nichts mehr schafft. Die Integration nutzt denselben `NoteIndexer`. `obsidian://`-Links öffnet `ACTION_VIEW`, ohne Obsidian kommt `unavailable`.

### 11. Einstellung „Als Standard-Assistent setzen“
Einstellungen → Assistent zeigt den Status (`RoleManager.isRoleHeld(ROLE_ASSISTANT)`, vor Android 10 die Einstellung `assistant`) und öffnet `Settings.ACTION_VOICE_INPUT_SETTINGS`. Gibt es die nicht, folgen `ACTION_MANAGE_DEFAULT_APPS_SETTINGS` und dann `ACTION_SETTINGS`. Die Rolle ist für Apps nicht anforderbar, der Nutzer wählt selbst. Nach der Rückkehr wird der Status neu geprüft.

## Folgen
- WP17 dockt über `voiceComponentsProvider` an (Entscheidung 4) und fügt `RECORD_AUDIO` hinzu. Der Manifest-Test erwartet dann diese Berechtigung.
- WP19 setzt den Assistenten per `cmd role add-role-holder android.app.role.ASSISTANT app.wendelin` und öffnet das Overlay mit `input keyevent KEYCODE_ASSIST`. `cmd voiceinteraction show` braucht eine Berechtigung, die die Shell nicht hat.
- Den Kotlin-Code testen nur der Emulator-Lauf (Registrierung, Overlay, Entsperren) und die Kanal-Attrappen. Ein Gerätetest folgt in WP19.
