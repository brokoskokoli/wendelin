# Wake-Word-Modell v8: Lizenzen und Namensnennung (WP130)

Das Modell enthält nur Klassifikatorgewichte (ONNX); Trainingsdaten und Aufnahmen werden nicht verteilt. Quellen laut Piper-MODEL_CARD (`rhasspy/piper-voices`, Stand 2026-10-22) bzw. Datensatzseite. Training: `tool/train_wake_word/run_v8.sh`.

## Stimmen für synthetische Positive und Negative (Piper, `de_DE`)
| Stimme (Ordner `v-…`) | Datensatz | Lizenz | Namensnennung |
|---|---|---|---|
| thorsten low, medium, high | Thorsten-Voice (Thorsten Müller) | CC0 | nicht verlangt, freiwillig |
| thorsten_emotional medium (8 Emotionen) | Thorsten-Voice | CC0 | nicht verlangt, freiwillig |
| kerstin low | rhasspy/dataset-voice-kerstin | CC0 | nicht verlangt |
| mls medium (236 Sprecher) | Multilingual LibriSpeech, OpenSLR 94 | CC-BY 4.0 | verlangt: „Multilingual LibriSpeech (Pratap et al., OpenSLR 94), CC-BY 4.0“ |
| eva_k x_low, ramona low, karlsson low | M-AILABS Speech Dataset (Caito) | Modellkarte „See URL“; Datensatzseite: BSD-artige Lizenz (Weitergabe und Nutzung auch kommerziell, mit oder ohne Änderung erlaubt; Urheberhinweis und Haftungsausschluss der Quelldaten beibehalten; Name der Urheber nicht zur Bewerbung nutzen) | verlangt: „M-AILABS Speech Dataset, Copyright (c) 2017-2019 M-AILABS“ |
| pavoque low | marytts/pavoque-data | CC-BY-NC-SA 4.0 | **nicht verwendet** (nicht kommerziell) |

Hinweis M-AILABS: Der Lizenztext steht auf der Datensatzseite (`caito.de`, Beitrag „The M-AILABS Speech Dataset“, Archivstand 2023), nicht in der Piper-Modellkarte. Vor der Veröffentlichung des Modells prüft der Orchestrator die Seite erneut.

## Daten für Negative und Merkmale
| Quelle | Verwendung | Lizenz | Namensnennung |
|---|---|---|---|
| Tatoeba, deutsche Sätze (nur Text, per Piper gesprochen) | Negativsätze | CC-BY 2.0 FR | „Tatoeba-Mitwirkende, tatoeba.org“ |
| FLEURS de_de, train und dev (Google) | echte Negativ-Sprache | CC-BY 4.0 | „FLEURS (Conneau et al.), CC-BY 4.0“ |
| Common Voice de, Version 17 (Mozilla, Spiegelung `fsicoli/common_voice_17_0`; Trainings-Shard, jeder dritte Clip) | echte Negativ-Sprache | CC0 | nicht verlangt, freiwillig: „Mozilla Common Voice“ |
| openWakeWord-Code, `melspectrogram.onnx`, `embedding_model.onnx` (Google speech_embedding) | eingefrorene Merkmale | Apache-2.0 | Lizenztext beilegen |
| Piper-TTS-Engine 1.8.0 | Synthese | MIT | Lizenztext beilegen |

Die mitgelieferten vortrainierten openWakeWord-Modelle (CC-BY-NC-SA) werden nicht verwendet. Rauschen, Hall und Brummen sind synthetisch.

## Eigene Aufnahmen
Echte Positive stammen aus Aufnahmen des Maintainers (nur Gerät 1, Blöcke 1 bis 3; Einwilligung liegt vor). Sie bleiben lokal und werden nicht veröffentlicht; veröffentlicht werden nur die Gewichte. Der Split ist in `tool/train_wake_word/real_split.py` fest verdrahtet und durch `test_real_split.py` abgesichert. Prüf-Aufnahmen (Gerät 1 Blöcke 4 bis 6, Gerät 2, Negativ-Aufnahmen) gelangen nie ins Training.
