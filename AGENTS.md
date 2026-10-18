# Wendelin – Hinweise für Agenten (Codex, Claude und andere)

Persönlicher Sprachassistent (Flutter, Android zuerst). Fachliche Grundlage ist `Voice Agent App – Gesamtkonzept.md`, das Design steht in `docs/design/DESIGN.md`.

## Verbindliche Dokumente
- `docs/ENGINEERING.md`: Layout, Abhängigkeitsregeln, Tests, Sicherheit und Git. Lies es vor jeder Codeänderung.
- `docs/ARCHITECTURE.md`: Architekturkarte (wo liegt was, Ports, Datenfluss, Checklisten „Feature → Dateien“).
- `docs/work-packages/STATUS.md`: Umsetzungsstand aller Meilensteine und Pakete (pflegt nur der Orchestrator auf main).
- `docs/work-packages/`: Arbeitspakete mit Abnahmekriterien. `REVIEW.md` beschreibt das Prüfprotokoll.
- `docs/adr/`: Architekturentscheidungen. Neue grundlegende Entscheidungen bekommen eine eigene ADR.

## Neue Orchestrator-Sitzung
- Sitzung mit `claude --name "Wendelin coding"` starten. Unter diesem Namen schicken die Paket-Sitzungen ihre Fertigmeldungen.
- Mit `/development-supervisor mach weiter` setzt sie nach Abschnitt 0 „Fortsetzen“ fort. Der Stand kommt aus `docs/work-packages/STATUS.md` (Abschnitt „Nächste Schritte“), aus `git worktree list` und aus den Übergabedateien im Ordner james-wt/handoff neben dem Repo.

## Konzeptänderungen
- **Wenn sich bei der Umsetzung herausstellt, dass etwas vom Konzept abweicht oder abweichen muss, wird das im Gesamtkonzept nachgetragen. Der Maintainer (Stefan) bekommt dazu eine kurze Liste der Änderungen und bestätigt sie.**
- Unbestätigte Änderungen stehen im Abschnitt „Änderungsprotokoll“ am Ende des Konzepts mit dem Status `offen`. Nach der Bestätigung wird der Status auf `bestätigt` gesetzt.
- Agenten ändern das Konzept nicht still. Sie melden Abweichungen in ihrem Abschlussbericht, und der Orchestrator trägt sie ein.

## Arbeiten
- Toolchain: Flutter 3.47 / Dart 3.13 (`/opt/homebrew/bin`), Android SDK unter `~/Library/Android/sdk`, AVD `Wendelin_AOSP_35` (AOSP-Image ohne Google Play, K7). Gerätetests: `tool/e2e_android.sh` (nur auf Emulatoren).
- `flutter pub get` im Repo-Root (Pub-Workspace). Das Gate läuft mit `dart run tool/gate.dart [--no-app] [paket…]`. Lokal läuft nur `--changed`, das volle Gate übernimmt CI (`.github/workflows/gate.yml`) vor dem Merge.
- Gate-Ausgabe ist kompakt (Tabelle am Ende, bei Rot das Ende der Fehlerausgabe); `--verbose` nur bei Bedarf. Lokal immer `--changed` (geänderte Pakete und ihre Abhängigen), auch vor dem Commit; das volle Gate läuft in CI.
- Einzelne Tests: `dart test test/<pfad>` im Paket, App-Tests mit `flutter test test/<pfad>` in `app/`.
- Goldens nur auf macOS aktualisieren (`flutter test --update-goldens`); auf Linux `flutter test --exclude-tags golden`.
- Reine Dart-Pakete unter `packages/` importieren kein Flutter. Gerätezugriff geht nur über Ports.
- Fakes zum Wiederverwenden stellt `package:<pkg>/fakes.dart` bereit, Contract-Suites `package:<pkg>/testing.dart`.
- Parallele Arbeit läuft in Git-Worktrees unter `../james-wt/<wp>`, mit einem Branch `wp/<nr>-<slug>` pro Arbeitspaket. Gemergt wird erst nach bestandenem Review.

## Agenten und Tokenverbrauch
- Lies gezielt: erst `grep -n`, dann den Ausschnitt mit `sed -n` oder Read mit Bereich. Ganze große Dateien liest du nicht.
- Bestehende Dateien änderst du mit Edit. Komplett neu schreibst du nur neue Dateien.
- Während der Arbeit und vor dem Commit läuft `dart run tool/gate.dart --changed`. Das volle Gate läuft in CI: Branch `wp/*` pushen (`git push -u origin wp/<nr>-<slug>`, nie `main`), dann im Hintergrund **einmal** `tool/ci_wait.sh <branch>` (kompakte Zusammenfassung, bei Rot die letzten Zeilen). Gemergt wird erst bei grünem CI und nach Review.
- Abschlussberichte sind kurz, höchstens etwa 10 bis 15 Zeilen. Belege nennst du als Datei:Zeile statt als langes Zitat.
- Nachbesserungen und Re-Reviews übernimmt ein frischer Agent mit Befundliste und Diff, statt einen großen Kontext fortzusetzen.
- Modelle: Coder nutzen Sonnet, Reviewer das Standardmodell (Entscheidung Maintainer 2026-10-13).

## Briefings
- Kurze Rollen-Briefings für Agenten liegen in `docs/agents/` (`coder.md`, `reviewer.md`, `integrator.md`, `common.md`).

## Git und Identität (wichtig)
- Erlaubt ist nur die Identität für `~/ai` (`~/.gitconfig-smart-ssh` per includeIf): `brokoskokoli <16724498+brokoskokoli@users.noreply.github.com>`, dazu als einziger Trailer `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Keine weiteren Trailer (insbesondere keine `Claude-Session`-Zeile), keine anderen Namen oder Mailadressen, insbesondere keine Arbeitgeber-Domains.
- Die Identität kommt aus der globalen `~/ai`-Konfiguration (kein repo-lokaler Override), Hooks in `tool/hooks/` prüfen sie. Niemals `--no-verify` oder Identitäts-Overrides verwenden.
- Das Repo ist öffentlich (`github.com/brokoskokoli/wendelin`). Keine Secrets, keine privaten Daten.

## Secrets und Live-Tests
- API-Keys für Live-Tests liegen außerhalb des Repos in `~/.wendelin-live.env`, jeweils mit kleinem Budget. Laden mit `set -a; . ~/.wendelin-live.env; set +a`. Niemals ausgeben, loggen oder committen.
- Live-Tests tragen `@Tags(['live'])` und sind standardmäßig übersprungen. Sie sollen sparsam sein: kleinste Modelle, wenige Tokens.
