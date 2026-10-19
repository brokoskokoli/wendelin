# Briefings für Agenten

Kurze Rollen-Briefings; die Regeln stehen in `AGENTS.md` (einzige Regelquelle), die gemeinsamen Rollenregeln in `common.md`. Ein Agent liest sein Briefing und danach gezielt das eigene Arbeitspaket.

- `common.md`: Identität, Secrets, Arbeitsort, Geräte, Warten, Übergabe (alle Rollen).
- `coder.md`: Arbeitspaket umsetzen oder nachbessern.
- `reviewer.md`: Arbeitspaket prüfen (Prüfprotokoll `docs/work-packages/REVIEW.md`).
- `integrator.md`: freigegebenen Branch mit `tool/merge_wp.sh` nach `main` mergen.
- `e2e.md`: Integrationstests auf dem Emulator ausführen (nur auf Auftrag des Orchestrators).

Die Rollen sind zusätzlich als Projekt-Agenten unter `.claude/agents/` abgelegt (`wendelin-coder`, `wendelin-reviewer`, `wendelin-e2e`) mit festem Modell; der Orchestrator gibt nur noch Arbeitspaket, Worktree, Befunde und Parallel-Hinweise mit.
