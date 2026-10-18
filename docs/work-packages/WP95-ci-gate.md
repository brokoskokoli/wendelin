# WP95 – CI als volles Gate (`.github/workflows/`, `app/test/support/golden_tolerance.dart`, Doku, Briefings)

**Zuordnung:** M5 (Beschleunigung, Entscheidung Maintainer 2026-10-18: Coder dürfen `wp/*`-Branches pushen). Grundlage: Analyse `docs/notes/dev-speedup-analysis.md` §1, §4.

## Inhalt
1. CI ist seit 2026-10-14 rot: 7 Goldens weichen auf dem ungepinnten `macos-latest` um 2876–3381 Pixel ab (Schwelle `ciGoldenMaxPixels = 2000`). macOS-Runner pinnen, Goldens nur dort; Toleranz begründet anpassen oder Goldens auf dem gepinnten Runner neu erzeugen (Golden-Update-Workflow mit Artefakt).
2. Ubuntu-Jobs: Matrix je Paket, App-Tests in Shards (ohne Goldens) mit di-Abdeckung, Rust-Job (fmt, clippy, test, frb-Prüfung, deny), kotlin-unit, check_*-Schritte; Caches für pub, cargo, gradle.
3. Auslösen bei Push auf `main` und `wp/*`; `tool/ci_wait.sh <branch>` wartet mit einem `gh run watch` und gibt eine kompakte Zusammenfassung (Job, Ergebnis, bei Rot die letzten Zeilen) aus.
4. Doku und Briefings: lokal `--changed`, volles Gate in CI vor dem Merge; Agenten pushen ihren Branch und warten mit `ci_wait.sh` (eine Meldung).

## Abnahmekriterien
- [ ] 3 grüne CI-Läufe auf main in Folge; Wandzeit ≤ 10–12 min.
- [ ] Push eines `wp/*`-Branches löst CI aus; ein absichtlich roter Golden bzw. Test fällt auf (Probe-Branch, danach gelöscht).
- [ ] CLAUDE.md, ENGINEERING.md, docs/agents/* angepasst. Keine Secrets in CI (Live-Tests bleiben übersprungen).
