# Architekturkarte

Wo liegt was, und welche Dateien gehören zu einer Änderung? Regeln und Abhängigkeiten stehen in `docs/ENGINEERING.md`, Entscheidungen in `docs/adr/`. Alle Pfadangaben hier prüft `tool/check_docs.dart` im Gate. Wer Dateien verschiebt, führt diese Karte nach.

## Pakete (reines Dart, `packages/`)

Kurzfassung der Abhängigkeiten (geprüft von `tool/check_deps.dart`): `core` hängt von nichts ab; `providers`, `tools`, `agent`, `storage`, `integrations` nur von `core`; `voice` von `core` und `agent`; `mcp` von `core` und `integrations`; `evals` von `core`, `providers`, `tools`, `agent`, `integrations`, `mcp`; die App von allen. Pakete mit Schnittstellen (alle außer `providers` und `tools`) haben `fakes.dart` (Fakes ohne `package:test`) und `testing.dart` (Fakes plus Contract-Suites).

| Paket | Einstieg | Wichtige Typen und Dateien |
| --- | --- | --- |
| `wendelin_core` | `packages/wendelin_core/lib/wendelin_core.dart` | Nachrichten (`Message`, `ContentBlock`, `ChatEvent`) in `src/messages/`, `LlmProvider`, `ProviderProfile`, `PrivacyLevel` in `src/provider/`, `Tool`, `Integration`, `ToolOutcome` in `src/tools/`, `AgentEvent` in `src/agent/agent_event.dart`, `Clock`/`IdGenerator` in `src/util/` |
| `wendelin_providers` | `packages/wendelin_providers/lib/wendelin_providers.dart` | Adapter `src/anthropic/anthropic_adapter.dart`, `src/openai/openai_adapter.dart`, `ProviderFactory` (`src/provider_factory.dart`), Modellkatalog und Kosten in `src/catalog/`, HTTP in `src/common/http_transport.dart`, TEE-Attestierung in `src/tee/` (Port `attestation_crypto.dart`, `phala_verifier.dart`, `attested_provider.dart`, `gpu_attestation.dart`; ADR 0014) |
| `wendelin_tools` | `packages/wendelin_tools/lib/wendelin_tools.dart` | `ToolRegistry` (`src/registry/tool_registry.dart`), `ToolExecutor` (`src/executor/tool_executor.dart`), `RiskPolicy` (`src/policy/risk_policy.dart`), `UndoManager` (`src/undo/undo_manager.dart`), `ArgumentValidator`, `ToolAuditSink` |
| `wendelin_agent` | `packages/wendelin_agent/lib/wendelin_agent.dart` | `AgentRunner` (`src/agent_runner.dart`), `ContextBuilder`, `ProviderResolver`, Routing-Regeln in `src/routing/` (`RuleBasedProviderResolver`, `routing_engine.dart`, `conditions.dart`), `SentenceChunker`, Ports in `src/ports.dart` |
| `wendelin_storage` | `packages/wendelin_storage/lib/wendelin_storage.dart` | drift-Datenbank `src/db/database.dart` und Tabellen `src/db/tables.dart`, Repositories (`src/repositories/repositories.dart`, Umsetzung `src/db/*_impl.dart`), `SecretStore` (`src/secret_store.dart`), Schema-Tests unter `test/drift/` |
| `wendelin_integrations` | `packages/wendelin_integrations/lib/wendelin_integrations.dart` | Je Integration ein Ordner unter `src/`: `calendar/`, `clipboard/`, `alarms/`, `memory/`, `web/` (Abruf, Suche), `weather/` (Wetter, Meer), `lists/`, `obsidian/`, `bring/`, `home_assistant/`, `http_tools/`; gemeinsame Bausteine in `src/common/` (`base_tool.dart`, `tool_args.dart`, `matching.dart`, `app_presence.dart`, `net_scope.dart`) |
| `wendelin_voice` | `packages/wendelin_voice/lib/wendelin_voice.dart` | `VoicePipeline` (`src/pipeline/voice_pipeline.dart`), `Endpointer`, Schnittstellen in `src/io/`, `SpokenAnswer` (`src/text/spoken_answer.dart`), `TtsSelector`, Modellkatalog und Download in `src/models/` |
| `wendelin_mcp` | `packages/wendelin_mcp/lib/wendelin_mcp.dart` | `McpClient` (`src/client.dart`), Transporte in `src/transport/`, OAuth in `src/oauth/oauth_flow.dart`, Abbildung auf Tools in `src/tools/mcp_integration.dart`, Netzregeln `src/net_policy.dart` |
| `evals` | `evals/lib/src/cli.dart` | Modell-Evals, M3-Fälle mit Fake-Backends (`evals/lib/src/case_backends.dart`), Routing-Tabelle (`routing_table.dart`), Live-Tests (`evals/README.md`) |

## App (`app/lib`)

| Ordner | Inhalt |
| --- | --- |
| `app/lib/main.dart`, `app/lib/app.dart`, `app/lib/bootstrap/` | Vier Einstiege: `main` (App), `assistantMain` (Overlay-Engine), `recognizerMain` (Spracherkennung für andere Apps, ADR 0008), `wakeWordMain` (Wake-Word-Dienst, ADR 0013); Start in Schritten unter `bootstrap/` (Storage öffnen, Geräteinfo, `ProviderScope` mit Overrides) |
| `app/lib/agent/` | `AgentController` (Anfragen, Bestätigungen, Undo), `ConversationReducer` und `ConversationState` (Events → UI-Zustand). Dazu fachfremd `bring_share.dart` und `money.dart` (N7) |
| `app/lib/di/` | Nur Verdrahtung: `Provider`-Definitionen, dünne Notifier, die an Paket-Logik delegieren, und Adapter auf Flutter-Plugins oder die Einstellungen (`SettingsHttpToolStore`, `SecretStoreHttpToolVault`, `SettingsMcpConfigStore`, `ToolRegistryUserIntegrations`). Logik liegt in Paketen: HTTP-Tool-Entwurf, -Repository und -Quelle in `packages/wendelin_integrations/lib/src/http_tools/`, `UserIntegrationSync` in `packages/wendelin_integrations/lib/src/user/`, MCP-Quelle in `packages/wendelin_mcp/lib/src/app/`, `VoiceSettings` und `ModelInstallStates` in `packages/wendelin_voice/lib/src/models/`, `ScopedSecretStore` in `wendelin_storage`. Neue Logik gehört in ein Paket, nicht hierher (Regel und Abdeckungsschwelle in `docs/ENGINEERING.md`) |
| `app/lib/platform/` | Implementierungen der Ports (Kanäle, Plugins, sherpa-onnx in `app/lib/platform/voice/`, Spracherkennung in `app/lib/platform/recognizer/`, Wake-Word-Dienst in `app/lib/platform/wake/` (ADR 0013), TEE-Prüfung über Rust in `app/lib/platform/attest/`) |
| `app/lib/ui/` | `design/` (Bausteine, Galerie), `screens/` (Hauptbildschirm, Texte in `labels.dart`), `settings/`, `onboarding/`, `overlay/`, `theme/`, Routen in `app/lib/ui/routes.dart` (setzt `general_routes.dart` und `integration_routes.dart` zusammen) |
| `app/lib/voice/` | `VoiceController` (Mikrofon, Pipeline, Sprachbestätigung), `voice_components.dart`; Gesprächsmodus: einmalige Nachfrage in `conversation_offer.dart`, Folgefenster in `voice_ui_state.dart`, Quelle der Aufnahme in `app/lib/platform/voice/capture_profile_follower.dart` (ADR 0015) |
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
| `HaApi`, `HaSecrets`, `HaEntityStore`, `HaDiscovery` | `packages/wendelin_integrations/lib/src/home_assistant/ha_ports.dart` | `HttpHaApi` im Paket, Secrets und Geräteauswahl in `app/lib/di/home_assistant.dart`, mDNS in `app/lib/platform/ha_discovery.dart` |
| `BringApi`, `BringSecrets` | `packages/wendelin_integrations/lib/src/bring/bring_api.dart` | `HttpBringApi` im Paket, Secrets in `app/lib/di/bring.dart` |
| `WebSearchBackend` | `packages/wendelin_integrations/lib/src/web/web_search_backend.dart` | Brave, Tavily, SearXNG im Paket, Auswahl in `app/lib/di/web_search.dart` |
| `HttpToolSecrets`, `HttpToolTransport` | `packages/wendelin_integrations/lib/src/http_tools/http_transport.dart` | Transporte und Repository im Paket, Secret-Adapter (`ScopedSecretStore`, Namensraum `http_tool.`) in `app/lib/di/http_tools.dart` |
| `McpSecrets`, `AuthorizationBrowser`, `McpCacheStore` | `packages/wendelin_mcp/lib/src/ports.dart` | folgt mit WP27 |
| `MemoryRetriever`, `HistoryProvider`, `ConversationRecorder`, `CostEstimator`, `BudgetGuard` | `packages/wendelin_agent/lib/src/ports.dart` | `app/lib/di/storage_adapters.dart`, `app/lib/di/costs.dart` |
| `NetworkStatus` | `packages/wendelin_agent/lib/src/routing/routing_context.dart` | `app/lib/platform/channel_network_status.dart` |
| `AudioInput`, `VoiceActivityDetector`, `SpeechToText`, `TextToSpeech`, `TriggerSource`, `BargeInDetector` (WP45, App-Adapter mit WP51/WP58) | `packages/wendelin_voice/lib/src/io/` | `app/lib/platform/voice/` (`record_audio_input.dart`, `silero_vad.dart`, `whisper_stt.dart`, `system_tts.dart`, `sherpa_tts.dart`), `app/lib/platform/assistant_platform.dart` |
| `WakeWordEngine`, `WakeFeatureExtractor`, `WakeVerifier`, `WakeTemplateStore` (WP44, zweistufiges Wake Word: Kandidat + Whisper-Nachprüfung, K29; App-Adapter mit WP50) | `packages/wendelin_voice/lib/src/wake/` (Logik: `CandidateWakeEngine`, `WakeWordListener`, `WakeWordTrigger`, `WakeWordBargeInDetector`, `calibrateThreshold`) | `app/lib/platform/voice/` (`ort_session.dart` C-API-Anbindung des onnxruntime von sherpa-onnx, `onnx_wake_models.dart` + `wake_feature_chain.dart` = `WakeFeatureExtractor`, WP60; Live-Dienst WP50). Einlernen, Kalibrieren, Ausprobieren (WP60): Logik `app/lib/voice/wake/` (`WakeEnroller`, `WakeCalibrator`, `WakeTester`, `SecretWakeTemplateStore` verschlüsselt im SecretStore), Provider `app/lib/di/wake_providers.dart` (Schalter Whisper-Nachprüfung `wakeVerifyProvider`), Oberfläche `app/lib/ui/settings/wake/` |
| `ModelStore` | `packages/wendelin_voice/lib/src/models/model_store.dart` | `app/lib/platform/voice/file_model_store.dart` |
| `AttestationNotifier` (WP52) | `app/lib/platform/channel_notifier.dart` | `ChannelAttestationNotifier` über `NotifyChannel.kt`; Aufrufer ist `AttestationHub` (`app/lib/di/attestation_hub.dart`) |
| `SecretStore` | `packages/wendelin_storage/lib/src/secret_store.dart` | `app/lib/platform/secure_secret_store.dart` |
| `AttestationCrypto` (WP46/WP47) | `packages/wendelin_providers/lib/src/tee/attestation_crypto.dart` | `RustAttestationCrypto` in `app/lib/platform/attest/rust_attestation_crypto.dart` über das Rust-Crate `native/attest` (`flutter_rust_bridge`, ADR 0017); Kollateral von Intel PCS (`pcs_collateral_client.dart`) mit Dateicache bis `nextUpdate` (`collateral_cache.dart`); Provider `attestationCryptoProvider` in `app/lib/di/attestation_providers.dart` |

## App-Verdrahtung

- **Start:** `app/lib/main.dart` öffnet die Datenbank (`openAppStorage`), liest `StartupSettings` (`app/lib/di/startup.dart`) und startet `WendelinApp` (`app/lib/app.dart`) bzw. das Overlay. Grundlage: ADR 0004.
- **Provider nach Bereich:** Basis (Uhr, Ids, Storage, Secrets, HTTP, Ports) in `app/lib/di/core_providers.dart`, Integrationen und Registry in `integration_providers.dart`, Agent, Kosten in `agent_providers.dart`; `providers.dart` re-exportiert nur; Sprache in `app/lib/di/voice_providers.dart` (Bausteine) und `voice_settings_providers.dart` (Einstellungen, Modell-Downloads); Provider-Profile und Routing in `app/lib/di/provider_config.dart`, `app/lib/di/routing.dart`; Agent-Bau in `app/lib/di/agent_factory.dart`; Einstellungen in `app/lib/di/preferences.dart`, `app/lib/di/app_settings.dart`.
- **Integrationsregistry:** eingebaute Integrationen als `IntegrationSpec`, eine Datei je Integration unter `app/lib/di/integrations/`, Liste in `integrations/registry.dart` (`integration_specs.dart` re-exportiert Typen und Liste), Geräteports gebündelt in `PlatformPorts` (`app/lib/platform/platform_ports.dart`). `IntegrationActivator` (`app/lib/di/integration_activator.dart`) schaltet ein und aus und fragt erst dann nach Berechtigungen. Nutzerdefinierte Integrationen (HTTP-Tools, MCP) kommen als `UserIntegrationSource` über `UserIntegrationSync` (`packages/wendelin_integrations/lib/src/user/`; die App liefert nur die Adapter in `app/lib/di/user_integrations.dart`, ADR 0012).
- **Gesperrtes Gerät (WP53, K16):** Jeder Auslöser (Power-Taste, Wake Word) läuft über `_onTrigger` in `assistant_overlay.dart`; bei Sperre setzt es `lockedModeProvider` und hört ohne Anzeige zu. `LockGateAgentRun` (`app/lib/voice/locked_agent_run.dart`) sitzt vor dem Agenten: nur `matchLockedCommand` (`packages/wendelin_voice/lib/src/text/locked_command.dart`, de/fr/en) führt eine Taschenlampen-Aktion über `lockedCommandRunnerProvider` aus (nur Spec mit `allowedWhileLocked`, Audit `whileLocked`), alles andere gibt den festen Satz „Bitte entsperre das Telefon“ (Audit `refused`, ohne Text) und danach den Entsperr-Dialog. Kein Modellaufruf, kein Verlauf.
- **Wake-Word-Dienst (WP50, ADR 0013):** `WakeWordService.kt` (Foreground-Dienst `microphone`, nicht exportiert) nimmt mit `AudioRecord` auf und betreibt die kopflose Engine `wakeWordMain` (`app/lib/platform/wake/device_wake_parts.dart`: Merkmalskette `wakeFeaturesFactoryProvider`, `CandidateWakeEngine` mit den Vorlagen aller Sprecher aus `wakeStoreProvider`, Stufe 2 `LazyWhisperVerifier` über `DeviceRecognizerEngines`). Start/Stopp: `WakeStarter.kt` (Quellen `app`, `vis`, `charge`, `unplug`, `notif`) nach `WakePolicy.kt` (JVM-Test); Einstellungen in `app/lib/di/wake_service.dart` (`wakeServiceProvider`: an/aus, Bedingung) werden über `WakePlatform` nach Kotlin gespiegelt. Barge-in im Gesprächsmodus: `app/lib/voice/wake/wake_barge_in.dart` (`wakeBargeInDetectorProvider`, im Bootstrap statt des leeren `bargeInDetectorProvider`). „Stopp“ allein (WP64b): eigene Vorlagen `SecretWakeTemplateStore.stop` (`wake.stop.<id>`), `CandidateWakeEngine.stopTemplates` (gleiche Merkmalskette, Treffer `stop`), nur im Barge-in, nicht im Leerlauf-Dienst; Einlernen/Löschen invalidiert `wakeBargeInDetectorProvider`, der alte Detektor endet erst im Leerlauf (`disposeWhenIdle`). Debug-Quelle für Gerätetests: `app/lib/debug/wake_test_audio.dart`.
- **Overlay-Engine:** `assistantMain` startet `AssistantOverlayApp` (`app/lib/ui/overlay/assistant_overlay.dart`) in eigener Flutter-Engine, gestartet von `AssistantActivity.kt`; beide Engines teilen die Datenbank über einen drift-Isolate (ADR 0006). Jeder Overlay-Start ruft `AgentController.beginFreshConversation` (`_fireFirst`): neue Sitzung ohne Verlauf (`SessionManager.beginFresh`), Datenschutz-Untergrenze zurückgesetzt (WP67); der App-Chat bleibt in seiner Sitzung (`SessionManager.ensure` bevorzugt die eigene).

## Datenfluss einer Anfrage

1. **Auslöser:** Mikrofon im Hauptbildschirm (`app/lib/ui/screens/main_screen.dart`, `app/lib/ui/design/mic_button.dart`), Power-Taste (`WendelinVoiceInteractionService.kt` → `WendelinVoiceSessionService.kt` → `AssistantActivity.kt` → Overlay, `AssistantTriggerSource` in `app/lib/platform/assistant_platform.dart`), Wake Word (`WakeWordService.kt` → headless `wakeWordMain` → `WakeHost` in `app/lib/platform/wake/wake_host.dart`; Treffer → `WakeHandoff` in `WakePolicy.kt` → `WendelinVoiceInteractionService.show()` → derselbe Weg wie die Power-Taste, der Dienst nimmt bis dahin weiter auf; das Overlay holt Pre-Roll und Nachlauf mit `takeWakeHandoff` unmittelbar vor dem Öffnen seines Mikrofons und startet mit `TriggerKind.wakeWord`, WP68, ADR 0013) oder Texteingabe (`app/lib/ui/screens/main_parts.dart`).
2. **Sprache:** `VoiceController` (`app/lib/voice/voice_controller.dart`) baut die `VoicePipeline` und übergibt den erkannten Text.
3. **Agent:** `AgentController.send` (`app/lib/agent/agent_controller.dart`) baut über `agentFactoryProvider` (`app/lib/di/agent_factory.dart`) einen `AgentRunner`.
4. **Routing:** `ProviderResolver` aus `app/lib/di/provider_config.dart`, Regeln in `packages/wendelin_agent/lib/src/routing/rule_based_resolver.dart` (ADR 0009). Start eines Laufs (Routing, Kontext, Untergrenze einer Wiederholung) in `packages/wendelin_agent/lib/src/run/run_start.dart`, Eskalation und Wiederholung in `packages/wendelin_agent/lib/src/run/escalation.dart`.
5. **Modell:** `AgentRunner` (`packages/wendelin_agent/lib/src/agent_runner.dart`) führt die Schleife (`_Run`). Den Kontext baut `context_builder.dart`, den Modellaufruf mit System-Prompt und Streaming `packages/wendelin_agent/lib/src/run/model_call.dart`, Limits zählt `packages/wendelin_agent/lib/src/run/run_budget.dart`, Tool-Runden führt `packages/wendelin_agent/lib/src/run/tool_round.dart` aus. Den gemeinsamen Zustand eines Laufs hält `packages/wendelin_agent/lib/src/run/run_state.dart`. Der Adapter kommt aus `wendelin_providers`.
6. **Tools:** `ToolExecutor` (`packages/wendelin_tools/lib/src/executor/tool_executor.dart`) prüft Argumente und Risiko (`RiskPolicy`), holt Bestätigungen und schreibt das Audit.
7. **Integration → Port → Plattform:** z. B. `calendar_write_tools.dart` → `CalendarPort` → `app/lib/platform/device_calendar_port.dart` → `CalendarChannel.kt`.
8. **Zurück:** `AgentEvent` (`packages/wendelin_core/lib/src/agent/agent_event.dart`) → `ConversationReducer` (`app/lib/agent/conversation_reducer.dart`) → Anzeige in `app/lib/ui/screens/conversation_view.dart` mit Tool-Karte (`app/lib/ui/design/tool_result_card.dart`), Bestätigung (`app/lib/ui/screens/confirmation_sheet.dart`, per Sprache `yes_no.dart`), Undo (`UndoManager`), Audit (`app/lib/di/audit_recorder.dart` → `packages/wendelin_storage/lib/src/db/audit_log_repository_impl.dart`).

## TEE-Anbieter in der App (WP52, ADR 0014)

- **Bau:** `ProviderFactory.create(..., attestation: AttestationWiring)` macht aus einem Phala-Profil (`needsAttestation`: Option `attestation: phala` oder Host `api.redpill.ai`, unabhängig von der Datenschutzstufe; Stufe „TEE“ bietet die Einrichtung nur für solche Profile an) einen `AttestedProvider` mit `PhalaVerifier` und `NrasGpuVerifier`. Die App gibt in `llmProviderFactoryProvider` (`app/lib/di/agent_providers.dart`) `RustAttestationCrypto` (`attestationCryptoProvider`), den `AttestationLogWriter` als `logSink` und den Pin-Speicher `SettingsAttestationPinStore` mit (`app/lib/di/attestation_providers.dart`). Ohne Verdrahtung baut `ProviderFactory.create` ein Profil mit Prüfung nicht (ArgumentError), nie ungeprüft. `attestationTransportProvider` ist null; nur der Gerätetest setzt dort Transport, Uhr und Nonce der Aufzeichnung. `storedProviderConfigProvider` wartet vorher auf das Modul.
- **E2EE (WP62, ADR 0018):** Alle Anfragen an Phala sind Ende-zu-Ende verschlüsselt (Protokoll v2). Rust: `native/attest/src/e2ee.rs` (Port `AttestationCrypto.e2ee*`); Protokollbaustein `packages/wendelin_providers/lib/src/tee/e2ee_v2.dart` (`E2eeProtocolV2`, `PhalaE2eeChannel`, `E2eeV2Wire`); Einhängepunkt `OpenAiChatAdapter.wireCodec` (`common/chat_wire.dart`); Schlüssel aus der Sitzung (`AttestedSession.e2eeKey`, Stufe `e2ee.key`). Fakes: `E2eeReference`, `FakeE2eeService` (`fakes.dart`). Feature „anderes Protokoll (v3)“: nur `e2ee_v2.dart` ersetzen.
- **NEAR AI (WP75, ADR 0019):** Profil mit Option `attestation: near` (Vorlage „NEAR AI (TEE)“, `packages/wendelin_providers/lib/src/catalog/provider_template.dart`) wird von `ProviderFactory` (`packages/wendelin_providers/lib/src/provider_factory.dart`, `attestationKind`) zu `AttestedProvider` mit `NearVerifier` (`packages/wendelin_providers/lib/src/tee/near/near_verifier.dart`: Modell- und Gateway-Quote, TLS-Pin, Quittung `GET /signature/{id}`) und `NearE2eeChannel` (`packages/wendelin_providers/lib/src/tee/near/near_e2ee.dart`: Feldverschlüsselung inkl. Tools). Krypto: Port `NearCrypto` (`near_crypto.dart`), Rust `native/attest/src/near_e2ee.rs`, Dart-Referenz `near_reference.dart`, Gegenstelle `FakeNearService`. Geräte-Fixture: `app/integration_test/near_app_e2e_test.dart` mit `app/integration_test/support/near_gateway.dart`. Feature „anderes NEAR-Protokoll“: nur `near_e2ee.dart` ersetzen.
- **Tinfoil SEV-SNP (WP76a):** Rust `native/attest/src/snp.rs` (Report parsen, VCEK→ASK→ARK mit gepinnten ARK-SPKI-Hashes Milan/Genoa/Turin, ECDSA P-384, TCB-Richtlinie, `report_data` = TLS-SPKI-Hash ‖ HPKE-Schlüssel); Vektoren `native/attest/tests/snp.rs` mit `tests/snp/` (öffentlicher Tinfoil-Report, AMD-KDS-Ketten). Port `SnpCrypto` (`packages/wendelin_providers/lib/src/tee/snp_crypto.dart`, Fake `FakeSnpCrypto`), Adapter `app/lib/platform/attest/rust_snp_crypto.dart`. VCEK/Kette holt der Aufrufer vom KDS (`kdsintf.amd.com/vcek/v1/<Produkt>/<chip_id>?blSPL&teeSPL&snpSPL&ucodeSPL`, Produkt durch Probieren). Sigstore, EHBP und Profil folgen in WP76b-d.
- **Hub:** `AttestationHub` (`app/lib/di/attestation_hub.dart`) kennt die lebenden `AttestedProvider`, kennt den GPU-Modus je Profil (`ProviderProfile.options['gpuCheck']`: aus/vorher/nachher, WP82; Einstellung im letzten Schritt des Provider-Dialogs, Migration des alten globalen `tee.gpuCheck` in `gpu_check_migration.dart`), bietet „neu prüfen“, „ohne GPU-Prüfung senden“ (einmalig) und das Vorwärmen beim App-Start und beim Overlay-Start (`warmUpAttestation`, `main_screen.dart`, `assistant_overlay.dart`; WP77: Attestierung, GPU-Prüfung und gepinnte Verbindung parallel), übergibt beim Neuaufbau eines Profils die geprüfte Sitzung an den neuen Provider (`register` → `adoptSessionOf`), und warnt per `AttestationNotifier` bei einem fehlgeschlagenen „Nachher“-Check.
- **Status je Antwort:** `AttestationGate` (`packages/wendelin_agent/lib/src/run/attestation_gate.dart`) meldet je Modellaufruf `AttestationStatusChanged` zuerst gelb (`logId` leer), dann das Endergebnis mit `reasonCode`. `ConversationReducer` hängt es an den `AssistantTextEntry` des Schritts (`AnswerAttestation`); ein spätes GPU-Ergebnis („Nachher“) kommt über `AgentController` (`lateFailure`). Anzeige: `AttestedAnswer` in `app/lib/ui/screens/conversation_view.dart` (Schild `AttestationShield`, Warnkarte, Texte in `app/lib/ui/attestation/attestation_texts.dart`).
- **GPU „Vorher“:** schlägt die Prüfung fehl, endet der Lauf mit `AgentFailed(cause: AttestationFailedException(stage: 'gpu'))`; der Controller setzt `ConversationState.gpuBlock`, der Hauptbildschirm fragt „Ohne GPU-Prüfung senden“ oder „Abbrechen“.
- **Keine Übergabe bei fehlgeschlagener Prüfung (Maintainer-Entscheidung):** Eine fehlgeschlagene oder nicht durchführbare Prüfung (Sitzung, Quittung, GPU) schickt die Anfrage nie an einen anderen Anbieter, weder still noch nach Rückfrage; es gibt keine Option „Ausweichen“. `AgentRunner._onAttestationError`: nur `unavailable` wird einmal beim selben Anbieter wiederholt, sonst endet der Lauf mit Grund. Der Nutzer fragt selbst neu (z. B. „nochmal mit Claude“ = neue Anfrage mit normaler Regel). Der GPU-Dialog „Ohne GPU-Prüfung senden“ bleibt beim selben Anbieter.
- **Prüfprotokoll:** Seite `app/lib/ui/settings/attestation_log_screen.dart` (Route `AppRoutes.attestationLog`, aus Einstellungen → Datenschutz) mit Detail `attestation_log_detail.dart`, Sitzungskarte je Anbieter und „Neu attestieren“, Export `AttestationLogRepository.exportJson` (nur Ids, Hashes, Stufen). Daten: `app/lib/di/attestation_log_view.dart`.
- **Einrichtung:** `ProviderSetupSession.probe` liefert `SetupTestResult.stages` (erste Attestierung je Stufe), Anzeige `app/lib/ui/settings/provider_setup/attestation_stages_card.dart`.
- **Gerätetest:** `app/integration_test/tee_app_e2e_test.dart` mit Fixture-Transport `app/integration_test/support/tee_gateway.dart` (überschreibt `llmProviderFactoryProvider`).

## Datenschutz und Taint (K9, K10)

- Stufen: `PrivacyLevel` (`packages/wendelin_core/lib/src/provider/privacy_level.dart`), Untergrenze je Nachricht als `Message.privacyFloor`.
- Tool-Katalog je Zielstufe: sensible Integrationen nur für ausreichend geschützte Ziele in `packages/wendelin_tools/lib/src/registry/tool_registry.dart`; Nutzer-Markierung „sensibel“ in `app/lib/di/sensitivity.dart`.
- Ausblenden geschützter Ergebnisse, Privatsphäre-Untergrenze und Taint: `PrivacyScope` (`hiddenFor`, `messagesFor`, `raiseFloorToTaint`, `visibleMemories`) in `packages/wendelin_agent/lib/src/run/privacy_scope.dart`. Dass die Untergrenze nie sinkt, erzwingt `RunState.raiseFloor` in `packages/wendelin_agent/lib/src/run/run_state.dart`.
- Ablehnung von Aufrufen auf nicht sichtbare Tools: `ToolRound` in `packages/wendelin_agent/lib/src/run/tool_round.dart`.
- Eskalation unter die Stufe nur mit Rückfrage: `Escalation` in `packages/wendelin_agent/lib/src/run/escalation.dart`, Regel „Privat“ in `packages/wendelin_agent/lib/src/routing/routing_engine.dart` und `app/lib/di/routing.dart`.
- Sensible Inhalte (Secrets, Kartennummern) erkennen: `packages/wendelin_core/lib/src/safety/sensitive_content.dart`, Sperre beim Speichern in `packages/wendelin_storage/lib/src/sensitive_content.dart`.

## Voice-Pipeline (ADR 0007, 0008)

VAD (`app/lib/platform/voice/silero_vad.dart`) → STT (`app/lib/platform/voice/whisper_stt.dart`) → Endpointing (`packages/wendelin_voice/lib/src/pipeline/endpointer.dart`) → Agent → Sprechtext (`spoken_answer.dart`, `speech_normalizer.dart` Stufe 0, `SentenceChunker`; Stufe 1 Hinweis in `ContextBuilder.speechHint`, Stufe 2 `<spoken>`-Block per `packages/wendelin_agent/lib/src/run/spoken_block.dart` und `AgentSpokenText`; Schutzstufen `SpokenVersion` und KI-Prüfung `packages/wendelin_agent/lib/src/run/spoken_check.dart` (WP55), Halten des Textes bis zum Urteil `packages/wendelin_voice/lib/src/pipeline/speech_hold.dart`) → TTS (`TtsSelector`, `speech_queue.dart`, System-TTS mit sherpa-Fallback). Modellkatalog `speech_model_catalog.dart`, Download `model_downloader.dart`, Installation `app/lib/platform/voice/model_installer.dart`. Whisper wird zwischen Overlay, App und Spracherkennung geteilt: `app/lib/platform/voice/whisper_share.dart`, `app/lib/platform/voice/whisper_registry.dart`.

## Plattformkanäle

Kotlin unter `app/android/app/src/main/kotlin/app/wendelin/`. Kanalnamen sind Konstanten in `app/lib/platform/channels.dart` und `CHANNEL` in der Kotlin-Klasse. **Das Manifest `app/channels.json` listet je Kanal Dart-/Kotlin-Dateien, Methoden (Richtung, Argumentschlüssel, Rückgabeart); `tool/check_channels.dart` (Gate) vergleicht es per Textanalyse mit beiden Seiten** (Methode nur auf einer Seite, Argumentschlüssel nur auf einer Seite, Kanal ohne Manifest-Eintrag und umgekehrt sind Fehler mit Datei und Zeile).

Die Logik ohne Android-Abhängigkeit liegt in reinen Kotlin-Klassen mit JVM-Unit-Tests (`app/android/app/src/test/kotlin/app/wendelin/`, Gate-Schritt `kotlin-unit`): `ChannelArgs.kt` (Argumentprüfung), `CalendarRows.kt` (Zeilen → Maps, Zeitzonen, Dauer, Filter), `VaultTree.kt` (`VaultResolver`: Pfade, Ordner anlegen, Lesen/Schreiben auf einem `VaultTree`), `OAuthRedirect.kt` (Redirect-Prüfung). Die Android-Seite dazu: `CalendarStore.kt`, `SafVaultTree.kt`.

| Kanal (`app.wendelin/…`) | Dart | Kotlin |
| --- | --- | --- |
| calendar | `app/lib/platform/device_calendar_port.dart` | `CalendarChannel.kt` |
| files | `app/lib/platform/saf_list_file_port.dart`, `app/lib/platform/document_text_import.dart` | `FilesChannel.kt` |
| vault | `app/lib/platform/saf_vault_port.dart` | `VaultChannel.kt` |
| apps | `app/lib/platform/channel_app_presence_port.dart` | `AppsChannel.kt` |
| torch | `app/lib/platform/channel_torch_port.dart` | `TorchChannel.kt` |
| multicast | `app/lib/platform/ha_discovery.dart` | `MulticastChannel.kt` |
| network | `app/lib/platform/channel_network_status.dart` | `NetworkChannel.kt` |
| assistant | `app/lib/platform/assistant_platform.dart` | `AssistantChannel.kt` |
| window | `app/lib/platform/screen_protection.dart` | `WindowChannel.kt` |
| auth | `app/lib/platform/channel_authorization_browser.dart` | `AuthChannel.kt` (mit `OAuthRedirectActivity.kt`) |
| notify (WP52) | `app/lib/platform/channel_notifier.dart` | `NotifyChannel.kt` |
| recognizer | `app/lib/platform/recognizer/recognizer_host.dart` | `RecognizerEngine.kt` (mit `WendelinRecognitionService.kt`, `RecognizerSwitch.kt`) |
| wake (WP50, Einstellungen der Haupt-App) | `app/lib/platform/wake/wake_platform.dart` | `WakeChannel.kt` (mit `WakeSettingsStore.kt`, `WakeStarter.kt`) |
| wake-engine (WP50, kopflose Engine des Dienstes) | `app/lib/platform/wake/wake_host.dart`, `app/lib/platform/wake/service_audio_input.dart` | `WakeWordService.kt` (mit `RecognizerEngine.kt`, `WakeConflictWatcher.kt`, `WakeNotifications.kt`) |

## HTTP-Stacks (N3)

Bewusst getrennt, je mit eigenen Timeouts und Fehlerabbildung. **Keinen neuen Stack anlegen**, sondern den passenden erweitern:
- LLM-Aufrufe und SSE: `packages/wendelin_providers/lib/src/common/http_transport.dart`
- MCP: `packages/wendelin_mcp/lib/src/transport/http_call.dart`
- Web-Abruf mit Zielprüfung: `packages/wendelin_integrations/lib/src/web/web_fetcher.dart` (`fetch_guard.dart`)
- Bring!: `packages/wendelin_integrations/lib/src/bring/http_bring_api.dart`
- HTTP-Tools: `packages/wendelin_integrations/lib/src/http_tools/http_transport.dart` (`http_target.dart`, ADR 0011)
- Modell-Download: `packages/wendelin_voice/lib/src/models/model_downloader.dart`

Netzziele: Adressbereiche (Loopback, RFC 1918, CGNAT/Tailscale, ULA, Link-Local, IPv4 in IPv6 …) klassifiziert **nur** `packages/wendelin_integrations/lib/src/common/net_scope.dart` (`classifyNet`, `NetScope`, `HostResolver`). `fetch_guard.dart` und `http_target.dart` enthalten nur ihre Policy (welche Bereiche erlaubt sind, welche Meldung kommt). `packages/wendelin_mcp/lib/src/net_policy.dart` (MCP-Server-URLs, `isHomeNetworkHost`, `isLoopbackHost`) fragt ebenfalls nur den Kern ab (WP36 b).

Text-Faltung für Namensvergleiche (Listen, Obsidian, Routing, phonetische Suche): **nur** `packages/wendelin_core/lib/src/text/fold.dart` (`foldForMatch`, `foldFlat`, `foldLetter`). `matching.dart` (`normalizeText` = `foldForMatch(basicOnly: true)`) und `routing_text.dart` nutzen sie. Ausnahme: `packages/wendelin_mcp/lib/src/tools/naming.dart` transliteriert Tool-Namen bewusst ä→ae (stabile Namen).

## Checklisten „Feature → Dateien“

**Neue eingebaute Integration**
1. Ordner `packages/wendelin_integrations/lib/src/<name>/` mit Integration, Tools und ggf. Port; `README.md` im Ordner (Tools, Risiko, Berechtigungen).
2. Einstiegspunkt `packages/wendelin_integrations/lib/<name>.dart` (Exporte mit `show`) und **eine** Zeile in `wendelin_integrations.dart`; Fakes und Contract in `fakes.dart`/`testing.dart` (nur anhängen).
3. Port-Implementierung in `app/lib/platform/`, Feld in `PlatformPorts`.
4. `IntegrationSpec` in eigener Datei `app/lib/di/integrations/<name>_spec.dart` (eigene Provider über `prepare`, nicht über `IntegrationDeps`) und **eine** Zeile in `app/lib/di/integrations/registry.dart`; Einrichtungsseite ggf. in `app/lib/ui/settings/integration_routes.dart` (und `setupPageFor` in `settings_routes.dart`).
5. Texte in `app/lib/ui/screens/labels.dart`, Berechtigung ggf. in `AndroidManifest.xml`.
6. Tests im Paket, Verdrahtung in `app/test/di/wiring_test.dart`.

**Neue Einstellungsseite**
1. Screen in `app/lib/ui/settings/` (Gerüst `settings_page.dart`).
2. Routenname in `app/lib/ui/routes.dart` (`AppRoutes`), Route in `app/lib/ui/settings/general_routes.dart` (allgemeine Seiten) bzw. `integration_routes.dart` (Seite einer Integration), Eintrag in `app/lib/ui/settings/settings_screen.dart`.
3. Gespeicherte Werte in `app/lib/di/preferences.dart` bzw. `app/lib/di/preference_models.dart`.
4. Widget- und Golden-Test unter `app/test/settings/` (Goldens nur auf macOS aktualisieren).

**Neuer Kotlin-Kanal**
1. Kotlin-Klasse in `app/android/app/src/main/kotlin/app/wendelin/`, registriert in `WendelinActivity.kt` (Basis von `MainActivity.kt` und `AssistantActivity.kt`).
2. Dart-Seite in `app/lib/platform/` mit Kanalname als Konstante in `app/lib/platform/channels.dart`, Test mit Mock-Handler unter `app/test/platform/`.
3. Kanal und alle Methoden in `app/channels.json` eintragen (sonst ist `tool/check_channels.dart` rot), Zeile in der Tabelle oben.
4. Logik ohne Android-Typen in eine reine Kotlin-Klasse (wie `CalendarRows.kt`, `VaultTree.kt`, Argumente über `ChannelArgs.kt`) mit JUnit-Test unter `app/android/app/src/test/kotlin/app/wendelin/`.

**Neue Provider-Art**
1. Adapter unter `packages/wendelin_providers/lib/src/<adapter>/` (Wire-Format nur dort), Contract-Suite `llmProviderContract` aus `wendelin_core`.
2. `ProviderType` (`packages/wendelin_core/lib/src/provider/provider_type.dart`), `ProviderFactory`, Vorlage in `packages/wendelin_providers/lib/src/catalog/provider_template.dart`.
3. Einrichtung in `app/lib/ui/settings/provider_setup_screen.dart` und `app/lib/di/provider_setup.dart`.
