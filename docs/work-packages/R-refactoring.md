# Refactoring für KI-Wartbarkeit (WP35–WP40, R1–R6)

Grundlage: Gutachten „Wartbarkeit von Wendelin durch KI-Agenten“ (Stand `main` @ 747ec72, 2026-10-13, Note 2). Das Gutachten liegt nicht im Repo. Die Pakete nennen jeweils den Abschnitt (H1–H4, M1–M8, N1–N7), auf den sie sich beziehen, und übernehmen die nötigen Belege. Der Maintainer hat alle sechs Pakete in dieser Reihenfolge freigegeben (2026-10-13).

## Ziel

Agenten sollen Wendelin mit weniger Kontext sicher ändern können. Dazu gehören eine kompakte Gate-Ausgabe und ein Teil-Gate, eine Architekturkarte, kleinere Review-Einheiten, weniger gemeinsame Verdrahtungsdateien, je eine Stelle für sicherheitsrelevante Bausteine, Logik in Paketen mit Abdeckungsregel und geprüfte Plattformkanäle.

Fachlich ändert sich nichts. Das Gesamtkonzept bleibt unverändert.

## Grundregel: verhaltensneutral

Jedes R-Paket ist ein reines Refactoring. Das heißt:
- **Keine Funktionsänderung.** Nutzertexte, Tool-Namen, Tool-Schemas, Risikostufen, Audit-Einträge, Einstellungs-JSON, Secret-Schlüssel, Datenbankschema und Kanalnamen bleiben byte-gleich. Ausnahme ist nur WP35, das Prüfwerkzeuge (`tool/`) und Doku ändert, nicht die App.
- **Tests bleiben grün und werden nicht aufgeweicht.** Bestehende Tests dürfen umziehen, aufgeteilt und auf neue Importe umgestellt werden. Eine geänderte Erwartung (`expect`, Golden, Fixture) ist ein Befund, außer der Abschlussbericht begründet sie einzeln, und es handelt sich nachweislich nicht um Verhalten (z. B. ein umbenannter Typ in einer Fehlermeldung eines Tests).
- **Goldens unverändert.** Kein `--update-goldens`. `git diff --stat main...HEAD -- '*.png'` ist leer.
- **Keine Abdeckungsverluste.** Abdeckung je Paket ist danach nicht niedriger als vorher (Toleranz 0,1 Prozentpunkte), die Zahl der Tests je Paket nicht kleiner, außer bei nachgewiesenen Duplikaten (z. B. N1).
- **Abhängigkeitsregeln** (`tool/check_deps.dart`) ändern sich nur mit ADR. Eine neue Kante zwischen Paketen ist eine Architekturentscheidung, kein Refactoring.
- Stellt ein Paket einen echten Fehler fest, wird er **nicht nebenbei behoben**. Er kommt in den Abschlussbericht und wird als eigenes Paket bzw. eigener Fix mit Regressionstest eingeplant. Ausnahme: Der Fehler verhindert das Refactoring. Dann gibt es einen getrennten Commit mit Regressionstest und Hinweis im Bericht.

## Reihenfolge und Abhängigkeiten

```
R1  WP35 Agenten-Tooling und Karte          sofort startbar, kollidiert mit nichts
R2  WP36 Gemeinsame Bausteine               nach WP35-Merge
      a) Netzziel-Kern ohne MCP, MemoryEntry, SSE-Testduplikat   sofort danach
      b) MCP-Netzpolitik auf den Kern                           nach WP27-Merge
      c) Text-Faltung                                           nach WP33-Merge
R3  WP37 Agent-Runner zerlegen              nach WP35-Merge, parallel zu WP36 möglich
R4  WP38 Verdrahtung entflechten            nach WP27, WP30, WP32 und WP31
R5  WP39 App-Logik in Pakete                nach WP38
R6  WP40 Plattformkanäle und große Screens  nach WP30 und WP32 (Kotlin, Einstellungen), WP27 (Kotlin-Redirect)
```

Begründung: R1 senkt sofort die Kontextkosten jedes folgenden Laufs und liefert den Größen-Check, an dem R2–R6 ihre Messwerte ablesen. R2 und R3 liegen in reinen Dart-Paketen mit ≥ 98 % Abdeckung und berühren die laufenden App-Pakete kaum. R4–R6 betreffen die App-Hotspots und kommen erst, wenn die Pakete gemergt sind, die dieselben Dateien ändern. Sonst entstehen genau die Konflikte, die sie beseitigen sollen.

### Stand der übrigen Pakete und Überschneidungen

| Paket | Stand (2026-10-13) | Berührt R-Paket | Regel |
| --- | --- | --- | --- |
| WP27 MCP-App | im Review | WP36 b (`net_policy`), WP38 (`providers.dart`, `integration_specs.dart`, `userIntegrationSources`), WP39 (`app/lib/di/mcp/*`, `McpSecrets`), WP40 (Kotlin-Redirect) | Diese Teile starten erst nach dem Merge von WP27. |
| WP30 Sprach-Robustheit | läuft | WP38 (`main.dart`, `app.dart`), WP39 (`voice_providers.dart`), WP40 (Kotlin-Session, `AssistantActivity`) | R4–R6 nach dem Merge |
| WP32 Onboarding/Einstellungen | läuft | WP38 (`routes.dart`, Einstellungsseiten), WP40 (`RecognizerSwitch`, `AssistantChannel`, Einstellungs-Screens, `SecretField`) | R4–R6 nach dem Merge. Was WP32 an den Screens schon zerlegt, entfällt in WP40. |
| WP33 STT-Qualität | läuft | WP36 c (Faltung, `resolveNote`), WP39 (`voice_providers.dart`) | WP36 c nach dem Merge. Nutzt WP33 eine neue Faltung, baut es sie gleich so, wie WP36 c sie beschreibt (siehe dort). |
| WP31 Sprach-UX | folgt (nach WP30, WP26) | WP36 c (gefalteter Titelvergleich B8), WP38 (`main_screen`, Overlay, Routen) | WP38 nach dem Merge von WP31 |
| WP29 E2E M3 | folgt | Kaum (`tool/e2e_android.sh`, `evals/`, Doku). WP35 ändert `tool/gate.dart`, nicht die Geräte-Skripte. | Läuft parallel. Bei gleichzeitiger Arbeit an `app/test/support/test_env.dart` oder `app/integration_test/` stimmen sich WP29 und WP38 über den Orchestrator ab. |

Ein neues Feature-Paket, das `wendelin_agent/src/agent_runner.dart` ändert (z. B. ein weiteres Routing-Paket), startet erst nach dem Merge von WP37. Ein neues Integrations-Paket startet möglichst erst nach WP38, weil es dann nur noch eigene Dateien anlegt.

ADR-Nummer vorab vergeben: **ADR 0013** Plattformkanäle (Manifest, ggf. Pigeon) für WP40, nur falls Pigeon oder eine andere Codegenerierung eingeführt wird. WP38 ergänzt ADR 0004 (App-Verdrahtung), WP39 ergänzt ADR 0012 (nutzerdefinierte Integrationen), soweit sich Ablageorte ändern.

## Größe der Review-Einheit

Richtwert (Gutachten H1): **höchstens ca. 1 500 Zeilen geänderter Produktivcode je Review-Einheit** (hinzugefügt plus entfernt unter `lib/` bzw. `app/lib/` und Kotlin `main`, ohne Tests, ohne generierten Code). Reine Verschiebungen, die `git diff --color-moved=zebra main...HEAD` als verschoben markiert, dürfen darüber hinausgehen, wenn der Abschlussbericht sie ausweist. Größere Pakete werden in Teil-Reviews mit eigenem Merge geschnitten (in den WPs als a/b/c vorgeschlagen). Jeder Teil hat ein eigenes Review nach `REVIEW.md`, mit eigenen Mutationsproben.

**Grenzfall:** `app/lib/ui/settings/http_tool_editor_screen.dart` hat genau 800 Zeilen, also die Fehlerschwelle des Größen-Checks (Stand WP35). Jede weitere Zeile macht das Gate rot. Laufende Pakete, die dort ändern (z. B. WP32 Secret-Felder), teilen die Datei vorher auf (siehe WP40, Editor-Abschnitte) statt sie auf die Allowlist zu setzen.

Messung: `git diff --shortstat main...HEAD -- '*/lib/*' ':!*.g.dart' ':!*.steps.dart'` plus Kotlin `main`. Ab WP35 liefert `dart run tool/check_sizes.dart --report` die Dateigrößen.

## Messwerte vorher/nachher

Jedes Paket hält im Abschlussbericht fest, was es verbessern soll, gemessen auf `main` vor dem Start und auf dem Branch vor dem Merge. Welche Werte das sind, steht im jeweiligen WP. Immer dabei:
- Abdeckung je berührtem Paket und Testanzahl (aus dem Gate),
- Zeilen der berührten Hauptdateien und das Ergebnis von `tool/check_sizes.dart --report` (ab WP35),
- Diff-Größe (Produktivcode, Tests, davon reine Verschiebungen),
- Gate-Laufzeit gesamt.

## Review-Fokus

Zusätzlich zu `REVIEW.md`:
1. **Mutationen gegen verschobene Invarianten.** Der Coder listet im Bericht jede Invariante, die umgezogen ist, mit alter und neuer Fundstelle (z. B. „Privatsphäre-Untergrenze steigt auf die Taint-Stufe“, „Rundenzähler wird bei Eskalation zurückgesetzt“, „`100.64.0.0/10` ist Heimnetz“, „Secret-Schlüssel `bring.password`“). Der Reviewer mutiert **jede** dieser Invarianten an der neuen Stelle, mindestens 5 je Teil-Review. Jede Mutation muss einen Test rot machen. Eine überlebende Mutation ist ein blocker, weil das Refactoring dann Abdeckung verloren hat.
2. **Diff-Größe.** Der Reviewer prüft den Richtwert und dass reine Verschiebungen wirklich nur verschoben sind (`--color-moved`). Gemischte Hunks (verschoben und gleichzeitig geändert) sind einzeln zu begründen.
3. **Keine Abdeckungsverluste.** Abdeckung und Testanzahl vorher/nachher vergleichen. Geänderte `expect`-Zeilen, gelöschte Tests und geänderte Fixtures/Goldens einzeln prüfen (`git diff main...HEAD -- '*_test.dart' | grep '^-.*expect'`).
4. **Verhaltensneutralität stichprobenartig belegen:** öffentliche Typen und Funktionen, die Pakete nach außen geben, bleiben gleich oder werden in einem Barrel weiter exportiert. Nutzertexte und Schlüssel bleiben byte-gleich (`git diff -S'<Text>'`).
5. **Lesbarkeit für Agenten:** Jede neue Datei hat einen Doc-Kommentar mit ihrer Aufgabe. `docs/ARCHITECTURE.md` ist nachgeführt.

## Regeln

Wie M1–M3: eigener Worktree je Paket unter `../james-wt/<wp>` mit Branch `wp/<nr>-<slug>` (bei Teil-Merges `wp/<nr><a|b|c>-<slug>`), Gate grün vor jedem Commit, Review nach `REVIEW.md` in eigenem Prüf-Worktree, Merge erst nach bestandenem Review. Konzeptabweichungen gibt es hier nicht. Falls doch eine auftaucht, steht sie im Abschlussbericht.

## Gerätetests – nur Emulator

Wie in `M3.md`, Abschnitt „Gerätetests – nur Emulator“: Agenten installieren nie auf ein echtes Gerät. Sie nutzen ausschließlich den AVD `Wendelin_AOSP_35` mit explizitem Serial (`DEVICE=emulator-xxxx`, `adb -s emulator-xxxx`, `flutter … -d emulator-xxxx`) und prüfen vorher `ro.kernel.qemu=1`. `E2E_ALLOW_DEVICE=1` setzt kein Agent. Gerätetests sind nur in WP38, WP39 und WP40 nötig (App-Verdrahtung bzw. Kotlin).

## Nicht eingeplant

- N2 (Änderungsprotokoll des Gesamtkonzepts auslagern): Das ändert das Konzept-Dokument und braucht eine Entscheidung des Maintainers. Es ist kein Teil dieser Pakete.
- N6 (Arbeitgeber-Begriffe im Hook) ist mit Commit d896ff7 erledigt.
- Pigeon für alle Kanäle (M6 Variante A): nur optional in WP40, mit ADR 0013.
