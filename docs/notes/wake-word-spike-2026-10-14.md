# Spike Wake Word (WP42, 2026-10-14)

Stand: nur Host-Messung (macOS, ohne Gerät) mit **synthetischen** Aufnahmen. Die Messung mit echten Aufnahmen des Maintainers, alle Emulator-/Geräteteile (Fragen 2 bis 6 auf dem Gerät) und die Prüfliste sind **offen** (siehe unten).

## Aufbau
- Skript: `tool/kws_measure.py` (Python, sherpa-onnx 1.13.8 aus dem venv `~/wendelin-models/kws/venv`, nichts im Repo). Anleitung: `tool/record_wake_fixtures.md`.
- Modelle (nur lokal in `~/wendelin-models/kws/`): `sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20` (Phoneme, chunk-8/16, encoder int8 je 4,4 MB, joiner int8 88 KB, decoder fp32 0,7 MB) und `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01` (BPE, chunk-16, int8 4,6 MB).
- Positivsatz: 90 Clips mit 9 deutschen macOS-Systemstimmen (`say`, 2 Tempi, 5 Sätze: „Wendelin“ allein, „Hey Wendelin“, 3 Sätze mit Kommando). Negativsatz: 0,3 bis 0,5 h deutsche Sprache (vorgelesene Repo-Dokus mit 8 Systemstimmen, `app/test/fixtures/stt/`). Bedingungen: `clean`, `noise` (SNR 10 dB), `reverb` (synthetische RT60 0,5 s).
- Aufruf (Beispiel): `~/wendelin-models/kws/venv/bin/python tool/kws_measure.py --model-dir <zh-en> --pos <pos> --neg <neg> --chunk 16 --thr 0.1,0.25 --boost 4,5,6 --neg-max-h 0.5 --kw "W EH1 N D AH0 L IH0 N"`.

## Ergebnisse (Trefferquote Positiv, Falschauslösungen je Stunde, Latenz Wortende → Treffer, nur „allein“-Clips)

zh-en, chunk-16, clean, 0,5 h Negativ:

| Phonemfolge | Boost | Schwelle | Treffer | FA/h | Latenz |
|---|---|---|---|---|---|
| W EH1 N D AH0 L IH0 N | 4 | 0,1 | 62 % | 56 | 0,55 s |
| W EH1 N D AH0 L IH0 N | 4 | 0,25 | 28 % | 22 | - |
| W EH1 N T AH0 L IH0 N | 4 | 0,1 | 63 % | 71 | 0,60 s |
| W IH1 N D AH0 L IH0 N | 4 | 0,1 | 43 % | 23 | 0,60 s |
| W EH1 N D L IH0 N | 5 | 0,1 | 38 % | 22 | - |
| V EH1 N D AH0 L IH1 N | 3 | 0,02 | 13 % | 7 | 0,47 s |
| V EH1 N D IH0 L IY1 N | 8 | 0,1 | 12 % | 9 | 0,43 s |
| V EH1 N D AH0 L IY2 N | 3 bis 8 | alle | 4 % | 2 | 0,47 s |

(Weitere Zeilen: Boost 5/6 verschlechtern das Verhältnis, FA/h bis über 100.) chunk-8: gleiche Größenordnung (V-Varianten 5 bis 14 %), Latenz etwa 0,1 s kürzer (0,27 bis 0,37 s). `W EH1 N D AH0 L IH0 N` mit Boost 8/Schwelle 0,02: 78 % Treffer bei 188 FA/h (Obergrenze der Empfindlichkeit).
gigaspeech-BPE, chunk-16, clean: beste Zeile `▁ VE ND E LINE` 18 % Treffer, 13 FA/h; `▁WE ND EL IN` 11 %. Unter `noise` fällt BPE auf 0 bis 7 %. Die zh-en-Phonemvarianten fallen unter `noise` auf 4 bis 6 %, unter `reverb` auf 3 bis 4 % (FA/h bis 69).
Echtzeitfaktor auf dem Host (1 Thread, Apple Silicon): 0,016 bis 0,028, das heißt etwa 1,6 bis 2,8 % eines Kerns Dauerlast. Emulator/Gerät: nicht gemessen.

## Befund
- Beide Modelle sind englisch trainiert. Ein deutsches „Wendelin“ wird nur über die englische Phonemfolge `W EH1 N D AH0 L IH0 N` (wie im Wörterbuch „Wendell“) erkannt, und auch das nur mit etwa 60 % bei weit über 2 FA/h. Kein Eintrag erreicht die WP-Grenzen (Treffer ≥ 80 %, FA ≤ 2/h). Mit Rauschen/Hall bricht es weiter ein.
- Vorbehalt: Die Positive sind Systemstimmen (nicht natürliche Sprecher); die Negative sind ebenfalls synthetisch, Zahl der FA je Stunde ist bei 0,3 bis 0,5 h Negativ grob (1 FA ≈ 2 bis 3/h). Echte Aufnahmen können besser oder schlechter ausfallen, die Größenordnung (weit unter 80 %) macht eine Änderung des Befunds aber unwahrscheinlich. Pipeline-Gegenprobe: englische Systemstimme + englisches Stichwort („hello world“, „light up“) wird erkannt, das Skript ist also in Ordnung.
- **Plan B ist ausgelöst** (Trefferquote < 80 %): eigenes Wake-Word-Modell (openWakeWord mit deutscher Piper-Stimme, Folgepaket). Bis dahin kein Standard-Schwellenwert und keine Empfindlichkeitsstufen festlegbar. Die zweite Stufe (Whisper-Bestätigung im Overlay) wäre mit den hier gemessenen FA-Raten zwingend.

## Entscheidungen (vorläufig)
- Modell: zh-en-3M als Platzhalter nur zum Pipeline-Test, nicht für den Betrieb; Entscheidung über das Modell fällt nach der Messung mit echten Aufnahmen bzw. mit dem Plan-B-Paket.
- Ort der Erkennung (Frage 3), Mikrofonübergabe (5), Startwege (4) und Barge-in-Audioquelle (6): **nicht gemessen**. Rein aus der Struktur: (a) `wakeWordMain`-Engine nutzt die vorhandene `sherpa_onnx`-Bibliothek (libsherpa-onnx-c-api arm64 4,5 MB, libonnxruntime 22 MB sind schon in der APK, also kein APK-Zuwachs außer Modell ca. 5 MB); (b) Kotlin-JNI bräuchte eine zusätzliche `libsherpa-onnx-jni.so` (Größenordnung 4 bis 5 MB je ABI, geschätzt) und eine zweite ONNX-Runtime-Variante. Empfehlung vorbehaltlich der PSS-Messung: (a).
- Modelllizenz: gigaspeech-Archiv nennt Apache-2.0 (README). Das zh-en-Archiv enthält keine Lizenzangabe; sherpa-onnx selbst steht unter Apache-2.0. **Offen:** Lizenz der zh-en-Gewichte (Trainingsdaten) vor jeder Nutzung klären.

## Offen / Maintainer
1. 20 bis 30 Aufnahmen nach `tool/record_wake_fixtures.md` (`~/wendelin-fixtures/wake/`, Ordner existierte nicht), Messung wiederholen und Tabelle ergänzen.
2. Emulator-Messungen (CPU, PSS, Foreground-Service nach Sleep/Doze, `onReady`-Start nach Neustart, `BOOT_COMPLETED`, `showSession`-Übergabe, AEC-Verfügbarkeit): offen. Der Emulator `emulator-5580` lief mit fremden E2E-Prozessen, außerdem braucht es eine Spike-APK mit Service; das war im Rahmen dieses Laufs nicht ohne Belegungskonflikt möglich.
3. Prüfliste für das echte Telefon aus WP42 (30× Wake aus 1 m/3 m, 8 h Alltag, HyperOS, AEC-Messplan).
4. Plan B (Folgepaket) einplanen.
