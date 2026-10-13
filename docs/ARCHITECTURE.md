# Architekturkarte

Wo liegt was, und welche Dateien gehören zu einer Änderung? Regeln und Abhängigkeiten stehen in `docs/ENGINEERING.md`, Entscheidungen in `docs/adr/`. Alle Pfadangaben hier prüft `tool/check_docs.dart` im Gate. Wer Dateien verschiebt, führt diese Karte nach.

## Pakete (reines Dart, `packages/`)

Kurzfassung der Abhängigkeiten (geprüft von `tool/check_deps.dart`): `core` hängt von nichts ab; `providers`, `tools`, `agent`, `storage`, `integrations` nur von `core`; `voice` von `core` und `agent`; `mcp` von `core` und `integrations`; `evals` von `core`, `providers`, `tools`, `agent`, `integrations`; die App von allen. Pakete mit Schnittstellen (alle außer `providers` und `tools`) haben `fakes.dart` (Fakes ohne `package:test`) und `testing.dart` (Fakes plus Contract-Suites).

| Paket | Einstieg | Wichtige Typen und Dateien |
| --- | --- | --- |
| `wendelin_core` | `packages/wendelin_core/lib/wendelin_core.dart` | Nachrichten (`Message`, `ContentBlock`, `ChatEvent`) in `src/messages/`, `LlmProvider`, `ProviderProfile`, `PrivacyLevel` in `src/provider/`, `Tool`, `Integration`, `ToolOutcome` in `src/tools/`, `AgentEvent` in `src/agent/agent_event.dart`, `Clock`/`IdGenerator` in `src/util/` |
| `wendelin_providers` | `packages/wendelin_providers/lib/wendelin_providers.dart` | Adapter `src/anthropic/anthropic_adapter.dart`, `src/openai/openai_adapter.dart`, `ProviderFactory` (`src/provider_factory.dart`), Modellkatalog und Kosten in `src/catalog/`, HTTP in `src/common/http_transport.dart` |
| `wendelin_tools` | `packages/wendelin_tools/lib/wendelin_tools.dart` | `ToolRegistry` (`src/registry/tool_registry.dart`), `ToolExecutor` (`src/executor/tool_executor.dart`), `RiskPolicy` (`src/policy/risk_policy.dart`), `UndoManager` (`src/undo/undo_manager.dart`), `ArgumentValidator`, `ToolAuditSink` |
| `wendelin_agent` | `packages/wendelin_agent/lib/wendelin_agent.dart` | `AgentRunner` (`src/agent_runner.dart`), `ContextBuilder`, `ProviderResolver`, Routing-Regeln in `src/routing/` (`RuleBasedProviderResolver`, `routing_engine.dart`, `conditions.dart`), `SentenceChunker`, Ports in `src/ports.dart` |
| `wendelin_storage` | `packages/wendelin_storage/lib/wendelin_storage.dart` | drift-Datenbank `src/db/database.dart` und Tabellen `src/db/tables.dart`, Repositories (`src/repositories/repositories.dart`, Umsetzung `src/db/*_impl.dart`), `SecretStore` (`src/secret_store.dart`), Schema-Tests unter `test/drift/` |
| `wendelin_integrations` | `packages/wendelin_integrations/lib/wendelin_integrations.dart` | Je Integration ein Ordner unter `src/`: `calendar/`, `clipboard/`, `alarms/`, `memory/`, `web/` (Abruf, Suche), `lists/`, `obsidian/`, `bring/`, `http_tools/`; gemeinsame Bausteine in `src/common/` (`base_tool.dart`, `tool_args.dart`, `matching.dart`, `app_presence.dart`, `net_scope.dart`) |
| `wendelin_voice` | `packages/wendelin_voice/lib/wendelin_voice.dart` | `VoicePipeline` (`src/pipeline/voice_pipeline.dart`), `Endpointer`, Schnittstellen in `src/io/`, `SpokenAnswer` (`src/text/spoken_answer.dart`), `TtsSelector`, Modellkatalog und Download in `src/models/` |
| `wendelin_mcp` | `packages/wendelin_mcp/lib/wendelin_mcp.dart` | `McpClient` (`src/client.dart`), Transporte in `src/transport/`, OAuth in `src/oauth/oauth_flow.dart`, Abbildung auf Tools in `src/tools/mcp_integration.dart`, Netzregeln `src/net_policy.dart` |
| `evals` | `evals/lib/src/cli.dart` | Modell-Evals und Live-Tests (`evals/README.md`) |

## App (`app/lib`)

| Ordner | Inhalt |
| --- | --- |
| `app/lib/main.dart`, `app/lib/app.dart` | Drei Einstiege: `main` (App), `assistantMain` (Overlay-Engine), `recognizerMain` (Spracherkennung für andere Apps, ADR 0008) |
| `app/lib/agent/` | `AgentController` (Anfragen, Bestätigungen, Undo), `ConversationReducer` und `ConversationState` (Events → UI-Zustand). Dazu fachfremd `bring_share.dart` und `money.dart` (N7) |
| `app/lib/di/` | Riverpod-Verdrahtung. Enthält heute auch App-Logik (`http_tool_draft.dart`, `http_tools.dart`, `user_integrations.dart`, Teile von `voice_providers.dart`); WP39 zieht sie in Pakete. Neue Logik gehört in ein Paket, nicht hierher |
| `app/lib/platform/` | Implementierungen der Ports (Kanäle, Plugins, sherpa-onnx in `app/lib/platform/voice/`, Spracherkennung in `app/lib/platform/recognizer/`) |
| `app/lib/ui/` | `design/` (Bausteine, Galerie), `screens/` (Hauptbildschirm, Texte in `labels.dart`), `settings/`, `onboarding/`, `overlay/`, `theme/`, Routen in `app/lib/ui/routes.dart` |
| `app/lib/voice/` | `VoiceController` (Mikrofon, Pipeline, Sprachbestätigung), `voice_components.dart` |
| `app/lib/debug/` | Überschreibungen für Gerätetests (nur Debug-Builds) |

## Ports

Ports liegen in dem Paket, das sie braucht; die Flutter-Implementierung liegt in `app/lib/platform/` (Ausnahmen: Adapter auf Repositories, Kosten und `SecretStore` liegen heute in `app/lib/di/`).

| Port | Fundort | App-Implementierung |
| --- | --- | --- |
| `CalendarPort` | `packages/wendelin_integrations/lib/src/calendar/calendar_port.dart` | `app/lib/platform/device_calendar_port.dart` |
| `ClipboardPort` | `packages/wendelin_integrations/lib/src/clipboard/clipboard.dart` | `app/lib/platform/flutter_clipboard_port.dart` |
| `AlarmPort` | `packages/wendelin_integrations/lib/src/alarms/alarms.dart` | `app/lib/platform/android_alarm_port.dart` |
| `MemoryStorePort` | `packages/wendelin_integrations/lib/src/memory/memory.dart` | `app/lib/platform/repository_memory_port.dart` |
| `ListFilePort` | `packages/wendelin_integrations/lib/src/lists/lists.dart` | `app/lib/platform/saf_list_file_port.dart` |
| `VaultPort`, `NoteIndexPort` | `packages/wendelin_integrations/lib/src/obsidian/ports.dart` | `app/lib/platform/saf_vault_port.dart`, `app/lib/platform/repository_note_index_port.dart` |
| `AppPresencePort` | `packages/wendelin_integrations/lib/src/common/app_presence.dart` | `app/lib/platform/channel_app_presence_port.dart` |
| `BringApi`, `BringSecrets` | `packages/wendelin_integrations/lib/src/bring/bring_api.dart` | `HttpBringApi` im Paket, Secrets in `app/lib/di/bring.dart` |
| `WebSearchBackend` | `packages/wendelin_integrations/lib/src/web/web_search_backend.dart` | Brave, Tavily, SearXNG im Paket, Auswahl in `app/lib/di/web_search.dart` |
| `HttpToolSecrets`, `HttpToolTransport` | `packages/wendelin_integrations/lib/src/http_tools/http_transport.dart` | Transporte im Paket, Secrets in `app/lib/di/http_tools.dart` |
| `McpSecrets`, `AuthorizationBrowser`, `McpCacheStore` | `packages/wendelin_mcp/lib/src/ports.dart` | folgt mit WP27 |
| `MemoryRetriever`, `HistoryProvider`, `ConversationRecorder`, `CostEstimator`, `BudgetGuard` | `packages/wendelin_agent/lib/src/ports.dart` | `app/lib/di/storage_adapters.dart`, `app/lib/di/costs.dart` |
| `NetworkStatus` | `packages/wendelin_agent/lib/src/routing/routing_context.dart` | `app/lib/platform/channel_network_status.dart` |
| `AudioInput`, `VoiceActivityDetector`, `SpeechToText`, `TextToSpeech`, `TriggerSource` | `packages/wendelin_voice/lib/src/io/` | `app/lib/platform/voice/` (`record_audio_input.dart`, `silero_vad.dart`, `whisper_stt.dart`, `system_tts.dart`, `sherpa_tts.dart`), `app/lib/platform/assistant_platform.dart` |
| `ModelStore` | `packages/wendelin_voice/lib/src/models/model_store.dart` | `app/lib/platform/voice/file_model_store.dart` |
| `SecretStore` | `packages/wendelin_storage/lib/src/secret_store.dart` | `app/lib/platform/secure_secret_store.dart` |

## App-Verdrahtung

- **Start:** `app/lib/main.dart` öffnet die Datenbank (`openAppStorage`), liest `StartupSettings` (`app/lib/di/startup.dart`) und startet `WendelinApp` (`app/lib/app.dart`) bzw. das Overlay. Grundlage: ADR 0004.
- **Provider nach Bereich:** Basis (Uhr, Ids, Storage, Secrets, HTTP) und Integrationen, Agent, Kosten in `app/lib/di/providers.dart` (wird mit WP38 geschnitten); Sprache in `app/lib/di/voice_providers.dart`; Provider-Profile und Routing in `app/lib/di/provider_config.dart`, `app/lib/di/routing.dart`; Agent-Bau in `app/lib/di/agent_factory.dart`; Einstellungen in `app/lib/di/preferences.dart`, `app/lib/di/app_settings.dart`.
- **Integrationsregistry:** eingebaute Integrationen als `IntegrationSpec` in `app/lib/di/integration_specs.dart`, Geräteports gebündelt in `PlatformPorts` (`app/lib/platform/platform_ports.dart`). `IntegrationActivator` (`app/lib/di/integration_activator.dart`) schaltet ein und aus und fragt erst dann nach Berechtigungen. Nutzerdefinierte Integrationen (HTTP-Tools, MCP) kommen als `UserIntegrationSource` über `UserIntegrationSync` (`app/lib/di/user_integrations.dart`, ADR 0012).
- **Overlay-Engine:** `assistantMain` startet `AssistantOverlayApp` (`app/lib/ui/overlay/assistant_overlay.dart`) in eigener Flutter-Engine, gestartet von `AssistantActivity.kt`; beide Engines teilen die Datenbank über einen drift-Isolate (ADR 0006).

## Datenfluss einer Anfrage

1. **Auslöser:** Mikrofon im Hauptbildschirm (`app/lib/ui/screens/main_screen.dart`, `app/lib/ui/design/mic_button.dart`), Power-Taste (`WendelinVoiceInteractionService.kt` → `WendelinVoiceSessionService.kt` → `AssistantActivity.kt` → Overlay, `AssistantTriggerSource` in `app/lib/platform/assistant_platform.dart`) oder Texteingabe (`app/lib/ui/screens/main_parts.dart`).
2. **Sprache:** `VoiceController` (`app/lib/voice/voice_controller.dart`) baut die `VoicePipeline` und übergibt den erkannten Text.
3. **Agent:** `AgentController.send` (`app/lib/agent/agent_controller.dart`) baut über `agentFactoryProvider` (`app/lib/di/agent_factory.dart`) einen `AgentRunner`.
4. **Routing:** `ProviderResolver` aus `app/lib/di/provider_config.dart`, Regeln in `packages/wendelin_agent/lib/src/routing/rule_based_resolver.dart` (ADR 0009). Start eines Laufs (Routing, Kontext, Untergrenze einer Wiederholung) in `packages/wendelin_agent/lib/src/run/run_start.dart`, Eskalation und Wiederholung in `packages/wendelin_agent/lib/src/run/escalation.dart`.
5. **Modell:** `AgentRunner` (`packages/wendelin_agent/lib/src/agent_runner.dart`) führt die Schleife (`_Run`). Den Kontext baut `context_builder.dart`, den Modellaufruf mit System-Prompt und Streaming `packages/wendelin_agent/lib/src/run/model_call.dart`, Limits zählt `packages/wendelin_agent/lib/src/run/run_budget.dart`, Tool-Runden führt `packages/wendelin_agent/lib/src/run/tool_round.dart` aus. Den gemeinsamen Zustand eines Laufs hält `packages/wendelin_agent/lib/src/run/run_state.dart`. Der Adapter kommt aus `wendelin_providers`.
6. **Tools:** `ToolExecutor` (`packages/wendelin_tools/lib/src/executor/tool_executor.dart`) prüft Argumente und Risiko (`RiskPolicy`), holt Bestätigungen und schreibt das Audit.
7. **Integration → Port → Plattform:** z. B. `calendar_tools.dart` → `CalendarPort` → `app/lib/platform/device_calendar_port.dart` → `CalendarChannel.kt`.
8. **Zurück:** `AgentEvent` (`packages/wendelin_core/lib/src/agent/agent_event.dart`) → `ConversationReducer` (`app/lib/agent/conversation_reducer.dart`) → Anzeige in `app/lib/ui/screens/conversation_view.dart` mit Tool-Karte (`app/lib/ui/design/tool_result_card.dart`), Bestätigung (`app/lib/ui/screens/confirmation_sheet.dart`, per Sprache `yes_no.dart`), Undo (`UndoManager`), Audit (`app/lib/di/audit_recorder.dart` → `packages/wendelin_storage/lib/src/db/audit_log_repository_impl.dart`).

## Datenschutz und Taint (K9, K10)

- Stufen: `PrivacyLevel` (`packages/wendelin_core/lib/src/provider/privacy_level.dart`), Untergrenze je Nachricht als `Message.privacyFloor`.
- Tool-Katalog je Zielstufe: sensible Integrationen nur für ausreichend geschützte Ziele in `packages/wendelin_tools/lib/src/registry/tool_registry.dart`; Nutzer-Markierung „sensibel“ in `app/lib/di/sensitivity.dart`.
- Ausblenden geschützter Ergebnisse, Privatsphäre-Untergrenze und Taint: `PrivacyScope` (`hiddenFor`, `messagesFor`, `raiseFloorToTaint`, `visibleMemories`) in `packages/wendelin_agent/lib/src/run/privacy_scope.dart`. Dass die Untergrenze nie sinkt, erzwingt `RunState.raiseFloor` in `packages/wendelin_agent/lib/src/run/run_state.dart`.
- Ablehnung von Aufrufen auf nicht sichtbare Tools: `ToolRound` in `packages/wendelin_agent/lib/src/run/tool_round.dart`.
- Eskalation unter die Stufe nur mit Rückfrage: `Escalation` in `packages/wendelin_agent/lib/src/run/escalation.dart`, Regel „Privat“ in `packages/wendelin_agent/lib/src/routing/routing_engine.dart` und `app/lib/di/routing.dart`.
- Sensible Inhalte (Secrets, Kartennummern) erkennen: `packages/wendelin_core/lib/src/safety/sensitive_content.dart`, Sperre beim Speichern in `packages/wendelin_storage/lib/src/sensitive_content.dart`.

## Voice-Pipeline (ADR 0007, 0008)

VAD (`app/lib/platform/voice/silero_vad.dart`) → STT (`app/lib/platform/voice/whisper_stt.dart`) → Endpointing (`packages/wendelin_voice/lib/src/pipeline/endpointer.dart`) → Agent → Sprechtext (`spoken_answer.dart`, `SentenceChunker`) → TTS (`TtsSelector`, `speech_queue.dart`, System-TTS mit sherpa-Fallback). Modellkatalog `speech_model_catalog.dart`, Download `model_downloader.dart`, Installation `app/lib/platform/voice/model_installer.dart`. Whisper wird zwischen Overlay, App und Spracherkennung geteilt: `app/lib/platform/voice/whisper_share.dart`, `app/lib/platform/voice/whisper_registry.dart`.

## Plattformkanäle

Kotlin unter `app/android/app/src/main/kotlin/app/wendelin/`. Kanalnamen sind Strings auf beiden Seiten (WP40 prüft sie künftig).

| Kanal (`app.wendelin/…`) | Dart | Kotlin |
| --- | --- | --- |
| calendar | `app/lib/platform/device_calendar_port.dart` | `CalendarChannel.kt` |
| files | `app/lib/platform/saf_list_file_port.dart`, `app/lib/platform/document_text_import.dart` | `FilesChannel.kt` |
| vault | `app/lib/platform/saf_vault_port.dart` | `VaultChannel.kt` |
| apps | `app/lib/platform/channel_app_presence_port.dart` | `AppsChannel.kt` |
| network | `app/lib/platform/channel_network_status.dart` | `NetworkChannel.kt` |
| assistant | `app/lib/platform/assistant_platform.dart` | `AssistantChannel.kt` |
| window | `app/lib/platform/screen_protection.dart` | `WindowChannel.kt` |
| recognizer | `app/lib/platform/recognizer/recognizer_host.dart` | `RecognizerEngine.kt` (mit `WendelinRecognitionService.kt`, `RecognizerSwitch.kt`) |

## HTTP-Stacks (N3)

Bewusst getrennt, je mit eigenen Timeouts und Fehlerabbildung. **Keinen neuen Stack anlegen**, sondern den passenden erweitern:
- LLM-Aufrufe und SSE: `packages/wendelin_providers/lib/src/common/http_transport.dart`
- MCP: `packages/wendelin_mcp/lib/src/transport/http_call.dart`
- Web-Abruf mit Zielprüfung: `packages/wendelin_integrations/lib/src/web/web_fetcher.dart` (`fetch_guard.dart`)
- Bring!: `packages/wendelin_integrations/lib/src/bring/http_bring_api.dart`
- HTTP-Tools: `packages/wendelin_integrations/lib/src/http_tools/http_transport.dart` (`http_target.dart`, ADR 0011)
- Modell-Download: `packages/wendelin_voice/lib/src/models/model_downloader.dart`

Netzziele: Adressbereiche (Loopback, RFC 1918, CGNAT/Tailscale, ULA, Link-Local, IPv4 in IPv6 …) klassifiziert **nur** `packages/wendelin_integrations/lib/src/common/net_scope.dart` (`classifyNet`, `NetScope`, `HostResolver`). `fetch_guard.dart` und `http_target.dart` enthalten nur ihre Policy (welche Bereiche erlaubt sind, welche Meldung kommt). `packages/wendelin_mcp/lib/src/net_policy.dart` stellt WP36 b darauf um.

## Checklisten „Feature → Dateien“

**Neue eingebaute Integration**
1. Ordner `packages/wendelin_integrations/lib/src/<name>/` mit Integration, Tools und ggf. Port; `README.md` im Ordner (Tools, Risiko, Berechtigungen).
2. Export in `packages/wendelin_integrations/lib/wendelin_integrations.dart`, Fakes und Contract in `fakes.dart`/`testing.dart` (nur anhängen).
3. Port-Implementierung in `app/lib/platform/`, Feld in `PlatformPorts`.
4. `IntegrationSpec` in `app/lib/di/integration_specs.dart`; Einrichtungsseite ggf. in `app/lib/ui/settings/settings_routes.dart`.
5. Texte in `app/lib/ui/screens/labels.dart`, Berechtigung ggf. in `AndroidManifest.xml`.
6. Tests im Paket, Verdrahtung in `app/test/di/wiring_test.dart`.

**Neue Einstellungsseite**
1. Screen in `app/lib/ui/settings/` (Gerüst `settings_page.dart`).
2. Route in `app/lib/ui/routes.dart`, Eintrag in `app/lib/ui/settings/settings_screen.dart`.
3. Gespeicherte Werte in `app/lib/di/preferences.dart` bzw. `app/lib/di/preference_models.dart`.
4. Widget- und Golden-Test unter `app/test/settings/` (Goldens nur auf macOS aktualisieren).

**Neuer Kotlin-Kanal**
1. Kotlin-Klasse in `app/android/app/src/main/kotlin/app/wendelin/`, registriert in `WendelinActivity.kt` (Basis von `MainActivity.kt` und `AssistantActivity.kt`).
2. Dart-Seite in `app/lib/platform/` mit Kanalname als Konstante, Test mit Mock-Handler unter `app/test/platform/`.
3. Zeile in der Tabelle oben.

**Neue Provider-Art**
1. Adapter unter `packages/wendelin_providers/lib/src/<adapter>/` (Wire-Format nur dort), Contract-Suite `llmProviderContract` aus `wendelin_core`.
2. `ProviderType` (`packages/wendelin_core/lib/src/provider/provider_type.dart`), `ProviderFactory`, Vorlage in `packages/wendelin_providers/lib/src/catalog/provider_template.dart`.
3. Einrichtung in `app/lib/ui/settings/provider_setup_screen.dart` und `app/lib/di/provider_setup.dart`.
