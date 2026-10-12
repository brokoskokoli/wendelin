# Arbeitspakete M0 + M1

Ziel dieses Durchlaufs: Meilensteine **M0 (Gerüst)** und **M1 (Text-Agent Android)** aus dem Gesamtkonzept.

**Definition of Done M1:** „Trag mir morgen um 10 Tauchen ein" funktioniert per Text mit Claude Haiku und mit einem OpenAI-kompatiblen Modell; ein Kalendereintrag wird angelegt, die Tool-Karte zeigt „Rückgängig", alles steht im Audit-Log.

## Reihenfolge und Abhängigkeiten

```
Welle 0   WP00 Gerüst (Workspace, Lints, Gate, CI, Hooks)               [Orchestrator]
Welle 1   WP01 Core-Verträge                                            -> WP00
Welle 2   WP02 Provider-Adapter    WP03 Tool-Laufzeit    WP04 Storage
          WP05 Agent-Schleife      WP06 Integrationen    WP07 Design-System (app)   -> WP01
Welle 3   WP08 App-Verdrahtung + Hauptbildschirm + Bestätigung          -> WP02..WP07
          WP10 Modell-Evals (CLI)                                       -> WP02, WP03, WP05, WP06
Welle 4   WP09 Einstellungen: Provider-Einrichtung, Integrationen, Audit-Log, Kosten, Gedächtnis, Onboarding  -> WP08
Welle 5   WP11 End-to-End auf Emulator, Live-Tests, README-Demo        -> alle
```

Jedes Paket: eigener Branch `wp/<nr>-<slug>` in eigenem Worktree, Umsetzung durch einen Coding-Agenten, Prüfung durch einen unabhängigen Review-Agenten nach `REVIEW.md`, Merge nach bestandenem Review.
