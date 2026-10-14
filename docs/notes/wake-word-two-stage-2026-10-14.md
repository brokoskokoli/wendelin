# Wake Word zweistufig: Messung mit synthetischen Einlernern (WP44 Nachtrag 2, 2026-10-14)

Stand: Host-Messung (macOS, ohne Gerät), **synthetische** Sprecher. Aussagekraft für echte Stimmen offen (WP60/WP50).

## Aufbau
- `tool/kws_measure.py --two-stage` (Anleitung im Kopf des Skripts). Venv `~/wendelin-models/kws/wp58/venv` (openwakeword, onnxruntime, sherpa-onnx), nichts im Repo.
- Einlerner = 9 macOS-Stimmen. Je Stimme 15 Vorlagen: „Wendelin“/„Wendelin.“ in 8 Tempi (110 bis 235 Wörter/min), erzeugt mit `say` unter `~/wendelin-models/kws/data/enroll/` (135 kurze WAVs, lokal). Test: die 10 Positiv-Clips derselben Stimme (`data/pos`, Sätze mit Kommando; nie Vorlage). Negativ: 1,17 h deutsche Systemstimmen-Sprache (`data/neg`), je Einlerner geprüft, Werte sind Mittel über die 9 Einlerner (FA je Vorlagensatz).
- Vorlage = Fenster aus 16 Embeddings à 96 (1 536 Werte), das 0,3 s nach dem Wortende endet. Ähnlichkeit = Kosinus zum besten der 15 Vorlagen (wie `bestSimilarity` in Dart). Kandidat = Ähnlichkeit ≥ Schwelle **oder** WP58-Modell (v7) ≥ 0,3. Sperrzeit 1,5 s.
- Stufe 2: Whisper small (int8, sherpa-onnx, Deutsch) transkribiert die letzten 2 s bis zum Fensterende; Treffer, wenn ein Wort (oder zwei benachbarte) höchstens 1 (bzw. 2) Editierschritte von „Wendelin“/Varianten entfernt ist (Spiegel von `matchesWakeWord`, Dart). Bedingungen: `clean` und `both` (Rauschen 10 dB SNR + Hall RT60 0,5 s, Vorlagen bleiben sauber).

## Ergebnis (Auszug, vollständige Tabelle: Lauf `--thr 0.8,0.85,0.9 --model wendelin_v7.onnx --cond clean,both`)
| Bedingung | Regel | Schwelle | Treffer Stufe 1 | Kandidaten/h | Treffer nach Stufe 2 (Abstand 1 / 2) | bestätigt/h (Abstand 1 / 2) |
|---|---|---|---|---|---|---|
| clean | Vorlage | 0,80 | 99 % | 31,8 | 33 / 48 % | 0,00 / 0,00 |
| clean | Vorlage | 0,85 | 84 % | 2,8 | 24 / 36 % | 0,00 / 0,00 |
| clean | Vorlage | 0,90 | 42 % | 0,0 | 8 / 11 % | 0 / 0 |
| clean | nur Modell v7 | 0,3 | 42 % | 17,9 | 16 / 20 % | 0,00 / 0,85 |
| clean | Modell 0,3 ODER Vorlage | 0,85 | 90 % | 20,7 | 31 / 42 % | 0,00 / 0,85 |
| both | Vorlage | 0,80 | 99 % | 246,6 | 0 / 1 % | 0,00 / 0,57 |
| both | Vorlage | 0,85 | 50 % | 9,1 | 0 / 0 % | 0 / 0 |
| both | Modell 0,3 ODER Vorlage | 0,85 | 71 % | 52,4 | 1 / 1 % | 0 / 0 |
Whisper-Rechenzeit: RTF 0,17 (small, 4 Threads, Host); base 0,05. Zusatzlauf mit Whisper base, Abstand 1, Schwelle 0,8 clean: Stufe 2 nur 14 %.

## Befund
- **Stufe 1 trägt:** Mit 15 persönlichen Vorlagen und Schwelle 0,85 liegt die Kandidatenquote bei 84 % (sauber) mit 2,8 Kandidaten/h; das WP58-Modell allein erreicht 42 % bei 18/h. Persönliche Vorlagen sind dem Pilotmodell klar überlegen (Ziel „≤ 1/h vor Stufe 2“ liegt bei Schwelle ~0,87 bis 0,9, dort 42 bis 60 % Treffer; die Kalibrierfunktion wählt sie je Sprecher).
- **Stufe 2 ist der Engpass bei synthetischen Stimmen:** bestätigt/h ist praktisch 0 (Falschauslösungen gibt es nach Stufe 2 so gut wie nie, auch 0,85/h nur mit Abstand 2), aber Whisper erkennt „Wendelin“ in den Systemstimmen nur zu 24 bis 48 % und unter Rauschen/Hall praktisch nicht (0 bis 1 %). Die Systemstimmen sind für Whisper schwer (z. B. „Wettelin“, „Wippenmann“). Ob echte Sprecher deutlich besser erkannt werden, ist nicht belegt; Abstand 2 hebt die Quote um etwa 12 Punkte bei weiterhin 0 bestätigten/h.
- Empfehlung für WP60/WP50: Abstand 1 als Standard (strenger), Abstand 2 als Option nach Messung mit echten Aufnahmen; Prüfung der Nachprüfung (Whisper-Text je Einlern-Aufnahme) als Teil des Einlernens, damit der Nutzer sieht, ob seine Aussprache bestätigt wird; sonst Vorlagen ohne Stufe 2 mit strengerer Schwelle (Kandidat = Auslösung).
- Grenzen: synthetische Positive und Negative, Vorlagen sauber, Tempo/Tonhöhe der Vorlagen durch `say` nur grob variiert; 1 FA ≈ 0,85/h; keine Gerätemessung.
