# Spike Sprachqualität: STT- und TTS-Kandidaten (WP102, 2026-10-19)

Grundlage für WP103 (K64). Gemessen auf dem Mac (Apple Silicon, 4 Threads, sherpa-onnx Python 1.13.8, int8-Modelle), mit `tool/voice_quality_measure.py` (Aufruf im Kopf der Datei). Keine Handy-Zahlen: Absolutzeiten und RAM gelten für den Mac; für das Telefon zählen die Verhältnisse (RTF) und die Reihenfolge. Echte Geräte-Werte misst Stefan im Folgepaket per Debug-Ansicht; die Emulator-Stichprobe fehlt (macht ein E2E-Agent).

## Messaufbau und Grenzen
- Eingabe: die 36 Befehls-Fixtures de/fr/en aus `app/test/fixtures/stt` (macOS `say`, 16 kHz) plus ein langer Satz je Sprache (ca. 35 Wörter), mit 300 ms Pre-Roll und 800 ms Endstille wie der Endpointer. Feste Sprache wie in der App. Normalisierung wie `stt_wer.dart` (Zahlen 0–20 als Wörter; „7h30“/„9h“ zählen deshalb als Fehler, bei allen Modellen gleich).
- Rauschen: synthetisch (weiß/rosa gemischt, 10 dB SNR), „GTCRN“ = `gtcrn_simple.onnx` davor.
- Nur 36 + 3 Sätze und Computerstimmen: Unterschiede unter etwa 3 Prozentpunkten sind Rauschen. Echte Stimmen sind ein anderer Test; eine zweite Messung mit Stefans Aufnahmen (Stimme `own` im Manifest) ist sinnvoll, bevor „groß“ als Standard gilt.
- RAM = Spitze des Prozesses (ein Modell, eine Sprache, ohne Flutter). Telefon-App liegt darüber (Dart-Heap, Audio, andere Modelle).
- RTF = Rechenzeit / Audiodauer (kleiner ist schneller).
- Hinweis-Begriffe: sherpa-onnx kennt für Whisper keinen Prompt (`from_whisper` hat keinen Parameter dafür). Hotwords gelten nur für Transducer mit `modified_beam_search`; bei Parakeet (NeMo-Transducer) geladen, aber ohne Wirkung (b6-Sätze identisch mit und ohne `hotwords_file`). Es bleibt bei der nachgelagerten Vokabular-Korrektur der App. „Wendelin-Treffer“ unten zählt, wie oft der Eigenname roh richtig kommt (6 Sätze).
- Wortfehlerraten unten sind Prozent der Wörter.

## STT (Standardbedingung: sauber, feste Sprache)

| Modell | Download | Laden | RAM-Spitze | WER de | WER fr | WER en | gesamt | langer Satz | Ø Satz | RTF kurz / lang |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| whisper-base (heute) | 161 MB | 0,4 s | 698 MB | 31,6 | 35,2 | 1,2 | 23,0 | 6,1 | 168 ms | 0,05 / 0,06 |
| whisper-small (heute) | 375 MB | 1,0 s | 1127 MB | 9,2 | 22,0 | 0,0 | 10,9 | 3,8 | 740 ms | 0,22 / 0,22 |
| whisper-medium | 946 MB | 1,7 s | 2385 MB | **3,9** | 14,3 | 0,0 | **6,5** | 3,0 | 1558 ms | 0,47 / 0,50 |
| whisper-turbo (large-v3-turbo) | 1037 MB | 0,9 s | 2199 MB | 13,2 | 12,1 | 0,0 | 8,5 | 3,0 | 1187 ms | 0,36 / 0,26 |
| parakeet-tdt-0.6b-v3 | 670 MB | 1,2 s | 1327 MB | **3,9** | 15,4 | 1,2 | 7,3 | 3,0 | **143 ms** | **0,04 / 0,04** |
| canary-180m-flash | 207 MB | 0,6 s | 734 MB | 14,5 | **11,0** | 0,0 | 8,5 | 0,8 | 160 ms | 0,05 / 0,07 |

Rauschen und GTCRN (WER gesamt in %; Wendelin-Treffer sauber / Rauschen / Rauschen+GTCRN):

| Modell | sauber | Rauschen | Rauschen + GTCRN | Wendelin-Treffer (6) |
|---|--:|--:|--:|--:|
| whisper-base | 23,0 | 43,5 | 42,3 | 0 / 0 / 0 |
| whisper-small | 10,9 | 28,2 | 36,7 | 4 / 3 / 1 |
| whisper-medium | 6,5 | 26,2 | 28,2 | 3 / 2 / 0 |
| whisper-turbo | 8,5 | 14,5 | 22,6 | 3 / 0 / 4 |
| parakeet-v3 | 7,3 | 25,0 | 33,9 | 3 / 0 / 0 |
| canary-180m-flash | 8,5 | 23,8 | 22,6 | 0 / 1 / 0 |

Beobachtungen:
- **GTCRN hilft nicht**: bei 4 von 6 Modellen steigt die WER (small +8,5, turbo +8,1, parakeet +8,9, medium +2,0 Punkte), bei base und Canary sinkt sie nur um 1,2. Die Modelle sind auf Rauschen trainiert; die Entrauschung erzeugt Artefakte. Nicht in die Pipeline einbauen (nur ggf. als Option, nach Test mit echtem Rauschen).
- **Parakeet v3** ist so genau wie medium auf Deutsch (3,9 %), englisch gut, aber mit RTF 0,04 etwa fünfmal schneller als small und zehnmal schneller als medium. RAM 1,3 GB ähnlich small. Schwächen: Einwort-Antworten ohne Sprachbindung („Ja.“ → „Yeah.“, de-11), Zahlen als Ziffern (zählt hier als Fehler bei >20 / Uhrzeiten, in der App egal), keine Sprachwahl/Hotwords, Französisch 15,4 %. Lizenz CC-BY-4.0 (Namensnennung in der App).
- **whisper-medium** ist am besten insgesamt, aber 2,4 GB RAM und RTF 0,5 auf dem Mac: auf dem Telefon vermutlich 5 bis 10 s je Satz. Nur als „maximal genau, langsam“.
- **whisper-turbo** bringt auf Deutsch nichts gegenüber small (13,2 %), halluziniert gelegentlich (de-07 wiederholt den Satz), ist aber rauschfest (14,5 %). Nicht empfohlen.
- **Canary-180m-flash** (207 MB, 734 MB RAM, schnell) ist am besten auf Französisch (11,0 %), de 14,5 %. Kleiner Kandidat für Französisch oder als „schnell + gut“ gegen base. Sprachbindung per `src_lang`.
- Französisch ist bei allen Modellen schwach (11 bis 35 %); ein Teil sind Zahl-/Uhrzeitschreibweisen und die synthetische Stimme „Flo“ (fr-04, fr-08).
- Die alten Werte aus `docs/notes/stt-wer-2026-10-13.md` (base 21 %, small 9,3 % mit fester Sprache) stimmen mit dieser Messung überein (23,0 / 10,9, Unterschied durch die Zusatzsätze).

## TTS

| Stimme | Sprache | Download | Laden | RAM-Spitze | RTF kurz / lang | erstes Audio (Satz 1) |
|---|---|--:|--:|--:|--:|--:|
| Piper thorsten medium (heute) | de | 37 MB | 1,0 s | 211 MB | 0,22 / 0,16 | 140–264 ms |
| Piper kerstin low (heute) | de | 37 MB | 0,7 s | 169 MB | 0,15 / 0,13 | 135–189 ms |
| Piper thorsten **high** | de | 55 MB | 1,0 s | 198 MB | 0,79 / 1,06 | 863–876 ms |
| Piper siwis medium (heute) | fr | 37 MB | 0,6 s | 204 MB | 0,15 / 0,11 | 96–188 ms |
| Piper ljspeech medium (heute) | en | 37 MB | 0,9 s | 236 MB | 0,14 / 0,10 | 80–134 ms |
| Piper lessac **high** | en | 55 MB | 1,0 s | 243 MB | 0,92 / 0,74 | 609–1043 ms |
| Kokoro v1.0 `ff_siwis` | fr | 190 MB | 0,8 s | 532 MB | 0,74 / 0,64 | 683–823 ms |
| Kokoro v1.0 `af_heart`, `bf_emma` | en | 190 MB (gemeinsam) | 0,8 s | 524–550 MB | 0,66–0,80 / 0,52–0,60 | 672–762 ms |
| Piper miro high (de, fr) | de/fr | 37 MB | 1,0 s | ~210 MB | 0,17 / 0,13 | 120–240 ms |

- „Erstes Audio“ = Zeit bis zum ersten Satz-Callback (die Pipeline synthetisiert satzweise; Kurztext / Langtext, wobei der erste Satz des Langtexts kurz ist).
- Kokoro kann **kein Deutsch** (Sprachen v1.0: en, fr, es, it, pt, hi, ja, zh).
- Piper „high“ ist auf dem Mac nur etwa so schnell wie Echtzeit (RTF ~1): auf dem Telefon wäre das hörbar stockend. Nicht als Standard; allenfalls „Qualität“ mit Warnung, wenn der Handy-RTF unter 0,5 liegt.
- Alle Hörproben wurden zur Plausibilität per Whisper small zurückerkannt (WER 0 bis 12 %, miro de 22 %), also keine kaputte Ausgabe.
- **Miro-Stimmen: nicht verwenden** (Lizenz CC BY-NC-SA 4.0, keine kommerzielle Nutzung, synthetisch trainiert).

Hörproben für Stefan: `/Users/stefanrichter/ai/james-wt/handoff/wp102-samples/<stimme>/<stimme>-<sprache>.wav` (derselbe Text je Sprache, 3 Sätze; eine Stimme spricht nur ihre Sprache). Rohdaten: `/Users/stefanrichter/ai/james-wt/handoff/wp102-stt.json`, `wp102-tts.json`.

## Quellen, Version, Lizenz

Release-Tags `asr-models`, `tts-models`, `speech-enhancement-models` unter github.com/k2-fsa/sherpa-onnx/releases (rollend, Stand 2026-10-19), Whisper-int8 als Einzeldateien von Hugging Face `csukuangfj/sherpa-onnx-whisper-*`.

| Modell | Bezug | Original-Lizenz |
|---|---|---|
| Whisper base / small / medium | HF `csukuangfj/sherpa-onnx-whisper-{base,small,medium}` (`*.int8.onnx`) | Apache-2.0 (openai/whisper-*) |
| Whisper large-v3-turbo | HF `csukuangfj/sherpa-onnx-whisper-turbo` | MIT |
| Parakeet TDT 0.6B v3 int8 | Release `asr-models`: `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2` (487 MB; hier als HF-Dateien geladen) | CC-BY-4.0 (nvidia) |
| Canary-180m-flash int8 | `asr-models`: `sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8.tar.bz2` (154 MB) | CC-BY-4.0 (nvidia) |
| GTCRN | `speech-enhancement-models`: `gtcrn_simple.onnx` (0,5 MB) | MIT (Modellkarte) |
| Piper thorsten medium/high, kerstin low | `tts-models`: `vits-piper-de_DE-*-int8.tar.bz2` | CC0 |
| Piper siwis medium | `vits-piper-fr_FR-siwis-medium-int8` | CC-BY-4.0 (Namensnennung) |
| Piper ljspeech medium | `vits-piper-en_US-ljspeech-medium-int8` | Public Domain |
| Piper lessac high | `vits-piper-en_US-lessac-high-int8` | Blizzard-2013-Lizenz (Edinburgh), vor Einbau prüfen |
| Kokoro multi-lang v1.0 int8 | `tts-models`: `kokoro-int8-multi-lang-v1_0.tar.bz2` (132 MB) | Apache-2.0 |
| Piper miro high (de, fr) | `vits-piper-{de_DE,fr_FR}-miro-high-int8` | CC BY-NC-SA 4.0, ausgeschlossen |

Modelle liegen unter `/Users/stefanrichter/ai/james-wt/handoff/wp102-models` (nicht im Repo).

## Empfehlung für WP103
1. **Standard bleibt `whisper-small`** (fest Sprache). Er bleibt ein vertretbarer Kompromiss und ist unverändert getestet.
2. **„Groß“ (wählbar): Parakeet TDT 0.6B v3 int8** (de/fr/en/es…, 670 MB, ~1,3 GB RAM). Auf Deutsch so gut wie whisper-medium bei Small-Geschwindigkeit oder besser; zuerst auf dem Handy messen (RTF, RAM). Hinweise: CC-BY-Nennung, Einwort-Ja/Nein gegen die Sprachprüfung des Assistenten absichern, kein Sprach-Zwang. Als Zusatz **whisper-medium** nur falls Stefan die höchste Genauigkeit will und Wartezeit akzeptiert (Gerät mit ≥ 6 GB RAM).
3. **Französisch:** Canary-180m-flash als schnelle Alternative (207 MB, beste fr-WER); sonst small/Parakeet. Whisper-turbo und GTCRN nicht einbauen.
4. **TTS:** Standard unverändert (Piper thorsten medium, siwis medium, ljspeech medium; alles RTF ≤ 0,22). **Kokoro** (190 MB, RTF ~0,6–0,8) als wählbare Stimme für Englisch und Französisch, wenn Stefan sie in den Hörproben besser findet; für Deutsch gibt es kein Kokoro. **Piper high** (thorsten, lessac) nur bei Handy-RTF < 0,5, sonst weglassen.
5. Nächster Schritt vor WP103: Handy-Messung mit der Debug-Ansicht (RAM, RTF) für Parakeet, medium und Kokoro; zweite WER-Messung mit echten Stimmen.
