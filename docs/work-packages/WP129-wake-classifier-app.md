# WP129 – Trainiertes Wake-Word-Modell (v8a) in der App, zweistufig

**Zuordnung:** K80 (Stationsmodus), Ergebnisse WP106/WP111/WP121 (K83, K98). Entscheidung Maintainer 2026-10-22: v7 in die App – Standard im Stationsmodus, auf dem Handy als wählbare Variante neben dem Vorlagen-Vergleich.

**Nachtrag K105 (WP130):** Statt v7 kommt **v8a** in die App (`~/wendelin-models/kws/wp130/out/wendelin_wp130_a.onnx`, SHA-256 `bfeb939d9e50c4913b27e4d082e5d620e3967af6c2603666e6bc40b30a06997d`); es enthält Aufnahmen des Maintainers nur aus dem Trainings-Split (K101) und darf veröffentlicht werden. Schwellen aus `docs/notes/` (Abschnitt v8) übernehmen. Vor dem Release-Asset die M-AILABS-Lizenz belegen. Wo unten „v7“ steht, gilt v8a.

## Ausgangslage
- App heute: Merkmalsmodelle (openWakeWord mel + embedding, Katalog `wake-features`) + Ähnlichkeit zu persönlichen Vorlagen (K31) → Bestätigung per STT. Platzhalter `wake-classifier-wendelin` (`packages/wendelin_voice/lib/src/models/speech_model_catalog.dart:436`).
- Gemessen ist der Weg v7 (Stufe 1, M≈0,3–0,5) + persönliches Feintuning + Parakeet-v3-Hotword (Stufe 2) + optional CAM++ (K80). Notizen `docs/notes/wake-word-model-2026-10-14.md`, `wake-word-station-spike.md`, `wake-word-compare.md`.

## Inhalt
1. **Modell veröffentlichen:** nur das **Basismodell v7** (trainiert auf synthetischen Stimmen/CC-BY-Daten, Lizenzen laut `wake-word-model-2026-10-14.md` prüfen und Namensnennung in der App-Lizenzseite ergänzen). **Nie** ein mit Aufnahmen des Maintainers feingetuntes Modell (`ft_v7*`) veröffentlichen. Hosting als GitHub-Release-Asset im Repo (Orchestrator lädt hoch, Coder liefert Datei-Pfad + SHA-256), Katalogeintrag mit SHA-256.
2. **Engine:** Klassifikator-Stufe 1 auf den vorhandenen Merkmalen (gleiche Fenster wie die Messung, Parität mit `tool/kws_measure.py` per Fixture-Test), Schwelle je Modus (Handy/Station) aus K80/K98, danach die vorhandene Stufe 2.
3. **Persönliches Feintuning** beim Einlernen auf dem Gerät (Aufnahmen bleiben verschlüsselt lokal), so wie in WP106 gemessen, oder begründet einfacher (z. B. nur letzte Schicht / Kalibrierung) – Abweichung melden.
4. **Auswahl:** Einstellung „Erkennung: Vorlagen | trainiertes Modell“ (Handy, Standard bleibt Vorlagen bis zum Gerätetest); Stationsmodus nutzt das Modell standardmäßig. „Stopp“ bleibt beim Vorlagen-Weg.
5. Logzeilen für Kandidat/Bestätigung je Stufe, damit der Gerätetest FA/h und Treffer zählen kann; Gerätetest-Block `docs/testing/m5/wp129.md`.

## Abnahmekriterien
- [ ] Paritätstest: App-Scores = Messskript-Scores auf Fixture (Toleranz begründen); Mutationsbeleg.
- [ ] Download mit SHA-Prüfung, Fehlerfall sauber; Lizenzhinweis.
- [ ] E2E (Emulator, nach Freigabe): `wake_chat_e2e`/Wake-E2E mit Modus „trainiertes Modell“ grün.
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE; RAM/CPU-Notiz am Emulator.
- [ ] Offen für den Maintainer: längere Negativ-Aufnahme mit Fernseher (≥ 1,5 h) zur Schwellen-Feinjustierung.
