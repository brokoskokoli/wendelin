# Arbeitspakete

Zweck: Ordner der offenen Arbeitspakete (`WPnn-<slug>.md`, Abnahmekriterien je Paket) und des Prüfprotokolls `REVIEW.md`. Der Umsetzungsstand aller Meilensteine und Pakete steht in **`STATUS.md`** (maßgeblich); einen Index pflegen wir hier nicht.

- Ablauf je Paket: eigener Branch `wp/<nr>-<slug>` im eigenen Worktree, Umsetzung durch einen Coder, Prüfung durch einen unabhängigen Reviewer nach `REVIEW.md`, Merge nach bestandenem Review und grünem CI (Rollen: `docs/agents/`).
- Paketgröße (Review-Einheit ca. 1 500 Zeilen geänderter Produktivcode, Messung, Schnitt in Teil-Merges) und Dateigrößen: `docs/ENGINEERING.md`, Abschnitt „Größen“. Merge-Hotspots: ebenda.
- Paketvorlage: Kopf „Zuordnung“, dann „Inhalt“ und „Abnahmekriterien“ (Beispiele: jedes offene Paket in diesem Ordner).
- Erledigte Pakete (WP01–WP60, Stopp-Wort/Gesprächston-Pakete), alte Meilensteinpläne (M2–M5) und alte Gerätetest-Listen sind gelöscht; der Verlauf steht in Git (`git log -- docs/work-packages/<datei>`), die Entscheidungen in Konzept, ADR und STATUS.
- Nummern ohne Paketdatei: WP00 (Gerüst, gleich im ersten Commit), WP34, WP69, WP139 und WP144 (nie vergeben), WP168 (erledigt laut STATUS, ohne Paketdatei).
- Meilensteinplan Ausbau: `M6-PLAN.md`.
