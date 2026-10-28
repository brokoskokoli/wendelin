# WP109 – Leitplanken: eine Regelquelle, main schützen, Größen-Ratsche, Aufräumskript (`AGENTS.md`, `docs/agents/`, `.claude/agents/`, `tool/`, CI)

**Zuordnung:** M5 (Prozess). Wunsch Maintainer 2026-10-19, Grundlage ist die Architekturanalyse vom 19.10. (Artifact „Architekturanalyse“, claude.ai/code/artifact/263afa70-af82-4d53-8c8e-2accc713247f).

Teile außerhalb des Repos und alles, was wirklich löscht, erledigt der Orchestrator selbst: GitHub-Ruleset, Sicherung und Entfernen von `james-device-test`, Aufräumen von handoff und Branches, Skill `development-supervisor`, `~/.claude/agents/wp-supervisor.md` und die untracked `.claude/settings.local.json` (Teil j). Das Paket ändert nur das Repo. Neue Skripte, die löschen, werden nur in Test-Repos ausgeführt.

## Inhalt

### 1. Eine Regelquelle
- `AGENTS.md` ist die einzige Regelquelle. `CLAUDE.md` bindet sie per `@AGENTS.md` ein und enthält nur Claude-Spezifisches (höchstens etwa 10 Zeilen).
- `.claude/agents/*.md` und `docs/agents/*.md` enthalten nur noch die Rolle und Verweise, keine kopierten Regeln. Identität und Trailer stehen nur noch in `docs/agents/common.md`, `AGENTS.md` verweist darauf.
- Widersprüche beheben:
  - a) `.claude/agents/wendelin-coder.md:16,29` (volles Gate, „nie pushen“) → lokal `--changed`, `wp/*`-Branch pushen, `tool/ci_wait.sh`, Abschluss „CI GRÜN“ mit Lauf-URL.
  - b) `.claude/agents/wendelin-coder.md:21`: toten lokalen Pfad entfernen.
  - c) `docs/work-packages/REVIEW.md:7,10,16-26` → kein lokales Gate (CI-Lauf prüfen), 3–10 Mutationen, Urteil FREIGABE/NACHBESSERN mit Blocker/Muss/Soll, wie in `wendelin-reviewer.md`.
  - d) `AGENTS.md:25` → `tool/t.sh` statt rohem `flutter test`/`dart test`; check_flaky-Regel ergänzen (keine Wanduhr-Asserts, kein `runAsync(Future.delayed)`, Bestand in `tool/flaky_allowlist.yaml` nur abbauen).
  - e) Übergabegrenze überall ~60 Werkzeugaufrufe bzw. ~120k Tokens.
  - f) Belegter Emulator: eine Regel, „melden, nicht warten“. Die Zuteilung übernimmt der Orchestrator.
  - g) Parallelität: eine Zahl für Paket-Sitzungen (aktuell bis 4) und eine für Sub-Agenten je Sitzung (1), an einer Stelle.
  - h) `CLAUDE.md:6` „ENGINEERING.md vor jeder Codeänderung“ → „bei Bedarf den passenden Abschnitt“.
  - i) `docs/agents/integrator.md` auf `tool/merge_wp.sh` umschreiben oder streichen; `docs/agents/e2e.md` kurz anlegen oder den Verweis entfernen.
- `check_docs` (`tool/src/doc_check.dart:9`, `checkedDocs`) prüft zusätzlich `AGENTS.md`, `CLAUDE.md`, `docs/agents/`, `.claude/agents/` und `docs/work-packages/REVIEW.md`.

### 2. main schützen
- `tool/merge_wp.sh` verweigert den Merge ohne grünen CI-Lauf (Workflow gate) auf genau dem Branch-SHA (`gh run list -c <sha>`). Für Tests ist der Befehl per Umgebungsvariable ersetzbar, wie `MERGE_WP_GATE`.
- Ein `pre-push`-Hook in `tool/hooks/` lehnt Pushes auf `main` ab. Erlaubt sind nur der Push nach `merge_wp.sh` und reine Doku-/Status-Commits des Orchestrators, beides über eine explizite Umgebungsvariable. Die Hook-Einrichtung (`core.hooksPath`) wird wie bei den bestehenden Hooks dokumentiert. Der Push-Schritt des Orchestrators (Merge, Status-Commit, Gate, Push) muss weiter in einem Befehl gehen.
- Ein CI-Schritt prüft Autor, Committer und Trailer aller Commits `merge-base..HEAD`: nur die noreply-Identität, genau ein `Co-Authored-By`-Trailer, keine `Claude-Session`-Zeile. Merge-Commits von GitHub selbst gibt es nicht (kein PR-Merge).

### 3. Größen-Ratsche
- Die heutigen Größenwarnungen (rund 119) kommen als Baseline in eine Allowlist (wie `tool/flaky_allowlist.yaml`). Eine neue Warnung ist rot, bestehende dürfen nur schrumpfen. Nach dem Schrumpfen meldet das Gate die veraltete Zeile.
- Dasselbe gilt für `// ignore:` und `// ignore_for_file:` mit einem Budget je Regel.

### 4. Aufräumskript `tool/cleanup_wt.sh <wp|branch>`
- Standard ist `--dry-run`, gelöscht wird nur mit `--apply`.
- Nach einem Merge entfernt es den Worktree `../james-wt/<wp>`, den Prüf-Worktree `rev-<wp>`, den lokalen und den entfernten Branch sowie `handoff/<wp>-*` (Session-Prompt, Logs). Andere Branches (z. B. `wp/43-spike-attestation`) und fremde Dateien fasst es nicht an.
- Gemergt heißt: Merge-Commit auf main enthält den Branch, oder er ist per Squash gemergt (Patch-ID-Vergleich oder Liste). Nicht gemergte Branches löscht es nicht.
- `merge_wp.sh` ruft es am Ende auf und ersetzt damit sein bisheriges Aufräumen.

## Abnahmekriterien
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE.
- [ ] Tests (Shell-Selbsttests wie bei `merge_wp.sh`) belegen:
  - `merge_wp.sh` lehnt bei rotem und bei fehlendem CI-Lauf ab und mergt bei grünem.
  - `pre-push` lehnt einen main-Push ohne Variable ab und lässt `wp/*` durch.
  - Eine neue Größenwarnung und ein neues `// ignore:` über Budget sind rot.
  - `cleanup_wt.sh` löscht ohne `--apply` nichts, mit `--apply` nur gemergte Branches (auch per Squash) und nur die genannten Pfade.
  - Der CI-Identitätsschritt ist rot bei fremdem Autor, zweitem Trailer und Session-Zeile.
- [ ] `grep` nach den alten Widersprüchen (volles Gate lokal, „nie pushen“, `ai/james/app`, `flutter test test/`, abweichende Übergabegrenzen, „wartet“ beim Emulator) findet in `AGENTS.md`, `CLAUDE.md`, `docs/agents/`, `.claude/agents/` und `REVIEW.md` nichts mehr.
- [ ] `check_docs` deckt die neuen Dateien ab (ein toter Pfad dort wird rot).
- [ ] `CLAUDE.md` höchstens etwa 10 Zeilen.

## Parallel-Hinweise
- Gleichzeitig laufen WP93 (Wake Word im Chat, App) und WP108 (Fehlerart, Integrations-Specs, l10n). WP108 kann `tool/size_allowlist.yaml` ändern: die Baseline nach `git merge origin/main` kurz vor dem Push neu erzeugen.
- `tool/merge_wp.sh`, `tool/hooks/` und `.github/workflows/gate.yml` ändert nur dieses Paket.
