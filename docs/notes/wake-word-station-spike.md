# Wake Word im Stationsmodus (WP106, 2026-10-19): Messung

Stand: Messung auf dem Host (macOS, ohne Gerät), nur Zahlen. Frage: Reicht Stufe 1 (Wake-Word-Modell oder Vorlagen) plus Stufe 2 (STT mit Hotword) plus Stufe 3 (Sprecherprüfung) für ein Handy, das 2 bis 3 m entfernt liegt, mit Fernseher und Küchengeräuschen? **Nicht erreicht:** keine Kombination liefert hohe Trefferquote und 0 FA/h zugleich. Skripte: `tool/train_wake_word/` (`station_measure.py`, `real_measure.py`, `train.py`, `mww_*`). Rohdaten liegen nur lokal unter `~/wendelin-models/kws/wp106/results/` und `~/wendelin-fixtures/wake/station/`, nichts davon im Repo.

## Messaufbau
- **Synthetisch** (`station_measure.py`): 9 macOS-Systemstimmen (Anna, Eddy, Flo, Grandma, Grandpa, Reed, Rocko, Sandy, Shelley; lokal erzeugt, nur Messung), Bedingungen `clean`, `both` (Rauschen 10 dB + Hall 0,5 s), `station` (2 bis 3 m, RT60 0,7 s, Pegel -10 bis -15 dB, Fernsehton aus FLEURS + synthetische Musik bei SNR 5 bis 10 dB, Mikrofonrauschen 25 dB). Negativ: 1,0 h Systemstimmen-Sprache (150 Clips; 8 Clips mit „Wendelin“ ausgeschlossen) und 1,0 h Fernsehton („Fernseher“).
- **Echte Aufnahmen** (`real_measure.py`): ein Sprecher, zwei Handys gleichzeitig (Station = liegend, Mobil = nah). Positiv-Datei per Energie-VAD in 47 Segmente geschnitten; Zuordnung zu den Bedingungen nur, wo die Segmentzahl zur Anleitung passt. **Sicher (n=10):** Segmente 16, 17, 20, 21 (Satz, 2 m), 32 bis 35 (Küche), 46, 47 (schnell). Übrige Segmente (Rest: 3 m, Fernseher, leise) sind nur ungefähr zugeordnet und stehen als „ev“ (3 m / TV / leise). Segmente 1 bis 5 sind das Einlernen (Vorlagen und CAM++-Profil je Gerät), getestet wird nur auf den übrigen. Negativ-Datei (**0,484 h** = 29 min Alltagssprache; nicht 1,0 h) zeitlich zum Station-Gerät ausgerichtet (Kreuzkorrelation der Energiehüllen, Versatz Station = Mobil + 1,44 s, Drift -0,004 s). Fundstellen per whisper-medium (unabhängig) gesucht: 2 vermeintliche „Wendelin“ (Station-Zeit ca. 1680 und 1700 s) hat Maintainer als **Verwechsler** bestätigt, dazu 3 weitere Verwechsler; **echte „Wendelin“-Fundstellen: 0** (`echt_n=0`). Labels stammen nie aus dem gemessenen Erkenner.
- **Auflösung der Negativ-Datei:** 0,484 h; 1 Ereignis entspricht 2,1 je Stunde, 2 Ereignisse 4,1 je Stunde. Bei 0 Ereignissen liegt die 95-%-Obergrenze bei etwa 3/0,484 = 6,2 je Stunde (Poisson), bei 1 Ereignis bei 9,8, bei 2 Ereignissen bei 13. „0 FA/h“ heißt deshalb nur „kein Ereignis in 29 min“; die Abnahme „≤ 2 FA/h“ lässt sich mit dieser Datei nicht belegen (dafür wären mindestens 1,5 h ohne Ereignis nötig). Treffer n=10: 10/10 = 72–100 %, 9/10 = 60–98 %, 8/10 = 49–94 %, 6/10 = 31–83 %, 5/10 = 24–76 %, 3/10 = 11–60 % (Wilson, 95 %).
- Treffer = irgendein Stufe-1-Ereignis im Wortbereich ±0,5 s des Segments übersteht alle Stufen. FA/h = Ereignisse in der Negativ-Datei, die alle Stufen überstehen (Verwechsler getrennt als „Verw/h“); **Fehlauslöser gesamt/h = FA/h + Verw/h** ist die Zahl, die ein Nutzer erlebt, denn auch ein Verwechsler löst aus.
- Stufe 2 spiegelt `matchesWakeWord` der App (`wake_verifier.dart`: Abstand 2, Zwei-Änderungs-Regel nur für ein Wort von mindestens 7 Zeichen w/v/f, Zweiwort-Treffer nie vor einem Funktionswort, `_notSplitTail`; Python-Spiegel `kws_measure.matches_wake_word`). Neu bewertet mit der App-Regel und mit Abstand 1 (nur unwesentliche Unterschiede: synthetisch Whisper clean 42,2 → 43,3 %, Parakeet-Hotword 2 clean FA 0,11 → 0,22/h; echte Aufnahmen **identisch** in allen Zeilen). Messfehler aus WP102 (Hotwords ohne `bpe_vocab` wirkungslos) geprüft: `bpe_vocab` ist gesetzt. **Basis des Boosts:** „Parakeet ohne Hotword“ ist `modified_beam_search` ohne Hotwords (gleiche Suche wie mit Hotwords); die frühere greedy-Basis war verfälscht. Sanity (synthetisch, 1336 Segmente, gegen diese Basis): Hotword 1/2/3/5 ändert den Text auf 150/332/701/1311 Segmenten, davon neu als „Wendelin“ erkannt 52/72/278/1259.

## Stufe 2: STT-Varianten (synthetisch, Stufe 1 = Vorlagen T0,85)
Treffer % und FA/h (Negativ / Fernseher), ohne Stufe 3, Stufe-2-Regel = App. „Basis“ = `modified_beam_search` ohne Hotwords, „greedy“ = Parakeet mit Standardsuche (nur zur Information).

| Stufe 2 | clean Treffer | clean FA/h | both Treffer | both FA/h | station Treffer | station FA/h (Neg / TV) |
|---|---|---|---|---|---|---|
| nur Stufe 1 | 84,4 | 4,45 / 36,0 | 50,0 | 33,3 / 34,8 | 58,9 | 35,4 / 88,0 |
| Whisper small | 43,3 | 0 / 0 | 0 | 0 / 0 | 2,2 | 0 / 0 |
| Parakeet greedy | 32,2 | 0 / 0 | 0 | 0 / 0 | 0 | 0 / 0 |
| Parakeet Basis (ohne Hotword) | 24,4 | 0 / 0 | 0 | 0 / 0 | 0 | 0 / 0 |
| Parakeet Hotword 1 | 67,8 | 0 / 0 | 0 | 0 / 0 | 1,1 | 0 / 0 |
| Parakeet Hotword 2 | 75,6 | 0,22 / 0 | 0 | 0 / 0 | 3,3 | 0,89 / 0 |
| Parakeet Hotword 3 | 84,4 | 0,67 / 2,4 | 6,7 | 7,7 / 0,9 | 21,1 | 9,7 / 4,8 |
| Parakeet Hotword 5 | 84,4 | 3,45 / 35,3 | 48,9 | 32,8 / 33,7 | 57,8 | 34,5 / 84,9 |

Der Boost wirkt monoton und trägt fast den ganzen Gewinn: gegenüber der fairen Basis (clean 24,4 %) hebt Hotword 2 den Treffer auf 75,6 %, Hotword 3 auf 84,4 %. Hotword 1 und 2 sind streng (Treffer niedrig, FA ≈ 0), Hotword 3 ist der Mittelweg (clean 0,67 FA/h, aber `station` 9,7 FA/h), bei Hotword 5 macht das Hotword fast jeden Ton zum „Wendelin“ (FA wie ohne Stufe 2). Auf verrauschten und entfernten Aufnahmen bricht die Trefferquote aller strengen Varianten ein (synthetisch `station`: höchstens 21 % bei Hotword 3).

Grenze der synthetischen Fernseher-Zahlen: Das Wake-Modell v7 wurde mit FLEURS dev als Trainingsnegativ trainiert, und das synthetische „Fernseher“-Set (und der Fernsehton der Bedingung `station`) besteht aus FLEURS dev. Für die Modellregeln (v7) sind die synthetischen Fernseher-FA also **geschönt**; für die Vorlagenregeln (hier gemessen, T0,85) und für v9 (FLEURS train) gilt das nicht.

## Echte Aufnahmen, Stufe 1 + Stufe 2 (Parakeet Hotword 2/3), Stufe 1 = Vorlagen T0,85
Je Gerät: Treffer sicher n=10 (ev 3 m / TV / leise), FA/h, Verw/h, gesamt/h = FA + Verw. „-“ = keine Stufe 3. Basis = `modified_beam_search` ohne Hotwords.

| Gerät | Stufe 2 | Stufe 3 | sicher % | ev % | FA/h | Verw/h | gesamt/h |
|---|---|---|---|---|---|---|---|
| Station | nur Stufe 1 | - | 100 | 100/100/100 | 939 | 8,3 | 948 |
| Station | nur Stufe 1 | CAM++ 0,45 | 90 | 100/100/100 | 92,9 | 8,3 | 101 |
| Station | Whisper small | - | 0 | 60/75/17 | 0 | 0 | 0 |
| Station | Parakeet Basis | - | 10 | 0/0/0 | 0 | 0 | 0 |
| Station | Parakeet Hotword 2 | - | 60 | 100/75/33 | 0 | 4,1 | 4,1 |
| Station | Parakeet Hotword 3 | - | 60 | 100/100/50 | 35,1 | 8,3 | 43,4 |
| Station | Parakeet Hotword 3 | CAM++ 0,45 | 60 | 100/100/50 | 6,2 | 8,3 | 14,5 |
| Mobil | nur Stufe 1 | - | 100 | 100/100/100 | 892 | 6,2 | 898 |
| Mobil | Whisper small | - | 20 | 60/100/17 | 0 | 0 | 0 |
| Mobil | Parakeet Basis | - | 10 | 0/25/0 | 0 | 0 | 0 |
| Mobil | Parakeet Hotword 2 | - | 60 | 100/75/67 | 2,1 | 6,2 | 8,2 |
| Mobil | Parakeet Hotword 3 | - | 80 | 100/100/100 | 24,7 | 6,2 | 30,9 |
| Mobil | Parakeet Hotword 3 | CAM++ 0,45 | 60 | 100/100/100 | 0 | 0 | 0 |

Das Hotword ist fast die ganze Wirkung: Ohne Hotword (faire Basis) besteht höchstens 1 von 10 sicheren Segmenten Stufe 2 (die frühere greedy-Basis lag mit 1 von 10 gleich).

Verwechsler (ähnlich klingende Wörter in der Negativ-Datei) bestehen Stufe 2 mit Hotword fast immer: das Hotword zieht sie zum Namen. CAM++ trennt sie nur teilweise (siehe Stufe 3). Die zwei früher als „echtes Wendelin“ geführten Fundstellen (Station ca. 1680 und 1700 s) hat Maintainer als Verwechsler bestätigt; sie sind in „Verw/h“ gezählt, echte Fundstellen: 0 (`echt_n=0`). Die Negativ-Datei enthält damit kein „Wendelin“, die Rate echter Auslösungen im Alltag ist hier nicht messbar.

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
| Mobil | v9 M0,5 | 57,7 | 40 | 58 |
| Mobil | microWakeWord M0,3 | 72,1 | 20 | 42 |

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
Skript `tool/train_wake_word/finetune_personal.py` (ein Kommando im Kopf). v7 und v9 werden mit den 8 kurzen Einlern-Wörtern (Segmente 1 bis 5 beider Geräte; der lange Satz in Segment 1 ist ausgelassen) feinabgestimmt: 2000 augmentierte Clips (Pegel, Hall, Rauschen, Tempo/Tonhöhe, EQ) plus die WP58-Features (Batch 512 = 384 WP58-Negative : 64 persönliche Positive : 64 synthetische Positive, also 6:1:1), 1200 Schritte, Lernrate 2e-4, ca. 1,5 min je Modell. Die Negativ-Datei und die Testsegmente gehen nicht ins Training; die v9-Features waren gelöscht, beide Modelle nutzen die WP58-Features (work5). Getestet auf den übrigen Segmenten (n=10 sicher) und der Negativ-Datei (0,484 h). Stufe 2 = Parakeet Hotword 2, ohne CAM++ (mit 0,45 sinkt Mobil auf 20 bis 30 %).

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
| Mobil | v7 vorher M0,5 | 33 | 30 | - | 30 | 80/75/50 | 0 | 0 |
| Mobil | v7 fein M0,5 | 72 | 60 | 100/100/100 | 60 | 80/100/33 | 0 | 0 |
| Mobil | v7 fein M0,7 | 43 | 50 | 100/100/100 | 50 | 80/100/67 | 0 | 0 |
| Mobil | v7 fein M0,9 | 16 | 50 | 100/100/100 | 40 | 80/100/67 | 0 | 0 |
| Mobil | v9 vorher M0,5 | 57,7 | 40 | - | 40 | 80/100/67 | 0 | 2,1 |
| Mobil | v9 fein M0,5 | 62 | 50 | 100/100/100 | 50 | 80/100/67 | 0 | 2,1 |
| Mobil | v9 fein M0,7 | 33 | 40 | 100/100/100 | 40 | 80/100/67 | 0 | 0 |
| Mobil | v9 fein M0,9 | 8 | 30 | 100/100/100 | 30 | 80/100/67 | 0 | 0 |

Fairer Vergleich: „vorher“ und „fein“ laufen mit derselben Stufe 2 (Hotword 2) ohne CAM++ (alle „vorher“-Zeilen neu aus denselben Läufen gelesen; früher stand Mobil v7 mit CAM++ 0,45 bei 20 %, ohne CAM++ sind es 30 %).

Das Feintuning hebt die Stufe-1-Treffer deutlich (Station 60 bis 70 → 90 %, Mobil 30 bis 40 → 50 bis 60 % bei M0,5), kostet aber etwa 1,5- bis 2,2-fach so viele Kandidaten (87 bis 97 statt 58 bis 66 je Stunde Station, 62 bis 72 statt 33 Mobil). Nach Stufe 2 (Hotword 2, ohne CAM++) bleiben 60 bis 80 % sicher (Station v9 M0,5 80 %, Mobil 50 bis 60 %) bei 0 FA/h und höchstens 2,1 Verwechsler/h (ein Ereignis, derselbe bestätigte Verwechsler), also Fehlauslöser gesamt 2,1/h bei 95-%-Obergrenze 9,8/h. Gegen „vorher“ bei gleicher Stufe 2: Station v7 60 → 60 %, v9 50 → 80 %; Mobil v7 30 → 60 %, v9 40 → 50 %. Grenze: Die Testsegmente stammen aus derselben Sitzung und demselben Raum wie die Einlern-Segmente (n=10, 1 Segment = 10 Punkte), die Werte sind eher optimistisch; ob es in anderen Räumen trägt, zeigt nur eine neue Aufnahme.

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
| Stufe 2 | Hotword 2 | Hotword 2 (sicher); Hotword 3 + CAM++ 0,45 (gleiche 60 % sicher, aber 14,5 Fehlauslöser/h gesamt: kein Gewinn gegenüber Hotword 2) |
| Stufe 3 | optional 0,45 | 0,45 nur mit Stufe 2 |

Einheitliche Station-Schwellen wären zu streng für das Handy und umgekehrt: Die Station braucht den niedrigeren Stufe-1-Schwellwert (Pegel -10 bis -15 dB und Hall), der Kandidatenstrom steigt, Stufe 2 und 3 müssen ihn filtern.

## Empfehlung
- Stationsmodus nur als **optionaler, getrennter Modus** mit eigenem Schwellensatz: Stufe 1 = Modell v7 M0,5 (ca. 58 Kandidaten/h; Vorlagen T0,85 sind empfindlicher, liefern aber ca. 900 Kandidaten/h, sodass Stufe 2 fast dauernd läuft – für die Station am Netz denkbar, fürs Handy wegen Akku nicht), Stufe 2 = Parakeet Hotword 2 (Hotword 3 nur zusammen mit CAM++ 0,45), kein Boost ab 3,0 ohne Stufe 3. Das ergibt auf echten Daten (Station) 60 % sicher (Wilson 31–83 %) bei **Fehlauslösern gesamt (FA + Verwechsler) 2,1 bis 4,1/h** mit Hotword 2 bzw. 14,5/h mit Hotword 3 + CAM++ (n=10, ein Sprecher, 0,484 h Negativ: 1 Ereignis = 2,1/h, die Zahlen sind nur Größenordnungen), nicht die Abnahme (80 %, ≤ 2 FA/h).
- Stufe 3 (CAM++) nur als Fernseher-/Fremdstimmen-Filter einplanen; sie ersetzt keine Stufe 2.
- Persönliches Feintuning (Einlern-Wörter, ca. 1,5 min Rechenzeit) lohnt sich: Stufe 1 = feinabgestimmtes v9 oder v7 M0,5 + Hotword 2 ohne CAM++ ergibt 60 bis 80 % sicher (Station; v9 80 %: Wilson 49–94 %) bzw. 50 bis 60 % (Mobil) bei 0 FA/h und 2,1 Verwechslern/h, also 2,1 Fehlauslöser/h gesamt (95-%-Obergrenze 9,8/h); das Einlernen müsste die Feinabstimmung in der App ausführen (Klassifikator ist klein, 0,86 MB). Vor einem Einbau: echte Daten von mehr Sprechern und Räumen messen (siehe Grenzen). **Aufwand Einbau (Schätzung):** Parakeet ist mit WP103 vorhanden (Hotword als Konfiguration, ca. 1 PT), CAM++ als Modell und Sprecherprofil im Einlernen (28 MB, `EmbeddingPort`, ca. 3 PT), Stationsmodus mit eigenen Schwellen, Einstellung und Dauerbetrieb (Strom, Wake-Lock, ca. 4 PT), Gerätetest (ca. 2 PT).

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
| macOS-Systemstimmen (Apple-SLA; nur lokale Messung, keine Weitergabe der Audios) | Apple-Lizenzvereinbarung |
| Whisper medium (OpenAI) | MIT (nur zur Beschriftung der Negativ-Datei) |
| Piper-Stimmen `thorsten`, `kerstin` (Training WP58) | CC0 |
| Piper-Stimme `mls` (OpenSLR 94, Training WP58) | CC-BY 4.0 |
| Tatoeba (Text) | CC-BY 2.0 FR |
| echte Aufnahmen | eigene Aufnahmen des Maintainers, privat, nicht im Repo |

## Grenzen
- n=10 sichere Segmente, ein Sprecher, ein Raum, zwei Handys; 1 Segment = 10 Prozentpunkte. Der Rest (26 Segmente) ist nur ungefähr zugeordnet. Die Negativ-Datei hat nur 0,484 h und keine echte „Wendelin“-Fundstelle (die zwei vermeintlichen sind bestätigte Verwechsler); Auflösung 1 Ereignis = 2,1/h, 95-%-Obergrenze bei 0 Ereignissen 6,2/h. Die Abnahme ≤ 2 FA/h ist damit nicht belegbar.
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
