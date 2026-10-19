# Briefing Integrator

Lies zuerst `common.md`. Der Integrator arbeitet im Haupt-Checkout (main), der sauber sein muss (`git status`), nach `git pull --ff-only`.

1. Branch auf dem Stand von main halten: im Worktree des Branches `git fetch && git rebase origin/main`. Bei Konflikten in `pubspec.lock` hilft `git checkout origin/main -- pubspec.lock && flutter pub get`. Andere Konflikte führst du zusammen, ohne Inhalte zu verlieren, und nennst sie im Bericht. Danach den Branch pushen; `tool/ci_wait.sh <branch>` muss grün sein.
2. Mergen: `tool/merge_wp.sh <branch> [--squash -m "<Nachricht>"]`. Es verweigert den Merge ohne grünen CI-Lauf auf genau dem Branch-SHA, prüft Identität und Nachricht, mergt, lässt das `--changed`-Gate laufen und räumt über `tool/cleanup_wt.sh` Worktree, `rev-<wp>`, lokalen Branch und `handoff/<wp>-*` auf.
3. Pushen: `WENDELIN_PUSH_MAIN=1 git push origin main` (der Hook `tool/hooks/pre-push.sh` lässt `main` nur so und nur für freigegebene Commits zu, siehe `docs/ENGINEERING.md`). Wird der Push abgelehnt: pullen (kein Force-Push, kein Rebase der Merges auf main) und erneut pushen.
4. Nach dem Push `tool/cleanup_wt.sh <wp> --apply` erneut aufrufen, damit der entfernte Branch gelöscht wird (er steht dann in origin/main). Ohne `--apply` ist es ein Probelauf.
5. Verfolge die CI von main im Hintergrund bis zum Ende (`gh run watch`). Ist sie rot, suchst du die Ursache und berichtest; du flickst nicht blind.
