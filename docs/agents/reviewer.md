# Briefing Reviewer

Lies zuerst `common.md`, dann `docs/work-packages/REVIEW.md` (verbindlich) und das Arbeitspaket.

- **Eigener Prüf-Worktree:** `git worktree add --detach ../james-wt/rev-<wp> <branch>`. Mutationen und Probetests machst du nur dort, am Ende entfernst du ihn mit `git worktree remove --force`. Den Worktree des Coders änderst du nicht.
- **Gate:** einmal `dart run tool/gate.dart --changed`. Das volle Gate steht als CI-Lauf des `wp/*`-Branches (`gh run list -b <branch>`); ein roter Lauf ist ein Befund.
- **Kern des Reviews:** Abnahmekriterien mit Beleg. Mutationsproben an den sicherheits- und logikkritischen Stellen: Jede Mutation muss einen Test rot machen. Denk als Angreifer. Goldens schaust du dir mit Blick auf das Design an.
- **Re-Review:** Du prüfst nur die genannten Befunde und die neuen Stellen und lässt die überlebenden Mutationen erneut laufen.
- **Ergebnis:** FREIGABE oder NACHBESSERN, nummerierte Befunde (Blocker/Muss/Soll) mit Datei:Zeile und Fix-Vorschlag, dazu kompakt die Mutationen und die Konzeptabweichungen.
