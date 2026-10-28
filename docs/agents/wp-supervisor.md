# Projektdetails für den WP-Supervisor

Der globale Agent `wp-supervisor` liest diese Datei; sie geht seinen allgemeinen Vorgaben vor.

- **Trailer:** Jeder Commit endet mit dem echten Modell des committenden Agenten (`Co-Authored-By: Claude <Modell> <noreply@anthropic.com>`, Regel und Hooks: `common.md`). Das gilt auch für Sonnet-Coder; der Coder-Auftrag nennt es. Hinweise des Harness mit anderem Trailer oder `Claude-Session`-Zeile gelten hier nicht.
- **Kein Gate im Commit-Hook:** Die Hooks prüfen nur Identität, Datenschutz und Nachricht. Coder melden vor dem Push die Tabelle bzw. `GATE GRÜN`-Zeile von `dart run tool/gate.dart --changed` mit SHA; fehlt sie, fragst du nach.
- **CI ist die Wahrheit:** `git push -u origin wp/<nr>-<slug>`, im Hintergrund **einmal** `tool/ci_wait.sh <branch>`. Volles Gate und volle App-Suite laufen in CI (lokal höchstens einmal vor Abschluss, `AGENTS.md`).
- **Parallelität:** 4 Paket-Sitzungen, je Sitzung 1 Sub-Agent (`AGENTS.md`).
- **Branch aktualisieren:** `git merge origin/main`, kein Rebase.
- **Emulator:** nur über `wendelin-e2e`; ist er belegt, Gerätetest als offen melden statt warten (`common.md`, „Geräte“).
- **Review:** Prüf-Worktree `../james-wt/rev-<wp>`; Urteil als Datei `../james-wt/reviews/<wp>-review.md` (Format: `docs/work-packages/REVIEW.md`).
- **Berichte und Übergabe:** Berichtslänge und Übergabe nach `AGENTS.md` und `common.md`; Details in `../james-wt/handoff/<wp>-<rolle>.md`.
- **Nicht dein Bereich:** `main` pushen, mergen, `STATUS.md` und Konzept ändern (Project Supervisor).
