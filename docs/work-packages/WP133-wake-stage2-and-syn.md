# WP133 – Wake Word: Nutzen von Stufe 2, v8a gegen v8c nur synthetisch

**Zuordnung:** K101, K105, Ergebnis WP130 (`docs/notes/wake-word-compare.md`, Abschnitt v8). Entscheidung Maintainer 2026-10-22: Stufe-2-Analyse sofort mit niedriger Last, Training v8a-syn/v8c-syn im freigegebenen Zeitfenster, danach Test gegen alle Aufnahmen des Maintainers.

## Anlass
- In WP130 senkt Stufe 2 (Parakeet-Hotword `hw2`) die Treffer von v8a deutlich (z. B. Huawei „Hey Wendelin“ 93 % → 40 %, „Wendelin“ 80 % → 60 %). Der Nutzen ist nur bei Verwechslern belegt (5–8 % → 1–6 %); auf der echten Negativ-Aufnahme (0,61 h je Gerät) hatte Stufe 1 schon kaum Fehlalarme. Kosten und Nutzen von Stufe 2 sind nicht gezielt untersucht.
- v8a/v8b enthalten Aufnahmen des Maintainers (Huawei B1–3). Ein Vergleich ohne diese Aufnahmen zeigt, wie gut das Modell für fremde Stimmen ist, und erlaubt die Prüfung auf **allen** Aufnahmen (Huawei B1–6, handy2 B1–6).

## Inhalt

### A. Stufe-2-Analyse (ohne Training, niedrige Last)
- Für v7 und v8a bei der Stufe-1-Schwelle des Arbeitspunkts (2 FA/h): Zähle getrennt
  1. echte Rufe, die Stufe 1 erkennt und Stufe 2 verwirft, je mit dem Text, den Parakeet erkannt hat (nur lokal, ins Repo nur Zählungen und Kategorien wie „Schreibvariante“, „abgeschnitten“, „leer“);
  2. Fehlalarme (echt, syn, FLEURS) und Verwechsler-Ereignisse, die Stufe 1 auslöst und Stufe 2 herausfiltert.
- Prüfe, ob eine tolerantere Stufe 2 die verlorenen Treffer zurückholt, ohne die gefilterten Fehlalarme zurückzubringen: Schreibvarianten (z. B. „Wendeling“, „Wendelien“), phonetischer Abgleich bzw. Editierabstand, längerer Ausschnitt (Nachlauf/Vorlauf). Jede Variante mit derselben Kreuzauswahl und Wilson-Intervallen wie WP130.
- Ergebnis: Empfehlung, ob Stufe 2 im Stationsmodus Standard bleibt, tolerant wird oder nur bei unsicheren Stufe-1-Werten (Band unter der Schwelle) greift.

### B. v8a-syn gegen v8c-syn (Training nur im vom Orchestrator freigegebenen Zeitfenster)
- Gleiche Pipeline wie WP130 (`tool/train_wake_word/run_v8.sh`), aber **ohne echte Positive** (neuer Schalter, z. B. `REAL_POS=0`; Standard bleibt wie WP130). Vorhandene Daten unter `~/wendelin-models/kws/wp130/gen` wiederverwenden, keine neuen Downloads nötig.
- Zwei Läufe: `a-syn` (hidden 128, 5000 Schritte, Seed 1) und `c-syn` (hidden 256, 5000 Schritte, Seed 1), nacheinander, `nice`, Threads begrenzt; vorher `memory_pressure` prüfen (freier Anteil ≥ 30 %, sonst nicht starten und melden).
- Messung mit `v8_measure.py` auf **allen** Blöcken (Huawei B1–6, handy2 B1–6), Stufe 1 und Stufe 2 (inkl. der besten Variante aus A), Vergleich mit v7 und v8a.
- Ergebnis: Wie viel des v8a-Vorsprungs aus der Sprecheranpassung kommt; ob das breitere Netz (c) etwas bringt; Empfehlung, welches Modell WP129 nimmt.

## Abnahmekriterien
- [ ] Neue Messung reproduzierbar per Skript unter `tool/train_wake_word/` mit Python-Tests (wie WP130), Schalter ohne echte Positive mit Test.
- [ ] Notiz `docs/notes/wake-word-compare.md`, neuer Abschnitt „Stufe 2 und v8-syn (WP133)“: Tabellen nur mit Zahlen, keine Transkripte, keine Namen, keine absoluten Pfade.
- [ ] Klare Empfehlung zu Stufe 2 (Standard / tolerant / nur Band) und zum Modell für WP129.
- [ ] Kein Modell mit Aufnahmen des Maintainers außer dem Trainings-Split (K101); a-syn/c-syn enthalten keine.
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE. Kein Gerätetest, kein Emulator.

## Parallel-Hinweise
- WP126 und WP125 ändern App-Code (Wake/Stopp); WP133 berührt nur `tool/train_wake_word/` und `docs/notes/`. Keine Konflikte erwartet.
- Rechner ist knapp (Swap fast voll): Teil A mit `nice -n 10` und höchstens 2 Threads; Teil B erst nach Freigabe durch den Orchestrator.
