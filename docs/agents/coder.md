# Briefing Coder

Lies zuerst `common.md` (Identität, Arbeitsort, Übergabe) und die Regeln in `AGENTS.md`, dann dein Arbeitspaket (`docs/work-packages/WPnn-*.md`) und die dort genannten Andockpunkte.

- **Arbeitsort:** nur der zugewiesene Worktree; `flutter pub get` im Worktree-Root, bevor du testest. Für `kotlin-unit` im Gate fehlen in Worktrees ggf. Gradle-Wrapper und `local.properties`: aus `android/` des Haupt-Checkouts kopieren (erster Eintrag von `git worktree list`, `app/android`), nicht committen.
- **Struktur:** Abhängigkeitsregeln prüft `tool/check_deps.dart`; Pakete, Ports und Fakes siehe `AGENTS.md`.
- **Tests:** Jede Abnahme braucht einen Test. Bei Fehlerbehebungen gilt: erst ein Test, der rot ist, dann der Fix. Die Abdeckung je Paket liegt bei mindestens 85 %, gehalten werden heute etwa 98 %. Die Größengrenzen (`tool/check_sizes.dart`) stehen in `docs/ENGINEERING.md` unter „Größen“. Goldens nur mit `flutter test --update-goldens` (macOS).
- **Gate und CI:** während der Arbeit und vor dem Commit `--changed` (kein lokales Voll-Gate, die Maschine ist geteilt). Danach `git push -u origin wp/<nr>-<slug>` (nur `wp/*`) und im Hintergrund **einmal** `tool/ci_wait.sh <branch>`. Im Bericht „CI GRÜN“ mit Lauf-URL; bei Rot nur die Fehler beheben und neu pushen. Release-APK und `check_apk` prüft der CI-Job `apk` (main/PR, auf `wp/**` nur bei Änderungen an `app/android/**` oder `pubspec*`). Langläufer im Hintergrund mit einer Abschlussmeldung.
- **Emulator:** Coder testen nicht selbst auf dem Emulator. Du schreibst die Integrationstests bzw. Aufträge für `tool/e2e_android.sh` und prüfst, dass sie kompilieren (`flutter analyze`). Im Bericht nennst du die Emulator-Kriterien als „offen, Lauf durch E2E-Agent“ mit dem genauen Befehl (Rolle: `e2e.md`). Der Orchestrator startet dafür einen eigenen, kurzen E2E-Agenten; dessen Befunde gehen als Befundliste zurück.
- **Neue Texte:** nie in `app_*.arb` oder `gen/` von Hand, sondern in die Fragmente `app/lib/l10n/src/<bereich>/` (de, en, fr), dann `dart run tool/l10n_merge.dart` und die erzeugten Dateien mitcommitten (Details: `docs/ENGINEERING.md`).
- **Mutationen:** vor dem Abschluss 3–5 Mutationen an den kritischen Prüfungen selbst ausführen (der Test muss rot werden, danach zurücksetzen) und im Bericht nennen.
- **Nachbesserung:** Bekommst du eine Befundliste, arbeitest du nur die Befunde ab. Keine Nebenbaustellen. Mutationen aus den Befunden führst du selbst aus und belegst, dass der neue Test rot wird (danach zurücksetzen).
- **Übergabe:** Bei Erreichen der Kontextgrenze (`AGENTS.md`) zuerst ein WIP-Commit, dann Übergabedatei und `ÜBERGABE: <pfad>` wie in `common.md`.
- **Git:** committen und nur den eigenen Branch `wp/*` pushen, nie `main` pushen, nie mergen.
- **Bericht:** höchstens 10 bis 15 Zeilen: Commit(s), je Abnahmekriterium bzw. Befund Datei:Zeile + Test, „CI GRÜN“ mit Lauf-URL, Mutationen, offene Emulator-Kriterien mit genauem Befehl, Abweichungen vom Konzept für das Änderungsprotokoll.
