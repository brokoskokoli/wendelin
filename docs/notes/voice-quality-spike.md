# Spike Sprachqualität: STT- und TTS-Kandidaten (WP102, 2026-10-19)

Grundlage für WP103 (K64). Gemessen auf dem Mac (Apple Silicon, 4 Threads, sherpa-onnx Python 1.13.8, int8-Modelle), mit `tool/voice_quality_measure.py` (Aufruf im Kopf der Datei). Keine Handy-Zahlen: Absolutzeiten und RAM gelten für den Mac; für das Telefon zählen die Verhältnisse (RTF) und die Reihenfolge. Echte Geräte-Werte misst Maintainer im Folgepaket per Debug-Ansicht; eine Emulator-Stichprobe steht unten.

## Messaufbau und Grenzen
- Eingabe: die 36 Befehls-Fixtures de/fr/en aus `app/test/fixtures/stt` (macOS `say`, 16 kHz) plus ein langer Satz je Sprache (ca. 35 Wörter), mit 300 ms Pre-Roll und 800 ms Endstille wie der Endpointer. Feste Sprache wie in der App. Normalisierung wie `stt_wer.dart` (Zahlen 0–20 als Wörter; „7h30“/„9h“ zählen deshalb als Fehler, bei allen Modellen gleich).
- Rauschen: synthetisch (weiß/rosa gemischt, 10 dB SNR), „GTCRN“ = `gtcrn_simple.onnx` davor.
- Nur 36 + 3 Sätze und Computerstimmen: Unterschiede unter etwa 3 Prozentpunkten sind Rauschen. Echte Stimmen sind ein anderer Test; eine zweite Messung mit Maintainers Aufnahmen (Stimme `own` im Manifest) ist sinnvoll, bevor „groß“ als Standard gilt.
- RAM = Spitze des Prozesses (ein Modell, eine Sprache, ohne Flutter). Telefon-App liegt darüber (Dart-Heap, Audio, andere Modelle).
- RTF = Rechenzeit / Audiodauer (kleiner ist schneller).
- Hinweis-Begriffe: sherpa-onnx kennt für Whisper keinen Prompt (`from_whisper` hat keinen Parameter dafür). Hotwords gibt es nur für Transducer mit `modified_beam_search`. Bei Parakeet gemessen (Abschnitt „Hotwords bei Parakeet“): sie wirken stark. Eine erste Messung ohne `bpe_vocab` zeigte keine Wirkung, weil die Hotwords dann gar nicht kodiert wurden; das war ein Messfehler. Für Whisper bleibt die nachgelagerte Vokabular-Korrektur der App. „Wendelin-Treffer“ unten zählt, wie oft der Eigenname roh richtig kommt (6 Sätze).
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
- **Parakeet v3** ist so genau wie medium auf Deutsch (3,9 %), englisch gut, aber mit RTF 0,04 etwa fünfmal schneller als small und zehnmal schneller als medium. RAM 1,3 GB ähnlich small. Schwächen: Einwort-Antworten ohne Sprachbindung („Ja.“ → „Yeah.“, de-11), Zahlen als Ziffern (zählt hier als Fehler bei >20 / Uhrzeiten, in der App egal), keine Sprachwahl, Französisch 15,4 %. Hotwords für den Eigennamen funktionieren (siehe unten). Lizenz CC-BY-4.0 (Namensnennung in der App).
- **whisper-medium** ist am besten insgesamt, aber 2,4 GB RAM und RTF 0,5 auf dem Mac: auf dem Telefon vermutlich 5 bis 10 s je Satz. Nur als „maximal genau, langsam“.
- **whisper-turbo**: Die deutsche WER 13,2 % kommt fast nur von einem Ausreißer: de-07 wiederholt den Satz („… halb sieben. Stell einen Wecker für halb sie“, 6 Fehler bei 6 Wörtern). Ohne de-07 liegt Deutsch bei **5,7 %** (small 10,0 %, medium 4,3 %, Parakeet 4,3 %, jeweils ohne de-07), Französisch 12,1 %, und es ist das rauschfesteste Modell (14,5 %). Vermutung: der int8-Decoder neigt zu Wiederholungsschleifen (nicht geprüft, keine fp32-Variante gemessen). Mit 1037 MB Download und 2,2 GB RAM bleibt es groß und mit RTF 0,3 deutlich langsamer als Parakeet; als Kandidat „robust bei Rauschen“ behalten, aber nur mit Schutz gegen Wiederholungen (z. B. Abbruch, wenn der Text länger als das Audio erlaubt) und erst nach Gerätemessung.
- **Canary-180m-flash** (207 MB, 734 MB RAM, schnell) ist am besten auf Französisch (11,0 %), de 14,5 %. Kleiner Kandidat für Französisch oder als „schnell + gut“ gegen base. Sprachbindung per `src_lang`.
- Französisch ist bei allen Modellen schwach (11 bis 35 %); ein Teil sind Zahl-/Uhrzeitschreibweisen und die synthetische Stimme „Flo“ (fr-04, fr-08).
- Vergleich mit `docs/notes/stt-wer-2026-10-13.md` (base 21,0 %, small 9,3 % mit fester Sprache): In die WER hier gehen wie dort nur die 36 Kurzsätze ein (lange Sätze und b6 stehen in eigenen Spalten), die Zusatzsätze erklären den Unterschied also nicht. Er liegt am anderen Messweg und an der Normalisierung: Deutsch ist fast gleich (small 9,2 gegen 9,2; base 31,6 gegen 30,3, ein Wort), Französisch weicht ab (small 22,0 gegen 17,6; base 35,2 gegen 30,8). Die alte Messung lief über `WhisperSpeechToText` der App (deren Textbereinigung, Einstellungen wie Pre-Roll und `tail_paddings`) und wertete „7h30“ als „sept heures 30“ richtig; dieses Skript ruft sherpa-onnx direkt mit `tail_paddings` im Standard auf und zählt „7h30“/„9h“ als Fehler. Welcher der Punkte wie viel ausmacht, wurde nicht einzeln getrennt; die Reihenfolge der Modelle ist in beiden Messungen gleich.

## Hotwords bei Parakeet (b6, Eigenname „Wendelin“)
Aufbau: `decoding_method=modified_beam_search`, `hotwords_file` mit `Wendelin` und `Wendelin-Test` (Score 3,0), `modeling_unit=bpe`, `bpe_vocab` = `tokenizer.vocab` aus der `.nemo`-Datei des Originals (`nvidia/parakeet-tdt-0.6b-v3`; im sherpa-Paket fehlt es). Aufruf: `stt --only parakeet-v3 --hotwords DIR`. Rohdaten: `../james-wt/handoff/wp102-stt-hotwords.json` und `wp102-stt-nohotwords.json` (gleicher Lauf ohne Hotwords).

| Parakeet v3 | ohne | mit Hotwords |
|---|--:|--:|
| b6-Sätze WER (6 Sätze, sauber) | 34,5 | **12,7** |
| Wendelin-Treffer sauber / Rauschen / Rauschen+GTCRN | 3/6, 0/6, 0/6 | **6/6, 5/6, 6/6** |
| WER 36 Kurzsätze sauber (de / fr / en) | 7,3 (3,9 / 15,4 / 1,2) | 7,3 (5,3 / 12,1 / 3,7) |
| WER Kurzsätze Rauschen / Rauschen+GTCRN | 25,0 / 33,9 | 27,4 / 42,3 |
| RTF kurz, RAM-Spitze | 0,047, 1247 MB | 0,040, 1396 MB |

- Der Name kommt jetzt roh richtig („Was steht in meiner Notiz Wendelin Test?“); vorher „Notizwendel im Test“, „Motipswindeln“. Beam Search mit Hotwords stört einzelne andere Sätze (de-07 „halb 7“ statt „halb sieben“, fr-05 „à cette heure et demie“ statt „à 7h30“, fr-07 „Lismo“), die Gesamt-WER bleibt sauber gleich, bei Rauschen steigt sie um 2 bis 8 Punkte. Nur ein Score (3,0) und ein Vokabular gemessen; ein Score unter 3 könnte die Nebenwirkung senken. In der App müssten alle Titel und Listennamen als Hotwords (Token-Kodierung per `bpe.vocab`) beim Laden übergeben werden; Änderungen am Vokabular heißen dann Erkenner neu bauen.

## TTS

| Stimme | Sprache | Download | Laden | RAM-Spitze | RTF kurz / lang | erstes Audio (Satz 1) |
|---|---|--:|--:|--:|--:|--:|
| Piper thorsten medium (heute) | de | 37 MB | 1,0 s | 211 MB | 0,22 / 0,16 | 140–264 ms |
| Piper kerstin low (heute) | de | 37 MB | 0,7 s | 169 MB | 0,15 / 0,13 | 135–189 ms |
| Piper thorsten **high** (int8) | de | 55 MB | 1,0 s | 198–235 MB | 0,79–1,27 / 0,82–1,06 | 635–1389 ms |
| Piper thorsten **high** (fp32) | de | 115 MB (entpackt 132) | 0,6 s | 373 MB | **0,43 / 0,29** | 188–490 ms |
| Piper siwis medium (heute) | fr | 37 MB | 0,6 s | 204 MB | 0,15 / 0,11 | 96–188 ms |
| Piper ljspeech medium (heute) | en | 37 MB | 0,9 s | 236 MB | 0,14 / 0,10 | 80–134 ms |
| Piper lessac **high** | en | 55 MB | 1,0 s | 243 MB | 0,92 / 0,74 | 609–1043 ms |
| Kokoro v1.0 `ff_siwis` | fr | 190 MB | 0,8 s | 532 MB | 0,74 / 0,64 | 683–823 ms |
| Kokoro v1.0 `af_heart` (en-us), `bf_emma` (britisch) | en | 190 MB (gemeinsam) | 0,7–0,8 s | 509–571 MB | 0,66–1,00 / 0,59–0,66 | 706–924 ms |
| Piper miro "high" (de, fr) | de/fr | 37 MB | 0,7–1,0 s | ~210 MB | 0,17 / 0,11–0,13 | 120–240 ms |

- „Erstes Audio“ = Zeit bis zum ersten Satz-Callback (die Pipeline synthetisiert satzweise; Kurztext / Langtext, wobei der erste Satz des Langtexts kurz ist).
- Kokoro kann **kein Deutsch** (Sprachen v1.0: en, fr, es, it, pt, hi, ja, zh).
- **Piper „high“ int8 ist auf dem Mac nur etwa so schnell wie Echtzeit (RTF 0,8 bis 1,3, zwei Läufe streuen stark; in den Rohdaten liegt nur der letzte Lauf), die fp32-Variante derselben Stimme dreimal schneller (RTF 0,3 bis 0,4)**: die int8-Quantisierung des großen Modells bremst auf dem Mac, sie spart nur Platz (55 gegen 115 MB Download). Wiederholte Messung von thorsten medium im selben Lauf: 0,17 / 0,12 (nicht in den Rohdaten). Für „high“ also fp32 nehmen (373 MB RAM); ob int8 auf ARM-Handys schneller ist, ist offen, ebenso lessac-high fp32 (nicht gemessen, Vermutung: gleiches Verhalten). Nicht als Standard; als wählbare „Qualität“ mit Warnung, wenn der Handy-RTF über 0,5 liegt.
- **Miro „high“** hat nur eine 18,5-MB-Modelldatei (int8), genau so groß wie thorsten medium (18,6 MB), und in seiner Konfiguration steht `quality: training`: Es ist keine echte high-Architektur, sondern das mittlere Modell unter dem Namen „high“, deshalb RTF wie medium. Ausgeschlossen ist es ohnehin wegen der Lizenz (unten).
- Alle Hörproben wurden zur Plausibilität per Whisper small zurückerkannt (WER 0 bis 12 %, miro de 22 %), also keine kaputte Ausgabe.
- **Miro-Stimmen: nicht verwenden** (Lizenz CC BY-NC-SA 4.0, keine kommerzielle Nutzung, synthetisch trainiert).

Hörproben für Maintainer: `../james-wt/handoff/wp102-samples/<stimme>/<stimme>-<sprache>.wav` (derselbe Text je Sprache, 3 Sätze; eine Stimme spricht nur ihre Sprache). Rohdaten: `../james-wt/handoff/wp102-stt.json`, `wp102-tts.json`.

## Emulator-Stichprobe (Größenordnung)
Android-Emulator `Wendelin_AOSP_35` (arm64-v8a, qemu nativ auf dem M3 Pro, 4 Kerne, 2,5 GB RAM, Android 15), sherpa-onnx v1.13.8 mit aarch64-Binaries, 4 Threads, je ein Lauf, int8:

| Modell | RTF kurz / lang | Latenz |
|---|--:|--:|
| whisper-small (de) | 0,565 / 0,291 | 1,6 s für 2,8 s Audio |
| Parakeet v3 | 0,058 / 0,043 | 0,16 s |
| Piper thorsten medium | 0,149 / 0,160 | 0,28 s |

Nur die Größenordnung: ein Lauf je Modell, Emulator ist kein Telefon. Kokoro, RAM und Ladezeit wurden nicht gemessen. Die Verhältnisse passen zum Mac (Parakeet etwa zehnmal schneller als small, Piper medium etwa so schnell wie am Mac), small ist im Emulator gegenüber dem Mac langsamer (RTF kurz 0,57 gegen 0,22).

## Quellen, Version, Lizenz

Release-Tags `asr-models`, `tts-models`, `speech-enhancement-models` unter github.com/k2-fsa/sherpa-onnx/releases (rollend, Stand 2026-10-19), Whisper-int8 als Einzeldateien von Hugging Face `csukuangfj/sherpa-onnx-whisper-*`.

| Modell | Bezug | Original-Lizenz |
|---|---|---|
| Whisper base / small / medium | HF `csukuangfj/sherpa-onnx-whisper-{base,small,medium}` (`*.int8.onnx`) | Apache-2.0 (openai/whisper-*) |
| Whisper large-v3-turbo | HF `csukuangfj/sherpa-onnx-whisper-turbo` | MIT |
| Parakeet TDT 0.6B v3 int8 | Release `asr-models`: `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2` (487 MB; hier als HF-Dateien geladen) | CC-BY-4.0 (nvidia) |
| Canary-180m-flash int8 | `asr-models`: `sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8.tar.bz2` (154 MB) | CC-BY-4.0 (nvidia) |
| GTCRN | `speech-enhancement-models`: `gtcrn_simple.onnx` (0,5 MB) | MIT (Modellkarte) |
| Piper thorsten medium/high, kerstin low | `tts-models`: `vits-piper-de_DE-*-int8.tar.bz2`, thorsten high auch fp32 `vits-piper-de_DE-thorsten-high.tar.bz2` | CC0 |
| Piper siwis medium | `vits-piper-fr_FR-siwis-medium-int8` | CC-BY-4.0 (Namensnennung) |
| Piper ljspeech medium | `vits-piper-en_US-ljspeech-medium-int8` | Public Domain |
| Piper lessac high | `vits-piper-en_US-lessac-high-int8` | Blizzard-2013-Lizenz (Edinburgh), vor Einbau prüfen |
| Kokoro multi-lang v1.0 int8 | `tts-models`: `kokoro-int8-multi-lang-v1_0.tar.bz2` (132 MB) | Apache-2.0 |
| Piper miro high (de, fr) | `vits-piper-{de_DE,fr_FR}-miro-high-int8` | CC BY-NC-SA 4.0, ausgeschlossen |

Modelle liegen unter `~/wendelin-fixtures/models` (früher `handoff/wp102-models`; Ordner per `WENDELIN_MODELS` änderbar) (nicht im Repo). Für Hotwords zusätzlich `tokenizer.vocab` aus `parakeet-tdt-0.6b-v3.nemo` (HF `nvidia/parakeet-tdt-0.6b-v3`, CC-BY-4.0) in `wp102-models/parakeet-bpe/`.

## Empfehlung für WP103
1. **Standard bleibt `whisper-small`** (fest Sprache). Er bleibt ein vertretbarer Kompromiss und ist unverändert getestet.
2. **„Groß“ (wählbar): Parakeet TDT 0.6B v3 int8** (de/fr/en/es…, 670 MB, ~1,3 GB RAM, mit Hotwords ~1,4 GB). Auf Deutsch so gut wie whisper-medium (3,9 % ohne Hotwords, 5,3 % mit Hotwords, beides unter der 3-Punkte-Schwelle) bei Small-Geschwindigkeit oder besser; zuerst auf dem Handy messen (RTF, RAM). Hinweise: CC-BY-Nennung, Einwort-Ja/Nein gegen die Sprachprüfung des Assistenten absichern, kein Sprach-Zwang, Hotwords-Liste aus Titeln/Namen beim Laden übergeben. Als Zusatz **whisper-medium** nur falls Maintainer die höchste Genauigkeit will und Wartezeit akzeptiert (Gerät mit ≥ 6 GB RAM).
3. **Französisch:** Canary-180m-flash als schnelle Alternative (207 MB, beste fr-WER); sonst small/Parakeet. **Eigennamen:** Parakeet mit Hotwords (b6-WER 34,5 auf 12,7 %, Treffer 6/6) ist der stärkste Hebel gegen Fehlerkennung von „Wendelin“; Wirkung auf die Gesamt-WER neutral, bei Rauschen leicht negativ. Whisper-turbo nur als späterer Kandidat für verrauschte Umgebung (Ausreißer de-07, siehe oben), GTCRN nicht einbauen.
4. **TTS:** Standard unverändert (Piper thorsten medium, siwis medium, ljspeech medium; alles RTF ≤ 0,22). **Kokoro** (190 MB, RTF ~0,6–0,8) als wählbare Stimme für Englisch und Französisch, wenn Maintainer sie in den Hörproben besser findet; für Deutsch gibt es kein Kokoro. **Piper thorsten high nur als fp32** (115 MB, 373 MB RAM, RTF 0,3 bis 0,4 am Mac; die int8-Variante ist langsamer und nicht empfohlen), wählbar als „Qualität“ bei Handy-RTF < 0,5; lessac high erst nach fp32-Messung.
5. Nächster Schritt vor WP103: Handy-Messung mit der Debug-Ansicht (RAM, RTF) für Parakeet, medium und Kokoro; zweite WER-Messung mit echten Stimmen.
