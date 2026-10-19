# Wake Word im Stationsmodus (WP106, 2026-10-19): Messung

Stand: Messung auf dem Host (macOS, ohne Gerät), nur Zahlen. Frage: Reicht Stufe 1 (Wake-Word-Modell oder Vorlagen) plus Stufe 2 (STT mit Hotword) plus Stufe 3 (Sprecherprüfung) für ein Handy, das 2 bis 3 m entfernt liegt, mit Fernseher und Küchengeräuschen? **Nicht erreicht:** keine Kombination liefert hohe Trefferquote und 0 FA/h zugleich. Skripte: `tool/train_wake_word/` (`station_measure.py`, `real_measure.py`, `train.py`, `mww_*`). Rohdaten liegen nur lokal unter `~/wendelin-models/kws/wp106/results/` und `~/wendelin-fixtures/wake/station/`, nichts davon im Repo.

## Messaufbau
- **Synthetisch** (`station_measure.py`): 9 Piper-Stimmen, Bedingungen `clean`, `both` (Rauschen 10 dB + Hall 0,5 s), `station` (2 bis 3 m, RT60 0,7 s, Pegel -10 bis -15 dB, Fernsehton aus FLEURS + synthetische Musik bei SNR 5 bis 10 dB, Mikrofonrauschen 25 dB). Negativ: 1,0 h Systemstimmen-Sprache (150 Clips; 8 Clips mit „Wendelin“ ausgeschlossen) und 1,0 h Fernsehton („Fernseher“).
- **Echte Aufnahmen** (`real_measure.py`): ein Sprecher, zwei Handys gleichzeitig (Station = liegend, Mobil = nah). Positiv-Datei per Energie-VAD in 47 Segmente geschnitten; Zuordnung zu den Bedingungen nur, wo die Segmentzahl zur Anleitung passt. **Sicher (n=10):** Segmente 16, 17, 20, 21 (Satz, 2 m), 32 bis 35 (Küche), 46, 47 (schnell). Übrige Segmente (Rest: 3 m, Fernseher, leise) sind nur ungefähr zugeordnet und stehen als „ev“ (3 m / TV / leise). Segmente 1 bis 5 sind das Einlernen (Vorlagen und CAM++-Profil je Gerät), getestet wird nur auf den übrigen. Negativ-Datei (1,0 h, Alltagssprache) zeitlich zum Station-Gerät ausgerichtet (Kreuzkorrelation der Energiehüllen, Versatz Station = Mobil + 1,44 s, Drift -0,004 s). Fundstellen von „Wendelin“ (2) und Verwechslern (3) per whisper-medium (unabhängig) geprüft und bestätigt; Labels stammen nie aus dem gemessenen Erkenner.
- Treffer = irgendein Stufe-1-Ereignis im Wortbereich ±0,5 s des Segments übersteht alle Stufen. FA/h = Ereignisse in der Negativ-Datei, die alle Stufen übersteht (Verwechsler und echte „Wendelin“ getrennt ausgewiesen, hier „Verw/h“).
- Stufe 2 spiegelt `matchesWakeWord` (Abstand 1). Messfehler aus WP102 (Hotwords ohne `bpe_vocab` wirkungslos) geprüft: `bpe_vocab` ist gesetzt, die Sanity-Prüfung zeigt, dass Hotwords den Text auf 603 bis 1314 von 1336 Segmenten ändern.

## Stufe 2: STT-Varianten (synthetisch, Stufe 1 = Vorlagen T0,85)
Treffer % (Stufe 1 allein in Klammern) und FA/h (Negativ / Fernseher), ohne Stufe 3.

| Stufe 2 | clean Treffer | clean FA/h | both Treffer | both FA/h | station Treffer | station FA/h (Neg / TV) |
|---|---|---|---|---|---|---|
| nur Stufe 1 | 84,4 | 4,45 / 36,0 | 50,0 | 33,3 / 34,8 | 58,9 | 35,4 / 88,0 |
| Whisper small | 42,2 | 0 / 0 | 0 | 0 / 0 | 3,3 | 0 / 0 |
| Parakeet ohne Hotword | 28,9 | 0 / 0 | 0 | 0 / 0 | 0 | 0 / 0 |
| Parakeet Hotword 1 | 67,8 | 0 / 0 | n. a. | n. a. | n. a. | n. a. |
| Parakeet Hotword 2 | 75,6 | 0,11 / 0 | 0 | 0 / 0 | 3,3 | 0,89 / 0 |
| Parakeet Hotword 3 | 84,4 | 0,56 / 2,4 | 6,7 | 7,7 / 0,9 | 21,1 | 9,7 / 4,8 |
| Parakeet Hotword 5 | 84,4 | 3,45 / 35,3 | 48,9 | 32,8 / 33,7 | 57,8 | 34,5 / 84,9 |

Boost wirkt monoton: Hotword 1 und 2 sind streng (Treffer niedrig, FA ~0), Hotword 3 ist der Mittelweg, ab Hotword 3 (clean) bzw. 3,0 steigt FA/h, bei 5 macht das Hotword fast jeden Ton zum „Wendelin“ (FA wie ohne Stufe 2). Auf verrauschten und entfernten Aufnahmen bricht die Trefferquote aller strengen Varianten ein (synthetisch `station`: höchstens 21 % bei Hotword 3).

## Echte Aufnahmen, Stufe 1 + Stufe 2 (Parakeet Hotword 2/3), Stufe 1 = Vorlagen T0,85
Je Gerät: Treffer sicher n=10 (ev 3 m / TV / leise), FA/h, Verw/h. „-“ = keine Stufe 3.

| Gerät | Stufe 2 | Stufe 3 | sicher % | ev % | FA/h | Verw/h |
|---|---|---|---|---|---|---|
| Station | nur Stufe 1 | - | 100 | 100/100/100 | 939 | 8,3 |
| Station | nur Stufe 1 | CAM++ 0,45 | 90 | 100/100/100 | 92,9 | 8,3 |
| Station | Whisper small | - | 0 | 60/75/17 | 0 | 0 |
| Station | Parakeet ohne | - | 10 | 40/25/0 | 0 | 0 |
| Station | Parakeet Hotword 2 | - | 60 | 100/75/33 | 0 | 4,1 |
| Station | Parakeet Hotword 3 | - | 60 | 100/100/50 | 35,1 | 8,3 |
| Station | Parakeet Hotword 3 | CAM++ 0,45 | 60 | 100/100/50 | 6,2 | 8,3 |
| Mobil | nur Stufe 1 | - | 100 | 100/100/100 | 892 | 6,2 |
| Mobil | Whisper small | - | 20 | 60/100/17 | 0 | 0 |
| Mobil | Parakeet Hotword 2 | - | 60 | 100/75/67 | 2,1 | 6,2 |
| Mobil | Parakeet Hotword 3 | - | 80 | 100/100/100 | 24,7 | 6,2 |
| Mobil | Parakeet Hotword 3 | CAM++ 0,45 | 60 | 100/100/100 | 0 | 0 |

Verwechsler (ähnlich klingende Wörter in der Negativ-Datei) bestehen Stufe 2 mit Hotword fast immer: das Hotword zieht sie zum Namen. CAM++ trennt sie nur teilweise (siehe Stufe 3). Echte „Wendelin“-Fundstellen in der Negativ-Datei: 2 (Station, ca. 1680 und 1700 s). Sie sind in „echt n“ nicht mitgezählt; mit n=2 ist daraus keine Rate ableitbar.

## Stufe 1: Modelle und Vorlagen (echte Aufnahmen, Negativ-Datei Station)
Kandidaten/h = Stufe-1-Ereignisse je Stunde in der Negativ-Datei; Treffer sicher (n=10) / Rest (26 Segmente, unsicher zugeordnet) nur Stufe 1. Regel T = Vorlagen (Schwelle), M = Modell (Schwelle).

| Gerät | Regel | Kand./h | sicher % | Rest % |
|---|---|---|---|---|
| Station | Vorlagen T0,85 | 948 | 100 | 100 |
| Station | Vorlagen T0,90 | 706 | 100 | 96 |
| Station | Vorlagen T0,93 | 504 | 50 | 92 |
| Station | Vorlagen T0,95 | 353 | 10 | 62 |
| Station | v7 M0,3 | 103 | 90 | 85 |
| Station | v7 M0,5 | 58 | 70 | 81 |
| Station | v7 M0,7 | 39 | 60 | 77 |
| Station | v9 M0,3 | 116 | 70 | 73 |
| Station | v9 M0,5 | 66 | 60 | 58 |
| Station | v9 M0,7 | 47 | 60 | 58 |
| Station | microWakeWord M0,2 | 124 | 50 | 62 |
| Station | microWakeWord M0,3 | 78 | 40 | 50 |
| Mobil | Vorlagen T0,85 | 898 | 100 | 100 |
| Mobil | Vorlagen T0,95 | 344 | 10 | 35 |
| Mobil | v7 M0,3 | 91 | 40 | 65 |
| Mobil | v7 M0,5 | 33 | 30 | 58 |
| Mobil | v9 M0,5 | n. a. | 40 | n. a. |
| Mobil | microWakeWord M0,3 | n. a. | 20 | n. a. |

Mit Stufe 2 (Parakeet Hotword 2) und CAM++ 0,45 hinter dem Modell:

| Gerät | Stufe 1 | sicher % | ev % (3 m/TV/leise) | FA/h | Verw/h |
|---|---|---|---|---|---|
| Station | v7 M0,5 | 60 | 100/75/33 | 0 | 2,1 |
| Station | v9 M0,5 | 50 | 100/50/17 | 0 | 2,1 |
| Station | microWakeWord M0,2 | 30 | 100/50/17 | 0 | 4,1 |
| Mobil | v7 M0,5 | 20 | 80/50/50 | 0 | 0 |
| Mobil | v9 M0,5 | 20 | 80/75/67 | 0 | 0 |
| Mobil | microWakeWord M0,2 | 0 | 60/50/33 | 0 | 0 |

Folgerung: Die Vorlagen sind das empfindlichste Stufe 1 (100 % sicher bei 948 Kand./h), die Modelle v7/v9 sind auf den ruhigen Segmenten schwächer, produzieren aber 15- bis 25-mal weniger Kandidaten. v9 ist nicht besser als v7 (mehr Sprecher und FLEURS ändern die echte Messung kaum), microWakeWord (61 KB, Apache-2.0) liegt darunter (Mobil mit Stufe 2 und 3: 0 % sicher). Die Treffer-Unterschiede zwischen v7/v9 liegen bei n=10 im Rauschen (1 Segment = 10 Punkte).

## Persönliches Feintuning (Stufe 1)
Skript `tool/train_wake_word/finetune_personal.py` (ein Kommando im Kopf). v7 und v9 werden mit den 8 kurzen Einlern-Wörtern (Segmente 1 bis 5 beider Geräte; der lange Satz in Segment 1 ist ausgelassen) feinabgestimmt: 2000 augmentierte Clips (Pegel, Hall, Rauschen, Tempo/Tonhöhe, EQ) plus die WP58-Features (Negative und synthetische Positive im Verhältnis 3:1:1 je Batch), 1200 Schritte, Lernrate 2e-4, ca. 1,5 min je Modell. Die Negativ-Datei und die Testsegmente gehen nicht ins Training; die v9-Features waren gelöscht, beide Modelle nutzen die WP58-Features (work5). Getestet auf den übrigen Segmenten (n=10 sicher) und der Negativ-Datei (1,0 h). Stufe 2 = Parakeet Hotword 2, ohne CAM++ (mit 0,45 sinkt Mobil auf 20 bis 30 %).

| Gerät | Modell, Schwelle | Stufe 1: Kand./h | sicher % | ev 3m/TV/leise % | + Hotword 2: sicher % | ev % | FA/h | Verw/h |
|---|---|---|---|---|---|---|---|---|
| Station | v7 vorher M0,5 | 58 | 70 | - | 60 | 100/75/33 | 0 | 2,1 |
| Station | v7 fein M0,5 | 97 | 90 | 100/100/100 | 60 | 100/75/33 | 0 | 2,1 |
| Station | v7 fein M0,7 | 64 | 80 | 100/100/100 | 60 | 100/100/33 | 0 | 2,1 |
| Station | v7 fein M0,9 | 37 | 80 | 100/100/100 | 70 | 60/100/33 | 0 | 2,1 |
| Station | v9 vorher M0,5 | 66 | 60 | - | 50 | 100/50/17 | 0 | 2,1 |
| Station | v9 fein M0,5 | 87 | 90 | 100/100/100 | 80 | 100/75/17 | 0 | 2,1 |
| Station | v9 fein M0,7 | 43 | 70 | 100/100/100 | 60 | 100/75/17 | 0 | 2,1 |
| Station | v9 fein M0,9 | 19 | 50 | 100/75/100 | 40 | 60/50/17 | 0 | 2,1 |
| Mobil | v7 vorher M0,5 | 33 | 30 | - | 20* | 80/50/50 | 0 | 0 |
| Mobil | v7 fein M0,5 | 72 | 60 | 100/100/100 | 60 | 80/100/33 | 0 | 0 |
| Mobil | v7 fein M0,7 | 43 | 50 | 100/100/100 | 50 | 80/100/67 | 0 | 0 |
| Mobil | v7 fein M0,9 | 16 | 50 | 100/100/100 | 40 | 80/100/67 | 0 | 0 |
| Mobil | v9 fein M0,5 | 62 | 50 | 100/100/100 | 50 | 80/100/67 | 0 | 2,1 |
| Mobil | v9 fein M0,7 | 33 | 40 | 100/100/100 | 40 | 80/100/67 | 0 | 0 |
| Mobil | v9 fein M0,9 | 8 | 30 | 100/100/100 | 30 | 80/100/67 | 0 | 0 |

(*) Vorher-Werte aus der Tabelle oben mit CAM++ 0,45; "vorher" mit Stufe 1 allein: sicher-Spalte aus der Stufe-1-Tabelle.

Das Feintuning hebt die Stufe-1-Treffer deutlich (Station 60 bis 70 → 90 %, Mobil 30 bis 40 → 50 bis 60 % bei M0,5), kostet aber etwa 1,5- bis 2,2-fach so viele Kandidaten (87 bis 97 statt 58 bis 66 je Stunde Station, 62 bis 72 statt 33 Mobil). Nach Stufe 2 bleiben 60 bis 80 % sicher (Station v9 M0,5 80 %, Mobil 50 bis 60 %) bei 0 FA/h und 2,1 Verwechsler/h (derselbe bestätigte Verwechsler). Grenze: Die Testsegmente stammen aus derselben Sitzung und demselben Raum wie die Einlern-Segmente (n=10, 1 Segment = 10 Punkte), die Werte sind eher optimistisch; ob es in anderen Räumen trägt, zeigt nur eine neue Aufnahme.

## Stufe 3: Sprecherprüfung (CAM++, 3D-Speaker, 28 MB, 50 ms je Segment)
Kosinus zu den Einlern-Segmenten, Perzentile (5 / 25 / 50 / 75 / 95):

| Menge | 5 | 25 | 50 | 75 | 95 |
|---|---|---|---|---|---|
| synthetisch, eigene Stimme (Positiv-Kandidaten) | 0,20 | 0,33 | 0,46 | 0,76 | 0,87 |
| synthetisch, fremd/Fernseher (Negativ-Kandidaten) | 0,02 | 0,09 | 0,16 | 0,23 | 0,40 |
| echt Station, eigene Stimme (Positiv-Ereignisse) | 0,23 | 0,34 | 0,38 | 0,56 | 0,67 |
| echt Station, Negativ-Ereignisse | 0,11 | 0,25 | 0,34 | 0,38 | 0,52 |
| echt Mobil, eigene Stimme | 0,26 | 0,31 | 0,37 | 0,51 | 0,65 |
| echt Mobil, Negativ-Ereignisse | 0,09 | 0,21 | 0,30 | 0,34 | 0,37 |

Auf echten Aufnahmen überlappen die Verteilungen deutlich (eigene Stimme Median 0,37 bis 0,38, fremde bis 0,52). Wirkung als Stufe 3 hinter Vorlagen T0,85 (Station, nur Stufe 1): 0,45 senkt FA/h von 939 auf 93 (sicher 100 → 90 %), 0,52 auf 39 (sicher 90 %, leise 83 %), 0,60 auf 4 (sicher 50 %). Synthetisch (clean, nur Stufe 1): 0,45 / 0,52 / 0,60 → FA/h 1,8 / 1,5 / 1,3, Treffer 84,4 / 84,4 / 83,3 %; unter `station` bricht der Treffer bei 0,45 auf 18,9 % (von 58,9 %) ein. **Stufe 3 allein macht kein Wake Word, sie ist nur sinnvoll hinter Stufe 2 oder zur Fernseher-Unterdrückung.**

## Latenz, RTF, RAM (Mac, Apple Silicon, 4 Threads, int8)
| Baustein | RTF | ms je Segment | RAM-Spitze (Prozess) | Laden |
|---|---|---|---|---|
| Stufe 1 (Vorlagen + v7) | 0,037 | - | 179 MB | 1,4 s |
| Whisper small | 0,216 | 623 | 983 MB | 1,7 s |
| Parakeet v3 ohne Hotword | 0,048 | 138 | 1114 MB | 1,1 s |
| Parakeet Hotword 1 / 2 / 3 / 5 | 0,071 / 0,046 / 0,057 / 0,052 | 206 / 133 / 166 / 151 | 1155 bis 1165 MB | 0,9 bis 1,3 s |
| CAM++ | - | 50 | 139 MB | 0,2 s |
Modellgrößen: v7 0,86 MB (+ Mel/Embedding 2,4 MB), microWakeWord 61 KB, CAM++ 28 MB, Parakeet 670 MB. Nur Host-Zahlen; Handy-Werte misst das Folgepaket. Bei 900 Kandidaten/h läuft Stufe 2 etwa 2 min je Stunde Audio (Vorlagen T0,85) bzw. 8 s je Stunde (v7 M0,5).

## Schwellen: Handy vs. Station
| | Handy (nah) | Station (2 bis 3 m) |
|---|---|---|
| Stufe 1 | Modell v7 M0,5 (33 Kand./h) | Modell v7 M0,5 oder Vorlagen T0,85 + Stufe 2 |
| Stufe 2 | Hotword 2 | Hotword 2 (sicher); Hotword 3 + CAM++ 0,45 (mehr Treffer, 6 FA/h) |
| Stufe 3 | optional 0,45 | 0,45 nur mit Stufe 2 |

Einheitliche Station-Schwellen wären zu streng für das Handy und umgekehrt: Die Station braucht den niedrigeren Stufe-1-Schwellwert (Pegel -10 bis -15 dB und Hall), der Kandidatenstrom steigt, Stufe 2 und 3 müssen ihn filtern.

## Empfehlung
- Stationsmodus nur als **optionaler, getrennter Modus** mit eigenem Schwellensatz: Stufe 1 = Vorlagen T0,85 (empfindlich) oder Modell v7 M0,5, Stufe 2 = Parakeet Hotword 2 (Hotword 3 nur zusammen mit CAM++ 0,45), kein Boost ab 3,0 ohne Stufe 3. Das ergibt auf echten Daten 60 % sicher bei 0 bis 6 FA/h (n=10, ein Sprecher), nicht die Abnahme (80 %, ≤ 2 FA/h).
- Stufe 3 (CAM++) nur als Fernseher-/Fremdstimmen-Filter einplanen; sie ersetzt keine Stufe 2.
- Persönliches Feintuning (Einlern-Wörter, ca. 1,5 min Rechenzeit) lohnt sich: Stufe 1 = feinabgestimmtes v9 oder v7 M0,5 + Hotword 2 ohne CAM++ ergibt 60 bis 80 % sicher (Station) bzw. 50 bis 60 % (Mobil) bei 0 FA/h; das Einlernen müsste die Feinabstimmung in der App ausführen (Klassifikator ist klein, 0,86 MB). Vor einem Einbau: echte Daten von mehr Sprechern und Räumen messen (siehe Grenzen). **Aufwand Einbau (Schätzung):** Parakeet ist mit WP103 vorhanden (Hotword als Konfiguration, ca. 1 PT), CAM++ als Modell und Sprecherprofil im Einlernen (28 MB, `EmbeddingPort`, ca. 3 PT), Stationsmodus mit eigenen Schwellen, Einstellung und Dauerbetrieb (Strom, Wake-Lock, ca. 4 PT), Gerätetest (ca. 2 PT).

## Lizenzen (alles lokal, nichts im Repo)
| Baustein | Lizenz |
|---|---|
| Parakeet TDT 0.6B v3 (NVIDIA) | CC-BY-4.0 (Namensnennung) |
| Whisper (OpenAI) | MIT |
| CAM++ (3D-Speaker, `campplus_sv_zh_en_16k`) | Apache-2.0 |
| microWakeWord (kahrendt) | Apache-2.0 |
| openWakeWord-Code, speech_embedding | Apache-2.0 |
| sherpa-onnx | Apache-2.0 |
| FLEURS (Google) | CC-BY 4.0 |
| Piper-Stimmen `thorsten`, `kerstin` | CC0 |
| Piper-Stimme `mls` (OpenSLR 94) | CC-BY 4.0 |
| Tatoeba (Text) | CC-BY 2.0 FR |
| echte Aufnahmen | eigene Aufnahmen des Maintainers, privat, nicht im Repo |

## Grenzen
- n=10 sichere Segmente, ein Sprecher, ein Raum, zwei Handys; 1 Segment = 10 Prozentpunkte. Der Rest (26 Segmente) ist nur ungefähr zugeordnet. Die Negativ-Datei hat 1,0 h und nur 2 echte „Wendelin“-Fundstellen.
- Neg-Scan nur auf der Station-Datei (Mobil-Zeiten daraus abgeleitet).
- Synthetische Bedingungen sind Modelle (Hall, Fernsehton), nicht echte Räume.
- Keine Handy-Zeiten, keine Dauerbetrieb-Messung (Strom).

## Abweichungen vom Plan
- Stufe-1-Schwellen der Vorlagen 0,85 und 0,9 statt der geplanten 0,93/0,95 (bei 0,93/0,95 sinken die Treffer auf 50/10 % sicher); 0,93 und 0,95 bleiben in den Tabellen.
- Sperrzeit Negativ-Ereignisse 3 s (38 Fenster), Positiv 1,5 s.
- Toleranz ±0,5 s um das Wortsegment.
- Neg-Scan nur auf der Station-Datei.
- Feintuning: nur 8 der 10 Einlern-Wörter (Segment 1 ist ein Satz), v9 mit den v7-Features (die v9-Features sind gelöscht).

## Erneut messen (je ein Kommando)
```
K=~/wendelin-models/kws
# synthetisch (Stufe 1 bis 3, ca. 55 min):
nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/station_measure.py --out $K/wp106/results
# echte Aufnahmen, Standard (v7, Vorlagen; ca. 55 min mit allen Varianten):
nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/real_measure.py --out $K/wp106/results/real
# anderes Modell (z. B. v9, ca. 4 min):
nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/real_measure.py --model $K/wp58/out/wendelin_v9.onnx --thr 0.93 --model-thr 0.3,0.5,0.7,0.9 --s2-thr M0.5,M0.7,M0.9 --spk-thr 0.45,0.52 --variants parakeet-hw2,parakeet-hw3 --out $K/wp106/results/v9
# Feintuning (ca. 3 min), danach real_measure --model $K/wp106/finetune/ft_v9.onnx --model-thr 0.5,0.7,0.9 --thr 0.95 --s2-thr M0.5,M0.7,M0.9 --variants parakeet-hw2 --spk-thr 0.45:
nice -n 10 $K/wp58/venv/bin/python -I tool/train_wake_word/finetune_personal.py
```
Eingaben: `~/wendelin-fixtures/wake/station/{pos,neg}/{station,mobile}/*.wav`. Neue Aufnahmen nach demselben Aufbau (Anleitung in den Fixtures) ablegen und die Kommandos wiederholen.
