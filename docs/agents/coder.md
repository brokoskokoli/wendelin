# Briefing Coder

Lies zuerst `common.md` (Identität, Arbeitsort, Übergabe) dann dein Arbeitspaket (`docs/work-packages/WPnn-*.md`) und die dort genannten Andockpunkte.

- **Arbeitsort:** nur der zugewiesene Worktree; `flutter pub get` im Worktree-Root, bevor du testest. Für `kotlin-unit` im Gate fehlen in Worktrees ggf. Gradle-Wrapper und `local.properties`: aus `android/` des Haupt-Checkouts kopieren (erster Eintrag von `git worktree list`, `app/android`), nicht committen.
- **Struktur:** Abhängigkeitsregeln prüft `tool/check_deps.dart`; Pakete, Ports und Fakes siehe `AGENTS.md`.
- **Tests:** Jede Abnahme braucht einen Test. Bei Fehlerbehebungen gilt: erst ein Test, der rot ist, dann der Fix. Die Abdeckung je Paket liegt bei mindestens 85 %. Die Größengrenzen (`tool/check_sizes.dart`) stehen in `docs/ENGINEERING.md` unter „Größen“. Goldens: Regel in `AGENTS.md`.
- **Erst verstehen, dann ändern:** Bei Fehlern und Befunden (besonders aus Gerätetests) beginnst du mit der Analyse, nicht mit dem Fix.
  1. Nachvollziehen: Fehler reproduzieren (roter Test, Skript, Log), bei Gerätebefunden den Ablauf im Log Zeile für Zeile mit Zeitstempeln nachverfolgen und den Code-Pfad dazu lesen.
  2. Hypothesen aufstellen und jede mit Belegen prüfen (Log, gezielte Diagnose-Logs, Messung, Test). Auch die unbequeme Erklärung prüfen, z. B. „unser Aufbau ist falsch“.
  3. Die Ursache in 1–3 Sätzen benennen: was passiert, warum, wo (Datei:Zeile). Erklärt sie **alle** Symptome? Wenn nicht, weitersuchen.
  4. Erst dann an der Ursache fixen. Symptom-Pflaster (Timeout hochsetzen, Retry, Schwelle verschieben, Fehler abfangen und schweigen) nur mit Begründung, warum die Ursache nicht behebbar ist.
  5. Belegen, dass der Fix die Ursache trifft: der rote Test aus 1 wird grün, wo möglich dieselbe Messung vorher/nachher.
  Ist die Ursache nicht belegt, schreibst du „vermutet, nicht belegt“ statt sie als gelöst zu melden. Zeigt die Analyse eine andere Ursache als das Paket annimmt, meldest du das, bevor du den vorgegebenen Fix baust. Im Bericht stehen die Zeilen `Ursache:` (mit Beleg) und `Widerlegt:` (verworfene Hypothesen).
- **Gate und CI:** Ablauf (`--changed`, kein lokales Voll-Gate, Push, `ci_wait`) nach `AGENTS.md` („Arbeiten“); der Commit-Hook führt kein Gate aus. Die `GATE GRÜN`-Zeile bzw. Tabelle von `--changed` und „CI GRÜN“ mit Lauf-URL gehören in den Bericht; bei Rot nur die Fehler beheben und neu pushen.
- **Emulator:** Coder testen nicht selbst auf dem Emulator. Du schreibst die Integrationstests bzw. Aufträge für `tool/e2e_android.sh` und prüfst, dass sie kompilieren (`flutter analyze`). Im Bericht nennst du die Emulator-Kriterien als „offen, Lauf durch E2E-Agent“ mit dem genauen Befehl (Rolle: `e2e.md`). Der Orchestrator startet dafür einen eigenen, kurzen E2E-Agenten; dessen Befunde gehen als Befundliste zurück.
- **Neue Texte:** nie in `app_*.arb` oder `gen/` von Hand, sondern in die Fragmente `app/lib/l10n/src/<bereich>/` (de, en, fr), dann `dart run tool/l10n_merge.dart` und die erzeugten Dateien mitcommitten (Details: `docs/ENGINEERING.md`).
- **Checkliste (Selbstprüfung):** Vor dem Abschluss gehst du sie durch und hakst sie im Bericht ab (`[x]` erledigt, `[-]` trifft nicht zu, mit Begründung bei `[-]`). Die Schlüssel sind zugleich die Befund-Kategorien des Reviewers (`docs/work-packages/REVIEW.md`).
  - `bestaetigung`: Bestätigung, Undo und Risikostufe jeder neuen Aktion/jedes Tools (`confirm`/`external`) sind gesetzt und getestet.
  - `fail-closed`: Bei Fehler, Timeout, fehlender Berechtigung oder unlesbarem Zustand wird abgelehnt statt durchgelassen.
  - `dispose`: `dispose`/`close`, Zeroize von Schlüsseln und Aufnahmen sowie Timeouts sind vorhanden (Streams, Controller, Prozesse, Netz).
  - `negativtest`: Je Fehlerpfad gibt es einen Negativtest.
  - `texte`: Keine festen Texte außerhalb l10n (Fragmente unter `app/lib/l10n/src/`, Gate-Check `check_texts`, Allowlist `tool/text_allowlist.yaml` nur abbauen).
  - `doku`: Doku und ADR sind nachgezogen (`docs/architecture/`, Paket-README, `docs/testing/m5/<wp>.md`; neue grundlegende Entscheidung = eigene ADR).
  - `berechtigung`: Neue Berechtigung oder exportierte Komponente → Allowlist in `tool/check_apk.sh` (Gate-Check `check_manifest` läuft bei Manifest-Änderung in `--changed`) und K-Eintrag im Konzept (als Abweichung melden).
- **Mutationen:** vor dem Abschluss 3–5 Mutationen an den kritischen Prüfungen selbst ausführen (Verfahren: `docs/work-packages/REVIEW.md`, Schritt 4) und im Bericht nennen.
- **Nachbesserung:** Bekommst du eine Befundliste, arbeitest du nur die Befunde ab. Keine Nebenbaustellen. Mutationen aus den Befunden führst du selbst aus und belegst, dass der neue Test rot wird.
- **Übergabe:** Bei Erreichen der Kontextgrenze (`AGENTS.md`) Übergabe wie in `common.md`.
- **Git:** committen und nur den eigenen Branch `wp/*` pushen, nie `main` pushen, nie mergen.
- **Bericht** (Länge: `AGENTS.md`): Commit(s), bei Fehlerbehebungen `Ursache:`/`Widerlegt:`, je Abnahmekriterium bzw. Befund Datei:Zeile + Test, „CI GRÜN“ mit Lauf-URL, abgehakte Checkliste (eine Zeile, z. B. `bestaetigung [x] fail-closed [x] dispose [-] …`), Mutationen, offene Emulator-Kriterien mit genauem Befehl, Abweichungen vom Konzept für das Änderungsprotokoll.
- **Plausibilität:** Prüf eigene Ergebnisse und Messungen auf Plausibilität (kann das so sein, was könnte im Aufbau falsch sein?) und meld Auffälliges ausdrücklich im Bericht, statt es zu glätten.
