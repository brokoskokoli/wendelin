# Briefings für Agenten

Kurze Rollen-Briefings; die Arbeitsregeln stehen in `AGENTS.md`, die gemeinsamen Rollenregeln (Identität, Secrets, Geräte, Übergabe) in `common.md`. Ein Agent liest sein Briefing und danach gezielt das eigene Arbeitspaket.

- `common.md`: Identität, Secrets, Arbeitsort, Geräte, Warten, Übergabe (alle Rollen).
- `coder.md`: Arbeitspaket umsetzen oder nachbessern.
- `reviewer.md`: Arbeitspaket prüfen (Prüfprotokoll `docs/work-packages/REVIEW.md`).
- `integrator.md`: Merge-Ablauf nach `main` mit `tool/merge_wp.sh` (führt der Project Supervisor aus, kein eigener Agent).
- `wp-supervisor.md`: Projektdetails für den globalen Agenten `wp-supervisor`.
- `e2e.md`: Integrationstests auf dem Emulator ausführen (nur auf Auftrag des Orchestrators).

Die Rollen sind zusätzlich als Projekt-Agenten unter `.claude/agents/` abgelegt (`wendelin-coder`, `wendelin-reviewer`, `wendelin-e2e`) mit festem Modell (Frontmatter); der Orchestrator gibt nur noch Arbeitspaket, Worktree, Befunde und Parallel-Hinweise mit.
