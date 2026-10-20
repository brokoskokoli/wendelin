# Wake Words im Vergleich (WP111): Messung

Stand: Teil A (synthetisch) gemessen, 2026-10-20/21. Teil B (echte Aufnahmen) offen. Nur Zahlen, keine Transkripte und keine Aufnahmen.

## Ziel
Frage: Ist „Hey Wendelin“ als Wake Word besser als „Wendelin“, und welches offene Erkennungsprogramm trägt es? Zielwerte: Treffer >= 80 %, <= 2 Fehlalarme je Stunde (FA/h) nach allen Stufen. Bezug ist WP106 (`docs/notes/wake-word-station-spike.md`). Porcupine entfällt (Entscheidung Stefan 2026-10-20).

## Aufbau
Zwei Wörter (`wendelin`, `hey`) x vier Stufe-1-Regeln, danach Stufe 2 (Parakeet ohne/mit Hotwords) auf identischem Audio (Rausch-Parameter je Clip per Seed, Paare „Wendelin“/„Hey Wendelin“ gleich).

Stufe-1-Regeln (`--rules`):
- `T<thr>`: Vorlagen (Kosinus gegen 15 Einlernclips je Stimme).
- `M<thr>`: openWakeWord v7 (mit Mix trainiert, deckt „Hey“ mit ab).
- `W<thr>`: microWakeWord, je Wort eigenes Modell (`--mww wendelin=..,hey=..`).
- `K<g|z><boost>/<thr>`: sherpa-onnx Keyword Spotting ohne Training, Wort frei eingegeben; `g` = gigaspeech (BPE), `z` = zh-en (Phoneme).

Stufe 2: Parakeet mit `parakeet-bs` (ohne Hotword), `parakeet-hw2`, `parakeet-hw3` (Hotword-Boost). Regel je Wort: `matches_wake_word` (App-Spiegel) bzw. `matches_hey_wake_word` (Hey-Wort direkt vor Wendelin-Treffer, `tool/kws_measure.py`). Stufe 3 (CAM++) ist in `--compare` nicht enthalten.

Kennzahlen: Treffer % (Wilson-95-%), Kandidaten/h Stufe 1, FA/h nach Stufe 2 (Poisson-Obergrenze), Verwechsler als Quote, „andere Phrase löst aus“ (für `wendelin`: Hey-Clips, Treffer erwartet; für `hey`: nacktes „Wendelin“, soll nicht auslösen), Latenz/RTF/RAM am Mac.

## Regeln der Messung
- Labels nie aus dem gemessenen Erkenner. Negativclips mit „Wendel…“ im Ausschluss: Treffer von Parakeet ODER Whisper small (nur diese beiden und die Namensregel `b6-*`; die Textvorlagen der Clips gehen nicht in den Ausschluss ein, sie enthalten nur Verwechsler wie „Wendel“, „Wendeltreppe“, kein „Wendelin“).
- Positive Paare müssen dieselben Dateinamen haben (`check_pairs`), sonst Abbruch.
- Negativsprache >= 1,5 h (Log „Negativ: .. h“, sonst Warnung).
- Wilson-Intervalle bei Treffern, Poisson-Obergrenzen bei FA/h; Station und Mobil getrennt (Bedingungen `clean`, `both`, `station`).

## Datenquellen
- Testsprache: macOS-Systemstimmen (9 Stimmen, `gen_say_test.py`) statt Piper, unabhängig von den Trainingsstimmen und vergleichbar mit WP106. Abweichung vom Paketwortlaut (Piper).
- Fernseher: FLEURS test (862 Clips, ca. 6 h), nicht im Training von v7/mww.
- Hintergrund und Hall: synthetisch (wp106 `bg`/`rirs`), kein FSD50K/FMA.
- Negativsprache synthetisch (Systemstimmen), Verwechsler 306 Clips, Einlernclips `enroll_hey` 135.

## microWakeWord-Training
- Positive: ca. 14k Piper-Clips Wendelin (10,3k bare + 40 % hey) bzw. ca. 9,4k hey; Verwechsler 10,2k, Sprache 10,8k, 2x Augmentierung.
- Schritte 40000 + 20000 je Wort (`run_mww.sh`, `STEPS=40000`), beide Trainings parallel unter `nice`.
- Logs: `~/wendelin-models/kws/wp111/mww/` (Arbeitsordner), `train_wendelin.log`, `train_hey.log`, `feats_*.log`, `run_mww.log` unter `~/wendelin-models/kws/wp111/`.
- Modelle: `mww/trained_{w,h}_main/tflite_stream_state_internal_quant/stream_state_internal_quant.tflite`.

## Ergebnisse
Alle Zahlen synthetisch (Systemstimmen, 135 Positive je Wort und Bedingung, Negativsprache 1,93 h, Fernseher 1,01 h FLEURS test; Vorlagen T: 9 Stimmen-Vorlagen, Stundenbasis 17,4 h bzw. 9,06 h). Treffer % mit Wilson-95-%-Intervall in eckigen Klammern. FA/h = Punktwert Sprache / Fernseher, in Klammern die Poisson-Obergrenze (95 %). Stufe 2: `bs` = Parakeet ohne Hotword, `hw2`/`hw3` = Hotword-Boost 2 bzw. 3. Ein Fehlalarm (FA) ist ein Treffer der Wortregel nach Stufe 1 und Stufe 2 auf Negativ; Verwechsler und „andere Phrase“ stehen in der CSV. † T: Einlernstimmen = Teststimmen, siehe „Fairness“; die Werte für T sind geschönt.

Vollansicht (alle Regeln x Stufe 2 x Bedingung, Verwechsler, „andere Phrase löst aus“, Kandidaten/h, Stunden): lokal `~/wendelin-models/kws/wp111/results/{nomww,mww}/compare_table.{md,csv}` und `compare_meta.json` (nicht im Repo).

**A. Beste Konfiguration mit FA/h <= 2 (Punktwert, Sprache und Fernseher)**


Handy (clean)

| Programm | Wendelin | Hey Wendelin |
|---|---|---|
| T Vorlagen † | T0,93 + hw3: **99 %** [96–100]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) | T0,93 + hw3: **100 %** [97–100]; FA/h 0,7 / 0,0 (≤ 1,3 / 0,4) |
| M openWakeWord v7 | M0,3 + hw2: **44 %** [36–52]; FA/h 1,6 / 0,0 (≤ 4,5 / 3,7) | M0,3 + hw2: **22 %** [16–30]; FA/h 1,0 / 0,0 (≤ 3,7 / 3,7) |
| W microWakeWord | W0,8 + hw2: **23 %** [17–31]; FA/h 1,0 / 0,0 (≤ 3,7 / 3,7) | W0,5 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) |
| K sherpa-KWS | Kz4/0,05 + bs: **26 %** [19–34]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) | Kz4/0,05 + hw2: **53 %** [44–61]; FA/h 0,5 / 0,0 (≤ 2,9 / 3,7) |

Handy mit Rauschen/Hall (both)

| Programm | Wendelin | Hey Wendelin |
|---|---|---|
| T Vorlagen † | T0,93 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) | T0,93 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) |
| M openWakeWord v7 | M0,3 + hw2: **9 %** [5–15]; FA/h 0,5 / 0,0 (≤ 2,9 / 3,7) | M0,3 + hw2: **7 %** [4–12]; FA/h 0,5 / 0,0 (≤ 2,9 / 3,7) |
| W microWakeWord | W0,5 + hw2: **1 %** [0–4]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) | W0,5 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) |
| K sherpa-KWS | Kz2/0,15 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) | Kz2/0,15 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) |

Station (station)

| Programm | Wendelin | Hey Wendelin |
|---|---|---|
| T Vorlagen † | T0,93 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) | T0,93 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) |
| M openWakeWord v7 | M0,3 + hw2: **11 %** [7–18]; FA/h 0,5 / 0,0 (≤ 2,9 / 3,7) | M0,3 + hw2: **11 %** [7–18]; FA/h 1,6 / 0,0 (≤ 4,5 / 3,7) |
| W microWakeWord | W0,9 + hw3: **18 %** [12–25]; FA/h 1,0 / 1,0 (≤ 3,7 / 5,5) | W0,5 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) |
| K sherpa-KWS | Kz2/0,15 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) | Kz4/0,05 + hw2: **1 %** [0–5]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) |

**B. Höchster Treffer ohne FA-Grenze (zeigt den Zielkonflikt)**


Handy (clean)

| Programm | Wendelin | Hey Wendelin |
|---|---|---|
| T Vorlagen † | T0,93 + hw3: **99 %** [96–100]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) | T0,93 + hw3: **100 %** [97–100]; FA/h 0,7 / 0,0 (≤ 1,3 / 0,4) |
| M openWakeWord v7 | M0,3 + hw3: **49 %** [41–57]; FA/h 10,4 / 7,0 (≤ 16,0 / 14,3) | M0,3 + hw3: **25 %** [19–33]; FA/h 8,8 / 8,9 (≤ 14,1 / 17,0) |
| W microWakeWord | W0,5 + hw3: **37 %** [29–45]; FA/h 25,4 / 2,0 (≤ 33,5 / 7,2) | W0,5 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) |
| K sherpa-KWS | Kz4/0,05 + hw3: **57 %** [49–65]; FA/h 15,5 / 7,0 (≤ 22,2 / 14,3) | Kz4/0,05 + hw3: **53 %** [45–62]; FA/h 3,1 / 0,0 (≤ 6,8 / 3,7) |

Handy mit Rauschen/Hall (both)

| Programm | Wendelin | Hey Wendelin |
|---|---|---|
| T Vorlagen † | T0,93 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) | T0,93 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) |
| M openWakeWord v7 | M0,3 + hw3: **17 %** [12–24]; FA/h 15,5 / 6,0 (≤ 22,2 / 13,0) | M0,3 + hw3: **21 %** [15–28]; FA/h 11,4 / 6,0 (≤ 17,2 / 13,0) |
| W microWakeWord | W0,5 + hw3: **11 %** [7–18]; FA/h 3,1 / 5,0 (≤ 6,8 / 11,6) | W0,5 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) |
| K sherpa-KWS | Kz4/0,05 + hw3: **1 %** [0–4]; FA/h 13,5 / 8,0 (≤ 19,7 / 15,7) | Kz2/0,15 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) |

Station (station)

| Programm | Wendelin | Hey Wendelin |
|---|---|---|
| T Vorlagen † | T0,93 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) | T0,93 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 0,2 / 0,4) |
| M openWakeWord v7 | M0,3 + hw3: **29 %** [22–37]; FA/h 32,1 / 11,9 (≤ 41,2 / 20,8) | M0,3 + hw3: **39 %** [31–47]; FA/h 27,4 / 6,0 (≤ 35,9 / 13,0) |
| W microWakeWord | W0,5 + hw3: **22 %** [16–30]; FA/h 3,6 / 3,0 (≤ 7,5 / 8,7) | W0,5 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) |
| K sherpa-KWS | Kz2/0,15 + bs: **0 %** [0–3]; FA/h 0,0 / 0,0 (≤ 1,9 / 3,7) | Kz4/0,05 + hw3: **2 %** [1–6]; FA/h 5,2 / 0,0 (≤ 9,5 / 3,7) |


**Lesehilfe.**
- Stufe 1 allein liefert bei v7 (M0,3) auf Station 76 % Treffer für „Hey Wendelin“ (Wendelin 64 %), aber 119 Kandidaten/h, und die jeweils andere Phrase löst zu 64 % (Hey-Modus: nacktes „Wendelin“) bzw. 76 % (Wendelin-Modus: „Hey Wendelin“) aus. Erst Stufe 2 macht daraus ein brauchbares FA/h, kostet aber den Großteil der Treffer. Hotword 2 ist der Kompromiss; Hotword 3 bringt Treffer, reißt aber die 2 FA/h (Tabelle B).
- „Hey Wendelin“ ist nicht grundsätzlich besser: K (sherpa-KWS, Phonem-Modell zh-en) gewinnt deutlich (`clean` 53 % gegen 26 %), M (v7) verliert (22 % gegen 44 %), W (microWakeWord) erreicht für „Hey“ 0 %, T ist gleich (und geschönt).
- Bedingungen `both`/`station`: Mit FA ≤ 2 kommt keine Konfiguration auf 20 %. T0,93 löst dort nie aus (0 Kandidaten), die Schwelle ist für Rauschen/Hall zu streng (nicht nachjustiert, weil T ohnehin geschönt ist).

**Rechenlast (Mac, Apple Silicon, Maschine stark ausgelastet, daher eher obere Werte).**
- Stufe 1, CPU-RTF: T 0,0001, W 0,001, M 0,036–0,038, K 0,046. Mediane Latenz Wortende bis Treffer (Stufe 1): T 0,27–0,37 s, M 0,19–0,42 s, W 0,34–0,37 s, K 0,36–0,60 s (n je Zelle 1–27, grob).
- Stufe 2 Parakeet: RTF 0,04–0,09, 124–263 ms je Segment.
- RAM (RSS): Stufe 1 (v7, Mel/Embedding) 177–182 MB, sherpa-KWS 96–98 MB, microWakeWord 47 MB, Parakeet ca. 1,04–1,08 GB.

## Fairness und Einschränkungen der Messung
**(a) Vorlagen T (Stimmen-Überlappung).** Die Einlernclips (`enroll_hey` bzw. `data/enroll` aus WP106) und die Testclips stammen aus denselben 9 Systemstimmen. Für „Hey Wendelin“ ist der Einlerntext derselbe wie im Testrahmen `f0` (nur das Wort, 27 der 135 Testclips; in den vier anderen Rahmen folgt ein Satz). Die Tempi unterscheiden sich (Einlernen 130 bis 214 in Schritten von 6, Test 150/175/205), es gibt also keine identischen Dateien, aber dieselbe Stimme mit demselben Text. T ≈ 100 % in `clean` (99 % bzw. 100 %) ist deshalb eine Obergrenze für ein persönlich eingelerntes Wort, kein Wert für fremde Sprecher.

**(b) Ausschluss aus der Negativmenge (10 von 166 Clips).** Ausgeschlossen werden Clips, bei denen Parakeet ODER Whisper small ein (Hey) Wendelin hört, sowie `b6-*` per Namensregel. Zählung:
- `b6-01` bis `b6-06` (6): die Textvorlage nennt „Wendelin“ (Notiz „Wendelin-Test“); echte Positive, gehören nicht in die Negativmenge.
- Nur Parakeet markiert (2): `s018_Eddy`, `s054_Grandpa`. Nur Whisper small markiert (2): `s006_Anna`, `s029_Flo`.
- Abgleich mit dem Ausgangstext: Die vier `s*`-Clips entsprechen je einem Satz (Satz 6 bzw. 5 der 12 Sätze je Stimme; Annahme: gleiche Satzreihenfolge in allen 9 Stimmenblöcken à 12 Clips). Derselbe Satz wurde bei den 6 bis 8 übrigen Stimmen von beiden Erkennern ohne Treffer erkannt. Der Text enthält „Wendelin“ also nicht; es sind Fehlhörer der Erkenner. Die Quelldatei der Sätze ließ sich im Messordner nicht mehr zuordnen (nicht Teil von `tool/`); der Abgleich beruht auf dem Querschnitt über die Stimmen.
- Folge: Der Ausschluss ist optimistisch. Blieben die 2 nur von Parakeet markierten Clips in der Negativmenge, kämen im ungünstigsten Fall 2 Fehlalarme hinzu: +1,0 FA/h bei 1,93 h, die Obergrenze einer Konfiguration mit bisher 0 Ereignissen stiege von 1,9 auf 3,7 FA/h. Betroffen in Tabelle A (Punktwert Sprache + 1,0): über 2 FA/h stiegen „Wendelin“ `clean` M0,3+hw2 (1,6 auf 2,6) und „Hey Wendelin“ `station` M0,3+hw2 (1,6 auf 2,6); knapp darüber (1,0 auf etwa 2,1) „Hey Wendelin“ `clean` M0,3+hw2, „Wendelin“ `clean` W0,8+hw2 und „Wendelin“ `station` W0,9+hw3. Alle übrigen Zellen blieben ≤ 2 (T mit 17,4 h Basis kaum betroffen). Für Teil B: die vier `s*`-Clips nach dem Stimmenquerschnitt in der Negativmenge belassen. Die 2 nur von Whisper markierten Clips ändern Parakeet nicht, wären aber relevant, falls eine App Whisper als Stufe 2 nähme (nicht gemessen). Stufe-1-Kandidaten aus den ausgeschlossenen Clips sind in den Zahlen nicht enthalten.

**(c) microWakeWord-Training (`train_wendelin.log` endet auffällig).** Der Endtest des quantisierten Streaming-Modells (`AUC 1.25334`, `Cutoff 1.00: frr=1.0000`, `Cutoff 0.99: frr=0.2533; faph=2.000`) ist kein gültiger AUC-Wert (über 1 ist nicht möglich): Die uint8-Ausgabe des quantisierten Modells ist am oberen Ende sehr grob, die Kurve besteht praktisch aus zwei Punkten (1,00 und 0,99), und die Integration läuft über eine nicht normierte Achse (Vermutung, Skript nicht untersucht). Aussagekräftiger sind die Validierungszeilen des nicht-streamenden Modells: bestes Modell mit Recall 87,0 % bei 0 FA/h (Schwelle 0,87); danach wurde der Umgebungs-FA bei weiterem Training schlechter (Schritt 42000: 46,6 FA/h, Schritt 54500: 25,1 FA/h bei „recall at no faph = 0“), das Training behält die besten Gewichte. „Hey“ endet normal (AUC 0,129 auf dessen Testsatz, frr 0,06 bei 0 bis 2 FA/h). Auf unserem Messsatz (Systemstimmen) erreicht das Modell trotzdem 0 % für „Hey“ und 38 % für „Wendelin“ (Stufe 1, W0,5, `clean`). Das spricht für einen Domänenunterschied (Training und interner Test nur Piper-Stimmen, ca. 14k bzw. 9k Positive, kein FSD50K/FMA) und nicht für einen Messfehler; eine Ursachenanalyse steht aus. Die Aussage „W unbrauchbar“ gilt nur für dieses Modell. Einschränkung: Die Verwechslerliste `CONF2` enthielt bei diesem Training „Hey Wendelin Müller“, also ein echtes Positiv als Negativ (nach dem Lauf aus `gen_samples.py` entfernt, nicht neu trainiert); ein Teil davon fiel vermutlich über `max_clip_duration_s=1.5` weg, der Einfluss auf „Hey“ (0 %) ist nicht untersucht.

**(d) Weitere Grenzen.** Test- und Negativsprache synthetisch (Systemstimmen); Rauschen, Hall und Fernseher simuliert; `both`/`station` sind strenger als die echten Aufnahmen aus WP106 (dort 60 % sicher mit Vorlagen und v7, Stufe 2 Hotword 2). Je Zelle n = 135 (Wilson-Breite bis etwa ±9 Punkte). Ein Messlauf je Konfiguration (Seed 1).

## Empfehlung
**Zielwerte (≥ 80 % Treffer, ≤ 2 FA/h nach allen Stufen) werden von „Hey Wendelin“ nicht erreicht, von „Wendelin“ ebenso wenig** (synthetisch, ohne Stufe 3).
- Handy, `clean`: beste ehrliche Konfiguration (ohne die geschönte Vorlagenregel T) für „Hey Wendelin“ ist sherpa-KWS `Kz4/0,05` + Parakeet Hotword 2 mit 53 % [44–61] bei 0,5 FA/h (Sprache) und 0 FA/h (Fernseher): 27 Punkte unter dem Ziel. „Wendelin“ erreicht mit v7 `M0,3` + Hotword 2 44 % [36–52] bei 1,6 FA/h. Mit Rauschen/Hall (`both`) 7 bis 9 % und auf der Station 11 bis 18 % bei ≤ 2 FA/h (Tabelle A); mit 3 bis 11 FA/h wären 21 bis 39 % möglich (Tabelle B). Die Lücke zum Ziel ist in den Störbedingungen groß (60 bis 70 Punkte).
- Mit Vorlagen T (persönlich eingelernt, gleiche Stimmen wie der Test, `clean`) werden 99 % bzw. 100 % bei ≤ 1 FA/h erreicht, aber das ist geschönt (Fairness a) und in `both`/`station` bei T0,93 bei 0 %.
- Vergleich der Wörter: kein klarer Gewinn für „Hey Wendelin“ mit den vorhandenen Modellen. Vorteil bei sherpa-KWS (Phonem-Modell, ohne Training), Nachteil bei v7 und microWakeWord; die Modelle v7 und mww sind nicht gleich gut auf „Hey“ trainiert (v7 mit Mix, mww nur Piper). Die erwartete Wirkung des „Hey“ (weniger Verwechsler wie „Wendeltreppe“) ist hier nur über die Spalte „Verwechsler“ der CSV sichtbar (bei den Konfigurationen der Tabelle A 0 bis 5 %).

**Empfehlung.**
- **Wort**: bei „Wendelin“ bleiben; die Entscheidung für „Hey Wendelin“ erst nach Teil B (echte Aufnahmen) und nach einem eigenen Stufe-1-Modell, das „Hey Wendelin“ mit mehr Stimmen lernt. Die synthetische Messung rechtfertigt den Wechsel nicht.
- **Programm**: Stufe 1 = openWakeWord v7 (`M`) wie in WP106; sherpa-KWS (`K`) ist als schlanke zweite Quelle für „Hey Wendelin“ ohne Training interessant (`Kz4/0,05`), aber nur in `clean` brauchbar (53 %); in `both`/`station` höchstens 2 % bei 5 FA/h. microWakeWord (`W`) mit dem hier trainierten Modell nicht verwenden (0 % „Hey“, wenige Treffer „Wendelin“, 47 MB RAM und 0,001 CPU-RTF sprechen aber für einen neuen Versuch mit anderen Trainingsdaten). Stufe 2 = Parakeet mit Hotword 2 (Hotword 3 hebt die Treffer, reißt aber die 2 FA/h).
- **Schwellen Handy** (Nähe, `clean`): Stufe 1 `M0,3`, Stufe 2 Hotword 2; erwartet etwa 40 bis 45 % bei 1 bis 2 FA/h, also unter dem Ziel; Feintuning aus WP106 (persönlich, 50 bis 60 % mobil) bleibt der bessere Hebel (nicht neu gemessen).
- **Schwellen Station** (2 bis 3 m, Fernseher): eigener Modus, Stufe 1 `M0,3` (119 Kandidaten/h) und Parakeet Hotword 2; erwartet etwa 11 % (synthetisch, streng) bei ≤ 2 FA/h; das echte Ergebnis aus WP106 (60 % sicher bei 2,1 bis 4,1 FA/h, n = 10) bleibt die bessere Grundlage. `M0,5` ist ruhiger (68 Kandidaten/h), aber nicht besser im Treffer-Verhältnis.
- Offen: **Teil B** (echte Aufnahmen von „Wendelin“ und „Hey Wendelin“ unter `~/wendelin-fixtures/wake/hey/raw-pos|raw-neg`, mehrere Sprecher, Räume, Fernseher) und danach die Entscheidung über das Wort; ohne diese Daten keine Änderung an App oder ADR.

## Kommandos (alle aus dem Repo-Root, `K=~/wendelin-models/kws`)
Venv wp58 (Python 3.12, WP58/WP106): `uv venv --python 3.12 $K/wp58/venv && uv pip install --python $K/wp58/venv/bin/python -r tool/train_wake_word/requirements.txt`; Piper-Stimmen unter `$K/wp58/dl`.

1. Testclips (macOS-Systemstimmen, nur lokal): `$K/wp58/venv/bin/python -I tool/train_wake_word/gen_say_test.py --out $K/wp111/data` (erzeugt `pos_wendelin`, `pos_hey`, `conf`, `enroll_hey`).
2. FLEURS test (Fernseher): `test.tar.gz` der Sprache de_de von `huggingface.co/datasets/google/fleurs` (CC-BY 4.0) entpacken, 16-kHz-WAVs (862 Clips) nach `$K/wp111/work/fleurs/test/`. Wie WP106 für `dev`.
3. Trainingsclips (Piper): `tool/train_wake_word/run_gen.sh` (Pfade über `K`, `R`). Es ruft `gen_samples.py --kind bare|hey --n 4500 --seed 31..34` und `--kind conf2 --n 2500 --seed 41,42`, jeweils `--voices $K/wp58/dl --wide --out <kind>` im Ordner `$K/wp111/gen`.
4. microWakeWord-venv: `uv venv --python 3.11 $K/wp111/mww-venv`, darin TensorFlow 2.18.1 und die Abhängigkeiten von `kahrendt/microWakeWord` (u. a. audiomentations, mmap_ninja, webrtcvad-wheels, pyyaml, scipy, soundfile, numpy 2.0); Quellen `git clone https://github.com/kahrendt/microWakeWord $K/wp106/mww-src` (Stand 4665173c).
5. Training: `tool/train_wake_word/run_mww.sh` (`STEPS=40000`). Es setzt `PYTHONPATH=$K/wp106/mww-src` und ruft mit dem mww-venv `mww_train.py prep --word wendelin`, `feats --word wendelin|hey --pos-rep 2 --conf-rep 2` und `train --word wendelin --name w_main` bzw. `--word hey --name h_main` je `--steps 40000 --threads 4` (parallel). Logs: `train_*.log`, `feats_*.log` in `$K/wp111`.
6. Messung: die zwei Kommandos unten.

Die Skripte `run_gen.sh` und `run_mww.sh` liegen unter `tool/train_wake_word/`.

Messung ohne mww (läuft mit `K=~/wendelin-models/kws`):
```
nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/station_measure.py --compare --cond clean,both,station --words wendelin,hey --rules T0.93,M0.3,M0.5,Kz2/0.15,Kz4/0.05,Kg4/0.05 --variants parakeet-bs,parakeet-hw2,parakeet-hw3 --neg-min 7 --neg-long-max 16 --tv-max-h 1.0 --fleurs $K/wp111/work/fleurs/test --out $K/wp111/results/nomww
```
Messung microWakeWord:
```
nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/station_measure.py --compare --cond clean,both,station --words wendelin,hey --rules W0.5,W0.8,W0.9 --mww wendelin=$K/wp111/mww/trained_w_main/tflite_stream_state_internal_quant/stream_state_internal_quant.tflite,hey=$K/wp111/mww/trained_h_main/tflite_stream_state_internal_quant/stream_state_internal_quant.tflite --variants parakeet-bs,parakeet-hw2,parakeet-hw3 --neg-min 7 --neg-long-max 16 --tv-max-h 1.0 --fleurs $K/wp111/work/fleurs/test --out $K/wp111/results/mww
```
Ausgabe je Lauf: `compare_table.md`, `compare_table.csv`, `compare_meta.json` im `--out`-Ordner. Selbsttests der Helfer: `$K/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_measure.py'`.

## Lizenzen (alles lokal, nichts im Repo)
Wie WP106: Parakeet TDT 0.6B v3 CC-BY-4.0; Whisper MIT; CAM++ Apache-2.0; microWakeWord Apache-2.0; openWakeWord-Code und speech_embedding Apache-2.0; sherpa-onnx und seine KWS-Modelle (gigaspeech, zh-en) Apache-2.0 (zh-en vor Nutzung im Produkt gegenprüfen); FLEURS CC-BY 4.0; macOS-Systemstimmen Apple-Lizenzvereinbarung (nur lokale Messung, Audios nicht weitergeben); Piper-Stimmen CC0 (Trainingsdaten).

## Abweichungen
- Testsprache Systemstimmen statt Piper (siehe Datenquellen); Einlern- und Teststimmen sind dieselben 9 Stimmen (Fairness a).
- Hintergrund/Hall synthetisch, kein FSD50K/FMA; Trainingsumfang des mww-Modells über dem Start-Beispiel des Projekts, aber kleiner als eine Vollproduktion (Fairness c).
- Persönliches Feintuning wurde nicht neu gemessen; CAM++-Stufe 3 nicht in `--compare`.
- Ausschlussregel der Negativmenge (Parakeet ODER Whisper small, `b6-*`) ist optimistisch (Fairness b: bis +1,0 FA/h im Worst Case).
- Teil B (echte Aufnahmen unter `~/wendelin-fixtures/wake/hey/`) fehlt: Ordner bei Start leer.
- Die Python-Selbsttests laufen nicht im Gate und nicht über `tool/t.sh` (nur Dart/Flutter), sondern per `unittest` wie oben.
- Maschine war während der Messläufe stark ausgelastet; Zeiten (RTF, ms je Segment) sind eher obere Werte.
