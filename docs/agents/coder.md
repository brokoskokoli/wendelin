# Briefing Coder

Lies zuerst `common.md`, dann dein Arbeitspaket (`docs/work-packages/WPnn-*.md`) und die dort genannten Andockpunkte.

- **Struktur:** reine Dart-Pakete unter `packages/` importieren kein Flutter. Gerätezugriff geht über Ports, Fakes liegen in `package:<pkg>/fakes.dart`, Contract-Suites in `package:<pkg>/testing.dart`. Die Abhängigkeitsregeln prüft `tool/check_deps.dart`.
- **Tests:** Jede Abnahme braucht einen Test. Bei Fehlerbehebungen gilt: erst ein Test, der rot ist, dann der Fix. Die Abdeckung je Paket liegt bei mindestens 85 %, gehalten werden heute etwa 98 %. Die Größengrenzen (`tool/check_sizes.dart`) stehen in `docs/ENGINEERING.md` unter „Größen“.
- **Gate:** während der Arbeit `--changed`. Einmal vor dem Abschluss-Commit das volle `dart run tool/gate.dart`, und wenn das Paket die App betrifft, zusätzlich Release-APK und `tool/check_apk.sh`.
- **Emulator:** Coder testen nicht selbst auf dem Emulator. Du schreibst die Integrationstests bzw. Aufträge für `tool/e2e_android.sh` und prüfst, dass sie kompilieren (`flutter analyze`). Im Bericht nennst du die Emulator-Kriterien als „offen, Lauf durch E2E-Agent“ mit dem genauen Befehl. Der Orchestrator startet dafür einen eigenen, kurzen E2E-Agenten; dessen Befunde gehen als Befundliste zurück.
- **Nachbesserung:** Bekommst du eine Befundliste, arbeitest du nur die Befunde ab. Keine Nebenbaustellen.
- **Git:** nur committen, nicht pushen und nicht mergen.
- **Bericht:** was umgesetzt ist, jedes Abnahmekriterium mit Beleg, Gate-Ergebnis, Commit-Hashes, Abweichungen vom Konzept, offene Punkte.
