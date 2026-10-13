# wendelin_providers

LLM-Adapter in reinem Dart: Anthropic Messages API und OpenAI-kompatible Chat Completions (OpenAI, Phala, OpenRouter, Mistral, Tinfoil, Ollama, eigene Endpunkte). Dazu Modellkatalog, Provider-Vorlagen und Kosten.

- `package:wendelin_providers/wendelin_providers.dart`: API (kein `fakes.dart`; Fakes für `LlmProvider` liegen in `wendelin_core`)

## Einstiegspunkte

| Datei | Inhalt |
| --- | --- |
| `lib/src/provider_factory.dart` | `ProviderFactory`: baut aus einem `ProviderProfile` und den Zugangsdaten einen `LlmProvider` |
| `lib/src/anthropic/` | `AnthropicMessagesAdapter`, Request-Bau, Stream-Decoder, Fehlerabbildung |
| `lib/src/openai/` | `OpenAiChatAdapter`, Request-Bau, Stream-Decoder, Fehlerabbildung |
| `lib/src/common/` | `HttpTransport` (Streaming, Timeouts, Abbruch), `runHealthProbe` (Verbindungs- und Modelltest), `Redactor` (keine Keys in Logs), `Credentials` |
| `lib/src/catalog/` | `ModelCatalog`, `ProviderTemplate` (Vorlagen der Einrichtung), `CostCalculator` |

## Regeln

- Provider-JSON (Wire-Format) existiert nur unter `lib/src/anthropic/` und `lib/src/openai/`; `tool/check_deps.dart` prüft das.
- Jeder Adapter besteht `llmProviderContract` (aus `package:wendelin_core/testing.dart`) gegen aufgezeichnete Streams in `test/fixtures/`.
- Debug-Logs ohne `x-api-key`/`Authorization` (siehe `Redactor`).
- Live-Tests tragen `@Tags(['live'])` und laufen nur mit Key aus der Umgebung.
