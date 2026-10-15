# Briefings für Agenten

Kurze Rollen-Briefings. Ein Agent liest sein Briefing und danach gezielt das eigene Arbeitspaket. Die übrigen Dokumente liest er nur bei Bedarf und nur ausschnittweise (`grep -n`, dann `sed -n`).

- `coder.md`: Arbeitspaket umsetzen oder nachbessern.
- `reviewer.md`: Arbeitspaket prüfen (Prüfprotokoll `docs/work-packages/REVIEW.md`).
- `integrator.md`: freigegebenen Branch nach `main` mergen.

Die Rollen sind zusätzlich als Projekt-Agenten unter `.claude/agents/` abgelegt (`wendelin-coder`, `wendelin-reviewer`, `wendelin-e2e`) mit festem Modell und den immer gleichen Regeln; der Orchestrator gibt nur noch Arbeitspaket, Worktree, Befunde und Parallel-Hinweise mit.
