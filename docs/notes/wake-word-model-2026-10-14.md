# Wake-Word-Modell „Wendelin“ (WP58, 2026-10-14): Pilot

Stand: Pilot-Training mit synthetischen Daten, Messung auf dem Host (macOS, ohne Gerät). **Die Abnahmegrenzen (Treffer ≥ 80 %, FA ≤ 2/h) sind nicht erreicht.** Aufnahmen des Maintainers (`~/wendelin-fixtures/wake/`) lagen nicht vor.

## Trainingsweg (Recherche, Stand 2026)
- openWakeWord (Apache-2.0, v0.6.0) trennt Mel-Spektrogramm (ONNX), Google-`speech_embedding` (ONNX, Apache-2.0, eingefroren) und einen kleinen Klassifikator (16 Embeddings × 96 → DNN, ca. 0,86 MB). Nur der Klassifikator wird trainiert. Der offizielle Weg (`openwakeword/train.py`, Colab-Notebook) setzt Piper-Beispiele, RIR/Hintergrundgeräusche und vorberechnete ACAV100M-Negativ-Features (ca. 16 GB) voraus, ist laut Community-Berichten seit 2023 abhängigkeitsbrüchig (Torch/Speechbrain-Pins) und braucht GPU und etwa 45 GB Platz. Der Mac hat nur etwa 12 GB frei. Daher eigenes, schlankes Skript (`tool/train_wake_word/`), das dieselbe Feature-Pipeline (`openwakeword.utils.AudioFeatures`) und dasselbe Klassifikator-Format (Eingabe `[1,16,96]`, Ausgabe `[1,1]`) nutzt. Gegenprobe: das offizielle `alexa`-Modell läuft mit unseren Features korrekt (Pipeline in Ordnung).
- Das ONNX-Modell läuft in openWakeWord direkt (`Model(wakeword_models=[…], inference_framework="onnx")`) und braucht keine neue Laufzeit; Mel-/Embedding-Modelle (2,4 MB) kämen in die App.

## Daten und Lizenzen (alles unter `~/wendelin-models/kws/wp58/`, nichts im Repo)
| Quelle | Verwendung | Lizenz |
|---|---|---|
| Piper `de_DE-thorsten-medium` | Positiv/Negativ-Synthese | CC0 |
| Piper `de_DE-kerstin-low` | dito | CC0 |
| Piper `de_DE-mls-medium` (236 Sprecher, OpenSLR 94) | dito | CC-BY 4.0 (Namensnennung) |
| Piper `eva_k`, `karlsson`, `ramona` (M-AILABS) | **nicht genutzt**: Lizenz „See URL“, nicht belegt | unklar |
| Piper `pavoque` | **nicht genutzt** | CC-BY-NC-SA 4.0 |
| Piper-TTS-Engine 1.8.0 | Synthese | MIT |
| Tatoeba deu (Text) | Negativsätze für TTS | CC-BY 2.0 FR |
| FLEURS de_de dev (1,26 h echte Sprache, 363 Clips) | Negativ-Füller | CC-BY 4.0 |
| openWakeWord-Code, `melspectrogram.onnx`, `embedding_model.onnx` | Features | Apache-2.0 |
Die mitgelieferten vortrainierten openWakeWord-Modelle sind CC-BY-NC-SA und werden nicht verwendet. Rauschen, Hall und Brummen sind synthetisch (keine Fremddatensätze). Das trainierte Modell enthält nur eigene Klassifikatorgewichte; mit Namensnennung (MLS, FLEURS, Tatoeba, Piper/Thorsten, Google speech_embedding) wären die Lizenzen für ein Einchecken ausreichend. Das Modell wird **nicht** eingecheckt, solange es die Abnahme nicht erfüllt; es wird dann wie Whisper per Skript erzeugt/geladen (`tool/train_wake_word/run.sh`).

## Aufbau (`tool/train_wake_word/`)
- `gen_samples.py`: Piper-Synthese, zufälliger Sprecher (MLS), Tempo 0,8 bis 1,3, Rauschparameter, Tonhöhe ±8 %; Positive „Wendelin“, „Hey Wendelin“ (+ Satzzeichen), Verwechsler („Wendel“, „Wendeltreppe“, „Vanille“, „Berlin“, „Wenzel“, „Windel“ …), Negativsätze. Ausreißer über 1,8 s verworfen.
- `train.py features`: baut 5-s-Clips (Positiv: Wort mit bekanntem Ende zwischen Füllsprache, 50 % mit Satz danach; Negativ: nur Füllsprache, 15 % Verwechsler, ca. 40 % echte FLEURS-Sprache), Augmentation (Hall RT60 0,2 bis 0,9 s, Bandbegrenzung, zufällige Klangfarbe, Rauschen weiß/rosa/braun/Brummen/Musik/Babble bei SNR 4 bis 35 dB, Wort-Tonhöhe 0,8 bis 1,25), Embeddings. Positiv-Fenster: Ende 0 bis 0,8 s nach Wortende, Fenster dazwischen werden ignoriert.
- `train.py train`: DNN 1536→128→128→1 (LayerNorm, Dropout 0,3), Hard-Negative-Gewichtung, 5000 Schritte, Export ONNX (dynamischer Batch).
- `eval.py`: Messung wie `tool/kws_measure.py` (gleiche Bedingungen clean/noise 10 dB/reverb RT60 0,5 s/both, gleiche macOS-Stimmen-Positive und -Negative), FA mit 2 s Sperrzeit. `run.sh`: gesamter Ablauf.
- Hinweis: openWakeWord-`embed_clips` braucht Clips als Vielfaches von 160 Samples und Batch ≥ 2 (bei 1 Clip Formfehler); in `common.embed` abgefangen.

## Ergebnis (Modell v7; Positiv 90 Clips, 9 macOS-Stimmen; Negativ 2,15 h deutsche Systemstimmen)
| Schwelle | clean Treffer / FA/h | noise (10 dB) | reverb | both |
|---|---|---|---|---|
| 0,50 | 39 % / 14,9 | 36 % / 13,0 | 60 % / 83 | 44 % / 16,3 |
| 0,70 | 31 % / 9,3 | 32 % / 7,0 | 54 % / 47 | 38 % / 8,8 |
| 0,90 | 28 % / 4,6 | 28 % / 3,7 | 47 % / 21 | 27 % / 2,8 |
| 0,98 | 21 % / 2,3 | 20 % / 0,9 | 34 % / 8,8 | 16 % / 0,0 |
Vollständige Tabelle: 9 Schwellen von 0,2 bis 0,98 (siehe `run.sh eval`). Modellgröße 858 KB (Klassifikator) + 2,4 MB (Mel/Embedding). **RTF 0,031 bis 0,038** (Mel + Embedding + Klassifikator, 1 Thread, Apple Silicon), also etwa 3,5 % eines Kerns. Auf dem Gerät nicht gemessen.
In-Domain (Piper, nicht gesehene Wortclips): 82 bis 91 % Fensterrecall bei 0,4 bis 0,5 % Fenster-FP.

Vorläufige Empfindlichkeitsstufen aus der Tabelle (nur zur Verdrahtung in WP44; **müssen mit echten Aufnahmen neu gesetzt werden**): niedrig 0,98, mittel 0,9, hoch 0,6. Selbst „hoch“ erreicht keine 80 %.

## Verlauf (Messung auf demselben Satz, clean, Schwelle 0,5)
v1 (5000 Piper-Wörter, 4 s Clips, strenge Fensteretiketten) 10 %; Fehler gefunden: erstes Fenster endet erst bei 2,0 s, Wörter davor lieferten keine Positiv-Fenster (→ 5-s-Clips, Wort ab 1,4 s) und Ausreißer-Clips (→ Filter) und zu strenge Positionsetiketten (→ „Wort im Fenster“) 13 bis 27 %; v6 (13 800 Wörter + echte Sprache) 24 %; v7 (+ Tonhöhe/Klangfarbe, 20 000 Positiv-Clips) 39 %. Größeres Netz (256 Neuronen, 8000 Schritte): kein Gewinn (40 %).

## Befund und Hochrechnung
- Die Genauigkeit hängt an der **Sprechervielfalt**: Die Stimme „Anna“ wird zu 100 % erkannt, andere macOS-Stimmen (Eddy, Reed, Grandpa, Shelley) fast nie. Piper hat nur 3 Stimmen mit 238 Sprechern der Qualität „medium/low“; Positiv-Daten dominieren keine echte Variation. Jeder Schritt mehr Vielfalt (Tonhöhe/Klangfarbe, mehr Wörter) brachte 10 bis 15 Prozentpunkte, ohne Sättigung.
- Offizielle Modelle brauchen ca. 30 000 h Negativ-Features und 100 000+ Positive. Wir hatten 6 h synthetisch + 1,3 h echt und 20 000 Positive. Aufwand: Erzeugung 1,2 h, Features 29 min, Training 2 min (5 Kerne); Speicher ca. 4,7 GB. Eine Vervielfachung der Positive (50 bis 100 k) ist in 2 bis 4 h machbar, ob sie 80 % erreicht, ist nicht belegt (Fehler vor allem Domänenlücke zu fremden TTS-Stimmen).
- Wahrscheinlicher wirksam: (1) **echte Aufnahmen des Maintainers** (20 bis 30 Clips, `tool/record_wake_fixtures.md`) als Mess- und Feintuning-Satz (nur lokal), (2) Zweitstufe Whisper-Bestätigung (bei diesen FA-Raten zwingend), (3) mehr echte deutsche Negativ-Sprache (FLEURS train 1,6 GB, Common Voice), (4) M-AILABS-Stimmen nach Klärung der Lizenz.
- Konzeptabweichung (zu melden): Plan B liefert mit rein synthetischen Daten **nicht** die geforderten Werte; WP44 sollte die Zweitstufe und die Feintuning-Schleife mit echten Aufnahmen einplanen.

## Offen
1. Aufnahmen des Maintainers → `eval.py` mit `--pos ~/wendelin-fixtures/wake/pos --neg ~/wendelin-fixtures/wake/neg` (Ordner existiert noch nicht).
2. Lizenz M-AILABS (eva_k/karlsson/ramona) klären; Namensnennung für MLS, FLEURS, Tatoeba festhalten.
3. Gerätemessung (CPU/PSS) und Einbindung (WP44) nicht gemacht.
