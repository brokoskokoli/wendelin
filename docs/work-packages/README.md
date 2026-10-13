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
| Refactoring für KI-Wartbarkeit (Gutachten 2026-10-13) | WP35–WP40 (R1–R6) | `R-refactoring.md` (verhaltensneutral; R1 WP35 Agenten-Tooling/Karte sofort; danach R2 WP36 gemeinsame Bausteine (Teile nach WP27/WP33) und R3 WP37 Agent-Runner parallel; R4 WP38 Verdrahtung nach WP27, WP30, WP32, WP31; R5 WP39 App-Logik in Pakete nach WP38; R6 WP40 Plattformkanäle/Screens nach WP27, WP30, WP32) |

## Größe eines Arbeitspakets

Richtwert: **höchstens ca. 1 500 Zeilen geänderter Produktivcode je Review-Einheit** (hinzugefügt plus entfernt unter `lib/` bzw. `app/lib/` und Kotlin `main`, ohne Tests und generierten Code). Größere Pakete werden in Teil-Merges (a/b/c) geschnitten, jeder Teil mit eigenem Review nach `REVIEW.md` und eigenen Mutationsproben. Messung: `git diff --shortstat main...HEAD -- '*/lib/*'` und `dart run tool/check_sizes.dart --report`. Größenregeln für Dateien und Funktionen: `docs/ENGINEERING.md`, Abschnitt „Größen“.

## Merge-Hotspots

Diese Dateien ändert fast jedes Feature-Paket. Regel: **nur anhängen, nicht umsortieren oder umformatieren; bei einem Konflikt den Integrator fragen**, statt selbst semantisch zu mergen. Die Liste wird nach WP38 (Verdrahtung entflechten) gekürzt.

- `packages/wendelin_integrations/lib/wendelin_integrations.dart`, `fakes.dart`, `testing.dart` (Barrels mit `show`-Listen)
- `app/lib/main.dart`, `app/lib/app.dart`
- `app/lib/di/providers.dart`, `app/lib/di/integration_specs.dart`
- `app/lib/ui/routes.dart`, `app/lib/ui/screens/labels.dart`
- `app/test/support/test_env.dart`, `app/test/di/wiring_test.dart`
- `app/android/app/src/main/AndroidManifest.xml`, `app/pubspec.yaml`
