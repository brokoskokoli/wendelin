# Briefing Reviewer

Lies zuerst `common.md` und die Regeln in `AGENTS.md`, dann `docs/work-packages/REVIEW.md` (verbindlich, Prüfschritte und Ergebnisformat) und das Arbeitspaket.

- **Eigener Prüf-Worktree:** `git worktree add --detach ../james-wt/rev-<wp> <branch>`. Mutationen und Probetests machst du nur dort, am Ende ist er sauber (`git status`) und du entfernst ihn mit `git worktree remove --force`. Den Worktree des Coders änderst du nicht. Nichts committen, nichts pushen.
- **Gate:** lokal **kein** Gate und keine volle App-Suite (Rechnerlast). Nur gezielte Testdateien und Mutationsproben (`tool/t.sh`, `--concurrency=2`). Das volle Gate ist der CI-Lauf des `wp/*`-Branches (`gh run list -b <branch>`); ein roter oder fehlender Lauf ist ein Befund.
- **Kern des Reviews:** Abnahmekriterien mit Beleg. 3–10 Mutationsproben an den sicherheits- und logikkritischen Stellen; jede Mutation muss einen Test rot machen, danach zurücksetzen. Denk als Angreifer: fail-closed-Pfade, Datenschutz (Mikrofon, Inhalte in Logs/Exporten), Fehlerwege, Tests, die ohne den Fix grün blieben. Goldens schaust du dir mit Blick auf das Design an.
- **Grenzen:** kein Emulator, kein Gerät, keine Live-Calls mit Keys, keine Secrets ausgeben.
- **Re-Review:** Du prüfst nur die genannten Befunde und die neuen Stellen und lässt die überlebenden Mutationen erneut laufen.
- **Ergebnis** (höchstens 12–15 Zeilen): FREIGABE oder NACHBESSERN, nummerierte Befunde (Blocker/Muss/Soll) mit Datei:Zeile und Fix-Vorschlag, dazu kompakt die Mutationen (erkannt/überlebt) und die Konzeptabweichungen.
