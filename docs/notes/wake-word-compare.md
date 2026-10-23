# Wake Words im Vergleich (WP111): Messung

Stand: Teil A (synthetisch) gemessen, 2026-10-20/21. Teil B (echte Aufnahmen, WP121) gemessen 2026-10-22, siehe Abschnitt „Teil B“ am Ende; Teil A und Anhang sind vom Platzhalter-Fehler (dort beschrieben) möglicherweise betroffen und nicht neu gemessen. Nur Zahlen, keine Transkripte und keine Aufnahmen.

## Ziel
Frage: Ist „Hey Wendelin“ als Wake Word besser als „Wendelin“, und welches offene Erkennungsprogramm trägt es? Zielwerte: Treffer >= 80 %, <= 2 Fehlalarme je Stunde (FA/h) nach allen Stufen. Bezug ist WP106 (`docs/notes/wake-word-station-spike.md`). Porcupine entfällt (Entscheidung Maintainer 2026-10-20).

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
- Teil B (echte Aufnahmen) fehlte bei WP111 (Ordner leer); er steht jetzt am Ende (WP121).
- Die Python-Selbsttests laufen nicht im Gate und nicht über `tool/t.sh` (nur Dart/Flutter), sondern per `unittest` wie oben.
- Maschine war während der Messläufe stark ausgelastet; Zeiten (RTF, ms je Segment) sind eher obere Werte.

## Anhang: alternative Wörter (Nebenexperiment 2026-10-21)

Wunsch Maintainer nach einer Klang-Recherche (Kandidaten „Hey Wendelix“, „Hey Octavia“, „Kobalos“, dazu „Alexa“ als Bezug). Aufbau wie Teil A: 135 Positiv-Clips je Wort (9 macOS-Systemstimmen), Negativsprache 1,93 h, FLEURS-test 1,0 h als Fernseher, Stufe 2 Parakeet bs/hw2 mit passendem Hotword. Für die neuen Wörter gibt es kein trainiertes Stufe-1-Modell, nur sherpa-KWS; „Alexa“ zusätzlich mit dem openWakeWord-Originalmodell.

| Wort | Programm (beste Regel) | clean | FA/h (clean) | both | station |
|---|---|---|---|---|---|
| Wendelin | sherpa-KWS Kz4/0,05 + hw2 | 56 % [47–64] | 2,1 | 0 % | 0 % |
| Wendelin | v7 M0,3 + hw2 | 44 % [36–52] | 1,6 | 9 % | 11 % |
| Hey Wendelin | sherpa-KWS Kz4/0,05 + hw2 | 53 % [44–61] | 0,5 | 0 % | 1,5 % |
| Hey Wendelix | sherpa-KWS Kz2/0,15 + hw2 | 26 % [19–34] | 0 | 0 % | 0 % |
| Alexa | sherpa-KWS Kz4/0,05 + hw2 | 12 % [7–18] | 0 | 0 % | 0 % |
| Alexa | openWakeWord `alexa.onnx` M0,3 + hw2 | 8 % [5–14] | 0 | 0 % | 0 % |
| Hey Octavia | sherpa-KWS Kz4/0,05 + hw2 | 11 % [7–18] | 0 | 0 % | 0 % |
| Kobalos | sherpa-KWS | 0 % | – | 0 % | 0 % |

Verwechsler nach Stufe 2 überall ≤ 2,3 % (neue Wörter 0–0,2 %), FA/h ≤ 2,1. Das Originalmodell für „Alexa“ reagiert fast nur auf eine der Stimmen; die Bedingungen sind für synthetisch trainierte Modelle sehr hart.

**Fazit:** Im gleichen Programm (sherpa-KWS, clean) ist kein Alternativwort besser als „Wendelin“. Der Hebel liegt bei Trainingsdaten (echte Aufnahmen, passende Domäne) und bei Stufe 2 unter Rauschen, nicht beim Wort. Die Empfehlung bleibt: bei „Wendelin“ bleiben, Teil B mit echten Aufnahmen entscheidet. Skriptkopien und Tabellen liegen lokal unter `~/wendelin-models/kws/wp111/{alexa,heyx,side-scripts}/` (nicht im Repo).

## Teil B: echte Aufnahmen (WP121, 2026-10-22)

Stand: gemessen 2026-10-22 (Labels aus Etappe 1, Messung `words_measure.py`, Etappe 4). Nur Zahlen, keine Transkripte und keine Aufnahmen; Ergebnisdateien (`grid.csv`, `tables.md`, `det.csv`, `det.png`) liegen lokal unter `~/wendelin-models/kws/wp121/results/`.

### Aufbau und Lesehilfe
- Daten je Gerät (Huawei, handy2): 5 Wörter (Wendelin, Hey Wendelin, Alexa, Hey Octavia, Kobalos) × 30 Äußerungen in 6 Blöcken à 5 (13 min Positive je Gerät); Negativ „Alltag leise“ 0,61 h je Gerät (echt), dazu synthetische Negativsprache (WP111, 1,93 h) und FLEURS test (1,01 h). **Huawei und handy2 nahmen dieselben Äußerungen gleichzeitig auf: nicht addieren, effektiv n = 30.**
- Programme: M = openWakeWord (Wendelin/Hey Wendelin v7, Alexa `alexa.onnx`, neu Hey Octavia und Kobalos), W = microWakeWord (nur Wendelin/Hey Wendelin), Kz/Kg = sherpa-KWS (zh-en / gigaspeech). Stufe 2 `-` (nur Stufe 1), `bs` / `hw2` / `hw3` = Parakeet (Beam-Search, Hotwords 2 / 3). Pro Wort/Programm sweept die Messung Schwelle (M, W) bzw. Boost/Schwelle (Kz, Kg) × Stufe 2.
- **Wortvergleich nur im selben Programm.** Modellvergleich (z. B. v7 gegen die neuen Modelle) getrennt: Die Modelle für Hey Octavia und Kobalos sind neu trainiert, `alexa.onnx` ist ein fremdes Modell; ein Unterschied zwischen Wörtern in Spalte M ist damit auch ein Unterschied zwischen Modellen.
- **Kalibrierung:** die Konfiguration mit der höchsten Trefferzahl, deren FA/h an der Kalibrierungsquelle ≤ Ziel (1 bzw. 2 FA/h) liegt; zwei getrennte Kalibrierungen: (a) synthetisch + FLEURS (3,0 h), (b) echte Negativ-Aufnahme (0,61 h). Die jeweils andere Quelle dient als Gegenprobe.
- **Kreuz-Auswahl zuerst:** Konfiguration auf Block 1–3 wählen, auf 4–6 zählen, und umgekehrt (je 15 Äußerungen). „In-sample“ (Auswahl auf allen 30) steht daneben und ist optimistisch (Abstand Kreuz zu in-sample bis 33 Punkte, z. B. Wendelin Kz bei echter Kalibrierung und 2 FA/h: Huawei 3/30 gegen 13/30). Intervalle: Wilson 95 % für Treffer, Poisson 95 % (Obergrenze) für FA/h; bei 0 Ereignissen in 0,61 h ist die Obergrenze 6,0 FA/h (3,0 h: 1,3), bei 1 Ereignis 9,1.
- Aussprachevarianten (Stufe 1 KWS und Stufe 2): für jedes Wort derselbe Slot-Mechanismus (`_prod` in `words_measure.py`), alle Kombinationen, keine an den Aufnahmen gewählt: Wendelin und Hey 6, Octavia 8, Kobalos 8, Alexa 4 Phonemfolgen; Schreibvarianten (BPE) 4/4/4/2.

### Ergebnisse
Treffer sind Äußerungen von 30 (je Gerät); „Kreuz“ = auf der anderen Blockhälfte gezählt. FA/h Kal. gilt für die in-sample-Konfiguration (Auswahl auf allen 30, Huawei); die Kreuz-Konfiguration hat je Fold eine eigene, deren FA/h die Tabelle nicht ausweist (je Fold ≤ Ziel).

#### Kalibrierung synthetisch + FLEURS (3,0 h, `echt`-Gegenprobe an der Negativ-Aufnahme)

Treffer Kreuz von 30 (Wilson 95 %), Huawei / handy2; FA/h Kal. = Punktwert (Poisson-Obergrenze 95 %) der in-sample-Konfiguration; Gegenprobe = FA/h der in-sample-Konfiguration an der anderen Quelle (Huawei).

| Wort | Prog. | 1 FA/h Kreuz H / h2 | 1 FA/h in-sample H / h2 | 2 FA/h Kreuz H / h2 | 2 FA/h in-sample H / h2 | 2 FA/h FA/h Kal. (Poisson) | 2 FA/h Gegenprobe |
|---|---|---|---|---|---|---|---|
| Wendelin | M | 19/30 / 20/30 | 23 / 22 | 83 % [66–93] / 83 % [66–93] | 25 / 25 | 1,7 (≤4,0) | echt 0,0 |
| Wendelin | W | 13/30 / 12/30 | 14 / 13 | 43 % [27–61] / 43 % [27–61] | 15 / 14 | 1,7 (≤4,0) | echt 0,0 |
| Wendelin | Kz | 1/30 / 8/30 | 5 / 8 | 0 % [0–11] / 27 % [14–44] | 6 / 8 | 1,36 (≤3,5) | echt 0,0 |
| Wendelin | Kg | 11/30 / 7/30 | 11 / 7 | 37 % [22–54] / 23 % [12–41] | 11 / 7 | 0,0 (≤1,3) | echt 0,0 |
| Hey Wendelin | M | 16/30 / 17/30 | 20 / 21 | 53 % [36–70] / 57 % [39–73] | 21 / 21 | 1,02 (≤3,0) | echt 0,0 |
| Hey Wendelin | W | 4/30 / 0/30 | 4 / 3 | 13 % [5–30] / 0 % [0–11] | 4 / 3 | 0,0 (≤1,3) | echt 0,0 |
| Hey Wendelin | Kz | 11/30 / 9/30 | 11 / 9 | 43 % [27–61] / 30 % [17–48] | 13 / 10 | 1,02 (≤3,0) | echt 0,0 |
| Hey Wendelin | Kg | 0/30 / 3/30 | 6 / 4 | 0 % [0–11] / 10 % [3–26] | 6 / 4 | 0,0 (≤1,3) | echt 0,0 |
| Alexa | M | 25/30 / 22/30 | 27 / 26 | 83 % [66–93] / 73 % [56–86] | 27 / 27 | 0,0 (≤1,3) | echt 6,53 |
| Alexa | Kz | 16/30 / 11/30 | 16 / 13 | 53 % [36–70] / 37 % [22–54] | 16 / 13 | 0,0 (≤1,3) | echt 0,0 |
| Alexa | Kg | 8/30 / 8/30 | 11 / 12 | 27 % [14–44] / 27 % [14–44] | 11 / 12 | 0,0 (≤1,3) | echt 0,0 |
| Hey Octavia | M | 24/30 / 27/30 | 26 / 28 | 80 % [63–90] / 90 % [74–97] | 26 / 28 | 0,0 (≤1,3) | echt 0,0 |
| Hey Octavia | Kz | 5/30 / 8/30 | 9 / 12 | 17 % [7–34] / 27 % [14–44] | 9 / 12 | 0,0 (≤1,3) | echt 0,0 |
| Hey Octavia | Kg | 0/30 / 1/30 | 4 / 4 | 0 % [0–11] / 3 % [1–17] | 4 / 4 | 0,0 (≤1,3) | echt 0,0 |
| Kobalos | M | 26/30 / 26/30 | 27 / 27 | 87 % [70–95] / 87 % [70–95] | 27 / 27 | 0,0 (≤1,3) | echt 0,0 |
| Kobalos | Kz | 5/30 / 12/30 | 8 / 12 | 17 % [7–34] / 40 % [25–58] | 8 / 12 | 0,0 (≤1,3) | echt 0,0 |
| Kobalos | Kg | 16/30 / 8/30 | 17 / 12 | 53 % [36–70] / 27 % [14–44] | 17 / 12 | 0,0 (≤1,3) | echt 0,0 |

#### Kalibrierung echte Negativ-Aufnahme (0,61 h je Gerät, `synth.`-Gegenprobe)

Treffer Kreuz von 30 (Wilson 95 %), Huawei / handy2; FA/h Kal. = Punktwert (Poisson-Obergrenze 95 %) der in-sample-Konfiguration; Gegenprobe = FA/h der in-sample-Konfiguration an der anderen Quelle (Huawei).

| Wort | Prog. | 1 FA/h Kreuz H / h2 | 1 FA/h in-sample H / h2 | 2 FA/h Kreuz H / h2 | 2 FA/h in-sample H / h2 | 2 FA/h FA/h Kal. (Poisson) | 2 FA/h Gegenprobe |
|---|---|---|---|---|---|---|---|
| Wendelin | M | 25/30 / 24/30 | 25 / 25 | 80 % [63–90] / 80 % [63–90] | 25 / 25 | 0,0 (≤6,0) | synth. 1,7 |
| Wendelin | W | 17/30 / 15/30 | 19 / 18 | 63 % [46–78] / 50 % [33–67] | 22 / 18 | 1,63 (≤9,1) | synth. 15,66 |
| Wendelin | Kz | 2/30 / 8/30 | 11 / 11 | 10 % [3–26] / 27 % [14–44] | 13 / 11 | 1,63 (≤9,1) | synth. 48,68 |
| Wendelin | Kg | 11/30 / 7/30 | 11 / 7 | 37 % [22–54] / 23 % [12–41] | 11 / 7 | 0,0 (≤6,0) | synth. 0,0 |
| Hey Wendelin | M | 20/30 / 20/30 | 22 / 21 | 67 % [49–81] / 57 % [39–73] | 22 / 21 | 0,0 (≤6,0) | synth. 6,13 |
| Hey Wendelin | W | 4/30 / 3/30 | 4 / 4 | 13 % [5–30] / 10 % [3–26] | 4 / 4 | 0,0 (≤6,0) | synth. 0,0 |
| Hey Wendelin | Kz | 15/30 / 13/30 | 18 / 17 | 50 % [33–67] / 43 % [27–61] | 18 / 17 | 0,0 (≤6,0) | synth. 26,55 |
| Hey Wendelin | Kg | 0/30 / 3/30 | 6 / 4 | 0 % [0–11] / 10 % [3–26] | 6 / 4 | 0,0 (≤6,0) | synth. 0,0 |
| Alexa | M | 14/30 / 16/30 | 17 / 21 | 53 % [36–70] / 53 % [36–70] | 19 / 21 | 1,63 (≤9,1) | synth. 0,0 |
| Alexa | Kz | 16/30 / 11/30 | 16 / 13 | 63 % [46–78] / 70 % [52–83] | 19 / 21 | 1,63 (≤9,1) | synth. 10,55 |
| Alexa | Kg | 21/30 / 11/30 | 21 / 17 | 70 % [52–83] / 57 % [39–73] | 21 / 22 | 0,0 (≤6,0) | synth. 10,89 |
| Hey Octavia | M | 24/30 / 27/30 | 26 / 28 | 80 % [63–90] / 90 % [74–97] | 26 / 28 | 0,0 (≤6,0) | synth. 0,0 |
| Hey Octavia | Kz | 5/30 / 8/30 | 9 / 12 | 17 % [7–34] / 27 % [14–44] | 9 / 12 | 0,0 (≤6,0) | synth. 0,0 |
| Hey Octavia | Kg | 0/30 / 1/30 | 4 / 4 | 0 % [0–11] / 3 % [1–17] | 4 / 4 | 0,0 (≤6,0) | synth. 0,0 |
| Kobalos | M | 27/30 / 24/30 | 27 / 27 | 90 % [74–97] / 80 % [63–90] | 27 / 27 | 0,0 (≤6,0) | synth. 0,0 |
| Kobalos | Kz | 5/30 / 12/30 | 8 / 12 | 17 % [7–34] / 40 % [25–58] | 8 / 12 | 0,0 (≤6,0) | synth. 0,0 |
| Kobalos | Kg | 16/30 / 8/30 | 17 / 12 | 53 % [36–70] / 27 % [14–44] | 17 / 12 | 0,0 (≤6,0) | synth. 0,0 |

#### Treffer je Block (Kalibrierung synthetisch + FLEURS, 2 FA/h)
Treffer von 5 je Block 1..6 für die in-sample-Konfiguration der Zeile (Kreuz-Konfigurationen je Fold: `tables.md`, lokal), Huawei und handy2.

| Wort | Prog. | Huawei Konfiguration | Huawei Block 1..6 | handy2 Konfiguration | handy2 Block 1..6 |
|---|---|---|---|---|---|
| Wendelin | M | M0.95 + hw3 | 4/5 5/5 5/5 4/5 4/5 3/5 | M0.95 + hw3 | 4/5 5/5 5/5 4/5 3/5 4/5 |
| Wendelin | W | W0.6 + hw2 | 3/5 2/5 2/5 4/5 4/5 0/5 | W0.6 + hw2 | 3/5 3/5 2/5 3/5 2/5 1/5 |
| Wendelin | Kz | Kz6/0.12 + hw2 | 2/5 2/5 1/5 1/5 0/5 0/5 | Kz3/0.25 + hw2 | 1/5 3/5 1/5 2/5 0/5 1/5 |
| Wendelin | Kg | Kg10/0.03 + hw2 | 3/5 2/5 3/5 2/5 1/5 0/5 | Kg10/0.03 + hw2 | 2/5 0/5 1/5 3/5 1/5 0/5 |
| Hey Wendelin | M | M0.98 + hw3 | 5/5 4/5 4/5 5/5 3/5 0/5 | M0.99 + hw3 | 3/5 5/5 4/5 5/5 1/5 3/5 |
| Hey Wendelin | W | W0.4 + hw2 | 0/5 0/5 3/5 0/5 1/5 0/5 | W0.4 + hw2 | 1/5 0/5 2/5 0/5 0/5 0/5 |
| Hey Wendelin | Kz | Kz3/0.12 + hw2 | 5/5 1/5 2/5 3/5 2/5 0/5 | Kz3/0.12 + hw2 | 2/5 3/5 1/5 3/5 0/5 1/5 |
| Hey Wendelin | Kg | Kg10/0.03 + hw2 | 4/5 2/5 0/5 0/5 0/5 0/5 | Kg6/0.12 + hw2 | 2/5 1/5 0/5 1/5 0/5 0/5 |
| Alexa | M | M0.5 + - | 5/5 4/5 5/5 5/5 3/5 5/5 | M0.2 + - | 5/5 5/5 5/5 3/5 4/5 5/5 |
| Alexa | Kz | Kz6/0.03 + bs | 4/5 4/5 1/5 4/5 2/5 1/5 | Kz3/0.12 + hw2 | 2/5 5/5 2/5 2/5 1/5 1/5 |
| Alexa | Kg | Kg3/0.03 + bs | 3/5 2/5 1/5 4/5 1/5 0/5 | Kg3/0.03 + bs | 1/5 3/5 2/5 3/5 3/5 0/5 |
| Hey Octavia | M | M0.2 + hw3 | 5/5 5/5 5/5 5/5 4/5 2/5 | M0.98 + hw3 | 5/5 5/5 5/5 5/5 3/5 5/5 |
| Hey Octavia | Kz | Kz10/0.03 + hw2 | 5/5 2/5 2/5 0/5 0/5 0/5 | Kz10/0.03 + - | 3/5 3/5 3/5 3/5 0/5 0/5 |
| Hey Octavia | Kg | Kg6/0.03 + hw2 | 4/5 0/5 0/5 0/5 0/5 0/5 | Kg6/0.03 + hw2 | 2/5 0/5 1/5 1/5 0/5 0/5 |
| Kobalos | M | M0.8 + hw3 | 5/5 5/5 5/5 4/5 3/5 5/5 | M0.99 + hw3 | 4/5 4/5 5/5 5/5 4/5 5/5 |
| Kobalos | Kz | Kz10/0.03 + hw3 | 5/5 1/5 0/5 1/5 0/5 1/5 | Kz10/0.03 + hw2 | 3/5 3/5 2/5 2/5 0/5 2/5 |
| Kobalos | Kg | Kg3/0.03 + - | 3/5 5/5 2/5 4/5 0/5 3/5 | Kg6/0.03 + hw3 | 2/5 4/5 1/5 1/5 2/5 2/5 |

#### Labelzählung (je Gerät, beide Geräte gleich)
Äußerungen ok/unsicher je Wort × Block 1..6 (5 je Zelle): „unsicher“ = zusammengezogen oder lang, Zählfenster größer. Dazu je Gerät 1 Versprecher (Block 2, Runde 2, statt Alexa „Octavia“ gesagt), nicht gewertet; die Alexa-Wiederholung steht in der Zählung. Gesamt je Gerät 139 ok, 11 unsicher, 1 Versprecher.

| Wort | B1 | B2 | B3 | B4 | B5 | B6 |
|---|---|---|---|---|---|---|
| Wendelin | 4/1 | 5/0 | 5/0 | 3/2 | 5/0 | 5/0 |
| Hey Wendelin | 5/0 | 5/0 | 5/0 | 2/3 | 5/0 | 5/0 |
| Alexa | 5/0 | 5/0 | 5/0 | 4/1 | 5/0 | 5/0 |
| Hey Octavia | 5/0 | 5/0 | 5/0 | 3/2 | 5/0 | 5/0 |
| Kobalos | 5/0 | 5/0 | 5/0 | 4/1 | 5/0 | 4/1 |

Auffällig: Block 4 hat 9 der 11 unsicheren Äußerungen (u. a. Wendelin und Hey Wendelin in einer Äußerung zusammengezogen), Block 1 und 6 je 1.

#### Negativ-Suche in der Negativ-Aufnahme
Whisper medium (nur zur Suche, nicht der gemessene Erkenner) über die Negativ-Aufnahme „Alltag leise“: Huawei 111 Fenster (24 s, Hop 20 s), davon 97 mit Sprache; handy2 110 Fenster, 109 mit Sprache. Gesucht: die fünf Wörter und Verwechsler (Regex-Klassen in `words_labels.py`). Ergebnis: **0 Fundstellen** (beide Geräte), die Negativ-Aufnahme enthält damit nach dieser Suche keines der Wörter. Grenzen: Whisper kann ein Wort verfehlen, Fenster ohne Sprachaktivität (> 10 dB, 3 % der Frames) wurden nicht transkribiert.

Zentrale Zahlen (Kreuz, 2 FA/h, synthetische Kalibrierung, Huawei / handy2; jeweils bestes Programm): Wendelin M 83 % / 83 %, Hey Wendelin M 53 % / 57 %, Alexa M 83 % / 73 %, Hey Octavia M 80 % / 90 %, Kobalos M 87 % / 87 %. Bei Kalibrierung an der echten Negativ-Aufnahme: Wendelin M 80 / 80, Hey Wendelin M 67 / 57, Alexa Kg 70 / 57 (M 53 / 53), Hey Octavia M 80 / 90, Kobalos M 90 / 80 (je Wilson ±15 Punkte, n = 30). M liegt in jeder Zeile vorn außer bei Alexa mit echter Kalibrierung (dort 0,61 h, Obergrenze ≤ 9,1 FA/h). Wendelin und Hey Wendelin unterscheiden sich im selben Programm (M, gleiches Modell v7): 83 % gegen 53–57 % bei 2 FA/h, die Wilson-Intervalle überlappen knapp (83 % [66–93] gegen 53 % [36–70] bzw. 57 % [39–73]); der Unterschied ist groß (26–30 Punkte), bei n = 30 aber nicht statistisch gesichert.

DET-Kurven (`det.csv`/`det.png`, nur lokal): nur als Hinweis, nicht zusätzlich ausgewertet; die Entscheidung stützt sich auf die Tabellen.

### Kontrollen
- **Alexa:** WP111 maß 8 % mit `alexa.onnx` auf synthetischen Systemstimmen; auf echten Aufnahmen trifft dasselbe Modell 27/30 (Stufe 1, Schwelle 0,5, ohne Stufe 2) und 73–83 % Kreuz bei 2 FA/h. Die 8 % lagen an den synthetischen Stimmen, nicht am Modell. Gleichzeitig zeigt Alexa die Grenze der synthetischen Kalibrierung: dort 0 FA/h, an der echten Negativ-Aufnahme 6,5 FA/h (Huawei) bzw. 11,5 FA/h (handy2); die Werte gehören zur jeweiligen in-sample-Konfiguration (Huawei M0.5, handy2 M0.2, jeweils ohne Stufe 2; handy2 bei M0.5 wären es 5 FA = 8,2 FA/h).
- **Kobalos, Octavia:** Parakeet war nie das Problem. Die KWS-Fehler kamen von der Aussprache (Phonem- und BPE-Varianten fehlten) und vom Platzhalter-Fehler (nächster Punkt). Mit allen Slot-Varianten treffen Kz/Kg Hey Octavia 0–12/30 (Kz 5–12, Kg 0–4) und Kobalos 5–17/30; Hey Octavia Kz hat nun Treffer (vorher 0/17 FA = Platzhalter-Artefakt). Die Werte der KWS-Programme bleiben klar unter M.
- **sherpa-Platzhalter:** `kws_measure.make_spotter` schrieb den Platzhalter-Keyword „hello @X“ in die Spotter-Datei; er feuerte auch in Streams mit anderen Wörtern, `K.run` zählte jedes Ergebnis als Treffer (konstante FA je Wort, 0 Treffer bei Hey Octavia Kz). Behoben: `words_measure.own_hits` zählt nur Ergebnisse mit eigenem Label, `KwsX` verwendet einen unwahrscheinlichen Platzhalter (`DUMMY_KW`); alle KWS-Caches wurden verworfen und neu gerechnet (480 Aufgaben). Die FA/h der KWS-Programme ändern sich jetzt mit der Schwelle (`fa_syn` in `grid.csv`: 8 bis 19 verschiedene Werte je Wort bei Kz, nur bei Hey Octavia konstant 0). **Teil A dieser Notiz und der Anhang (WP111) und WP106 nutzten `K.run` und sind davon möglicherweise betroffen (KWS-Spalten); sie wurden nicht neu gemessen.** Für „Wendelin“ ist der Effekt kaum zu erwarten, aber nicht geprüft. Nachtrag (Nachbesserung Runde 1): `kws_measure.run` verwirft den Platzhalter jetzt selbst (`PLACEHOLDER`) und die Platzhalter-Datei ist je Inhalt und Prozess eindeutig (`dummy_path`); künftige Läufe von WP106/WP111/`station_measure` sind damit korrekt, die alten Pakete wurden nicht neu gemessen.

### Grenzen
- FA/h: nur 0,61 h „Alltag leise“ je Gerät (eine Umgebung); 0 Ereignisse heißen ≤ 6,0 FA/h (95 %). Ziele von 1–2 FA/h sind damit an echten Daten nicht prüfbar, nur ein Hinweis. Die synthetische Kalibrierung unterschätzt echte FA/h deutlich (Alexa: 0 gegenüber 6,5–11,5).
- n = 30 effektiv (zwei Geräte = dieselben Äußerungen), wenige Sprecher und Räume; Wilson-Intervalle ±15–20 Punkte. Gerätedifferenzen (Kg Kobalos 53 % gegen 27 %) liegen im Rauschen.
- Auswahl-Bias: in-sample schätzt um bis zu 33 Punkte zu hoch (Kz/Kg am stärksten, weil dort die Konfigurationsmenge am größten ist).
- Modelle Hey Octavia/Kobalos: nur ein Training, kein Zufallsvergleich (Seeds nicht wiederholt).

### Training der neuen Modelle (Octavia, Kobalos)
Pipeline wie v7 (kein `--wide`): ca. 14000 Positive je Wort (v7: 5000 + 8734 = 13,7k), 3100 Verwechsler aus eigenen Listen (`CONF_OCT`, `CONF_KOB`), Negative + FLEURS dev wie `wp58`, Features `--n-pos 20000 --n-neg 7000`, 5000 Schritte; Modelle `oct.onnx` (nur „Hey Octavia“, kein bares „Octavia“ als Positiv) und `kob.onnx` (je ca. 0,86 MB). Aufruf `tool/train_wake_word/run_words.sh`.

### Empfehlung
- **Wendelin** (M, Stufe 2 hw3) bleibt: Kreuz 83 % bei 2 FA/h (synth. Kalibrierung), 80 % bei echter Kalibrierung, gegenüber 53–67 % für „Hey Wendelin“ im selben Programm (Intervalle überlappen knapp, der Unterschied ist nicht gesichert, aber in jeder Kalibrierung gleichgerichtet). Auch Octavia (80–90 %) und Kobalos (80–90 %) erreichen das nur mit eigenem Training, also nicht besser als Wendelin im Rahmen der Intervalle; ein Wechsel des Wortes ist nach diesen Daten nicht begründet.
- Programm: M vor Kz/Kg und W. KWS bleibt Rückfall (Kz/Kg hier 0–70 %, stark vom Wort abhängig).
- Vor einer Produktentscheidung: Negativ-Aufnahme verlängern (mehrere Stunden, mit Fernseher), mehr Sprecher/Räume, KWS-Messungen aus Teil A/WP111 neu rechnen.

### Reproduzierbar (aus dem Repo-Root, `P="nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/words_measure.py"`, `K=~/wendelin-models/kws`)
```
nice -n 10 tool/train_wake_word/run_words.sh                 # oct.onnx, kob.onnx unter $K/wp121/models
$P s1 oww                          # M (Wendelin/Hey v7, alexa) + W; bei vorhandenen oct/kob: run_oww_x
$P s1 kws --jobs 2                 # sherpa-KWS Kz/Kg (480 Aufgaben)
$P s2 --variants bs --threads 4    # dann hw2, hw3 nacheinander (Parakeet ca. 1 GB RAM je Prozess)
$P report                          # grid.csv, tables.md, det.csv, det.png
$P kontrolle                       # Stufe 1 an den Labels
```
Label-Schritte (`words_labels.py`, vor der Messung; Rohaufnahmen und Labels liegen nur lokal unter `~/wendelin-fixtures/wake/words`):
```
L="nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/words_labels.py"
$L convert                         # Rohaufnahmen -> work/*.wav
$L events                          # Energie-VAD beider Geräte, Whisper medium je Ereignis -> work/events.json
$L label                           # Ansagen und Reihenfolge -> labels/labels.csv (Abweichungen: labels/manual.csv)
$L neg                             # Negativ-Suche -> labels/neg_hits.csv
```
Tests:
```
$K/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_measure.py'
```
Etappe 4 lief mit s2, dann s1 oww (neue Modelle), s2 erneut, report. Der erste s2-Durchlauf brach ab (`KeyError: pos_huawei|oct`, oww-x-Spalten fehlten) und wurde nach s1 oww wiederholt.

### Abweichungen (Teil B)
- Keine Vorlagen-Regel T (Teil A) in Teil B; microWakeWord nur für Wendelin/Hey Wendelin; oWW-Schwellen 0,2 bis 0,99; Positive als fortlaufende Aufnahme je Gerät geschnitten (Labels aus Etappe 1); matplotlib im wp58-venv; die Python-Selbsttests laufen nicht im Gate.
- Platzhalter-Fehler in `kws_measure` (Teil A/Anhang evtl. betroffen, nicht neu gemessen); Aussprachevarianten aus der Slot-Regel statt aus Aufnahmen; neue Modelle oct/kob mit v7-Pipeline.

## v8 (WP130)

openWakeWord v8, nur Deutsch (Pipeline `tool/train_wake_word/run_v8.sh`, Lizenzen `docs/notes/wake-word-v8-licenses.md`). Daten: 35 866 Positive (Piper, 9 Stimmen, Tempo 0,75–1,5, plus v7-Positive, plus 29 echte Clips aus Huawei Block 1–3 je 100-fach), 10 297 Verwechsler, 18 794 Negative (19,2 h), FLEURS train/dev. Varianten: **v8a** 5000 Schritte, Seed 1 (SHA-256 `bfeb939d9e50c4913b27e4d082e5d620e3967af6c2603666e6bc40b30a06997d`), **v8b** 10 000 Schritte, Seed 2 (`ff63b28ac4f247aecf3de093fef0705d7c5e1aac670dbf872bbd49c652fcf73a`). Je 0,86 MB.

Messung `tool/train_wake_word/v8_measure.py` nur auf dem Prüf-Split: Huawei Block 4–6 (n = 15 je Wort), handy2 Block 1–6 (n = 30). Ziel 2 FA/h, kalibriert auf der echten Negativ-Aufnahme des Geräts (0,61 h je Gerät, also höchstens 1 FA), Schwelle per Kreuzauswahl über die Prüf-Blöcke (ein Block ausgelassen), Wilson 95 %. Verwechsler: 300 Clips (conf_v8-Texte, Seed 9001, macOS-Stimmen). Die Stimmen sind fremd, die Texte aber dieselben wie im Training.

| Gerät | Wort | v7 Stufe 1 | v8a Stufe 1 | v8b Stufe 1 | v7 + hw2 | v8a + hw2 | v8b + hw2 |
|---|---|---|---|---|---|---|---|
| huawei | Wendelin | keine Schwelle ≤ Ziel | **80 %** [55–93] | 93 % [70–99] | 60 % [36–80] | 60 % [36–80] | 53 % [30–75] |
| huawei | Hey Wendelin | keine Schwelle ≤ Ziel | **93 %** [70–99] | 93 % [70–99] | 33 % [15–58] | 40 % [20–64] | 40 % [20–64] |
| handy2 | Wendelin | keine Schwelle ≤ Ziel | **77 %** [59–88] | 73 % [56–86] | 67 % [49–81] | 67 % [49–81] | 63 % [46–78] |
| handy2 | Hey Wendelin | keine Schwelle ≤ Ziel | **90 %** [74–97] | 87 % [70–95] | 63 % [46–78] | 63 % [46–78] | 57 % [39–73] |

Arbeitspunkte Stufe 1 (Schwelle 0,98–0,99): v8a FA/h echt 0,0–1,6, syn 1,0–1,6, FLEURS 1,0, Verwechsler-Clips mit Ereignis 5–8 % [3–11]. v8b bei 0,99: FA/h echt 1,6, Verwechsler 15 % [11–19]. v7 erreicht 2 FA/h nur mit Stufe 2. Mit hw2: Verwechsler bei v7 1–7 %, bei v8a 1–6 %. Kalibrierung auf syn + FLEURS ergibt dieselben Stufe-1-Zahlen. Die „beste Wahl“ (Stufe frei in der Kreuzauswahl) liegt für Wendelin bei v8a unter Stufe 1 allein (47 % bzw. 60 %), weil die Auswahl je Block zwischen den Stufen wechselt. Volle Tabellen lokal unter `~/wendelin-models/kws/wp130/results/v8_table.md`.

### Empfehlung
- **v8a übernehmen.** Bei 2 FA/h erreicht v8a mit Stufe 1 allein 77–93 %. v7 hält das Ziel ohne Stufe 2 nicht ein. Mit Stufe 2 (hw2) sind beide Modelle gleich gut. Bei Huawei überlappen sich die Intervalle von Stufe 1 und v7 + hw2, bei handy2 „Hey Wendelin“ (90 % [74–97] gegen 63 % [46–78]) nur knapp.
- Stufe 1 kostet einiges: 5–8 % der Verwechsler-Clips lösen aus, mit hw2 nur 1–6 %.
- v8a ist in keiner Zelle signifikant besser als v7 + hw2 (die Intervalle überlappen überall). Ein Teil des Vorsprungs kann aus der Sprecheranpassung kommen, denn die Stimme des Maintainers steckt in v8, nicht in v7.
- v8b (doppelte Schritte) bringt nichts dazu und erzeugt die doppelte Verwechsler-Rate.

### Grenzen
- Prüfsprecher ist der Maintainer. Seine Stimme steckt mit Huawei Block 1–3 im Training, und für andere Sprecher fehlt eine Messung. handy2 ist ein anderes Gerät, die Blöcke sind dieselbe Sitzung.
- Für die Negativzeit gibt es je Gerät nur 0,61 h echte Aufnahme, das sind höchstens 1 FA. Die FA/h-Werte sind damit grob. n = 15 bzw. 30 je Zelle.
- Ein Lauf je Variante. Common Voice fehlt in v8a/v8b (Plattenplatz), `N_CV=0` überspringt den Schritt ohne Download (so entstanden v8a/v8b); mit dem Standard lädt das Skript das Shard.

### Reproduzierbar (aus dem Repo-Root, `K=~/wendelin-models/kws`)
```
N_CV=0 NJ=4 THREADS=4 TAG=a nice -n 5 tool/train_wake_word/run_v8.sh alle
TAG=b STEPS=10000 SEED=2 THREADS=4 nice -n 5 tool/train_wake_word/run_v8.sh train
nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/v8_measure.py --threads 2 --model v8a=$K/wp130/out/wendelin_wp130_a.onnx --model v8b=$K/wp130/out/wendelin_wp130_b.onnx
```

## Stufe 2 und v8-syn (WP133)

### A. Nutzen von Stufe 2 (Analyse ohne Training, 2026-10-22)

Skript `tool/train_wake_word/stage2_analysis.py` (Selbsttest `test_stage2_analysis.py`). Es nutzt die Stufe-1-Kurven und Stufe-2-Texte aus WP130 (lokal, `$K/wp130/results`), gleicher Prüf-Split, gleiche Kreuzauswahl (2 FA/h, Kalibrierung echte Negativ-Aufnahme), Wilson 95 %. Transkripte bleiben lokal; hier nur Zahlen und Kategorien. Begriffe: **Ereignis** = Stufe-1-Wert über der Schwelle; **Spitzenwert** = Maximum von Stufe 1 im Ereignis; **Band** = Stufe 2 prüft nur Ereignisse mit Spitzenwert unter der Obergrenze, darüber nimmt die App direkt an.

**Verworfene echte Rufe (v8a, Stufe-1-Arbeitspunkt):** Stufe 1 trifft 12/15, 14/15, 23/30, 27/30 (Huawei W, Huawei HW, handy2 W, handy2 HW); hw2 verwirft davon 7, 9, 5, 9 (30 Rufe). Kategorien: leer 10, anderes Wort 14, abgeschnitten (nur „Hey“) 3, „Hey“ fehlt 3, Schreibvariante 0. „Anderes Wort“ ist fast immer eine englische Lesart: Parakeet v3 wählt die Sprache selbst und fällt bei kurzen Ausschnitten oft ins Englische. v7 sieht gleich aus.

**Spitzenwerte (v8a, feste Schwelle 0,98, beide Wörter, 90 Prüf-Rufe; Verwechsler 300 Clips, für beide Wörter dieselben):**

| Spitzenwert Stufe 1 | echte Rufe | davon besteht hw2 | Verwechsler-Ereignisse | davon besteht hw2 (W / HW) |
|---|---|---|---|---|
| 0,98–0,995 | 8 | 5 | 13 | 3 / 2 |
| 0,995–0,999 | 23 | 15 | 8 | 0 / 0 |
| ≥ 0,999 | 46 | 26 | 2 | 2 / 0 |
| nicht erkannt | 13 | – | – | – |

Stufe 1 ist ein Modell für beide Wörter, die Verwechsler-Ereignisse sind daher gleich; erst die Stufe-2-Regel unterscheidet („Hey Wendelin“ verlangt ein Hey-Wort und lässt weniger Verwechsler durch). Auf der echten Negativ-Aufnahme filtert hw2 bei 0,98 höchstens 1 Ereignis, bei syn und FLEURS 1–3.

**Varianten (v8a, Treffer Kreuzauswahl; Verwechsler und FA bei fester Schwelle 0,98).** Zwei Bezugszeiten: „Spitze“ = Spitzenwert im Ereignis mit 1,5 s Vorschau (`peak_at` in `stage2_analysis.py`), den die App nicht hat; „App“ = Entscheidungsfenster der App mit Halten (`stage2_cut.py`, Ausschnitt 2,0 s / 0,9 s). **Maßgeblich ist App**, die Spitze-Zeilen sind optimistisch.

| Stufe 2 | Bezug | Huawei W | Huawei HW | handy2 W | handy2 HW | Verwechsler W / HW (von 300) | FA syn / FLEURS / echt |
|---|---|---|---|---|---|---|---|
| keine (Stufe 1 allein) | – | 80 % [55–93] | 93 % [70–99] | 77 % [59–88] | 90 % [74–97] | 23 / 23 | 3 / 1 / 0–1 |
| hw2 (heute) | Spitze | 60 % [36–80] | 40 % [20–64] | 67 % [49–81] | 63 % [46–78] | 5 / 2 | 0 / 0 / 0 |
| hw2 + Band 0,999 | Spitze | 87 % [62–96] | 80 % [55–93] | 90 % [74–97] | 73 % [56–86] | 5 / 4 | 1 / 1 / 0 |
| hw2 + Band 0,995 | Spitze | 80 % [55–93] | 93 % [70–99] | 93 % [79–98] | 90 % [74–97] | 13 / 12 | 2 / 1 / 0 |
| hw2 (heute) | **App** | 47 % [25–70] | 40 % [20–64] | 63 % [46–78] | 60 % [42–75] | 5 / 2 | 0 / 0 / 0 |
| hw2 + Band 0,999 | **App** | 67 % [42–85] | 87 % [62–96] | 80 % [63–90] | 73 % [56–86] | 5 / 4 | 1 / 1 / 0 |
| hw2 + Band 0,995 | **App** | 80 % [55–93] | 93 % [70–99] | 83 % [66–93] | 83 % [66–93] | 12 / 11 | 2 / 1 / 0 |
| hw2 + Pegel-Norm. + Band 0,999 | **App** | 73 % [48–89] | 80 % [55–93] | 83 % [66–93] | 73 % [56–86] | 5 / 4 | 1 / 1 / 0 |
| Whisper small, Sprache de | – | 40 % [20–64] | 20 % [7–45] | 53 % [36–70] | 37 % [22–54] | 3 / 1 | 0 / 0 / 0 |
| Parakeet Hotword-Score 4 | – | 73 % [48–89] | 93 % [70–99] | 80 % [63–90] | 87 % [70–95] | 13 / 10 | 1–2 / 1 / 0–1 |

Stufe 1 allein ändert sich mit dem Bezug nicht. Die Spitze-Zeilen wählen in der Kreuzauswahl aus Schwellen 0,2–0,99 (`stage2_analysis.py`), die App-Zeilen nur aus 0,95–0,99 (`stage2_cut.py`); der Unterschied Spitze → App mischt damit beide Effekte: Band 0,999 74 → 73 (Raster) → 69 (Bezugszeit), hw2 54 → 53 → 50, Band 0,995 81 → 79 → 76, also etwa 1 Treffer auf das Raster und etwa 4 auf die Bezugszeit. Manche Spitze-Arbeitspunkte liegen bei 0,2–0,9 mit mehr Verwechslern, als die Spalte „bei 0,98“ zeigt. Unter App-Bezug bleibt die Rangfolge gleich: Summe der vier Zellen (von 90 Rufen) Band 0,995 76 > Band 0,999 69 > hw2 50, mit Spitze 81 > 74 > 54. Der Abstand zwischen Band 0,995 und 0,999 bleibt bei 7 Treffern, die Intervalle überlappen in jeder Zelle. Band 0,999 verliert unter App-Bezug 5 Treffer (Huawei Wendelin 13 → 10, handy2 Wendelin 27 → 24, Huawei „Hey Wendelin“ 12 → 13), Band 0,995 und hw2 ebenfalls 5 bzw. 4. Bei fester Schwelle 0,98 stimmen die Bezüge nur für hw2 + Band 0,999 überein (66 Treffer, Verwechsler 5 / 4); hw2 allein hat 47 statt 46, Band 0,995 73 Treffer und Verwechsler 12 / 11 statt 13 / 12.

**Auswahlverzerrung:** Band (0,999) und Variante wurden auf denselben Prüfdaten gewählt, auf denen sie hier berichtet werden; die Trefferzahlen sind damit eher optimistisch, und alle Unterschiede zwischen den Bändern liegen innerhalb der Wilson-Intervalle. Eine Bestätigung auf frischen Daten (Teil B) steht aus.

Ohne Wirkung (gleich hw2): Editierabstand 3, Kölner-Phonetik-Präfix, „Hey“ optional (holt 0–2 von 9). Längerer Ausschnitt (Vorlauf 3,0 s, Nachlauf 1,8 s) verschlechtert (27–57 %). Whisper mit fester Sprache Deutsch liefert deutsche, aber oft falsche Wörter und trifft seltener als Parakeet. Score 4 halluziniert das Hotword (mehrfach wiederholt) und lässt so viele Verwechsler durch wie Band 0,995.

**Weitere Stufe-2-Varianten (v8a, feste Schwelle 0,98, 90 Rufe, Bezug Spitze; mit App-Bezug hw2 47, hw2 + Norm. 54, hw2 + Norm. + Band 0,999 66; Verwechsler W / HW von 300):** hw2 heute 46 Treffer, 5 / 2; hw2 mit Pegel-Normalisierung des Ausschnitts (Spitze 0,5) 52, 4 / 2; Hotword-Score 3 60, 7 / 4 (dazu 2 syn); `blank_penalty` 1 / 2 48 / 51, 5 / 2. Mit Band 0,999 liegen alle Varianten innerhalb weniger Treffer. In der Kreuzauswahl ist die Normalisierung gemischt (je Zelle −1 bis +4); kein Unterschied ist signifikant.

**Plausibilität „leer“:** Kein Aufbaufehler. Der Ausschnitt entspricht der App (2,0 s vor bis 0,9 s nach dem Treffer), Neudekodieren reproduziert die Cache-Texte, 16 kHz. Bei 27 von 30 verlorenen Rufen liegt das Wort ganz im Ausschnitt; 3 sind abgeschnitten (Stufe 1 löst bei „Hey Wende…“ bzw. bei langen Äußerungen aus). Die „leeren“ Rufe sind leise (Wort −37 bis −43 dBFS gegen −27 bis −33 dBFS bei erkannten).

**Ausschnitt und Parität mit der App** (`stage2_cut.py`, Aufruf `stage2_analysis.py --cut-only`): Die App entscheidet am Fenster mit dem Spitzenwert (Halten); das liegt 0–0,32 s (meist 0,08 s) nach der ersten Überschreitung, die bisher gemessen wurde. Bei fester Schwelle 0,98 geben beide Bezugszeiten für hw2 + Band 0,999 dasselbe (66 Treffer, Verwechsler 5 / 4); in der Kreuzauswahl nicht (Tabelle oben, App-Bezug 5 Treffer weniger). Vorlauf 1,2–2,0 s × Nachlauf 0,9–1,8 s liegen alle innerhalb ±3 Treffer; nur Vorlauf 2,5 s ist schlechter (hw2 allein 38–42 statt 46–47, nur ein Hinweis). App-Werte 2,0 s / 0,9 s bleiben.

**Fehlalarme mit mehr Negativzeit** (`stage2_extra_neg.py`): zusätzlich FLEURS-de-Test ohne die erste Stunde (2,15 h) und Multilingual LibriSpeech Deutsch, Test-Split (14,29 h, CC-BY 4.0, nicht im Training; lokal). FA/h über alle Negativquellen ohne Verwechsler (20,6 h), v8a, Schwelle 0,98, Poisson 95 %:

| Stufe 2 | Ereignisse | FA/h | Obergrenze |
|---|---|---|---|
| keine (Stufe 1 allein) | 28 | 1,36 | 1,96 |
| hw2 immer | 0 | 0 | 0,18 |
| hw2 + Band 0,999 | 3 | 0,15 | 0,43 |
| hw2 + Band 0,995 | 9 | 0,44 | 0,83 |

Belastbar ist vor allem MLS (14,3 h, 30 Sprecher, daher Obergrenze eher zu knapp). Das eine MLS-Ereignis bei Band 0,999 ist ein „Hallo“ (Spitzenwert 0,9996), ein Muster, das auch bei den Verwechslern auftaucht. Vorgelesene Sprache ersetzt keine lange Alltagsaufnahme (Fernsehen, Gespräche, Raumhall). **Nicht monoton in der Schwelle:** Mit Halten (App-Parität) startet bei niedrigerer Schwelle das Ereignis früher, wird beim ersten Abfall mit kleinerer Spitze entschieden, und die spätere höhere Spitze fällt in die Sperrzeit; das Ereignis geht dann an hw2 statt direkt durch (MLS: Ereignisse mit Spitze ≥ 0,999 gleich 0 / 1 / 1 bei 0,95 / 0,98 / 0,99). Das ist App-Verhalten, kein Rechenfehler, aber für die Wahl der Stufe-1-Schwelle (WP129) relevant: niedrigere Schwelle heißt weniger Direktannahmen.

**Empfehlung (Maintainer bestätigt 2026-10-22):** Stufe 2 im Stationsmodus nur im **Band unter 0,999**: Spitzenwert ≥ 0,999 nimmt die App direkt an, darunter prüft hw2 wie bisher; Ausschnitt 2,0 s / 0,9 s bleibt. Gegenüber hw2 immer deutlich mehr Treffer (App-Bezug 69 statt 50 von 90) bei fast gleichem Verwechsler-Schutz (5 / 4 statt 5 / 2 von 300) und rund 0,15 FA/h (≤ 0,43) mehr. Band 0,995 bringt wenige Treffer mehr (76 von 90, Intervalle überlappen), aber mehr als doppelt so viele Verwechsler (12 / 11) und dreimal so viele Fehlalarme. Pegel-Normalisierung vor hw2 ist ein kleiner, kostenloser Zugewinn (optional). Tolerantere Regeln, längerer Ausschnitt, Whisper auf Deutsch, stärkerer Boost und `blank_penalty` sind nicht besser. Grundsätzlich tut sich ein allgemeiner Erkenner mit einem einzelnen, leisen Eigennamen schwer; ein wortspezifischer Prüfer (Bewertung „passt Wendelin“ oder Vorlagen-Vergleich) ist als Folgepunkt vorgeschlagen.

**Vergleich der Wörter (Band 0,999):** mit App-Bezug Kreuzauswahl Wendelin 34/45, Hey Wendelin 35/45; feste Schwelle 31/45 gegen 35/45; Verwechsler 5 gegen 4 (mit Spitze: 40/45 gegen 34/45 und 32/45 gegen 34/45; die scheinbare Überlegenheit von „Wendelin“ verschwindet unter App-Bezug). Kein belastbarer Unterschied; Stufe 1 ist für beide dasselbe Modell, nur Stufe 2 trennt über das Hey-Wort.

Reproduzierbar (Repo-Root, `K=~/wendelin-models/kws`): `nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/stage2_analysis.py --threads 2 --model v8a=$K/wp130/out/wendelin_wp130_a.onnx` → `$K/wp130/results/stage2_table.md` (lokal). Die Zahlen bei fester Schwelle 0,98 (Spitzenwerte, Verwechsler, FA) stehen dort in Abschnitt 6 (Option `--fixed-thr`, Standard 0,98; `--report-only` rechnet nur aus den Caches), die Treffer-Spalten in Abschnitt 4. Ausschnitt: `… stage2_analysis.py --cut-only --model v8a=…` → `stage2_cut_table.md`. Negativquellen: `nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/stage2_extra_neg.py --model v8a=$K/wp130/out/wendelin_wp130_a.onnx --threads 2` → `stage2_extra_neg.md` (lokal; lädt den MLS-Test-Split einmalig nach `$K/wp133/dl`).

### B. v8a-syn gegen v8c-syn (2026-10-23)

Frage: Bringt die Sprecheranpassung mit 29 echten Clips (v8a) etwas gegenüber einem Modell ganz ohne echte Positive, und hilft ein größeres Netz? Zwei Modelle nur mit synthetischen Positiven (kein echter Clip, Log `real_pos 0`, Sidecar `real_pos 0`, Prüfung `assert_syn_only`): **a-syn** (hidden 128) und **c-syn** (hidden 256), je 5000 Schritte, Seed 1, sonst wie v8a (Training 11 bzw. 18 min bei 2 Threads). v8a: 29 echte Clips, je 100-fach. Gleicher Prüf-Split, gleiche Kreuzauswahl (2 FA/h, Kalibrierung echt), Wilson 95 %. Die v7- und v8a-Zeilen sind mit Teil A identisch (Tabellen-Diff leer). Modelle, Kurven und Transkripte bleiben lokal; hier nur Zahlen.

**1. Kreuzauswahl Stufe 1 (2 FA/h), Prüf-Split.** Zellen: Huawei W, Huawei HW, handy2 W, handy2 HW.

| Modell | Huawei W | Huawei HW | handy2 W | handy2 HW | Summe (Wilson 95 %) | davon Wendelin | davon Hey Wendelin |
|---|---|---|---|---|---|---|---|
| v8a | 12/15 | 14/15 | 23/30 | 27/30 | 76/90, 84 % [76–91] | 35/45 | 41/45 |
| a-syn | 11/15 | 9/15 | 22/30 | 17/30 | 59/90, 66 % [55–75] | 33/45 | 26/45 |
| c-syn | 11/15 | 12/15 | 24/30 | 20/30 | 67/90, 74 % [65–82] | 35/45 | 32/45 |
| v7 | keine Konfiguration unter dem Ziel | | | | | | |

Zum Vergleich der Streuung: v8b (WP130, Seed 2, 10 000 Schritte) 14, 14, 22, 26 = 76/90, also gleich v8a; bei den Treffern ist die Seed-Streuung klein. Bei den Verwechslern ist sie es nicht: v8b verdoppelt sie mit anderem Seed (WP130, 15 % gegen 5–8 %). Mit Kalibrierung synthetisch + FLEURS findet Stufe 1 bei a-syn und c-syn keine Konfiguration unter dem Ziel (FA syn bei 0,99: a-syn 2,6, c-syn 1,6–3,1 je Stunde; v8a 1,0). Über alle Blöcke 1–6 (nur v7 und die Modelle ohne echte Positive): a-syn 24, 22, 22, 17 = 85/120, 71 % [62–78]; c-syn 25, 26, 24, 20 = 95/120, 79 % [71–85].

**2. Feste Schwelle 0,98 (Spitze-Bezug, Ereignisse), Prüf-Split.** Verwechsler = Verwechsler-Ereignisse (300 Clips, Wendelin / Hey Wendelin, eine Zahl bei Gleichstand), syn = Ereignisse auf den synthetischen Negativen, echt = Ereignisse in 1,22 h echter Negativ-Aufnahme.

| Modell | Stufe 1: Treffer (HW) | Verwechsler | syn | echt | Band 0,999: Treffer (HW) | Verwechsler | syn | echt | hw2 immer |
|---|---|---|---|---|---|---|---|---|---|
| v7 | 74/90 (36) | 49 | 13 | 7 | 69/90 (32) | 27 | 5 | 0 | 43/90 |
| v8a | 77/90 (41) | 23 | 3 | 1 | 66/90 (34) | 5 / 4 | 1 | 0 | 46/90 |
| a-syn | 64/90 (29) | 40 | 8 | 4 | 56/90 (22) | 10 / 8 | 2 | 0 | 42/90 |
| c-syn | 69/90 (33) | 44 | 6 | 1 | 56/90 (24) | 16 / 14 | 1 | 0 | 43/90 |

Wilson 95 % der Stufe-1-Summen: v8a 86 % [77–91], c-syn 77 % [67–84], a-syn 71 % [61–79]. Band 0,999: v8a 73 % [63–81], a-syn und c-syn je 62 % [52–72].

Andere Schwellen, Band 0,999 (Treffer, Verwechsler W / HW): bei 0,95 v8a 75 (7 / 4), a-syn 56 (13 / 9), c-syn 57 (17 / 14); bei 0,99 v8a 61 (4 / 3), a-syn 54 (9 / 8), c-syn 57 (15 / 13). Über alle Blöcke bei 0,98 mit Band 0,999: a-syn 83/120 (Verwechsler 10 / 8), c-syn 84/120 (16 / 14), v7 97/120 (27); Wilson 69 % [60–77], 70 % [61–77], 81 % [73–87]. Die Wilson-Intervalle zählen Rufe als unabhängig; Rufe desselben Sprechers sind es nicht, die Intervalle sind eher zu eng.

**3. Methodenbefund: Kreuzauswahl allein täuscht.** In den Kreuzauswahl-Zeilen mit Band 0,999 (Abschnitt 4 der Analyse, Raster 0,2–0,99) liegen v7 bei 75/90, a-syn 68, c-syn 73, v8a 74, also gleichauf. v7 (0,3–0,99), a-syn (0,3–0,99) und c-syn (0,2–0,99) wählen dort überwiegend niedrigere Schwellen mit 4–15 % Verwechsler-Clips, v8a überwiegend 0,95 und höher (1–3 %), teils 0,7–0,9 mit etwa 6 % und bei handy2 „Hey Wendelin“ auch 0,2 mit 2 % (Abschnitt 5 der Analyse). Gleiche Treffer bei ungleichem Verwechsler-Schutz: Die Auswahl kann ein schwächeres Modell durch eine niedrige Schwelle ausgleichen und bezahlt mit Verwechslern, die die FA-Kalibrierung (Negativ-Sprache, kaum ähnliche Wörter) nicht sieht (Deutung, nicht weiter geprüft). Die Modelle vergleicht man deshalb zusätzlich bei fester Schwelle (Abschnitt 6e der Analyse); die Kreuzauswahl allein reicht nicht. Auch die feste Schwelle ist je Modell ein anderer Arbeitspunkt (bei 0,98 a-syn echt 4 / syn 8, v8a 1 / 3); hier trägt der Vergleich, weil v8a bei 0,95, 0,98 und 0,99 gegenüber a-syn und c-syn in Stufe 1 und im Band mehr Treffer bei weniger Verwechslern hat (v7 trifft im Band etwas öfter, 69 gegen 66 bei 0,98, mit fünf- bis siebenmal so vielen Verwechslern (27 gegen 5 / 4)).

**4. Das Band schützt bei den syn-Modellen schlechter.** Verwechsler mit Spitzenwert ≥ 0,999 (am Band vorbei) sind bei a-syn und c-syn deutlich häufiger als bei v8a (bei 0,98: 10 / 8 und 16 / 14 gegen 5 / 4). Das ist eine Einzellauf-Beobachtung: Die Verwechsler streuen zwischen Seeds stark (v8b), der Unterschied zwischen a-syn und c-syn liegt in dieser Streuung. Eine Erklärung haben wir nicht untersucht.

**Empfehlung.** WP129 nimmt v8a mit Stufe-1-Schwelle 0,98 und dem Band aus Teil A: Spitzenwert ≥ 0,999 direkt, 0,98–0,999 prüft hw2. c-syn hat gegen a-syn in Stufe 1 überall mehr Treffer (Prüf-Split 69 gegen 64 bei 0,98; Kreuzauswahl 67 gegen 59), im Band gleich viele (56 / 56). Der Verwechsler-Unterschied ist mit einem Seed nicht belastbar, ob das größere Netz lohnt, bleibt offen (Folgepunkt: mehrere Seeds). Die Sprecheranpassung mit 29 echten Clips bringt vor allem „Hey Wendelin“ (Stufe 1: 41/45 gegen 26/45 bei a-syn und 32/45 bei c-syn), auch auf handy2, das nicht im Training war: ein Sprecher-, kein Geräteeffekt.

**Grenzen.**
- Ein Sprecher (alle echten Aufnahmen vom Maintainer): „fremde Stimme“ ist nur durch das syn-Modell nachgebildet, nicht gemessen. Die Aussage „Anpassung hilft“ gilt für diesen Sprecher.
- Ein Seed je syn-Modell. Die Streuung ist nur über v8a gegen v8b (gleiche Treffersumme, doppelte Verwechsler) abgeschätzt, nicht für a-syn und c-syn; der Abstand zu v8a (a-syn 17, c-syn 9 Treffer in der Kreuzauswahl) ist groß gegen den einen Streuungsvergleich, und für die Verwechsler ist die Streuung groß (v8b); mehr als diesen haben wir nicht.
- Der Spitze-Bezug ist optimistisch (die App hat ihn nicht); mit App-Bezug sind es bei v8a etwa 5 Treffer weniger. Die App-Parität (`stage2_cut.py`) ist nur für v8a gemessen, die Rangfolge der Modelle ist es nicht unter App-Bezug.
- Echte Negativzeit nur 1,22 h; ein Ereignis je Gerät ist die FA-Grenze, die „echt“-Spalte unterscheidet 0 von 1 kaum.

**Reproduzierbar (Repo-Root, `K=~/wendelin-models/kws`, nur aus den Caches):** `M=$K/wp130/out/wendelin_wp130; nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/stage2_analysis.py --report-only --threads 2 --fixed-thr 0.95,0.98,0.99 --model v8a=${M}_a.onnx --model a-syn=${M}_a-syn.onnx --model c-syn=${M}_c-syn.onnx` → `stage2_table.md` (Abschnitt 6 je Modell und Schwelle, 6e: Vergleichstabelle). Alle Blöcke ohne v8a: dasselbe mit `--split all` und nur den Modellen `a-syn`, `c-syn` (v7 ist immer dabei) → `stage2_table_all.md`.

## Vorlagen zentriert (WP134)

Frage (WP134 Teil B, nur Messung, kein App-Code): Soll der Vorlagen-Vergleich für „Wendelin“ (Kosinus eines 1536er-Fensters gegen die Einlern-Vorlagen) zentriert werden, und welche Schwelle gilt dann? Skript `tool/train_wake_word/template_center_measure.py` (Selbsttest `test_template_center_measure.py`), Arbeitsdaten lokal unter `$K/wp134` (nie im Repo).

**Aufbau.** Die App-Kette ist in Python nachgebildet: Strom in Blöcken zu 1280 Samples mit 480 Samples Kontext, Mel `x/10+2`, ein Embedding je 76 Mel-Frames, Fenster aus 16 Embeddings (`wake_feature_chain.dart`); Einlernen wie `embedUtterance` (1 s und 2 s Polster, Fenster mit Ende 300 ms nach dem Wortende; Ausschnitt wie `UtteranceCapture`: 200 ms Vorlauf, Wortende plus 160 ms, Grenzen aus den Labels); Vergleich wie `_closest` (höchster Kosinus über die Vorlagen). **Abgleich mit Dart:** dieselben 40 s Huawei-Aufnahme durch die echte `WakeFeatureChain` (ONNX, Blöcke zu 320 Samples) und durch die Nachbildung: 476 Fenster, gleiche `endSample`-Folge, Kosinus Fenster gegen Fenster min 0,99998, Mittel 0,99999 (der Offline-Weg von openWakeWord, den die älteren Messungen nutzten, liegt nur bei Mittel 0,992 / min 0,969, deshalb die Nachbildung). Nicht nachgebildet: die Sprachgrenzen des Aufnahme-Erkenners (hier die Labels), der Klassifikator-Weg (ODER-Regel), Rasterphasen des Stroms (eine Phase).

**Split.** Vorlagen nur huawei Block 1–3, Wort „Wendelin“ (14 Clips, `ok` und `unsicher` bis 2 s). Prüfung: huawei Block 4–6 und handy2 Block 1–6 (45 „Wendelin“, 45 „Hey Wendelin“, Treffer = höchste Ähnlichkeit mit Fensterende im Labelfenster, Fenster wie `words_measure`), echte Negativ-Aufnahmen (je 0,61 h), FLEURS test (1,0 h, „Fernseher“), digitale Stille und Rauschen (je 120 s), 300 Verwechsler (WP130, in 2 s rosa Raumrauschen eingebettet). Mittel und Schwelle werden nie auf Prüfclips mit Positiven gefittet: V1 aus den Einlern-Fenstern, V2 aus FLEURS dev (0,5 h, 21 171 Fenster, getrennt von FLEURS test), V2b zu gleichen Teilen aus FLEURS dev, synthetischem Rauschen und digitaler Stille; die Schwelle hängt nur an Negativ-Aufnahmen (niedrigster Wert mit höchstens 2 FA/h, Ereignisse mit 1,5 s Sperre). „Streng“ nimmt den Fernseher hinzu, gewählt auf der einen Hälfte der FLEURS-Clips, berichtet auf der anderen.

**Varianten.** V0 roh (heute); V1 zentriert mit dem Mittel aller Einlern-Fenster (Wort + Hintergrund); V2 zentriert mit festem Mittel aus neutraler Sprache; V2b mit festem Mittel aus Sprache, Rauschen, Stille. Jeweils mit Polster der Vorlagen `zero` (digitale Nullen, heute) oder `noise` (weißes Rauschen mit dem Pegel der aufgenommenen 200 ms Vorlauf).

**Warum Polster-Vorlagen?** Es sind keine eigenen Vorlagen, sondern jede Vorlage trägt Polster: Das Fenster ist 2,0 s lang und endet 0,3 s nach dem Wortende, das Wort ist etwa 0,7 s lang, davor liegen die 1 s digitale Nullen. Median 49 % der Samples im Vorlagenfenster sind digitale Nullen (min 13 %, max 54 %), bei `noise` 1 %. Ähnlichkeit der Vorlagen zur digitalen Stille (roh): 0,79–0,85 (Median 0,80), mit Rauschpolster 0,81–0,85; keine Vorlage ist stilleähnlich (>0,9). Die „3 von 16 Stille-Polster-Vorlagen“ aus WP126 konnte ich mit den Huawei-Vorlagen **nicht** reproduzieren (vermutlich Vorlagen des Maintainers mit leisem Wort, nicht geprüft). Leave-one-out unter den 14 Vorlagen (roh): min 0,76, Median 0,95, max 0,97.


**Ergebnis.**
- **Roh (V0) hat kaum Abstand zum Hintergrund:** Stille 0,85, Rauschen 0,86–0,87, Fernseher bis 0,89, schwächster „Wendelin“-Treffer 0,84 (unter der Stille). Jede Schwelle unter 0,88 löst in Rauschen aus; die Schwelle für ≤2 FA/h liegt bei 0,89–0,90 und damit 0,02–0,03 über dem Rauschen. Der Treffer-Abstand ist klein: bei gleicher FA-Rate auf dem Fernseher (Kurvenvergleich) trifft V0 mit digitalem Polster nur 71 % [57–82] („Hey Wendelin“ 33 % [21–48]), mit Rauschpolster 93 % [82–98] („Hey Wendelin“ 44 % [31–59]).
- **Zentriert (V1/V2/V2b):** Stille −0,15 bis 0,24, Rauschen 0,02–0,37 gegen Schwellen 0,43–0,55, also Abstand 0,1–0,4 statt 0,02. Bei gleicher FA-Rate auf dem Fernseher: „Wendelin“ 93–98 % [82–100] (42–44 von 45), „Hey Wendelin“ 49–73 %; mit `noise`-Polster und V2b 98 % [88–100] und 69 % [54–80]. Die Intervalle von V0-`noise` und zentriert überlappen bei „Wendelin“ (93 % gegen 93–98 %); der Gewinn bei den Treffern ist klar nur gegenüber V0 mit digitalem Polster, bei „Hey Wendelin“ (Vorlagen sind „Wendelin“) deutlich (69 gegen 44 %).
- **Verwechsler** (300 synthetische Clips): bei gleicher Fernseher-Rate lösen V0 5–16, zentriert 18–25 Clips aus (6–8 % gegen 2–5 %). Zentrieren kostet hier Trennschärfe gegen ähnliche Wörter; bei der strengen Schwelle sind es 29–64 gegen 25–31 (V0). Das Maß ist synthetisch (nur Stimmen disjunkt zum Training), kein Alltagsmaß.
- **Warmstart:** keine Variante löst in digitaler Stille oder in einem der fünf Rauschstücke (weiß 3/10/30 LSB, rosa 10/100 LSB) aus, weder mit der ruhigen noch mit der strengen Schwelle. Die Spanne ist bei V0 aber nur 0,02–0,04, zentriert 0,1–0,4.
- **Polster:** Das digitale Polster allein kostet bei V0 22 Punkte „Wendelin“ (71 gegen 93 % bei gleicher FA-Rate; ruhige Schwelle handy2 80 gegen 93 %); es ist der größere Teil des V0-Defizits. Bei V1 zieht es das Mittel auf die Stille (Stille 0,24, Rauschen bis 0,37 gegen −0,02 und bis 0,10 mit `noise`), weil das Mittel dann zur Hälfte aus digitalen Nullen besteht (schlechter als `noise`). V2/V2b sind vom Polster kaum abhängig.
- **Empfehlung:** Vorlagen mit Rauschpolster (Pegel des Vorlaufs) statt digitaler Nullen, **zentriert mit festem Mittel V2b** (Sprache + Rauschen + Stille, 1536 Werte, an `wakeFeatureVersion` gebunden, Herkunft: nicht Einlern- und nicht Prüfdaten). Schwelle (streng, Auswahl auf echten Negativ-Aufnahmen und einer Fernseher-Hälfte) **0,50**; die Schwellen aller zentrierten Varianten streuen 0,43–0,55 (jede beruht auf 1–4 Ereignissen, Unsicherheit etwa ±0,05). Das Einlern-Mittel V1 ist mit `noise`-Polster fast gleichwertig (Schwelle 0,47, Stille −0,02), hängt aber am Raumrauschen beim Einlernen.
- **Konsequenzen für den Code (jetzt umgesetzt, siehe „Umsetzung in der App“):** `wakeMinThreshold` und `wakeProvisionalThreshold` (0,85) sind Werte des rohen Kosinus und müssen für den zentrierten Vergleich neu gesetzt werden (Vorschlag 0,50 vorläufig, Untergrenze 0,40); Vorlagen von vor der Änderung sind roh gespeichert (Neueinlernen oder Mittel nachrechnen; das Polster lässt sich nachträglich nicht entfernen).

**Saubere Prüfmenge.** handy2 Block 1–3 ist nach Angabe des Maintainers dieselbe Aufnahmesitzung wie die Vorlagen (nicht von mir geprüft); „sauber“ nimmt deshalb nur huawei Block 4–6 und handy2 Block 4–6 (n = 30 je Wort). Die Spitzen je Gerät und Wort stehen in Label-Reihenfolge; das Skript prüft per Assertion (`clean_peaks`), dass die Blöcke nichtfallend sortiert sind, bevor es nach Block 4–6 teilt (sonst bricht es ab). Die Schwellen hängen nur an Negativ-Aufnahmen, die Teilmenge ändert sie nicht. Treffer „Wendelin“ / „Hey Wendelin“ (Wilson-Intervall) bei der **strengen** Schwelle:

| Polster | Var. | Schwelle | Wendelin sauber | Hey Wendelin sauber |
|---|---|---|---|---|
| zero | V0 (heute) | 0,89 | 83 % (25/30) [66–93] | 40 % (12/30) [25–58] |
| noise | V0 | 0,89 | 90 % (27/30) [74–97] | 43 % (13/30) [27–61] |
| noise | V1 | 0,47 | 97 % (29/30) [83–99] | 70 % (21/30) [52–83] |
| noise | V2 | 0,47 | 97 % (29/30) [83–99] | 73 % (22/30) [56–86] |
| noise | **V2b** | **0,50** | **97 % (29/30) [83–99]** | **77 % (23/30) [59–88]** |

Bei der ruhigen Schwelle (0,47) trifft V2b-`noise` ebenfalls 29/30 und „Hey“ 26/30; im Kurvenvergleich (gleiche FA-Rate auf dem Fernseher) 29/30 und 19/30. Die Erwartung 29/30 und 23/30 trifft zu. **Plausibilität:** Der Gewinn gegenüber heute (83 gegen 97 %, „Hey“ 40 gegen 77 %) ist nur bei „Hey Wendelin“ außerhalb der Intervall-Überlappung; bei „Wendelin“ überlappen die Intervalle (66–93 gegen 83–99), und V0-`noise` (90 %) ist nicht klar schlechter. Die Zahl 29/30 hängt an einem einzigen Ruf; das Ziel „mindestens wie vorher“ ist erfüllt, ein klarer Gewinn beim Hauptwort ist nicht belegt.

**Umsetzung in der App (WP134 Teil B).** Das feste Mittel V2b steht als `packages/wendelin_voice/lib/src/wake/wake_center_mean.g.dart` (1536 Werte, base64; erzeugt mit `template_center_measure.py export`, deterministisch aus FLEURS dev [CC-BY 4.0, Google], synthetischem Rauschen und digitaler Stille zu gleichen Teilen; kein Einlern- und kein Prüfclip, kein Fit auf Prüfdaten), gebunden an `wakeFeatureVersion` (Test) und mit der Kennung `v2b-1`. Der Kosinus zentriert in `bestSimilarity(…, mean:)` (Engine `_closest`, Tester, Kalibrator, Leave-one-out; der Barge-in nutzt dieselbe Engine). Das Einlernen polstert mit Gauß-Rauschen im Pegel der ersten 200 ms der Aufnahme (Seed 134, mindestens 1 LSB) statt mit Nullen. Schwellen: vorläufig 0,50, Untergrenze 0,40, Obergrenze der Kalibrierung 0,90, Ereignis-Untergrenze 0,30, Antwort-Untergrenze 0,40. Vorlagen ohne Kennung (`center` fehlt im JSON) werden beim Laden ignoriert (`isCompatible`), im Wake-Wort-Bildschirm steht „neu einlernen“; kalibrieren und ausprobieren sind dafür gesperrt. `candidateWakeMargin` von -0,10 auf -0,05 gesetzt (Stufe 1 im Barge-in bei gelernter Schwelle 0,50 also 0,45 statt 0,40). Gemessen (V2b, Rausch-Polster, 14 Vorlagen huawei Block 1–3, Kandidaten = Ereignisse mit 1,5 s Sperre): Stille (max −0,15) und Rauschen (max 0,15) lösen bei 0,40 und 0,45 nicht aus; echte Negativ-Aufnahmen bei 0,40 18/h (huawei, handy2 je 0,61 h), bei 0,45 1,6 und 4,9/h; FLEURS test (Fernseher, 1,00 h) bei 0,40 88/h, bei 0,45 30/h, bei 0,50 4/h. Begründung: bei 0,40 lägen die Fernseher-Kandidaten weit über 30/h und Stufe 2 liefe zu oft, bei 0,45 an der Grenze. Die Zahlen stammen aus der Skript-Kette, nicht aus der App. Risiko: Die schwächste „Wendelin“-Spitze liegt bei 0,45–0,49, ein Kandidat kann bei 0,45 also knapp verfehlt werden (nicht gesondert gemessen; E2E `voice_barge_in`).

**Zweifel und Grenzen.**
- Ein Sprecher, Vorlagen von einem Gerät (huawei), n = 45 je Wort: die Wilson-Intervalle sind breit und zählen Rufe als unabhängig. Die Rangfolge der zentrierten Varianten untereinander (V1/V2/V2b, `zero`/`noise`) ist **nicht** belegt; belegt ist nur der Abstand zu V0 in den Abständen zu Stille und Rauschen und, mit dem digitalen Polster, bei den Treffern.
- Negativ-Aufnahmen sind „Alltag leise“ (1,22 h): ruhige Schwelle ergibt 8–12 FA/h auf Sprache (FLEURS, vorgelesen, kein echter Fernseher). Streng sind es 2–8/h (1–4 Ereignisse in 0,5 h); die Auswahlhälften sind klein. Die ruhige Schwelle ist für Fernseher zu locker, auch bei V0 (2–4/h).
- Die Gegenprobe (Schwelle vom anderen Gerät) bestätigt die Treffer (huawei 15/15, handy2 29–30 von 30 zentriert), aber die FA auf dem eigenen Negativ liegen bei 0–4 Ereignissen (0,61 h erlaubt 1).
- Die Nachbildung der Aufnahme (Labels statt Erkenner) und das Rauschpolster (weißes Rauschen, App-Code gibt es dafür noch nicht) weichen von der App ab; die Kette selbst ist gegen Dart abgeglichen. Eine Rasterphase, keine Streuung über Phasen (WP129 fand beim Klassifikator bis 0,17 p95 zwischen App und Skript; für Vorlagen nicht gemessen).
- Keine Klassifikator-Kopplung: In der App entscheidet die ODER-Regel; die Messung gilt dem Vorlagen-Weg allein.

**Reproduzierbar (Repo-Root, `K=~/wendelin-models/kws`):** `nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/template_center_measure.py run --threads 2` (Cache der Fenster unter `$K/wp134/cache`, erster Lauf etwa 10 min, danach unter 1 min; Selbsttest: `$K/wp58/venv/bin/python -I -m unittest discover -s tool/train_wake_word -p 'test_template_center_measure.py'`). Rohtabelle des Laufs:

Negativ echt: huawei 0.61 h, handy2 0.61 h (zusammen 1.22 h, erlaubt 2 Ereignisse bei 2/h); FLEURS-Fernseher test 1.00 h (Auswahlhälfte 0.50 h, Berichtshälfte 0.50 h).

**Verteilungen der Ähnlichkeit** (Spitze je Strom bzw. Clip):

| Polster | Var. | Stille max | Rauschen max (weiß 3/10/30, rosa 10/100) | Negativ echt p99,9 / max (hu; h2) | Fernseher p99,9 / max | Wendelin Spitze min / Median / max | Verwechsler Median / p90 / max |
|---|---|---|---|---|---|---|---|
| zero | V0 | 0,85 | 0,87 / 0,87 / 0,87 / 0,87 / 0,86 | 0,88 / 0,88; 0,87 / 0,88 | 0,87 / 0,89 | 0,84 / 0,91 / 0,96 | 0,86 / 0,88 / 0,91 |
| zero | V1 | 0,24 | 0,35 / 0,33 / 0,33 / 0,37 / 0,30 | 0,44 / 0,49; 0,41 / 0,52 | 0,47 / 0,56 | 0,46 / 0,68 / 0,86 | 0,43 / 0,53 / 0,62 |
| zero | V2 | 0,18 | 0,27 / 0,25 / 0,26 / 0,28 / 0,23 | 0,38 / 0,46; 0,35 / 0,44 | 0,40 / 0,51 | 0,41 / 0,66 / 0,86 | 0,39 / 0,50 / 0,60 |
| zero | V2b | -0,13 | 0,08 / 0,06 / 0,07 / 0,09 / 0,02 | 0,41 / 0,51; 0,39 / 0,47 | 0,45 / 0,55 | 0,49 / 0,69 / 0,87 | 0,43 / 0,52 / 0,63 |
| noise | V0 | 0,85 | 0,87 / 0,86 / 0,87 / 0,87 / 0,86 | 0,88 / 0,88; 0,87 / 0,88 | 0,87 / 0,89 | 0,84 / 0,92 / 0,96 | 0,86 / 0,89 / 0,91 |
| noise | V1 | -0,02 | 0,10 / 0,09 / 0,08 / 0,09 / 0,04 | 0,36 / 0,46; 0,35 / 0,43 | 0,41 / 0,55 | 0,42 / 0,68 / 0,87 | 0,38 / 0,50 / 0,62 |
| noise | V2 | 0,22 | 0,28 / 0,29 / 0,27 / 0,28 / 0,28 | 0,38 / 0,44; 0,36 / 0,44 | 0,42 / 0,55 | 0,36 / 0,68 / 0,87 | 0,40 / 0,51 / 0,64 |
| noise | V2b | -0,15 | 0,15 / 0,11 / 0,10 / 0,11 / 0,08 | 0,39 / 0,51; 0,38 / 0,47 | 0,45 / 0,57 | 0,45 / 0,71 / 0,88 | 0,42 / 0,52 / 0,65 |

**Schwelle ruhig:** niedrigster Wert mit höchstens 2 FA/h auf den echten Negativ-Aufnahmen (beide Geräte zusammen):

| Polster | Var. | Schwelle | FA echt hu / h2 | FA/h Fernseher (Ereignisse) | Wendelin huawei B4–6 | Wendelin handy2 | Wendelin gesamt | Hey Wendelin gesamt | Verwechsler-Clips | löst nach Warmstart aus (Stille / Rauschen) |
|---|---|---|---|---|---|---|---|---|---|---|
| zero | V0 | 0,89 | 0 / 0 | 2,0 (1) | 93 % (14/15) [70–99] | 80 % (24/30) [63–90] | 84 % (38/45) [71–92] | 51 % (23/45) [37–65] | 25/300 | nein |
| zero | V1 | 0,49 | 0 / 2 | 11,9 (6) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 80 % (36/45) [66–89] | 73/300 | nein |
| zero | V2 | 0,44 | 2 / 0 | 10,0 (5) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 80 % (36/45) [66–89] | 91/300 | nein |
| zero | V2b | 0,47 | 2 / 0 | 11,9 (6) | 100 % (15/15) [80–100] | 100 % (30/30) [89–100] | 100 % (45/45) [92–100] | 89 % (40/45) [77–95] | 87/300 | nein |
| noise | V0 | 0,89 | 0 / 0 | 4,0 (2) | 93 % (14/15) [70–99] | 93 % (28/30) [79–98] | 93 % (42/45) [82–98] | 53 % (24/45) [39–67] | 31/300 | nein |
| noise | V1 | 0,43 | 1 / 1 | 8,0 (4) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 87 % (39/45) [74–94] | 91/300 | nein |
| noise | V2 | 0,45 | 0 / 0 | 10,0 (5) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 82 % (37/45) [69–91] | 84/300 | nein |
| noise | V2b | 0,47 | 1 / 1 | 8,0 (4) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 89 % (40/45) [77–95] | 79/300 | nein |

**Schwelle streng:** wie ruhig, zusätzlich mit der Auswahlhälfte des Fernsehers (FA/h Fernseher auf der anderen Hälfte):

| Polster | Var. | Schwelle | FA echt hu / h2 | FA/h Fernseher (Ereignisse) | Wendelin huawei B4–6 | Wendelin handy2 | Wendelin gesamt | Hey Wendelin gesamt | Verwechsler-Clips | löst nach Warmstart aus (Stille / Rauschen) |
|---|---|---|---|---|---|---|---|---|---|---|
| zero | V0 | 0,89 | 0 / 0 | 2,0 (1) | 93 % (14/15) [70–99] | 80 % (24/30) [63–90] | 84 % (38/45) [71–92] | 51 % (23/45) [37–65] | 25/300 | nein |
| zero | V1 | 0,52 | 0 / 0 | 8,0 (4) | 100 % (15/15) [80–100] | 93 % (28/30) [79–98] | 96 % (43/45) [85–99] | 73 % (33/45) [59–84] | 40/300 | nein |
| zero | V2 | 0,46 | 1 / 0 | 8,0 (4) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 76 % (34/45) [61–86] | 64/300 | nein |
| zero | V2b | 0,52 | 0 / 0 | 2,0 (1) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 73 % (33/45) [59–84] | 29/300 | nein |
| noise | V0 | 0,89 | 0 / 0 | 4,0 (2) | 93 % (14/15) [70–99] | 93 % (28/30) [79–98] | 93 % (42/45) [82–98] | 53 % (24/45) [39–67] | 31/300 | nein |
| noise | V1 | 0,47 | 0 / 0 | 4,0 (2) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 78 % (35/45) [64–87] | 53/300 | nein |
| noise | V2 | 0,47 | 0 / 0 | 6,0 (3) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 80 % (36/45) [66–89] | 63/300 | nein |
| noise | V2b | 0,50 | 1 / 0 | 4,0 (2) | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 82 % (37/45) [69–91] | 53/300 | nein |

**Kurvenvergleich:** Schwelle mit höchstens 2 FA/h auf dem ganzen Fernseher-Satz (keine Einsatz-Schwelle, nur gleiche FA-Rate je Variante):

| Polster | Var. | Schwelle | FA echt hu / h2 | FA/h Fernseher (Ereignisse) | Wendelin huawei B4–6 | Wendelin handy2 | Wendelin gesamt | Hey Wendelin gesamt | Verwechsler-Clips | löst nach Warmstart aus (Stille / Rauschen) |
|---|---|---|---|---|---|---|---|---|---|---|
| zero | V0 | 0,90 | 0 / 0 | – | 67 % (10/15) [42–85] | 73 % (22/30) [56–86] | 71 % (32/45) [57–82] | 33 % (15/45) [21–48] | 5/300 | nein |
| zero | V1 | 0,55 | 0 / 0 | – | 93 % (14/15) [70–99] | 93 % (28/30) [79–98] | 93 % (42/45) [82–98] | 69 % (31/45) [54–80] | 18/300 | nein |
| zero | V2 | 0,51 | 0 / 0 | – | 93 % (14/15) [70–99] | 93 % (28/30) [79–98] | 93 % (42/45) [82–98] | 60 % (27/45) [45–73] | 24/300 | nein |
| zero | V2b | 0,53 | 0 / 0 | – | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 73 % (33/45) [59–84] | 25/300 | nein |
| noise | V0 | 0,89 | 0 / 0 | – | 93 % (14/15) [70–99] | 93 % (28/30) [79–98] | 93 % (42/45) [82–98] | 44 % (20/45) [31–59] | 16/300 | nein |
| noise | V1 | 0,51 | 0 / 0 | – | 93 % (14/15) [70–99] | 97 % (29/30) [83–99] | 96 % (43/45) [85–99] | 64 % (29/45) [50–77] | 22/300 | nein |
| noise | V2 | 0,53 | 0 / 0 | – | 93 % (14/15) [70–99] | 93 % (28/30) [79–98] | 93 % (42/45) [82–98] | 49 % (22/45) [35–63] | 20/300 | nein |
| noise | V2b | 0,54 | 0 / 0 | – | 100 % (15/15) [80–100] | 97 % (29/30) [83–99] | 98 % (44/45) [88–100] | 69 % (31/45) [54–80] | 21/300 | nein |

**Gegenprobe Gerät:** Schwelle nur aus dem Negativ des anderen Geräts (huawei-Schwelle aus handy2 und umgekehrt), FA auf dem eigenen Negativ, Treffer „Wendelin“ auf dem eigenen Gerät:

| Polster | Var. | -> huawei: Schwelle, FA, Treffer | -> handy2: Schwelle, FA, Treffer |
|---|---|---|---|
| zero | V0 | 0,88, 4, 14/15 | 0,89, 0, 24/30 |
| zero | V1 | 0,52, 0, 15/15 | 0,49, 2, 29/30 |
| zero | V2 | 0,42, 4, 15/15 | 0,45, 0, 29/30 |
| zero | V2b | 0,46, 2, 15/15 | 0,52, 0, 29/30 |
| noise | V0 | 0,89, 0, 14/15 | 0,89, 0, 28/30 |
| noise | V1 | 0,43, 1, 15/15 | 0,42, 2, 29/30 |
| noise | V2 | 0,45, 0, 15/15 | 0,43, 3, 29/30 |
| noise | V2b | 0,47, 1, 15/15 | 0,45, 3, 30/30 |
