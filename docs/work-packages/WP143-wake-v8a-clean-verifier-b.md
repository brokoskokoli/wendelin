# WP143 – Wake Word in der App: Modell v8a (Stimmenset clean) und Prüfer B als Stufe 2

**Zuordnung:** K110, K115 (zurückgestellt), Ergebnis WP137. Entscheidung Maintainer 2026-10-24: v8a (Stimmenset clean, Seed 1) als Stufe 1, Prüfer B (zentrierter Vorlagen-Vergleich je Frame) als Stufe 2, Parakeet (hw2) als Rückfall ohne Vorlagen. Beide Wörter („Wendelin“, „Hey Wendelin“) wecken, Direktannahme ab 0,999 bleibt. Danach Release-Kandidat für den App-Test.

## Lieferung WP137 (Spezifikation, Paritätsdaten: Commit im WP137-Branch, HEAD beim Orchestrator)
- **Stufe 1:** neues ONNX (ein Ausgang, Architektur, Fenster und Merkmale wie v8a, oww-0.5.1), 858 044 Bytes, SHA-256 `6b41519fa776f5d6c810d0323c64df86433e636d17ddb512d1a630acd9c2e58b`. Der Orchestrator lädt es als Release-Datei hoch. Im Katalog nur die neue URL und die SHA tauschen.
- **Prüfer B:**
  - Ausschnitt 1,9 s vor bis 0,85 s nach dem Entscheidungsfenster (Ende), Pegel auf Spitze 0,5, daraus oww-Melspektrogramm und Embedding (≈ 25 Frames × 96).
  - Vorlagen: Einlern-Aufnahmen ohne Polster, gleich normiert, als Folge (m × 96, m = 2–6). Der Zuschnitt muss exakt dem der Messung entsprechen.
  - Zentrieren je Frame mit `mu` (96, aus `wake_verifier_b_mu.json`, Feature-Version oww-0.5.1-mel-emb-1), danach auf Länge 1 normieren.
  - Score je Vorlage: Kosinus je Frame-Paar, gemittelt über die Vorlagenlänge, Maximum über den Versatz. Gesamtwert ist das Mittel der besten 3 Vorlagen.
  - Schwelle je Wort aus der Lieferung (HW 0,6815 für dieses Modell).
  - 6 Vorlagen je Wort reichen, gleichmäßig aus den Einlern-Aufnahmen gewählt (oder alle mit Top-3, gleichwertig).

## Inhalt
1. **Katalog:** Eintrag auf das neue Modell umstellen. Der Download-Ordner ist eine eigene Release-Datei, die Lizenzangaben bleiben wie bisher.
2. **Prüfer B** als `WakeVerifier` (Port wie hw2) in Dart; `mu` als generierte Konstante mit Feature-Version; Paritätstest gegen die gelieferten Python-Werte (Toleranz dokumentieren).
3. **Vorlagen für B:** Beim Einlernen zusätzlich die Frame-Folge im Zuschnitt der Messung speichern, je Wort (W, HW). Die Migration von Altvorlagen ohne Folge führt zu „Neu einlernen für den Prüfer“; bis dahin gilt der Rückfall hw2. Mit WP142 abstimmen (Einlernen, `matchesHeyWakeWord` strict/lenient): erst nach dem WP142-Merge rebasen.
4. **Ablauf Stufe 2:** Liegen Vorlagen vor, entscheidet B im Band (0,98–0,999). Sonst prüft hw2 wie bisher. Die Direktannahme ab 0,999 bleibt (WP141-Halten).
5. **Log:** `wake-decision … verifier=b|hw2 score=… thr=…`, ohne Audio und ohne Text.
6. **Speicher:** Wird hw2 nicht gebraucht (B aktiv), lädt die App Parakeet nicht für Stufe 2 vor.

## Abnahmekriterien
- [ ] Paritätstest Dart gegen Python grün, Tests mit Mutationsbeleg (Schwelle, Zentrierung, Top-3, Versatz-Maximum).
- [ ] E2E auf dem Emulator: Einlernen, dann Wake über B (`verifier=b`); ohne Vorlagen Rückfall auf hw2; Modell-Download mit SHA-Prüfung (Release-Datei).
- [ ] Rechenzeit je B-Prüfung und Speicher am Emulator gemessen und berichtet.
- [ ] Gate `--changed`, CI grün, Review FREIGABE, Gerätetest-Block ins laufende Protokoll.

## Zweifel (aus WP137)
- Die B-Schwelle ist unsicher: Auf der Trainingsseite nimmt sie ~4 % der Positiven an, im Prüf-Split ~60 %.
- B trennt „Wendelin“ nicht von „Hey Wendelin“ (deshalb K115 zurückgestellt).
- Die Prüf-Rufe sind nur etwa 60 unabhängige.

## Parallel-Hinweise
- WP142 (Einlernen) läuft: gleiche Wake-Dateien, Merge erst nach WP142. WP137 rechnet nur in `tool/train_wake_word/` und `docs/notes/`. Kein Wort zu Lizenzen oder Stimmenwahl ins Repo.
