# wendelin_agent

Agent-Schleife in reinem Dart: Kontext aufbauen, Modell aufrufen, Tools ausführen lassen, Limits und Eskalation, Routing-Regeln (ADR 0003, ADR 0009). Nutzt Provider und Tools nur über die Schnittstellen aus `wendelin_core`.

- `package:wendelin_agent/wendelin_agent.dart`: API
- `package:wendelin_agent/fakes.dart`: Fakes der Ports und des Routings, ohne `package:test`
- `package:wendelin_agent/testing.dart`: Fakes plus Contract-Suite `toolCategoryMatcherContract`

## Einstiegspunkte

| Datei | Inhalt |
| --- | --- |
| `lib/src/agent_runner.dart` | `AgentRunner` (`AgentRun`): eine Anfrage bis zur Antwort, Runden, Budget, Eskalation, Pause bei Bestätigung, Taint und Privatsphäre-Untergrenze. WP37 zerlegt die Datei. |
| `lib/src/agent_config.dart` | `AgentConfig` (Runden, Zeit, Tokens, Systemprompt) |
| `lib/src/context_builder.dart` | `ContextBuilder`: Systemprompt, Gedächtnis, Verlauf |
| `lib/src/provider_resolver.dart` | `ProviderResolver`, `Resolution`: welches Ziel eine Anfrage bekommt |
| `lib/src/routing/` | Regeln (`rule_set.dart`, JSON in `rule_set_json.dart`), Bedingungen (`conditions.dart`), Auswertung (`routing_engine.dart`), `RuleBasedProviderResolver` |
| `lib/src/ports.dart` | `MemoryRetriever`, `HistoryProvider`, `ConversationRecorder`, `CostEstimator`, `BudgetGuard` |
| `lib/src/give_up_classifier.dart`, `lib/src/sentence_chunker.dart` | Aufgabe-Erkennung für die Eskalation, Satzweise Ausgabe für die Sprache |

## Regeln

- Invarianten zu Datenschutz und Eskalation sind in `agent_runner.dart` kommentiert; Änderungen daran brauchen Tests und Mutationsproben.
- Neue Ports gehören nach `lib/src/ports.dart`, ihre Fakes nach `lib/testing/`.
