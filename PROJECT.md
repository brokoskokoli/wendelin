# Projektregeln: Arbeitsorte und Rollen

Diese Datei sagt den globalen Skills und Agenten (`project-supervisor`, `wp-supervisor`, `research-supervisor`, `researcher`, `research-reviewer`), wo sie in diesem Repository arbeiten. Die Regeln selbst stehen in `AGENTS.md` (einzige Regelquelle); diese Datei nennt nur die Orte.

## Projekt
- **Name:** Wendelin (Kurzname für Agenten, Branches und Sitzungen: `wendelin`)
- **Zweck:** Persönlicher Sprachassistent (Flutter, Android zuerst).
- **Repository:** öffentlich auf GitHub (Regeln „Öffentliches Repo“ in `docs/agents/common.md`).
- **Maintainer:** der Nutzer.
- **Orchestrator-Sitzung:** beliebiger Name, Start mit `/project-supervisor mach weiter`. Paket- und Research-Sitzungen bekommen den aktuellen Namen im Prompt und melden sich dort.

## Arbeitsorte

| Bereich | Pfad | Wer arbeitet dort | Regeln |
| --- | --- | --- | --- |
| App (Flutter) | `app/` | Coder über Arbeitspakete | `AGENTS.md`, `docs/ENGINEERING.md` |
| Reine Dart-Pakete | `packages/` | Coder über Arbeitspakete | `docs/ENGINEERING.md` (kein Flutter-Import) |
| Konzept (Quelle der Wahrheit) | `Voice Agent App – Gesamtkonzept.md` (unter 60 KB; bestätigte K-Einträge per `tool/concept_archive.dart --apply` nach `docs/concept-changelog/`) | Project Supervisor pflegt das Änderungsprotokoll, Maintainer bestätigt | `AGENTS.md` „Konzeptänderungen“ |
| Design | `docs/design/DESIGN.md` | Project Supervisor | – |
| Architektur | `docs/ARCHITECTURE.md` (Index), `docs/architecture/` | Project Supervisor, Coder | – |
| Architekturentscheidungen | `docs/adr/` | Project Supervisor | – |
| Rollen-Briefings | `docs/agents/`, `.claude/agents/` | Project Supervisor | – |
| Arbeitspakete und Umsetzungsstand | `docs/work-packages/` (`STATUS.md`, `REVIEW.md`, `WPnn-<slug>.md`, `M<n>-PLAN.md`) | Project Supervisor, WP-Supervisor | `docs/work-packages/README.md` |
| Gerätetests je Paket | `docs/testing/m5/` | WP-Supervisor schreibt, Maintainer testet | `docs/testing/m5/README.md` |
| Research (Analysen, Messungen, Trainings) | bisher kein eigener Ordner; Wake-Word-Training unter `tool/train_wake_word/`, Spikes als Arbeitspakete | – | vor dem ersten Research-Auftrag mit dem Maintainer festlegen |
| Werkzeuge, Gate, Hooks | `tool/` (`gate.dart`, `merge_wp.sh`, `cleanup_wt.sh`, `hooks/`) | Project Supervisor | `docs/agents/integrator.md` |
| Worktrees und Übergaben | `../james-wt/` (`wpNN`, `rev-wpNN`, `handoff/`, `reviews/`, `e2e-keep/`) | alle Agenten | `AGENTS.md` |
| Testordner des Maintainers | außerhalb des Repos (Ort im Gedächtnis des Orchestrators) | Project Supervisor legt APK, `VERSION.txt`, Testprotokoll ab | – |

## Rollen

| Rolle | Wie | Aufgabe |
| --- | --- | --- |
| Project Supervisor | Skill `project-supervisor` (global) in der Hauptsitzung | Gesamtüberblick, Pakete anlegen, Sitzungen starten, mergen, Konzept und Änderungsprotokoll pflegen, Release-Kandidaten bauen |
| WP-Supervisor | Agent `wp-supervisor` (global), eigene Sitzung | genau ein Arbeitspaket bis zum Ziel |
| Coder | Projekt-Agent `wendelin-coder` | Code (Sonnet) |
| Reviewer | Projekt-Agent `wendelin-reviewer` | prüft, ändert nichts (Standardmodell) |
| E2E | Projekt-Agent `wendelin-e2e` | Emulator `Wendelin_AOSP_35`, nur `DEVICE=emulator-5554` |

## Branches
- Arbeitspaket: `wp/NN-<slug>` im Worktree `../james-wt/wpNN`
- Gemergt wird nur durch den Project Supervisor nach `main` (`tool/merge_wp.sh`, Push mit `WENDELIN_PUSH_MAIN=1`).
- Release-Kandidat: Tag `v<pubspec-version>-rcN` auf main nach grünem Gate (`docs/RELEASE.md`).
