# Arbeitspakete M0 + M1

Ziel dieses Durchlaufs: Meilensteine **M0 (Gerüst)** und **M1 (Text-Agent Android)** aus dem Gesamtkonzept.

**Definition of Done M1:** „Trag mir morgen um 10 Tauchen ein" funktioniert per Text mit Claude Haiku und mit einem OpenAI-kompatiblen Modell; ein Kalendereintrag wird angelegt, die Tool-Karte zeigt „Rückgängig", alles steht im Audit-Log.

## Reihenfolge und Abhängigkeiten

```
Welle 0   WP00 Gerüst (Workspace, Lints, Gate, CI, Hooks)               [Orchestrator]
Welle 1   WP01 Core-Verträge                                            -> WP00
Welle 2   WP02 Provider-Adapter    WP03 Tool-Laufzeit    WP04 Storage
          WP05 Agent-Schleife      WP06 Integrationen    WP07 Design-System (app)   -> WP01
          WP12 Listen-Integration (Dart-Teil)                            -> WP06
Welle 3   WP08 App-Verdrahtung + Hauptbildschirm + Bestätigung          -> WP02..WP07
          WP10 Modell-Evals (CLI)                                       -> WP02, WP03, WP05, WP06
Welle 4   WP09 Einstellungen: Provider-Einrichtung, Integrationen, Audit-Log, Kosten, Gedächtnis, Onboarding  -> WP08
Welle 5   WP11 End-to-End auf Emulator, Live-Tests, README-Demo        -> alle
```

Jedes Paket: eigener Branch `wp/<nr>-<slug>` in eigenem Worktree, Umsetzung durch einen Coding-Agenten, Prüfung durch einen unabhängigen Review-Agenten nach `REVIEW.md`, Merge nach bestandenem Review.

## Weitere Meilensteine

| Meilenstein | Pakete | Übersicht |
| --- | --- | --- |
| M2 Sprache und Assistent | WP15–WP20 | `M2.md` |
| M3 Routing, MCP, Erweiterung | WP21–WP29 | `M3.md` (Welle A parallel: WP21 Routing-Regeln, WP22 MCP-Client, WP23 HTTP-Tools, WP24 Bring!, WP25 App-Erkennung; Welle B: WP26–WP28 App; Welle C: WP29 E2E) |
| M2-Nachbesserungen (Gerätetest 2026-10-13) | WP30–WP33 | `M2-fixes.md` (Welle 1 parallel: WP30 Sprach-Robustheit, WP32 Onboarding/Einstellungen, WP33 STT-Qualität; Welle 2: WP31 Sprach-UX nach WP30 und WP26) |
| Vorlesefreundliche Antworten (Wunsch 2026-10-13, K19) | WP41 | `WP41-speech-friendly-answers.md` (nach WP31) |
| Sprechfassung: Schutzstufen und KI-Prüfung (Wunsch 2026-10-14) | WP55 | `WP55-spoken-version-check.md` (nach WP41) |
| Power-Taste nach längerer Pause, Akku-Hinweise (Rückmeldung 2026-10-14) | WP56 | `WP56-assistant-after-idle.md` (sofort) |
| Spike lokales Sprachmodell (Wunsch 2026-10-14) | WP57 | `WP57-spike-local-llm.md` (abgeschlossen; Entscheidung: nicht weiter verfolgt) |
| Eigenes Wake-Word-Modell (Plan B aus WP42) | WP58 | `WP58-wake-word-model.md` (vor WP44) |
| Kein automatischer Anbieterwechsel (Entscheidung 2026-10-14) | WP59 | `WP59-no-auto-escalation.md` (nach WP52) |
| Refactoring für KI-Wartbarkeit (Gutachten 2026-10-13) | WP35–WP40 (R1–R6) | `R-refactoring.md` (verhaltensneutral; R1 WP35 Agenten-Tooling/Karte sofort; danach R2 WP36 gemeinsame Bausteine (Teile nach WP27/WP33) und R3 WP37 Agent-Runner parallel; R4 WP38 Verdrahtung nach WP27, WP30, WP32, WP31; R5 WP39 App-Logik in Pakete nach WP38; R6 WP40 Plattformkanäle/Screens nach WP27, WP30, WP32) |
| M4 Wake Word und TEE | WP42–WP54 | `M4.md` (Welle 0 Spikes parallel: WP42 Wake Word/Audio, WP43 Attestierung/Rust-Build; Welle A parallel: WP44 Wake-Word-Kern, WP45 Gesprächsmodus/Barge-in, WP46 Attestierungs-Kern (a/b), WP47 Rust-Prüfmodul, WP48 Taschenlampe, WP49 Prüfprotokoll-Speicher; Welle B App nach WP38/WP40: WP50 Wake-Word-Dienst (a/b), WP51 Gesprächsmodus/Barge-in App, WP52 TEE in der App, WP53 Taschenlampe bei Sperre; Welle C: WP54 E2E) |

## Größe eines Arbeitspakets

Richtwert: **höchstens ca. 1 500 Zeilen geänderter Produktivcode je Review-Einheit** (hinzugefügt plus entfernt unter `lib/` bzw. `app/lib/` und Kotlin `main`, ohne Tests und generierten Code). Größere Pakete werden in Teil-Merges (a/b/c) geschnitten, jeder Teil mit eigenem Review nach `REVIEW.md` und eigenen Mutationsproben. Messung: `git diff --shortstat main...HEAD -- '*/lib/*'` und `dart run tool/check_sizes.dart --report`. Größenregeln für Dateien und Funktionen: `docs/ENGINEERING.md`, Abschnitt „Größen“.

## Merge-Hotspots

Diese Dateien ändert fast jedes Feature-Paket. Regel: **nur anhängen, nicht umsortieren oder umformatieren; bei einem Konflikt den Integrator fragen**, statt selbst semantisch zu mergen. Mit WP38 entschärft (je Integration eigene Barrel-, Spec- und Routendatei; `main.dart`, `app.dart`, `providers.dart` und `test_env.dart` sind schlank bzw. Re-Export-Barrels).

- `packages/wendelin_integrations/lib/wendelin_integrations.dart` (nur noch eine Exportzeile je Integration), `fakes.dart`, `testing.dart`
- `app/lib/di/integrations/registry.dart` (eine Zeile je Integration)
- `app/lib/ui/routes.dart` (`AppRoutes`-Namen), `app/lib/ui/screens/labels.dart`
- `app/test/di/wiring_test.dart`
- `app/android/app/src/main/AndroidManifest.xml`, `app/pubspec.yaml`
