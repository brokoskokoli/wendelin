# WP30 – Sprach-Robustheit: Ja/Nein-Zuhören, Power-Taste, Startverzögerung, Speicher (`app/` + Kotlin)

Abhängig von: – (sofort startbar auf main). Bezug: Gerätetest 2026-10-13 (`M2-fixes.md`), Befunde **B7, B10, B11, B14**. Andockpunkte: `app/lib/voice/voice_controller.dart` (`start`, `_onPending`, `_confirmByVoice`, `_capture`, `_pipelineFor`), `app/lib/di/voice_providers.dart` (`speechToTextProvider`, `voiceComponentsProvider`), `app/lib/voice/voice_components.dart` (`activeVoiceProvider`), `app/lib/platform/voice/whisper_share.dart`, Kotlin `WendelinVoiceSessionService.kt` und `AssistantActivity.kt`. ADRs: 0006 (Overlay), 0007 (Sprach-Plattform, §12 Hintergrund), 0008 (geteiltes Whisper).

Allgemein gilt: Jeder Befund bekommt zuerst eine **Diagnose ohne Inhalte**, also Logzeilen mit Ereignis, Grundcode, Dauer, Modell-ID und Engine (`app`/`overlay`/`recognizer`). Erkannter Text, Transkripte, Notiznamen und Prompt-Inhalte kommen nie ins Log, auch nicht im Debug-Build. Die Zeilen erscheinen auch im Release-Log (wie „Whisper-Zeit …“), unter einem eigenen Präfix (z. B. `Wendelin/voice:`), damit der Maintainer sie mit `adb logcat` filtern kann. Danach folgen ein Test, der den Fehler ohne Fix rot zeigt, der Fix und ein messbares Kriterium.

## B7 – Nach der Ja/Nein-Frage wird sporadisch nicht zugehört (Hoch)

Beobachtet: Die Bestätigungskarte kommt und die Frage wird gesprochen, danach startet keine zweite `AudioRecord`-Sitzung. Es gab keinen Fehler und keinen Hinweis. Der Fall trat auf mit base, unscharfer Notizzuordnung und im selben Prozess, in dem vorher das Overlay lief. Der Gegenfall mit small nach einem App-Neustart lief richtig.

**Diagnose:** Jeder stille Ausstieg in `_onPending`/`_confirmByVoice`/`_capture` loggt einen Grundcode, z. B. `confirm-skip reason=pipeline-idle|no-components|audio-running|already-confirming|not-open(cancelled|replaced|answered)|capture-null(no-speech|aborted|stream-error)|tts-error`. Dazu kommen Start und Ende der Antwort-Aufnahme und die Quelle der gesprochenen Frage (`confirmByVoice` oder Antwort-TTS).

**Hypothesen** (aus dem Bericht und dem Code):
- H1: `_onPending` steigt aus, weil `_pipeline?.state == VoiceState.idle` ist, wenn `pending` gesetzt wird. Das passiert, wenn die Pipeline nach dem Agent-Ereignis schon idle meldet oder die Frage erst nach dem Ende der Antwort-TTS ankommt.
- H2: `audio.isRunning` ist noch `true`, weil der Stopp der ersten Aufnahme noch nicht abgeschlossen ist oder `MeteredAudioInput` nach Overlay-Nutzung im selben Prozess einen veralteten Zustand hat.
- H3: `_confirming` steht noch von einer früheren Frage. Ein Ausstieg vor dem `try` setzt ihn nicht zurück.
- H4: `stillOpen()` wird `false`. Ein `cancel()` aus einem Lebenszyklus-Ereignis (Fokuswechsel, Overlay-Engine) erhöht `_cancels`, oder die Notizauflösung (Rückfrage, zweiter Tool-Aufruf) erzeugt eine neue `PendingQuestion`-Instanz, sodass `identical` scheitert.
- H5: `_capture` liefert sofort `null`, weil `audio.start()` gleich endet oder einen Fehler wirft, bevor `AudioRecord` angelegt wird (Mikrofon noch von der anderen Engine gehalten).

**Tests:**
- Widget-/Provider-Tests mit Fakes (`FakeAudioInput`, `FakeSpeechToText`, Fake-Agent mit `PendingQuestion`) für jede Hypothese. Jede Variante soll entweder zuhören oder sichtbar auf Tippen umschalten. Tabellentest über die Reihenfolgen „pending vor/nach Pipeline-idle“, „pending vor/nach TTS-Ende“, „zweite PendingQuestion“ und „Audio stoppt verzögert“.
- Emulator: `tool/e2e_android.sh` so erweitern, dass die WAV-Einspeisung eine **zweite Äußerung** („Nein“ bzw. „Ja“) nach der Frage liefert (D3-Ablauf), einmal mit vorheriger Overlay-Nutzung im selben Prozess (`cmd voiceinteraction show`).

**Fix:** Die gefundene Ursache beheben. Zusätzlich gilt allgemein: Kann die Stimm-Bestätigung nicht starten oder bricht sie ohne Antwort ab, zeigt die Karte „Antworte per Tipp“, und das wird gesprochen, wenn die Anfrage per Stimme kam. Ein stiller Ausstieg ist nicht mehr möglich.

**Messkriterium:** Im Emulatorlauf wird über 20 Wiederholungen von D3 (mit und ohne vorherige Overlay-Nutzung) jedes Mal zugehört oder „Antworte per Tipp“ gezeigt. Es gibt 0 stille Ausstiege. Jeder Ausstieg hat genau eine Grundcode-Zeile.

## B10 – Power-Taste öffnet das Overlay sporadisch nicht (Hoch)

Beobachtet: Nach Overlay-Nutzung, Schließen und App-Nutzung kam der Assistenten-Aufruf an (`AssistDisclosure`), aber es wurde keine `AssistantActivity` erzeugt. Erst das Beenden des Prozesses half.

**Diagnose:** Logzeilen ohne Inhalt in `WendelinVoiceSessionService.onNewSession`, `WendelinVoiceSession.onCreate/onShow/onHide/onDestroy` (mit `showFlags`) sowie um `startAssistantActivity` (Erfolg oder Exception mit Klassenname). Ebenso in `AssistantActivity.onCreate/onNewIntent/onDestroy` und beim Schließen über den Kanal (`requestClose`, `finish`, `isFinishing`).

**Hypothesen:**
- H1: Die Session ruft direkt nach `startAssistantActivity` `hide()` auf, aber nie `finish()`. Eine hängende, versteckte Session bekommt bei späteren Aufrufen kein `onShow` mehr oder wird nicht neu erzeugt.
- H2: `startAssistantActivity` scheitert still, weil die `singleTask`-Activity der Task `app.wendelin.assistant` noch beendet wird oder die Task in einem Zwischenzustand ist. Dann wird sie weder erzeugt noch per `onNewIntent` erreicht.
- H3: Die Overlay-Engine hängt nach dem Schließen, sodass die Activity gar nicht erst startet oder sofort wieder `finish()` ruft.

**Tests:**
- Robolectric- bzw. JVM-Test der Session-Logik, soweit sie ohne System läuft. Die Reihenfolge `onShow → startAssistantActivity → hide/finish` wird in eine testbare Hilfsklasse gezogen.
- Emulator-Schleife (neues Skript oder Modus in `tool/e2e_android.sh`, nur mit `emulator-`-Serial): `adb -s emulator-xxxx shell cmd voiceinteraction show` → warten → Overlay schließen (Zurück) → App in den Vordergrund und wieder Home → 2 min warten (im Schnelllauf 10 s) → erneut `show`. Das läuft 30 Durchläufe. Gezählt werden `wm_create_activity app.wendelin/.AssistantActivity` gegen die Zahl der `show`-Aufrufe.

**Fix:** Nach der gefundenen Ursache, mindestens aber: Die Session beendet sich nach dem Start der Activity sauber (`finish()` bzw. `onHide` → `finish()`). Ein Fehlschlag von `startAssistantActivity` wird geloggt und einmal mit frischem Intent wiederholt. Die Activity räumt ihren Zustand in `onDestroy` vollständig auf.

**Messkriterium:** In der Emulator-Schleife erzeugen 30 von 30 Aufrufen die Activity. Ein Fehlschlag ist im Release-Log mit Grund sichtbar.

## B11 – Erster Mikrofon-Tipp nach einer Pause: ~2 s bis zur Aufnahme (Mittel)

Beobachtet: Zwischen Tipp und `AudioRecord set()` lagen 1,97 s, beim zweiten Tipp 10 ms. Nach dem Entsperren im Overlay vergingen ebenso 1–2 s. Die Verzögerung liegt in der App vor der Mikrofon-Anforderung.

**Diagnose:** Logzeile `mic-ready after=<ms> load=<ms> model=<id> engine=<app|overlay>` vom Tipp bzw. Auslöser bis zum ersten Audio-Frame, aufgeteilt in Modell-Laden (`activeVoiceProvider`/`speechToTextProvider`, VAD) und Audio-Start.

**Hypothese:** `start()` wartet auf `activeVoiceProvider.future`. Das lädt beim ersten Mal das Whisper-Isolat und das Modell (absichtlich „nicht beim App-Start“, Kommentar in `voice_components.dart`). Im Overlay passiert das in der eigenen Engine noch einmal. Nach einer Pause kann das Modell freigegeben oder die Engine neu sein.

**Fix:**
- Die Aufnahme startet sofort nach dem Tipp (bzw. nach dem Entsperren) und puffert die Frames. VAD und Whisper laden parallel. Der Puffer wird nach dem Laden in die Pipeline gespielt, sodass der Satzanfang nicht verloren geht. Die Obergrenze ist die maximale Äußerungsdauer.
- Vorwärmen: Ist der Hauptbildschirm oder das Overlay sichtbar und sind die Modelle installiert, wird Whisper im Hintergrund geladen. Das gilt nicht bei gesperrtem Gerät vor dem Entsperren. Die Freigabe richtet sich nach B14.
- Der Zustand „Moment …“ als Anzeige gehört zu WP31. WP30 liefert dafür das Signal im `VoiceUiState` (z. B. `preparing`).

**Tests:** Provider-Test mit Fake-Komponenten, deren Laden 2 s braucht (Fake-Uhr): Das erste Audio-Frame wird nach ≤ 50 ms angefordert, und eine sofort gesprochene Äußerung wird vollständig erkannt. Ein Test zeigt, dass ohne installierte Modelle nicht aufgenommen wird (Hinweis wie bisher).

**Messkriterium:** Tipp → Aufnahme ≤ 150 ms im Widget-/Integrationstest. Auf dem Emulator steht `mic-ready after` im Log bei ≤ 300 ms, auch beim ersten Tipp nach einem Kaltstart.

## B14 – Speicher mit whisper-small ≈ 1,3 GB PSS statt ≈ 0,5 GB (Mittel)

Beobachtet: `TOTAL PSS` 1,3 GB, davon Native Heap ~0,95 GB, nach Nutzung von App und Overlay, Offline-Stimme und Fragen in drei Sprachen im selben Prozess.

**Diagnose:** Logzeilen `model-load`/`model-free` mit Modell-ID, Engine und Dauer für Whisper, Silero und sherpa-TTS. Zusätzlich gibt es im Debug-Build einen Zähler der lebenden Whisper-Backends je Prozess.

**Hypothesen:**
- H1: App-Engine und Overlay-Engine laden jeweils ein eigenes `IsolateWhisperBackend` (`speechToTextProvider` je `ProviderContainer`). small liegt dann doppelt im Speicher. Das Teilen aus ADR 0008 nutzt heute nur der Erkenner.
- H2: Beim Modellwechsel (base → small) wird das alte Backend nicht freigegeben, etwa weil eine Engine es noch hält.
- H3: Das Offline-TTS-Modell (sherpa) bleibt zusätzlich resident.

**Fix:** Pro Prozess gibt es höchstens ein geladenes Whisper je Modell. Die Overlay-Engine nutzt das Whisper der App-Engine über den geteilten Port (`lookupSharedWhisper`) und lädt nur, wenn keines da ist. Dann übernimmt sie die Besitzrolle, und die App nutzt es mit. Liegt die App im Hintergrund und ist keine Anfrage offen, werden Whisper und sherpa-TTS nach einer Frist freigegeben (Vorschlag 2 min). Das Vorwärmen aus B11 lädt erneut. Beim Modellwechsel wird das alte Modell freigegeben, bevor das neue lädt. ADR 0008 wird um das Teilen zwischen App und Overlay ergänzt.

**Tests:** Provider-Tests mit Fake-Backend, das die Instanzen zählt. Zwei Container (App und Overlay) ergeben genau ein Backend. Ein Modellwechsel ergibt danach genau ein Backend (das neue). Nach der Frist im Hintergrund ergibt sich 0. Der Besitzerwechsel beim Schließen der App-Engine bleibt ohne Absturz.

**Messkriterium:** Emulator, small, App und Overlay je einmal genutzt: `dumpsys meminfo app.wendelin` mit `TOTAL PSS` ≤ 0,8 GB (vorher Messung als Ausgangswert festhalten), höchstens ein `model-load whisper-small` im Log. Nach dem Modellwechsel folgt ein `model-free` für das alte Modell.

## Abnahmekriterien
- [ ] Diagnose-Logzeilen für B7, B10, B11 und B14 sind vorhanden, im Release-Log sichtbar und ohne Inhalte. Ein Test prüft an einer Beispielanfrage, dass keine Transkripte oder Notiznamen im Log landen.
- [ ] B7: Tabellentest der Ausstiegswege. Kein stiller Ausstieg mehr, sondern Zuhören oder „Antworte per Tipp“. Der Regressionstest für die gefundene Ursache ist ohne Fix rot.
- [ ] B7: Emulator-E2E mit zweiter eingespeister Äußerung (Ja und Nein), auch nach Overlay-Nutzung im selben Prozess.
- [ ] B10: Session beendet sich sauber, Fehlschlag von `startAssistantActivity` wird geloggt und wiederholt. Emulator-Schleife 30/30.
- [ ] B11: Aufnahme startet vor dem Modell-Laden und puffert. Test mit 2 s Ladezeit verliert keinen Satzanfang. `preparing`-Signal für WP31 vorhanden.
- [ ] B14: höchstens ein Whisper je Prozess (App + Overlay), Freigabe nach Frist im Hintergrund und beim Modellwechsel, Tests mit zählendem Fake. ADR 0008 ergänzt.
- [ ] Gerätetests nur auf `Wendelin_AOSP_35` mit explizitem Serial, Messwerte (mic-ready, PSS, 30/30) im Abschlussbericht.
- [ ] Gate grün, APK baut, `tool/check_apk.sh` grün.

## Prüfliste für den Maintainer (echtes Telefon)
Vorher das Log leeren und danach nur die Diagnosezeilen ziehen (keine Inhalte): `adb logcat -c` … `adb logcat -d | grep 'Wendelin/voice'`. Die Engine steht in jeder Dart-Zeile (`engine=app|overlay|recognizer`), die Kotlin-Zeilen der Session tragen den Tag `Wendelin/voice`.
- [ ] D3 mit base und mit small je 5× per Stimme beantworten, davon 2× direkt nach Overlay-Nutzung ohne App-Neustart. Jedes Mal wird zugehört oder „Antworte per Tipp“ angezeigt (und gesagt). Je Frage gibt es genau eine Zeile `confirm-exit reason=…`: `answered(yes|no)` oder `tap=true` mit Grund (`capture-null(mic-timeout|no-speech|start-error)`, `unclear`, `stt-error`). Hängt die Systemstimme, steht vorher `confirm-prompt … result=tts-timeout`. Im Fehlerfall die Zeilen beilegen.
- [ ] Overlay öffnen → schließen → App nutzen → Home → 2 min warten → Power-Taste lang. Das 5× wiederholen. Das Overlay kommt jedes Mal. Je Aufruf erwartet: `session-new`, `session-show`, `assistant-start attempt=1 result=ok`, `overlay-create`, `session-finish reason=arrived`. Bei `result=missing`, `result=error` oder `session-finish reason=missing|start-error` die Zeilen beilegen (auch mit `adb logcat -d -b events | grep AssistantActivity`).
- [ ] Nach 5 min ohne Sprachnutzung: erster Tipp aufs Mikrofon und sofort sprechen. Der Satzanfang wird erkannt. Die Zeile `mic-ready after=<ms> load=<ms>` notieren (Ziel `after` ≤ 300 ms, `load` darf größer sein). Dasselbe nach dem Entsperren im Overlay (`engine=overlay`).
- [ ] `adb shell dumpsys meminfo app.wendelin` mit small nach App- und Overlay-Nutzung: `TOTAL PSS` notieren (Ziel ≤ 0,8 GB). Im Log höchstens ein `model-load … model=whisper-small kind=whisper` je Prozess, das Overlay meldet `model-share`. Nach 2 min im Hintergrund erneut messen: `release reason=idle` und `model-free … kind=whisper` stehen im Log.
