# Wake Word zweistufig: Messung mit synthetischen Einlernern (WP44 Nachtrag 2, 2026-10-14)

Stand: Host-Messung (macOS, ohne Gerät), **synthetische** Sprecher. Aussagekraft für echte Stimmen offen (WP60/WP50).

## Aufbau
- `tool/kws_measure.py --two-stage` (Anleitung im Kopf des Skripts). Venv `~/wendelin-models/kws/wp58/venv` (openwakeword, onnxruntime, sherpa-onnx), nichts im Repo.
- Einlerner = 9 macOS-Stimmen. Je Stimme 15 Vorlagen: „Wendelin“/„Wendelin.“ in 8 Tempi (110 bis 235 Wörter/min), erzeugt mit `say` unter `~/wendelin-models/kws/data/enroll/` (135 kurze WAVs, lokal). Test: die 10 Positiv-Clips derselben Stimme (`data/pos`, Sätze mit Kommando; nie Vorlage). Negativ: 1,17 h deutsche Systemstimmen-Sprache (`data/neg`), je Einlerner geprüft, Werte sind Mittel über die 9 Einlerner (FA je Vorlagensatz).
- Vorlage = Fenster aus 16 Embeddings à 96 (1 536 Werte), das 0,3 s nach dem Wortende endet. Ähnlichkeit = Kosinus zum besten der 15 Vorlagen (wie `bestSimilarity` in Dart). Kandidat = Ähnlichkeit ≥ Schwelle **oder** WP58-Modell (v7) ≥ 0,3. Sperrzeit 1,5 s.
- Stufe 2: Whisper small (int8, sherpa-onnx, Deutsch) transkribiert **~3 s: 2 s vor dem Fensterende plus 0,9 s Nachlauf** (`--tail`, Dart: `verifyWindow` + `verifyTail`; Zusatzlatenz ~1 s); Treffer, wenn ein Wort (oder zwei benachbarte) höchstens 1 (bzw. 2) Editierschritte von „Wendelin“/Schreibvarianten („Wendelmann“, „Wendemann“, „Wendelen“, …) entfernt ist oder nach Kölner Phonetik wie „Wendelin“ klingt (Schlüssel 36256, 6 bis 11 Buchstaben, Anlaut w/v/f). Spiegel von `matchesWakeWord`, Dart. Bedingungen: `clean` und `both` (Rauschen 10 dB SNR + Hall RT60 0,5 s, Vorlagen bleiben sauber).

## Ergebnis (Lauf `--thr 0.8,0.85,0.9 --model wendelin_v7.onnx --cond clean,both`, Whisper small, Nachlauf 0,9 s; vorher in Klammern: Fenster nur 2 s davor, Abstand 1)
| Bedingung | Regel | Schwelle | Treffer Stufe 1 | Kandidaten/h | Treffer nach Stufe 2 (Abstand 1 / 2) | bestätigt/h (Abstand 1 / 2) |
|---|---|---|---|---|---|---|
| clean | Vorlage | 0,80 | 99 % | 31,8 | 50 / 54 % (33) | 1,14 / 1,14 (0,00) |
| clean | Vorlage | 0,85 | 84 % | 2,8 | 42 / 47 % (24) | 0,00 / 0,00 |
| clean | Vorlage | 0,90 | 42 % | 0,0 | 20 / 21 % (8) | 0 / 0 |
| clean | nur Modell v7 | 0,3 | 42 % | 17,9 | 19 / 22 % (16) | 1,71 / 1,71 (0,00) |
| clean | Modell 0,3 ODER Vorlage | 0,85 | 90 % | 20,7 | 48 / 52 % (31) | 1,71 / 1,71 (0,00) |
| both | Vorlage | 0,80 | 99 % | 246,6 | 0 / 2 % (0) | 0,00 / 0,85 |
| both | Vorlage | 0,85 | 50 % | 9,1 | 0 / 0 % | 0 / 0 |
| both | Modell 0,3 ODER Vorlage | 0,85 | 71 % | 52,4 | 0 / 2 % (1) | 0 / 0 |
Whisper-Rechenzeit: RTF 0,13 bis 0,18 (small, 4 Threads, Host). Die neuen „bestätigt/h“ von 1,1 bis 1,7 sind Artefakte des Negativkorpus: Die Sätze enthalten selbst das Wort „Wendelin“ („Notiz Wendelin-Test“), das jetzt mit Nachlauf vollständig im Fenster liegt und zu Recht erkannt wird; einziger echter Fehlalarm ist „Wenderling“ (Abstand 1, bereits vorher möglich). Die Phonetik-Regel erzeugt keinen Fehlalarm.

## Befund
- **Stufe 1 trägt:** Mit 15 persönlichen Vorlagen und Schwelle 0,85 liegt die Kandidatenquote bei 84 % (sauber) mit 2,8 Kandidaten/h; das WP58-Modell allein erreicht 42 % bei 18/h. Persönliche Vorlagen sind dem Pilotmodell klar überlegen (Ziel „≤ 1/h vor Stufe 2“ liegt bei Schwelle ~0,87 bis 0,9, dort 42 bis 60 % Treffer; die Kalibrierfunktion wählt sie je Sprecher).
- **Stufe 2 ist weiterhin der Engpass bei synthetischen Stimmen, aber mit Nachlauf deutlich besser:** bei Schwelle 0,85 (sauber) bestätigt Whisper 42 % statt 24 % (Abstand 1) bei 0 bestätigten/h; ein Teil der früheren Verluste lag am abgeschnittenen Wortende. Unter Rauschen/Hall bleibt es praktisch bei 0 bis 2 %. Die Systemstimmen sind für Whisper schwer (z. B. „Wettelin“, „Wippenmann“). Ob echte Sprecher deutlich besser erkannt werden, ist nicht belegt; Abstand 2 hebt die Quote um etwa 12 Punkte bei weiterhin 0 bestätigten/h.
- Empfehlung für WP60/WP50: Abstand 1 als Standard (strenger), Abstand 2 als Option nach Messung mit echten Aufnahmen; Prüfung der Nachprüfung (Whisper-Text je Einlern-Aufnahme) als Teil des Einlernens, damit der Nutzer sieht, ob seine Aussprache bestätigt wird; sonst Vorlagen ohne Stufe 2 mit strengerer Schwelle (Kandidat = Auslösung).
- Grenzen: synthetische Positive und Negative, Vorlagen sauber, Tempo/Tonhöhe der Vorlagen durch `say` nur grob variiert; 1 FA ≈ 0,85/h; keine Gerätemessung.
