# WP37 – R3: Agent-Runner zerlegen (`wendelin_agent`)

Abhängig von: **WP35** (Größen-Check mit `agent_runner.dart` auf der Allowlist, Messwerte). Parallel zu WP36 möglich (keine gemeinsamen Dateien). Übersicht und Grundregeln: `R-refactoring.md` (verhaltensneutral). Bezug: Gutachten **M1** (`_Run` mit 18 veränderlichen Feldern, `_loop` mit 7 `continue`-Pfaden, Testdatei mit 2 054 Zeilen), Lange Funktionen (`_loop` 125, `_escalate` 87, `_runTools` 84 Zeilen). Konzept-Bezug zum Gegenlesen: „Agent-Schleife“ (8 Tool-Runden, 60 s, Eskalation), K9/K10 (Privatsphäre, Taint, Tool-Katalog je Zielstufe). ADRs: 0003 (Agent-Schleife), 0009 (Routing-Regeln).

Andockpunkte: `packages/wendelin_agent/lib/src/agent_runner.dart` (`AgentRunner`, `_Run` ab :172, `drive`, `_loop` ab :256, `_escalate`, `_runTools`, `_refuseRound`, `_hiddenFor`, `_raiseFloorToTaint`, `_withoutPrivateHistory`, `_checkBeforeCall`, `_retryCurrentCall`, `_assignCallIds`, `_earlierExecution`), `packages/wendelin_agent/test/agent_runner_test.dart`, `packages/wendelin_agent/test/support.dart`.

**Kollisionsprüfung (2026-10-13):** Kein laufendes oder geplantes Paket ändert `wendelin_agent/lib/src/agent_runner.dart`. Die Branches von WP30, WP32 und WP33 haben keine Commits in `packages/wendelin_agent`. WP27 (im Review) ändert `wendelin_agent` nicht. WP31 ändert `app/lib/agent/agent_controller.dart` (`newTopic`), nicht den Runner. WP29 nutzt den Runner in `evals/` nur über die öffentliche API, die hier unverändert bleibt. Vor dem Start prüft der Coder das erneut (`git log main..<branch> -- packages/wendelin_agent` für alle offenen `wp/*`-Branches). Ein neues Paket, das den Runner ändert (z. B. weitere Routing- oder Eskalationsregeln), startet erst nach dem Merge von WP37.

## Inhalt

**Zerlegung von `_Run`** (Vorschlag des Gutachtens, der Coder darf Schnitte begründet anpassen):
- `src/run/privacy_scope.dart`: Privatsphäre und Taint. Untergrenze aus Ziel und Verlauf, Anheben auf die Taint-Stufe (`_raiseFloorToTaint`), Ausblenden von Tools je Zielstufe (`_hiddenFor`), Verlauf ohne private Teile (`_withoutPrivateHistory`), Zustimmung unter der Untergrenze (`_belowFloorConsented`, `_consentDeclined`). Eine Klasse mit klarer Schnittstelle, die `_Run` fragt („darf dieses Ziel diese Nachricht sehen?“, „welche Tools sind sichtbar?“).
- `src/run/run_budget.dart`: Runden, Runden je Provider, Tokens, ungültige Aufrufe, Budget-Warnung. Wertobjekt oder kleine Klasse mit `onRound()`, `onTokens()`, `onInvalidCall()`, `onEscalated()` (setzt die Zähler je Provider zurück) und Abfragen wie `exhausted`. Grenzwerte (8 Runden, Token-Limit) bleiben dieselben Konstanten.
- `src/run/escalation.dart`: `_escalate` mit den Gründen (`userRequested`, `providerError`, `modelGaveUp` …), Kettenauswahl über den Resolver, Wechsel des Providers, Ereignis `Routed`.
- `src/run/tool_round.dart`: `_runTools`, `_refuseRound`, `_sourceIds`, `_earlierExecution`, `_assignCallIds`. Ausführung einer Tool-Runde einschließlich Ablehnung, Bestätigung, Quellen-IDs für Taint.
- `agent_runner.dart` behält `AgentRunner`, die Schleife (`drive`, `_loop`) und die Ereignis-Ausgabe (`emit`, `_segmentStreamed` → `AgentTextReset`). Ziel ≤ ca. 400 Zeilen. `_loop` wird so gegliedert, dass jeder `continue`-Pfad eine benannte Methode oder einen benannten Fall hat (z. B. `_retryOrEscalateOnError`, `_handlePauseTurn`).
- **Zustand bündeln:** Die 18 Felder von `_Run` werden auf die neuen Klassen verteilt. Was in `_Run` bleibt, steht in einem kommentierten Block „Lauf-Zustand“. `_epoch`, `_abortKind`, `_timer`, `_current`, `_context`, `_messages` gehören erkennbar zusammen.
- **Invarianten-Kommentare:** Jede Invariante, die heute über die Klasse verteilt ist, steht als kurzer Kommentar an der Stelle, die sie erzwingt, und im Doc-Kommentar der Klasse. Mindestens: Zähler je Provider werden bei Eskalation zurückgesetzt; die Privatsphäre-Untergrenze sinkt in einem Lauf nie; nach einem geschützten Ergebnis steigt die Untergrenze auf die Taint-Stufe; `_segmentStreamed` steuert `AgentTextReset`; `pauseTurn` ohne Tool-Aufruf setzt fort, ohne eine Runde zu zählen (bzw. wie heute in `agent_runner.dart:318-323` beschrieben); Abbruch hat Vorrang vor Fehler; ein wiederholter Aufruf nach retrybarem Fehler passiert höchstens einmal je Runde.
- Alle neuen Dateien sind `src/`-intern (nicht exportiert). Die öffentliche API (`AgentRunner`, Konstruktorparameter, `AgentRun`, Events) bleibt unverändert, auch `AgentRunner.hiddenTool`.

**Tests aufteilen**
- `agent_runner_test.dart` (2 054 Zeilen) wird nach Themen in vier bis fünf Dateien geschnitten, z. B. `test/run/loop_test.dart` (Grundablauf, Abbruch, Timeout, Pause), `test/run/privacy_test.dart` (Untergrenze, Taint, Tool-Katalog, Zustimmung), `test/run/budget_test.dart` (Runden, Tokens, ungültige Aufrufe), `test/run/escalation_test.dart`, `test/run/tool_round_test.dart`. Jede Datei ≤ 600 Zeilen. Gemeinsame Helfer in `test/support.dart` bzw. `test/run/run_support.dart`.
- Die Testfälle ziehen **unverändert** um (Name, Aufbau, Erwartung). Jeder bisherige Testname existiert danach genau einmal (Liste vorher/nachher per `dart test --reporter=json` oder `grep "test('"`, im Bericht abgeglichen).
- Neue Unit-Tests für `RunBudget` und `PrivacyScope` direkt (ohne Schleife) sind erwünscht, ersetzen aber keinen Schleifentest.

## Abnahmekriterien
- [ ] Verhaltensneutral: öffentliche API von `wendelin_agent` unverändert (Diff von `lib/wendelin_agent.dart` und der exportierten Typen leer). Ereignisfolgen identisch. Bestehende Testfälle ziehen unverändert um, keine geänderte Erwartung. App, `wendelin_voice` und `evals` kompilieren ohne Änderung.
- [ ] Abgleich der Testnamen vorher/nachher im Bericht: keiner fehlt, keiner doppelt. Testanzahl in `wendelin_agent` ≥ vorher.
- [ ] `agent_runner.dart` ≤ ca. 400 Zeilen, keine Funktion > 80 Zeilen in `src/run/` und im Runner, `_Run` mit höchstens 8 eigenen veränderlichen Feldern. `agent_runner.dart` von der Größen-Allowlist (WP35) entfernt.
- [ ] Testdateien je ≤ 600 Zeilen, `agent_runner_test.dart` existiert nicht mehr als Sammeldatei (oder nur noch als kleiner Rest ≤ 600 Zeilen).
- [ ] Invarianten-Kommentare an allen oben genannten Stellen. Liste der Invarianten mit alter und neuer Fundstelle im Bericht.
- [ ] Mutationsproben im Review (≥ 8, weil Kernlogik): u. a. Zähler bei Eskalation nicht zurücksetzen, Taint-Anhebung entfernen, Untergrenze darf sinken, Rundengrenze ±1, Retry zweimal statt einmal, `AgentTextReset` nicht senden, Abbruch nach Fehler prüfen statt davor, ausgeblendetes Tool doch anbieten. Jede Mutation macht einen Test rot.
- [ ] Abdeckung `wendelin_agent` ≥ vorher (99,1 %), Gate grün (voll, weil App und voice den Runner nutzen).
- [ ] Diff-Richtwert: ≤ ca. 1 500 Zeilen geänderter Produktivcode; Testverschiebung und reine Verschiebungen ausgewiesen. Wird der Richtwert überschritten, Schnitt in WP37a (Budget, Eskalation) und WP37b (Privatsphäre, Tool-Runde, Testaufteilung).
- [ ] Messwerte vorher/nachher im Bericht: Zeilen `agent_runner.dart`, Felder von `_Run`, längste Funktion, Zahl der `continue`-Pfade in `_loop`, Zeilen der größten Testdatei, Abdeckung, Testanzahl, Laufzeit `dart run tool/gate.dart wendelin_agent`.
- [ ] `docs/ARCHITECTURE.md` (Abschnitte „Datenfluss“ und „Datenschutz und Taint“) zeigt auf die neuen Dateien. ADR 0003 bekommt einen Absatz zur Aufteilung.

Gerätetests: keine nötig (reines Dart). Falls doch ein Emulatorlauf erfolgt, nur `Wendelin_AOSP_35` mit explizitem Serial (`R-refactoring.md`).
