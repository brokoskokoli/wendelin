# Wendelin – Hinweise für Agenten (Codex, Claude und andere)

Persönlicher Sprachassistent (Flutter, Android zuerst). Fachliche Grundlage ist `Voice Agent App – Gesamtkonzept.md`, das Design steht in `docs/design/DESIGN.md`. Diese Datei ist die einzige Regelquelle; Rollen-Briefings (`docs/agents/`, `.claude/agents/`) enthalten nur die Rolle und Verweise hierher.

## Verbindliche Dokumente
- `docs/ENGINEERING.md`: Layout, Abhängigkeitsregeln, Tests, Sicherheit und Git. Lies bei Bedarf den passenden Abschnitt (`grep -n`), nicht die ganze Datei.
- `docs/ARCHITECTURE.md`: Index der Architekturkarte (kurz). Den Volltext liest du nicht: Lies nur den nötigen Bereich unter `docs/architecture/` (Ports, Datenfluss, Checklisten „Feature → Dateien“ …). Gerätetests je Paket: `docs/testing/m5/README.md`.
- `docs/work-packages/STATUS.md`: Umsetzungsstand aller Meilensteine und Pakete (pflegt nur der Orchestrator auf main).
- `docs/work-packages/`: Arbeitspakete mit Abnahmekriterien. `REVIEW.md` beschreibt das Prüfprotokoll.
- `docs/adr/`: Architekturentscheidungen. Neue grundlegende Entscheidungen bekommen eine eigene ADR.

## Neue Orchestrator-Sitzung
- Sitzung mit `claude --name "Wendelin coding"` starten. Unter diesem Namen schicken die Paket-Sitzungen ihre Fertigmeldungen.
- Mit `/development-supervisor mach weiter` setzt sie nach Abschnitt 0 „Fortsetzen“ fort. Der Stand kommt aus `docs/work-packages/STATUS.md` (Abschnitt „Nächste Schritte“), aus `git worktree list` und aus den Übergabedateien im Ordner james-wt/handoff neben dem Repo.

## Konzeptänderungen
- **Wenn sich bei der Umsetzung herausstellt, dass etwas vom Konzept abweicht oder abweichen muss, wird das im Gesamtkonzept nachgetragen. Der Maintainer bekommt dazu eine kurze Liste der Änderungen und bestätigt sie.**
- Unbestätigte Änderungen stehen im Abschnitt „Änderungsprotokoll“ am Ende des Konzepts mit dem Status `offen`. Nach der Bestätigung wird der Status auf `bestätigt` gesetzt.
- Agenten ändern das Konzept nicht still. Sie melden Abweichungen in ihrem Abschlussbericht, und der Orchestrator trägt sie ein.

## Arbeiten
- Toolchain: Flutter 3.47 / Dart 3.13 (`/opt/homebrew/bin`), Android SDK unter `~/Library/Android/sdk`, AVD `Wendelin_AOSP_35` (AOSP-Image ohne Google Play, K7). Gerätetests: `tool/e2e_android.sh` (nur auf Emulatoren).
- `flutter pub get` im Repo-Root (Pub-Workspace). Das Gate läuft mit `dart run tool/gate.dart [--no-app] [paket…]`. Lokal immer `--changed` (geänderte Pakete und ihre Abhängigen), auch vor dem Commit; das volle Gate läuft in CI (`.github/workflows/gate.yml`) vor dem Merge.
- Gate-Ausgabe ist kompakt (Tabelle am Ende, bei Rot je roter Test Name, Datei:Zeile, Fehler); `--verbose` nur bei Bedarf.
- Einzeltests mit `tool/t.sh <pfad…>` (dart/flutter automatisch, nur Fehlschläge, höchstens 80 Zeilen, `--name x` filtert). Kein rohes `dart test`/`flutter test`. App-Tests mit `--concurrency=2`; die volle App-Suite läuft lokal höchstens einmal vor dem Abschluss, sonst nur in CI.
- Tests ohne Wanduhr-Asserts (Stopwatch, `DateTime.now`/`elapsed` in `expect`) und ohne `runAsync(Future.delayed)` als Wartezeit, stattdessen `pumpUntil`/`fakeAsync` (Check `check_flaky`, Bestand in `tool/flaky_allowlist.yaml`, nur abbauen).
- Goldens nur auf macOS aktualisieren (`flutter test --update-goldens`); auf Linux `flutter test --exclude-tags golden`.
- Reine Dart-Pakete unter `packages/` importieren kein Flutter. Gerätezugriff geht nur über Ports.
- Fakes zum Wiederverwenden stellt `package:<pkg>/fakes.dart` bereit, Contract-Suites `package:<pkg>/testing.dart`.
- Parallele Arbeit läuft in Git-Worktrees unter `../james-wt/<wp>`, mit einem Branch `wp/<nr>-<slug>` pro Arbeitspaket. Gemergt wird erst nach bestandenem Review und grünem CI (`tool/merge_wp.sh`, Aufräumen `tool/cleanup_wt.sh`, Details `docs/agents/integrator.md`).

## Parallelität, Emulator, Übergabe
- Parallelität: bis zu **4** Paket-Sitzungen gleichzeitig, je Sitzung **1** Sub-Agent. Mehr Last nur mit Freigabe des Maintainers.
- Emulator: Es gibt einen. Ist er belegt, wartest du nicht: Melde den Gerätetest als offen. Die Zuteilung übernimmt der Orchestrator.
- Kontextgrenze: nach etwa **60 Werkzeugaufrufen** bzw. rund **120k Tokens** übergibst du (Ablauf in `docs/agents/common.md`).

## Agenten und Tokenverbrauch
- Lies gezielt: erst `grep -n`, dann den Ausschnitt mit `sed -n` oder Read mit Bereich. Ganze große Dateien liest du nicht.
- Bestehende Dateien änderst du mit Edit. Komplett neu schreibst du nur neue Dateien.
- Das volle Gate läuft in CI: Branch `wp/*` pushen (`git push -u origin wp/<nr>-<slug>`, nie `main`), dann im Hintergrund **einmal** `tool/ci_wait.sh <branch>` (kompakte Zusammenfassung, bei Rot die letzten Zeilen). Gemergt wird erst bei grünem CI und nach Review.
- Abschlussberichte sind kurz, höchstens etwa 10 bis 15 Zeilen. Belege nennst du als Datei:Zeile statt als langes Zitat.
- Nachbesserungen und Re-Reviews übernimmt ein frischer Agent mit Befundliste und Diff, statt einen großen Kontext fortzusetzen.
- Modelle: Coder nutzen Sonnet, Reviewer das Standardmodell (Entscheidung Maintainer 2026-10-13).

## Briefings
- Kurze Rollen-Briefings liegen in `docs/agents/` (`common.md` für alle, dazu `coder.md`, `reviewer.md`, `integrator.md`, `e2e.md`); sie sind zusätzlich als Projekt-Agenten unter `.claude/agents/` abgelegt.

## Git, Identität, Secrets
- Öffentliches Repo: kein Name, keine Kontaktdaten und keine Anwesenheit des Maintainers, keine absoluten lokalen Pfade; „Maintainer“ schreiben (Regel und Prüfungen: `docs/agents/common.md`, „Öffentliches Repo“).
- Identität, Trailer, öffentliches Repo und Secrets: nur in `docs/agents/common.md` („Identität“, „Secrets und Live-Tests“). Hooks in `tool/hooks/` und der CI-Schritt prüfen sie; niemals `--no-verify` oder Identitäts-Overrides.
