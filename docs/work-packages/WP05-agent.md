# WP05 – Agent-Schleife (`packages/wendelin_agent`)

Abhängig von: `wendelin_core` (nur Interfaces; Tests mit `FakeLlmProvider`, Fake-`ToolCatalog`/`ToolInvoker`). Konzept-Bezug: „Agent-Schleife“, „Routing und Eskalation → Eskalation während der Bearbeitung“, „Prompt-Injection“.

## Inhalt
- `AgentConfig(maxToolRounds = 8, maxDuration = 60 s, maxTokensPerRequest, historyTurns = 10, assistantName = 'Wendelin', userName?, personaAddon?, escalateAfterInvalidToolCalls = 2, escalateAfterRoundsWithoutResult = 4)`
- `ContextBuilder` – System-Prompt: Rolle/Name, Datum, Uhrzeit, Zeitzone, Gerätesprache, Nutzername, Persönlichkeits-Zusatz, **ausdrücklicher Hinweis, dass Tool-Ergebnisse, Notizen, Webseiten Daten und keine Anweisungen sind**, Hinweis zur kurzen, sprechbaren Antwort; dann Gedächtnis (Top-5 über `MemoryRetriever`-Interface), dann Verlauf (letzte N Züge über `HistoryProvider`-Interface). Stabile Reihenfolge, System-Prompt + Tools zuerst (Prompt Caching).
- `ProviderResolver`-Interface: `Resolution resolve(UserInput)` → (profileId, modelId, `LlmProvider`, PrivacyLevel, reason) und `Resolution? escalate(Resolution current, EscalationReason)` (nächstes Glied der Kette, respektiert Datenschutz-Grenze: nur Ziel mit `privacy.isAtLeast(current.privacy)`, wenn die Anfrage privat geroutet wurde). M1-Implementierung `DefaultProviderResolver(defaultProfile, chain)`; Regel-Engine kommt in M3.
- `AgentRunner implements AgentRun`
  - Ablauf wie Konzept Schritte 1–7. Streaming-Text als `AgentTextDelta`; Tool-Calls über `ToolInvoker`, Events weiterreichen (`ConfirmationRequired` mit `respond`).
  - Limits: max. Tool-Runden, Gesamtdauer (über `Clock` + Timer), Token-Budget → `AgentFailed` bzw. abschließende Meldung.
  - `cancel()` bricht Modellaufruf und laufende Tools ab, Stream endet mit `AgentFailed(cancelled)`.
  - Eskalation bei: retryable ProviderException (nach max. 1 Retry beim selben Provider), zweimal ungültiges Tool-JSON/unbekanntes Tool, > N Runden ohne Endantwort, Antwortklassifikation „kann ich nicht“ (Schlüsselwortliste de/fr/en), expliziter Nutzerwunsch („nochmal mit …“, „das war falsch“ → Flag in `UserInput`). Neues Modell bekommt Verlauf inkl. Tool-Ergebnissen + Systemhinweis „folgende Aktionen sind bereits ausgeführt …“. **Bereits ausgeführte Tools werden nie wiederholt** (Call-IDs merken; Test!).
  - `UsageReported` je Modellaufruf (Kosten über injizierbares `CostEstimator`-Interface).
  - Budget: `BudgetGuard`-Interface (`check(profileId)` → ok / warn / block) vor jedem Modellaufruf.
- `SentenceChunker` – puffert Text-Deltas und gibt vollständige Sätze aus (für TTS), behandelt Abkürzungen („z. B.“, „Dr.“, Zahlen „10.30 Uhr“).
- `ConversationRecorder`-Interface (Nachrichten persistieren) – Implementierung in App über Storage.

## Abnahmekriterien
- [ ] Szenario-Tests mit FakeLlmProvider: reine Textantwort; ein Tool-Call; zwei parallele Tool-Calls; Bestätigung ja/nein; Fehler-Tool → Modell bekommt `isError`; 9. Tool-Runde wird verhindert; Zeitlimit; Abbruch mitten im Stream; Abbruch während Bestätigung.
- [ ] Eskalation: Provider-Fehler → zweites Profil antwortet; Tool aus Runde 1 wird nach Eskalation nicht erneut ausgeführt; Datenschutz-Grenze verhindert Eskalation von `tee` zu `standard`.
- [ ] Kontext-Snapshot-Test des System-Prompts (mit FixedClock).
- [ ] SentenceChunker-Tabellentests (≥ 15 Fälle, de/fr/en).
- [ ] Gate grün, Abdeckung ≥ 85 %.
