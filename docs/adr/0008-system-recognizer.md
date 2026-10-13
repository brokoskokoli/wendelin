# ADR 0008 – Lokale System-Spracherkennung (`RecognitionService` mit Whisper)

Status: vorgeschlagen · 2026-10-13

## Kontext
Android verlangt für den Standard-Assistenten einen `RecognitionService` (ADR 0006 §2). Bis WP18 war das ein Platzhalter mit `ERROR_CLIENT`: Solange Wendelin Assistent war, hatten andere Apps keine Spracheingabe. WP20 betreibt den Dienst mit dem lokalen Whisper und Silero VAD aus WP17 (ADR 0007). Auf Geräten ohne Google-Dienste (K7) wird Wendelin damit zur Offline-Spracherkennung für alle Apps.

Offen war, wo Whisper für den Dienst läuft:
- **A – nativ in Kotlin:** sherpa-onnx über seine Java/Kotlin-API (eigene AAR bzw. `libsherpa-onnx-jni.so`).
- **B – Headless-Flutter-Engine:** Der Dienst startet eine Flutter-Engine ohne Oberfläche, die den vorhandenen Dart-Code ausführt (Silero, `Endpointer`, Whisper-Isolat).

## Entscheidung: B, Headless-Engine mit geteiltem Whisper

| Kriterium | A nativ | B Headless (gewählt) |
|---|---|---|
| APK-Größe | Das Flutter-Plugin bringt nur die C-API mit (`libsherpa-onnx-c-api.so`, keine JNI). A bräuchte zusätzlich die JNI-Bibliothek und eine zweite `libonnxruntime.so` derselben Version (sonst Konflikt beim Packen), geschätzt +5 bis +25 MB je ABI. | Keine neue native Bibliothek. Debug-APK gemessen 250,6 MB (WP17: 250 MB), nur Kotlin- und Dart-Code kommen hinzu. |
| Endpointing „wie die Pipeline“ | Silero-Aufruf, `Endpointer` (Pre-Roll, 800 ms Stille, 30 s, Mindestsprechdauer, 8 s ohne Sprache) und Whisper-Bereinigung (Stille-Sperre, Halluzinationen, Konfidenz) müssten in Kotlin nachgebaut und doppelt gepflegt werden. | Derselbe Code: `RecognitionSession` (wendelin_voice) nutzt `Endpointer` und `EndpointConfig`, `WhisperSpeechToText` dieselbe Bereinigung. Einstellungen (Modell, Schwelle, Mindestsprechdauer) gelten für beide. |
| Speicher | Ein eigenes Modell im Kotlin-Heap. Ist in der App Whisper geladen, liegt es doppelt im Speicher (base ~0,2 GB, small ~0,5 GB). | Die App veröffentlicht ihren Whisper-Isolat-Port prozessweit (`IsolateNameServer`). Der Erkenner nutzt ihn mit, statt ein zweites Modell zu laden (§3). Sonst lädt er sein eigenes und gibt es 30 s nach der letzten Anfrage frei. Die Engine selbst kostet einige zehn MB, nur solange ein Client verbunden ist. |
| Startzeit | Modell laden, sonst nichts. | Kalte Engine plus Modell. Das Mikrofon läuft sofort (Kotlin), die Frames werden gepuffert, bis Dart bereit ist. `onReadyForSpeech` kommt deshalb ohne Wartezeit. Gemessen auf dem Emulator (Debug/JIT, arm64, Whisper base): Ergebnis 0,5–0,65 s nach dem Ende der Endstille, Engine-Start und Laden eingeschlossen. |
| Gleichzeitigkeit | Eigenes Modell, frei von der App. | Eigene Engine (eigenes Isolat), keine Riverpod- oder DB-Abhängigkeit. Ein geteiltes Whisper arbeitet Aufträge der Reihe nach ab. Antwortet es nicht innerhalb von 3 s (beschäftigt oder Besitzer weg), lädt der Erkenner sein eigenes. |
| Wartbarkeit | Zweite Implementierung von VAD, Endpointing und Whisper-Bereinigung in Kotlin, mit eigenen Tests. | Kotlin übernimmt nur Android: Bindung, Berechtigung, Aufnahme, Callbacks, Fehlercodes. Die Logik steckt in reinem Dart mit Unit-Tests (`recognition_session_test.dart`, `recognizer_host_test.dart`). |

## Einzelheiten

### 1. Ablauf
`WendelinRecognitionService.onStartListening`:
1. Prüft, ob der Dienst aktiv sein darf (Rolle **und** Einstellung, §4), sonst `ERROR_CLIENT`. Prüft dann die Mikrofon-Berechtigung, sonst `ERROR_INSUFFICIENT_PERMISSIONS`: Wendelin selbst braucht `RECORD_AUDIO`. Ab Android 12 prüft der Dienst zusätzlich den direkten Aufrufer aus dessen `AttributionSource`: Laufzeitberechtigung und App-Op `RECORD_AUDIO` (`unsafeCheckOpNoThrow`), ohne den Zugriff zu verbuchen. `PermissionChecker.checkPermissionForPreflight` für die ganze Kette ist keine öffentliche API. Davor lehnt schon das Framework (`RecognitionService`) Aufrufer ohne Berechtigung ab. Audio vom Aufrufer (`EXTRA_AUDIO_SOURCE`, Android 13) wird nicht unterstützt und ergibt `ERROR_CLIENT`, Wendelin nimmt nur selbst auf.
2. Öffnet das Mikrofon (`AudioRecord`, `VOICE_RECOGNITION`, 16 kHz mono PCM16). Ab Android 12 läuft die Aufnahme über einen Context mit der `AttributionSource` des Aufrufers, sie zählt also für die aufrufende App im Vordergrund. Danach `onReadyForSpeech`.
3. Startet bei Bedarf die Engine (`RecognizerEngine`, Einstieg `recognizerMain`) und schickt `start` mit `EXTRA_LANGUAGE` und den gespiegelten Einstellungen.
4. Schickt alle 100 ms einen Audio-Block an Dart und meldet den Pegel per `onRmsChanged` (dBFS −60…0 → −2…10).
5. Dart (`RecognizerHost` → `RecognitionSession`) meldet `began` (`onBeginningOfSpeech`), `ended` (`onEndOfSpeech`, Mikrofon aus), dann `result` (`onResults` mit einer Hypothese und `CONFIDENCE_SCORES`) oder `error`.

`onStopListening` schaltet das Mikrofon sofort in Kotlin ab und schickt `stop`. Dart beendet daraufhin den Audio-Stream (`ChannelAudioInput.end`): Die bis dahin empfangenen Blöcke werden noch erkannt, ohne Sprache kommt `ERROR_NO_MATCH`. Das gilt auch, wenn die Engine noch startet und die Modelle prüft, weil `start`, Audio und `stop` in Kotlin gepuffert und in dieser Reihenfolge zugestellt werden. `onCancel` stoppt das Mikrofon, danach kommen keine Callbacks mehr. Ein Wächter beendet eine Anfrage nach 90 s mit `ERROR_CLIENT`. `onDestroy` ruft `shutdown` (gibt Whisper frei) und zerstört die Engine.

Teilergebnisse (`onPartialResults`) gibt es nicht: Whisper erkennt die Äußerung als Ganzes. `onBufferReceived` wird nicht gesendet, damit kein Audio an andere Apps geht.

### 2. Fehlercodes
| Fall | Code |
|---|---|
| Stille bis zum Timeout ohne Sprache (8 s) | `ERROR_SPEECH_TIMEOUT` |
| Sprache gehört, aber leerer Text; `stopListening` ohne Sprache | `ERROR_NO_MATCH` |
| Keine Mikrofon-Berechtigung (Aufrufer oder Wendelin) | `ERROR_INSUFFICIENT_PERMISSIONS` |
| Audio vom Aufrufer (`EXTRA_AUDIO_SOURCE`) | `ERROR_CLIENT` |
| Mikrofon fällt aus | `ERROR_AUDIO` |
| `EXTRA_LANGUAGE` nicht de/fr/en | `ERROR_LANGUAGE_NOT_SUPPORTED` (vor Android 12 `ERROR_CLIENT`) |
| Whisper oder Silero nicht geladen | `ERROR_CLIENT`, Hinweis im Log „Wendelin → Einstellungen → Sprache“ |
| Rolle fehlt oder Angebot aus, Engine-/Whisper-Fehler, Zeitüberschreitung | `ERROR_CLIENT` |
| Zweite gleichzeitige Anfrage eines anderen Clients | `ERROR_RECOGNIZER_BUSY` (Basisklasse `RecognitionService`) |

### 3. Whisper teilen (`whisper_share.dart`, `whisper_registry.dart`)
`speechToTextProvider` (App und Overlay) registriert den Eingangs-Port seines Whisper-Isolats unter `app.wendelin/whisper/<modell>` im `IsolateNameServer` und meldet ihn bei `dispose` wieder ab. Das Isolat beantwortet neben den eigenen Aufträgen auch geteilte: Listen mit `TransferableTypedData` und Antwort-Port, weil Engines verschiedene Isolat-Gruppen sind und keine Records austauschen können. Der Erkenner prüft zuerst mit `ping` (3 s), ob das Isolat lebt, und vor jeder Erkennung noch einmal. Endet die Engine der App, ohne `dispose` aufzurufen, läuft der `ping` nach 3 s ins Leere statt erst nach Ablauf der Frist. Antwortet das geteilte Whisper nicht (kein `pong` oder keine Antwort binnen 20 s plus Länge der Aufnahme; bis WP19 waren es 60 s), meldet es `unavailable`. Der Erkenner lädt dann sein eigenes Modell und erkennt dieselbe Äußerung damit. Ein Fehler des Modells selbst (`failed`) führt nicht zum Ausweichen. Das eigene Modell wird 30 s nach der letzten Anfrage freigegeben. Gezählt werden die laufenden Anfragen, und die Frist beginnt auch dann, wenn eine Anfrage schon vorbei ist, bevor das Modell fertig geladen hat.

### 4. Aktivierung
Die Komponente bleibt im Manifest deaktiviert. `RecognizerSwitch` schaltet sie nur ein, wenn Wendelin die Assistenten-Rolle hält **und** die Einstellung „Als Spracherkennung für andere Apps anbieten“ (Einstellungen → Assistent, Standard an) gesetzt ist. Die Einstellung liegt in den SharedPreferences `app.wendelin.recognizer`, weil Kotlin sie ohne Dart lesen muss. Sie gilt sofort. Jede Anfrage prüft beides erneut, denn Rollenwechsel lassen sich nicht beobachten. Auf dem Emulator geprüft: Ist das Angebot aus, bleibt Wendelin Assistent (`voice_interaction_service`, `dumpsys voiceinteraction`), und Anfragen an den Dienst scheitern.

### 5. Einstellungen ohne Datenbank
Die Erkenner-Engine öffnet die Datenbank nicht. Eine dritte Engine am gemeinsamen drift-Isolat würde dessen Lebensdauer an den kurzlebigen Dienst koppeln (ADR 0006 §1). Stattdessen spiegelt die Haupt-App Modell, Sprache („Wie die App“ aufgelöst, `''` = automatisch), VAD-Schwelle und Mindestsprechdauer bei jedem Start und jeder Änderung über `app.wendelin/assistant` in dieselben SharedPreferences (`recognizerConfigSyncProvider`). Ohne Spiegel gelten die Standardwerte (whisper-base, automatisch). Die Sprache kommt aus `EXTRA_LANGUAGE` (Hauptsprache von `de-DE` usw.), sonst aus der Einstellung.

### 6. Datenschutz
Audio bleibt im Speicher: Es geht von Kotlin über den Kanal zu Dart und wird nach der Erkennung verworfen. Es wird weder geschrieben noch geloggt noch an Clients gesendet. Das Log enthält nur Fehlercodes und die Textlänge, nie den Text.

### 7. Test-Audio
Ein debuggable Build (`FLAG_DEBUGGABLE`) liest statt des Mikrofons eine WAV aus `cacheDir/recognizer-test/`, wenn der Intent das Extra `app.wendelin.test.AUDIO_FILE` trägt (nur einfacher Dateiname). Die WAV läuft in Echtzeit, danach folgt Stille. Release-Builds ignorieren das Extra. Den Emulator-Test führt `tool/e2e_recognizer.sh` aus (Instrumentationstest `RecognitionServiceTest`, Fixtures nur im Test-APK).

## Folgen
- WP19: Die Frist für das geteilte Whisper ist 20 s plus Länge der Aufnahme. Auf dem Emulator braucht Whisper small im Mittel 0,15 × die Audiodauer (base 0,05 ×, `docs/notes/m2-e2e-2026-10-13.md`), die Frist läuft also nur ab, wenn der Besitzer hängt oder weg ist. Jede Erkennung schreibt ihre Dauer ohne Inhalt ins Log („Erkenner: Whisper-Zeit …“). Auf dem Gerät noch offen und Teil von `docs/testing/m2-device.md`: Kaltstart (Release/AOT) und Speicher, die Aufnahme über die Attribution aus einer fremden App im Vordergrund (der Emulator-Test ruft aus dem eigenen Prozess auf) und das geteilte Whisper. Eine eigene Client-App für den Pfad „Aufrufer hat die Berechtigung, Wendelin nicht“ gibt es nicht.
- Das Teilen von Whisper ist im Desktop-FFI-Test und in Unit-Tests geprüft. Auf dem Gerät (App mit geladenem Whisper, dann Spracheingabe in einer anderen App) ist es noch nicht geprüft.
- `onCheckRecognitionSupport` (Android 13) ist nicht umgesetzt. Clients, die vorher fragen, bekommen die Standardantwort des Frameworks.
