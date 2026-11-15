# Wendelin – Hinweise für Agenten (Codex, Claude und andere)

Persönlicher Sprachassistent (Flutter, Android zuerst). Fachliche Grundlage ist `Voice Agent App – Gesamtkonzept.md`, das Design steht in `docs/design/DESIGN.md`. Regelquellen: diese Datei (Arbeitsregeln, Identität, Secrets, Geräte) und `docs/ENGINEERING.md` (technische Referenz). Die Regeln gelten für jeden Beitrag, ob von Menschen oder Agenten.

## Verbindliche Dokumente
- `docs/ENGINEERING.md`: Layout, Abhängigkeitsregeln, Tests, Sicherheit und Git. Lies bei Bedarf den passenden Abschnitt (`grep -n`), nicht die ganze Datei.
- `docs/ARCHITECTURE.md`: Index der Architekturkarte (kurz). Den Volltext liest du nicht: Lies nur den nötigen Bereich unter `docs/architecture/` (Ports, Datenfluss, Checklisten „Feature → Dateien“ …).
- `docs/adr/`: Architekturentscheidungen. Neue grundlegende Entscheidungen bekommen eine eigene ADR.

## Konzeptänderungen
- Das Gesamtkonzept ist die fachliche Quelle der Wahrheit. Wenn sich bei der Umsetzung herausstellt, dass etwas vom Konzept abweicht oder abweichen muss, wird das nicht still geändert: Beschreibe die Abweichung im Pull Request; der Maintainer entscheidet und bestätigt sie.

## Arbeiten
- Toolchain: Flutter 3.47 / Dart 3.13 (`/opt/homebrew/bin`), Android SDK unter `~/Library/Android/sdk`, AVD `Wendelin_AOSP_35` (AOSP-Image ohne Google Play, K7). Gerätetests: `tool/e2e_android.sh` (nur auf Emulatoren, siehe „Geräte“).
- `flutter pub get` im Repo-Root (Pub-Workspace). Das Gate läuft mit `dart run tool/gate.dart [--no-app] [paket…]`. Lokal immer `--changed` (geänderte Pakete und ihre Abhängigen), auch vor dem Commit; das volle Gate läuft in CI (`.github/workflows/gate.yml`) und muss vor dem Merge grün sein. Dazu den eigenen Branch pushen (nie `main`), einen Pull Request öffnen und im Hintergrund **einmal** `tool/ci_wait.sh <branch>` (kompakte Zusammenfassung, bei Rot die letzten Zeilen).
- Gate-Ausgabe ist kompakt (Tabelle am Ende, bei Rot je roter Test Name, Datei:Zeile, Fehler); `--verbose` nur bei Bedarf. Pro Checkout läuft ein Gate zur Zeit (parallele Läufe überschreiben Coverage-Dateien).
- Einzeltests mit `tool/t.sh <pfad…>` (dart/flutter automatisch, nur Fehlschläge, höchstens 80 Zeilen, `--name x` filtert). Kein rohes `dart test`/`flutter test`. App-Tests mit `--concurrency=2`; die volle App-Suite läuft lokal höchstens einmal vor dem Abschluss, sonst nur in CI.
- Tests ohne Wanduhr-Asserts (Stopwatch, `DateTime.now`/`elapsed` in `expect`) und ohne `runAsync(Future.delayed)` als Wartezeit, stattdessen `pumpUntil`/`fakeAsync` (Check `check_flaky`, Bestand in `tool/flaky_allowlist.yaml`, nur abbauen).
- Goldens aktualisieren: Workflow `update-goldens` oder lokal auf macOS `flutter test --update-goldens` (Ausnahme zur `tool/t.sh`-Regel).
- Reine Dart-Pakete unter `packages/` importieren kein Flutter. Gerätezugriff geht nur über Ports.
- Fakes zum Wiederverwenden stellt `package:<pkg>/fakes.dart` bereit, Contract-Suites `package:<pkg>/testing.dart`.
- Gemergt wird über einen Pull Request, erst nach bestandenem Review und grünem CI.

## Git, Identität, Secrets
- **Identität:** Committen darf nur `brokoskokoli <16724498+brokoskokoli@users.noreply.github.com>` (`git config user.name` muss `brokoskokoli` sein). Die Nachricht endet mit genau einem Trailer mit dem Modell, auf dem der committende Agent läuft: `Co-Authored-By: Claude <Modell> <noreply@anthropic.com>` (z. B. `Claude Sonnet 4.6`, `Claude Opus 5.5 (1M context)`, `Claude Haiku 4.5`). Keine `Claude-Session`-Zeile, keine anderen Trailer, keine anderen Namen oder Mailadressen (insbesondere keine Arbeitgeber-Domains); Hooks in `tool/hooks/` und der CI-Job `commit-identity` lehnen das ab. Nie `--no-verify`, nie Identitäts-Overrides (`git -c user.*`, `GIT_AUTHOR_*`/`GIT_COMMITTER_*`). Gepusht wird nur der eigene Arbeitsbranch, nie `main`; `main` ändert sich nur über gemergte Pull Requests: ein PR mit grünem CI wird im Checkout auf `main` mit `tool/merge_pr.sh <pr> --model "<Modell>"` gemergt und mit `WENDELIN_PUSH_MAIN=1 git push origin main` gepusht (Hook `tool/hooks/pre-push.sh`; ohne Werkzeug nur reine Doku-Commits). Bricht Werkzeug oder Hook ab, wird die Ursache behoben – weiterhin nie `--no-verify`.
- **Secrets und Live-Tests:** Das Repo ist öffentlich (`github.com/brokoskokoli/wendelin`): keine Secrets, keine privaten Daten, keine echten Sprachaufnahmen, keine Modelle (synthetische Fixtures sind ok). API-Keys für Live-Tests liegen in einer lokalen env-Datei außerhalb des Repos (kleines Budget), geladen mit `set -a; . <datei>; set +a`; Werte nie ausgeben, loggen oder committen. Live-Tests tragen `@Tags(['live'])`, sind standardmäßig übersprungen und laufen nur, wenn ausdrücklich verlangt: sparsam (kleinstes Modell, wenige Tokens, Anzahl im Bericht).
- **Öffentliches Repo:** Kein Name, keine Kontaktdaten und keine Anwesenheit des Maintainers in Dateien, Tests, Berichten und Commit-Nachrichten: „Maintainer“ schreiben. Keine absoluten lokalen Pfade (stattdessen `~/…` oder „lokal, nicht im Repo“). Zwei private Listen liegen unter `~/.config/wendelin/` (nie ausgeben oder ins Repo legen): `forbidden-terms.txt` (Begriffe; geprüft von `tool/hooks/privacy-guard.sh` im pre-commit und vom Gate-Schritt `check_privacy`) und `forbidden-identities` (verbotene Identitäten/Adressen, ein Regex je Zeile; geprüft von `tool/hooks/commit-msg-guard.sh` und `tool/check_secrets.dart`). Ohne die Dateien (CI) entfällt nur diese Prüfung, Pfadmuster auch ohne Liste (CI). Selbsttests verwenden nur erfundene Begriffe.
- **Geräte:** nur ein Emulator `Wendelin_AOSP_35` mit explizitem Serial `emulator-xxxx`, über `tool/android_device.sh`. `tool/e2e_android.sh` startet den Emulator selbst, wenn keiner läuft, und beendet ihn am Ende jedes Laufs; `E2E_KEEP_EMULATOR=1` lässt ihn für Folgeläufe stehen (der letzte Lauf ohne die Variable beendet ihn). Einen Emulator startest du sonst nie von Hand. Niemals ein echtes Gerät, niemals `E2E_ALLOW_DEVICE`. Ist der Emulator belegt oder fremd, wartest du nicht, sondern meldest den Gerätetest als offen. Fremde Prozesse fasst du nicht an (kein `pkill`/`killall`).

## Agenten und Tokenverbrauch
- Lies gezielt: erst `grep -n`, dann den Ausschnitt mit `sed -n` oder Read mit Bereich. Ganze große Dateien liest du nicht.
- Bestehende Dateien änderst du mit Edit. Komplett neu schreibst du nur neue Dateien.
- Mechanische Massenänderungen (Umbenennen, Texte migrieren, viele gleichartige Edits) per Skript/Codemod, nicht mit Hunderten Edit-Aufrufen.
- Lange Läufe (Gate, Build, Emulator, CI) im Hintergrund starten und auf **eine** Abschlussmeldung warten, keine Warteschleifen (`pgrep`/`sleep`-Loops). Kurze Läufe (< 10 min) im Vordergrund mit passendem Timeout.
- Abschlussberichte sind kurz; Belege nennst du als Datei:Zeile statt als langes Zitat.
