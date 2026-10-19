# WP110 – Agenten-Leitplanken und CI-Entlastung (`.claude/`, `tool/`, `docs/agents/`, CI)

**Zuordnung:** M5 (Prozess). Wunsch Maintainer 2026-10-19, Grundlage ist die Architekturanalyse vom 19.10. (Maßnahmen 3, 4, 6, 9; Artifact claude.ai/code/artifact/263afa70-af82-4d53-8c8e-2accc713247f). Start erst nach dem Merge von WP109 (baut auf der einen Regelquelle, dem pre-push-Hook und `merge_wp.sh` mit CI-Pflicht auf).

Teil B (außerhalb des Repos: `~/.claude/agents/wp-supervisor.md`, Vorlage `session-prompt.md` im Skill) macht der Orchestrator.

## Inhalt

### 1. Claude-Code-Hooks im Projekt
- Eingecheckt in `.claude/settings.json`, Skripte unter `tool/hooks/claude/`.
- **Zuerst** anhand der Claude-Code-Doku prüfen, welche Felder die Hook-Eingabe hat (z. B. `session_id`, `agent_id`, `transcript_path`, `tool_name`, `tool_input`), und wie Ablehnung bzw. `additionalContext` zurückgegeben werden. Das Ergebnis kommt kurz in den Bericht.
- **PreToolUse auf Bash** lehnt mit kurzer Begründung als Rückmeldung ab:
  - `git … --no-verify`
  - `git push` auf main außerhalb von `merge_wp.sh` bzw. ohne die Freigabe-Variable aus WP109
  - `pkill`, `killall`
  - `git -c user.*`
  - `GIT_AUTHOR_*`- und `GIT_COMMITTER_*`-Overrides
  - Robust gegen naheliegende Varianten: Kettenbefehle, `env`, Anführungszeichen, `git -C <pfad>`, `HEAD:main`, `refs/heads/main`.
- **PostToolUse** zählt die Werkzeugaufrufe je Agent bzw. Sitzung. Gibt es keine Agent-ID, zählt der Hook über `transcript_path`.
  - Ab 60 Aufrufen: `additionalContext` „jetzt übergeben (common.md Übergabe)“.
  - Ab 90 Aufrufen: alles außer Write/Edit und `git commit` blockieren, damit die Übergabe noch möglich ist.
  - Der Zählerstand liegt außerhalb des Repos (Temp- bzw. Scratch-Verzeichnis).
- Die Hooks dürfen den Orchestrator nicht behindern: Merge, Status-Commit und Push laufen weiter über den WP109-Weg.
- Selbsttests für beide Hooks in `tool/self_test`.

### 2. Selbstprüfung des Coders
Grundlage sind die häufigsten Review-Befunde aus 98 Nachbesserungs-Commits.
- **Checkliste in `docs/agents/coder.md`**, die der Coder im Abschlussbericht abhakt:
  - Bestätigung, Undo und Risikostufe
  - fail-closed
  - dispose, zeroize und Timeouts
  - ein Negativtest je Fehlerpfad
  - keine festen Texte außerhalb l10n
  - Doku und ADR nachgezogen
  - neue Berechtigung oder Komponente → APK-Allowlist und K-Eintrag
- Der Reviewer prüft die Checkliste mit (`docs/agents/reviewer.md`).
- **Checks im Gate:**
  - Den vorhandenen Scan auf feste Texte als Gate-Check mit Allowlist, nur abbauen.
  - Die `check_apk`-Allowlist (Berechtigungen und Komponenten) gegen `AndroidManifest.xml` prüfen, ohne APK-Build. Der Check läuft in `--changed`, sobald sich ein Manifest ändert (war 3× erst in CI rot).

### 3. CI entlasten (`.github/workflows/gate.yml`, `tool/gate.dart`)
- Commits, die nur `docs/**` oder `*.md` ändern, lassen nur `check_docs` laufen. Heute lösen 35 % der Läufe reine `docs(status)`-Commits aus. Bezug ist der Diff gegen die Merge-Basis bzw. den vorigen Push. Die CI-Pflicht in `merge_wp.sh` (WP109) muss mit diesen verkürzten Läufen umgehen: Ein Paket-Branch mit Code bekommt immer das volle Gate.
- `gate.dart --only <paket>` läuft ohne globale Checks und ohne Werkzeug-Selbsttests. Die Matrix nutzt das, die globalen Checks laufen einmal in einem eigenen Job.
- `wendelin_integrations` auf 2 Shards.

### 4. Rollen und Modelle (Repo-Teil)
- `model: opus` in `.claude/agents/wendelin-reviewer.md`.
- Der Reviewer legt sein Urteil als Datei ab. Den Pfad legt `docs/work-packages/REVIEW.md` fest, z. B. `../james-wt/handoff/<wp>-review.md` (bei Re-Review `-review2.md`).
  - Inhalt: Urteil, Befunde mit Kategorie aus der Checkliste, Anzahl Mutationen und überlebende Mutationen.
  - Kurzes, maschinenlesbares Kopfformat, damit die Quote „beim ersten Review sauber“ (heute 7 %) messbar wird. Ein kleines Auswerteskript ist optional.

### 5. Emulator-Sperre in `tool/e2e_android.sh`
- `mkdir`-Lock je Emulator-Serial mit PID und WP (Umgebungsvariable bzw. Branch), Freigabe per `trap`.
- Ist der Emulator belegt, sofort eine klare Meldung „belegt durch WPnn, PID …“ und Exit-Code ungleich 0, kein Warten.
- Verwaiste Locks (PID existiert nicht mehr) werden übernommen.

### 6. Nachtrag (Orchestrator 2026-10-19)
- `tool/gate.dart` wählt für `kotlin-unit` selbst ein passendes JDK (zuerst openjdk@21, sonst Android-Studio-JBR, wie `tool/e2e_android.sh`), wenn `JAVA_HOME` auf ein zu neues JDK zeigt. Beim WP93-Merge war das Gate auf main mit JDK 23 rot und mit openjdk@21 grün.

## Abnahmekriterien
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE.
- [ ] Hook-Selbsttests belegen jede Sperre (inkl. Varianten), dass erlaubte Befehle durchgehen (z. B. `git push origin wp/…`, `git commit`), und die Schwellen 60/90.
- [ ] Ein Commit nur unter `docs/` startet in CI nur `check_docs` (Beleg: Lauf-URL oder Workflow-Test).
- [ ] Eine neue Berechtigung im Manifest ohne Allowlist-Eintrag ist lokal in `--changed` rot.
- [ ] Ein neuer fester Text außerhalb l10n ist rot.
- [ ] Emulator-Sperre: zweiter Lauf bricht mit Meldung ab, nach Ende oder Abbruch ist die Sperre frei, verwaiste Sperre wird übernommen (Shell-Selbsttest).
- [ ] Reviewer-Urteilsdatei für dieses Paket liegt im festgelegten Format vor.

## Parallel-Hinweise
- Läuft nach WP109. Parallel ggf. App-Pakete (WP93, WP108, WP92c): `tool/e2e_android.sh` vor dem Push mit `origin/main` abgleichen. Die neuen Hooks erst aktivieren (in `.claude/settings.json` auf main), wenn ihre Selbsttests grün sind. Sie gelten dann für alle Sitzungen im Repo und in den Worktrees.
