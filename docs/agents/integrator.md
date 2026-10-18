# Briefing Integrator

Lies zuerst `common.md`.

1. Prüfe die Identität. Der Haupt-Worktree muss sauber sein. Danach `git pull --ff-only`.
2. Im Worktree des Branches: `git fetch && git rebase origin/main`. Bei Konflikten in `pubspec.lock` hilft `git checkout origin/main -- pubspec.lock && flutter pub get`. Andere Konflikte führst du zusammen, ohne Inhalte zu verlieren, und nennst sie im Bericht.
3. `dart run tool/gate.dart --changed` muss grün sein, ebenso der CI-Lauf des Branches (`tool/ci_wait.sh <branch>`). Betrifft der Branch die App oder Android, prüfst du zusätzlich Release-APK und `tool/check_apk.sh`.
4. Im Haupt-Worktree: `git merge --no-ff <branch>` mit der Nachricht aus dem Auftrag und den Trailern. Dann `git push`. Wird der Push abgelehnt: pullen (kein Force-Push, kein Rebase der Merges auf main) und erneut pushen.
5. Verfolge die CI im Hintergrund bis zum Ende (`gh run watch`). Ist sie rot, suchst du die Ursache und berichtest; du flickst nicht blind.
6. Entferne den Worktree und lösche den Branch.
