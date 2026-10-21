# Ports

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
| `SpotifyApi`, `SpotifySecrets`, `SpotifyAppLauncher`, `SpotifyAuthBrowser` | `packages/wendelin_integrations/lib/src/spotify/spotify_api.dart` | `HttpSpotifyApi` im Paket, Secrets in `app/lib/di/spotify.dart`, Launcher und Login-Browser in `app/lib/platform/spotify_platform.dart` |
| `WebSearchBackend` | `packages/wendelin_integrations/lib/src/web/web_search_backend.dart` | Brave, Tavily, SearXNG im Paket, Auswahl in `app/lib/di/web_search.dart` |
| `HttpToolSecrets`, `HttpToolTransport` | `packages/wendelin_integrations/lib/src/http_tools/http_transport.dart` | Transporte und Repository im Paket, Secret-Adapter (`ScopedSecretStore`, Namensraum `http_tool.`) in `app/lib/di/http_tools.dart` |
| `McpSecrets`, `AuthorizationBrowser`, `McpCacheStore` | `packages/wendelin_mcp/lib/src/ports.dart` | folgt mit WP27 |
| `MemoryRetriever`, `HistoryProvider`, `ConversationRecorder`, `CostEstimator`, `BudgetGuard` | `packages/wendelin_agent/lib/src/ports.dart` | `app/lib/di/storage_adapters.dart`, `app/lib/di/costs.dart` |
| `NetworkStatus` | `packages/wendelin_agent/lib/src/routing/routing_context.dart` | `app/lib/platform/channel_network_status.dart` |
| `AudioInput`, `VoiceActivityDetector`, `SpeechToText`, `TextToSpeech`, `TriggerSource`, `BargeInDetector` (WP45, App-Adapter mit WP51/WP58) | `packages/wendelin_voice/lib/src/io/` | `app/lib/platform/voice/` (`record_audio_input.dart`, `silero_vad.dart`, `whisper_stt.dart`, `system_tts.dart`, `sherpa_tts.dart`), `app/lib/platform/assistant_platform.dart` |
| `WakeWordEngine`, `WakeFeatureExtractor`, `WakeVerifier`, `WakeTemplateStore` (WP44, zweistufiges Wake Word: Kandidat + Whisper-Nachprüfung, K29; App-Adapter mit WP50) | `packages/wendelin_voice/lib/src/wake/` (Logik: `CandidateWakeEngine`, `WakeWordListener`, `WakeWordTrigger`, `WakeWordBargeInDetector`, `calibrateThreshold`; WP113: Barge-in Stufe 2 mit `BargeVerifier`/`TranscriptBargeVerifier` und `SpokenTextSink`, Gegenprüfung durch Whisper, siehe `docs/notes/barge-stop-verify.md`; App: `app/lib/voice/wake/lazy_barge_verifier.dart`) | `app/lib/platform/voice/` (`ort_session.dart` C-API-Anbindung des onnxruntime von sherpa-onnx, `onnx_wake_models.dart` + `wake_feature_chain.dart` = `WakeFeatureExtractor`, WP60; Live-Dienst WP50). Einlernen, Kalibrieren, Ausprobieren (WP60): Logik `app/lib/voice/wake/` (`WakeEnroller`, `WakeCalibrator`, `WakeTester`, `SecretWakeTemplateStore` verschlüsselt im SecretStore), Provider `app/lib/di/wake_providers.dart` (Schalter Whisper-Nachprüfung `wakeVerifyProvider`), Oberfläche `app/lib/ui/settings/wake/` |
| `ModelStore` | `packages/wendelin_voice/lib/src/models/model_store.dart` | `app/lib/platform/voice/file_model_store.dart` |
| `AttestationNotifier` (WP52) | `app/lib/platform/channel_notifier.dart` | `ChannelAttestationNotifier` über `NotifyChannel.kt`; Aufrufer ist `AttestationHub` (`app/lib/di/attestation_hub.dart`) |
| `SecretStore` | `packages/wendelin_storage/lib/src/secret_store.dart` | `app/lib/platform/secure_secret_store.dart` |
| `AttestationCrypto` (WP46/WP47) | `packages/wendelin_providers/lib/src/tee/attestation_crypto.dart` | `RustAttestationCrypto` in `app/lib/platform/attest/rust_attestation_crypto.dart` über das Rust-Crate `native/attest` (`flutter_rust_bridge`, ADR 0017); Kollateral von Intel PCS (`pcs_collateral_client.dart`) mit Dateicache bis `nextUpdate` (`collateral_cache.dart`); Provider `attestationCryptoProvider` in `app/lib/di/attestation_providers.dart` |
