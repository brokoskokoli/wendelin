# wendelin_core

Verträge, die alle anderen Pakete teilen. Reines Dart ohne Abhängigkeiten außer `meta` und `collection` (ADR 0002). Hier stehen Typen, keine Logik mit Seiteneffekten.

- `package:wendelin_core/wendelin_core.dart`: API
- `package:wendelin_core/fakes.dart`: `FakeLlmProvider` (auch für den Demo-Modus der App) und Fake-Tools, ohne `package:test`
- `package:wendelin_core/testing.dart`: Fakes plus Contract-Suites `llmProviderContract` und `toolInvokerContract`

## Wichtige Typen

| Bereich | Ordner | Typen |
| --- | --- | --- |
| Nachrichten | `lib/src/messages/` | `Message` (mit `privacyFloor`), `ContentBlock` (sealed), `ChatRequest`, `ChatEvent` (sealed, Stream eines Providers), `ToolSpec`, `Usage`, `StopReason` |
| Provider | `lib/src/provider/` | `LlmProvider`, `ProviderProfile`, `ProviderType`, `PrivacyLevel`, `ModelInfo`, `ProviderException` und Unterklassen, `CancelToken` |
| Tools | `lib/src/tools/` | `Tool`, `RiskLevel`, `Integration`, `ToolContext`, `ToolOutcome`, `ToolInvoker` (`tool_runtime.dart`) |
| Agent | `lib/src/agent/` | `AgentRun`, `AgentEvent` (sealed, Events an die UI), `UserInput` |
| Sicherheit | `lib/src/safety/` | `SensitiveFinding`, Erkennung sensibler Inhalte |
| Werkzeuge | `lib/src/util/`, `lib/src/sse/` | `Clock`, `IdGenerator`, JSON-Lesehilfen, `SseParser` |

## Regeln

- Neue Felder an Wertobjekten mit `==`/`hashCode`, `toJson`/`fromJson` und Test.
- Zeit und Ids nur über `Clock` und `IdGenerator`.
- Eine neue Abhängigkeit dieses Pakets ist eine Architekturentscheidung (ADR).
