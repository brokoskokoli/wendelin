# WP98 – Konfliktarm parallel arbeiten (l10n-Tooling, Testlisten, Goldens, Doku, Merge-Skript)

**Zuordnung:** M5 (Beschleunigung, Wunsch Maintainer 2026-10-18: Konfliktpunkte im Code entschärfen). Grundlage: `docs/notes/dev-speedup-analysis.md` §6, §7.

## Inhalt
1. **l10n-Fragmente** (zusammen mit dem Abschluss von WP79): ARB-Dateien je Bereich (`app/lib/l10n/<bereich>/<bereich>_de.arb` …) plus `tool/l10n_merge.dart`, das die Gesamt-ARB erzeugt; Gate prüft, dass Erzeugtes aktuell ist. Prüfen, ob die generierten Dateien statt eingecheckt im Build erzeugt werden können.
2. **Testlisten aus der Registry** statt fester Zahlen/Listen (`trust_registry_test`, `schemas_test`, Integrationen-Zähler, `wiring_test`, `registry_probe_test`); Golden `integrationen.png` mit fester Fake-Liste.
3. **Doku:** `docs/ARCHITECTURE.md` als kurzer Index plus Bereichsdateien (`docs/architecture/<bereich>.md`); Gerätetests je WP als eigene Datei (`docs/testing/m5/<wp>.md`) mit erzeugtem Index; Tabellen, die aus Code ableitbar sind, erzeugen und in `check_docs` prüfen.
4. `tool/merge_wp.sh <branch>`: Identität aller Commits prüfen, `--no-ff`-Merge, `--changed`-Gate, Worktree/Branch aufräumen (Push separat).

## Abnahmekriterien
- [ ] Zwei Probe-Branches, die je eine Integration mit Texten, Trust-Eintrag und Doku-Zeile hinzufügen, mergen ohne manuellen Konflikt.
- [ ] Gate erkennt veraltete erzeugte Dateien; Briefings verweisen auf den ARCHITECTURE-Index statt den Volltext. Gate grün.
