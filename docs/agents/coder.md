# Briefing Coder

Lies zuerst `common.md`, dann dein Arbeitspaket (`docs/work-packages/WPnn-*.md`) und die dort genannten Andockpunkte.

- **Struktur:** reine Dart-Pakete unter `packages/` importieren kein Flutter. Gerätezugriff geht über Ports, Fakes liegen in `package:<pkg>/fakes.dart`, Contract-Suites in `package:<pkg>/testing.dart`. Die Abhängigkeitsregeln prüft `tool/check_deps.dart`.
- **Tests:** Jede Abnahme braucht einen Test. Bei Fehlerbehebungen gilt: erst ein Test, der rot ist, dann der Fix. Die Abdeckung je Paket liegt bei mindestens 85 %, gehalten werden heute etwa 98 %. Die Größengrenzen (`tool/check_sizes.dart`) stehen in `docs/ENGINEERING.md` unter „Größen“.
- **Gate:** während der Arbeit und vor dem Commit `--changed` (die Maschine ist geteilt, kein lokales Voll-Gate). Das volle Gate läuft in CI: `git push -u origin wp/<nr>-<slug>` (nur `wp/*`, nie `main`), dann im Hintergrund **einmal** `tool/ci_wait.sh <branch>`. Im Bericht „CI GRÜN“ mit Lauf-URL; bei Rot nur die Fehler beheben und neu pushen. Release-APK und `check_apk` prüft der CI-Job `apk` (main/PR, auf `wp/**` nur bei Änderungen an `app/android/**` oder `pubspec*`).
- **Emulator:** Coder testen nicht selbst auf dem Emulator. Du schreibst die Integrationstests bzw. Aufträge für `tool/e2e_android.sh` und prüfst, dass sie kompilieren (`flutter analyze`). Im Bericht nennst du die Emulator-Kriterien als „offen, Lauf durch E2E-Agent“ mit dem genauen Befehl. Der Orchestrator startet dafür einen eigenen, kurzen E2E-Agenten; dessen Befunde gehen als Befundliste zurück.
- **Nachbesserung:** Bekommst du eine Befundliste, arbeitest du nur die Befunde ab. Keine Nebenbaustellen.
- **Git:** committen und nur den eigenen Branch `wp/*` pushen (für das CI-Gate, siehe Gate), nie `main` pushen, nie mergen.
- **Bericht:** was umgesetzt ist, jedes Abnahmekriterium mit Beleg, Gate-Ergebnis, Commit-Hashes, Abweichungen vom Konzept, offene Punkte.
