# Speicher mit whisper-small auf dem Emulator (WP30, B14, 2026-10-13)

## Aufbau
- **Gerät:** AVD `Wendelin_AOSP_35` (AOSP ohne Google Play, Android 15, arm64) mit eigenem Serial `emulator-5584`, gestartet mit `-no-audio`. Das Mikrofon liefert deshalb Stille.
- **Build:** Release-APK (`flutter build apk --release --target-platform android-arm64`) mit dem Stand von WP30 nach dem Review: Vorwärmen nur bei Sprachnutzung, Freigabe im Hintergrund, Overlay teilt das Whisper der App, nur die zuletzt genutzte sherpa-Stimme bleibt geladen.
- **Modelle:** whisper-small (int8), Silero VAD und die Offline-Stimme `tts-de-thorsten` per `adb root` nach `files/models/` kopiert. Einstellungen (`onboarding.done`, `voice.settings` mit `whisper-small` und Sprachausgabe `sherpa`) direkt in die App-Datenbank geschrieben. Kein Provider eingerichtet.
- **Messung:** `adb shell dumpsys meminfo app.wendelin`, Wert `TOTAL PSS` und `Native Heap` (PSS), jeweils einige Sekunden nach dem Schritt.

## Release-Build

| # | Zustand | TOTAL PSS | Native Heap | Log |
|---|---|---|---|---|
| 0 | frisch installiert, Onboarding offen | 81 MB | 22 MB | – |
| 1 | Hauptbildschirm, keine Modelle | 84 MB | 24 MB | – |
| 2a | small installiert, Sprache nie genutzt | 84 MB | 24 MB | `prewarm-skip reason=unused` |
| 2b | Start nach einer Sprachanfrage (vorgewärmt) | 525 MB | 446 MB | `model-load whisper-small`, `prewarm` |
| 2c | Mikrofon-Tipp, Stille (small geladen, ohne Offline-Stimme) | 523 MB | 441 MB | `mic-ready after=577 load=9` |
| 4 | Overlay offen (`KEYCODE_ASSIST`), App im Hintergrund | 559 MB | 460 MB | Overlay: `model-share whisper-small`, kein zweites `model-load` |
| 4b | Overlay geschlossen | 538 MB | 455 MB | `release reason=overlay-close` |
| 5 | small und Offline-Stimme (thorsten) geladen | 607 MB | 522 MB | `model-load kind=tts-sherpa` |
| 6 | App 2 min im Hintergrund | 188 MB | 86 MB | `release reason=idle`, `model-free whisper-small`, `model-free tts-sherpa` |

Bewertung:
- whisper-small kostet geladen etwa 440 MB, die zweite Engine des Overlays etwa 35 MB. Sie lädt kein zweites Modell. Die Offline-Stimme kommt mit etwa 70 MB hinzu.
- Mit App, Overlay und Offline-Stimme, aber noch ohne Erkennung, liegt der Prozess bei etwa 0,6 GB. Mit Erkennung kommen rund 390 MB hinzu (nächster Abschnitt), damit wird das Ziel von höchstens 0,8 GB verfehlt.
- Wer nur tippt, trägt kein Whisper mehr (Zeile 2a). Ab der ersten Sprachanfrage wärmt der Hauptbildschirm 24 h lang vor (Zeile 2b).
- Im Hintergrund fällt der Prozess nach der Frist auf etwa 190 MB. Den Rest belegen die Engine, der Dart-Heap und Grafikpuffer.
- `mic-ready after` lag beim ersten Tipp auf dem Emulator bei 577–804 ms (Release, ohne Vorwärmen 804 ms). Das liegt über dem Ziel von 300 ms. Die Zeit verbringt die App vor dem Öffnen des Mikrofons. Gemessen wurde auf einem Emulator ohne Audio. Auf dem Telefon prüft das die Prüfliste in WP30.

## Nach der ersten Erkennung

Im Release-Build kann der Emulator keine Sprache liefern, denn die WAV-Einspeisung gibt es nur im Debug-Build. Gemessen wurde deshalb im Debug-Build mit der WAV aus `app/test/fixtures/stt/` über das Overlay (`files/e2e/overlay.json`). Die absoluten Werte enthalten den größeren Dart-Heap des Debug-Builds. Aussagekräftig ist der Unterschied vor und nach der Erkennung.

| # | Zustand (Debug-Build) | TOTAL PSS | Native Heap | Log |
|---|---|---|---|---|
| D1 | Hauptbildschirm, small installiert, nie genutzt | 326 MB | 31 MB | – |
| D2 | Mikrofon-Tipp, Stille (small geladen) | 768 MB | 449 MB | `model-load whisper-small` |
| D3 | Overlay mit WAV, **nach der ersten Erkennung** | 1 286 MB | 842 MB | Overlay `model-share`, `Whisper-Zeit … Rechenzeit 1767 ms` |
| D4 | Overlay geschlossen | 1 157 MB | 833 MB | – |
| D5 | Overlay mit WAV, nach der zweiten Erkennung | 1 383 MB | 928 MB | kein zweites `model-load whisper-small` |
| D6 | App 2 min im Hintergrund | 444 MB | 109 MB | `release reason=idle` |

Bewertung:
- Das Laden von whisper-small kostet in beiden Builds etwa 420–440 MB Native Heap (D2 gegen 2c).
- **Die erste Erkennung kommt mit weiteren rund 390 MB Native Heap hinzu (D2 → D3), die zweite mit rund 100 MB (D5).** Das sind Puffer von onnxruntime im Whisper-Isolat: die CPU-Arena und vorbereitete Gewichte. Sie bleiben, bis das Modell freigegeben wird. Ein zweites Modell im Prozess gibt es nicht, das Overlay teilt.
- Hochgerechnet auf den Release-Build mit App, Overlay, Offline-Stimme und Erkennung ergeben sich etwa 525 + 35 + 70 + 390 ≈ 1,0 GB. Das liegt über dem Ziel von 0,8 GB. Die 1,3 GB aus dem Gerätetest erklären sich damit zum größeren Teil aus diesen Puffern und nicht nur aus dem doppelt geladenen Modell.
- Die Freigabe im Hintergrund gibt alles wieder ab (D6). Der Rest liegt im Debug-Build höher, weil die Dart-VM dort mehr belegt.

## onnxruntime-Arena
sherpa-onnx 1.13.8 bietet keine Einstellung, die CPU-Speicherarena von onnxruntime abzuschalten. `OfflineModelConfig` und `OfflineWhisperModelConfig` kennen nur `numThreads`, `provider`, `debug` und die Modellpfade. `EnableCpuMemArena` kommt in der nativen Bibliothek nur in der Konfiguration der GPU-Provider (CUDA/TensorRT) vor. Ohne eigenen Build von sherpa-onnx lässt sich die Arena nicht abschalten, deshalb wurde nichts geändert. Mögliche nächste Schritte, nicht Teil von WP30: eine kürzere Freigabefrist nach der letzten Erkennung, weniger Threads für Whisper (prüfen, ob die Arena je Thread wächst) oder ein eigener sherpa-onnx-Build mit `DisableCpuMemArena`.
