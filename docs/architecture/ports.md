# Ports

Ports liegen in dem Paket, das sie braucht; die Flutter-Implementierung liegt in `app/lib/platform/` (Ausnahmen: Adapter auf Repositories, Kosten und `SecretStore` liegen heute in `app/lib/di/`).

**Die Tabelle aller Ports mit Namensendung `Port`, `Api`, `Secrets` oder `Store` (Paket, Datei, Implementierer, Fakes) wird erzeugt:** [generated/ports.md](generated/ports.md) (`dart run tool/gen_docs.dart`, im Gate geprüft). Sie ist die Quelle für „wo liegt der Port, wer setzt ihn um“; hier stehen nur die Ports mit anderem Namensmuster und die Erklärungen dazu.

Hinweise zur erzeugten Tabelle: Implementierer auf Paketebene (`Http…Api`) und in der App (`app/lib/platform/`, `app/lib/di/`) stehen in einer Spalte; Fakes (`package:<pkg>/fakes.dart` bzw. `testing.dart`) getrennt davon. Ein neuer Port bekommt keinen Handeintrag, er erscheint nach dem nächsten `gen_docs`.

## Ports mit anderem Namensmuster (von Hand)

| Port | Fundort | App-Implementierung |
| --- | --- | --- |
| `HaDiscovery` | `packages/wendelin_integrations/lib/src/home_assistant/ha_ports.dart` | mDNS in `app/lib/platform/ha_discovery.dart` |
| `SpotifyAppLauncher`, `SpotifyAuthBrowser` | `packages/wendelin_integrations/lib/src/spotify/spotify_api.dart` | Launcher und Login-Browser in `app/lib/platform/spotify_platform.dart` |
| `WebSearchBackend` | `packages/wendelin_integrations/lib/src/web/web_search_backend.dart` | Brave, Tavily, SearXNG im Paket, Auswahl in `app/lib/di/web_search.dart` |
| `HttpToolTransport` | `packages/wendelin_integrations/lib/src/http_tools/http_transport.dart` | Transporte und Repository im Paket; Secret-Adapter (`ScopedSecretStore`, Namensraum `http_tool.`) in `app/lib/di/http_tools.dart` |
| `AuthorizationBrowser` | `packages/wendelin_mcp/lib/src/ports.dart` | `app/lib/platform/channel_authorization_browser.dart` |
| `MemoryRetriever`, `HistoryProvider`, `ConversationRecorder`, `CostEstimator`, `BudgetGuard` | `packages/wendelin_agent/lib/src/ports.dart` | `app/lib/di/storage_adapters.dart`, `app/lib/di/costs.dart` |
| `NetworkStatus` | `packages/wendelin_agent/lib/src/routing/routing_context.dart` | `app/lib/platform/channel_network_status.dart` |
| `AudioInput`, `VoiceActivityDetector`, `SpeechToText`, `TextToSpeech` (optional `PrefetchingTextToSpeech`: `prepare` synthetisiert den nächsten Satz im Voraus, `speakPrepared` spielt ihn; die `SpeechQueue` hält einen Satz Vorlauf und verwirft ihn bei Stopp, WP120), `TriggerSource`, `BargeInDetector` (WP45, App-Adapter mit WP51/WP58) | `packages/wendelin_voice/lib/src/io/` | `app/lib/platform/voice/` (`record_audio_input.dart`, `silero_vad.dart`, `whisper_stt.dart`, `system_tts.dart`, `sherpa_tts.dart`), `app/lib/platform/assistant_platform.dart` |
| `WakeWordEngine`, `WakeFeatureExtractor`, `WakeVerifier` (`WakeTemplateStore` steht in der erzeugten Tabelle; WP44, zweistufiges Wake Word: Kandidat + Whisper-Nachprüfung, K29; App-Adapter mit WP50) | `packages/wendelin_voice/lib/src/wake/` (Logik: `CandidateWakeEngine`, `WakeWordListener`, `WakeWordTrigger`, `WakeWordBargeInDetector`, `calibrateThreshold`; WP113: Barge-in Stufe 2 mit `BargeVerifier`/`TranscriptBargeVerifier` und `SpokenTextSink`, Gegenprüfung durch Whisper, siehe `docs/notes/barge-stop-verify.md`; App: `app/lib/voice/wake/lazy_barge_verifier.dart`) | `app/lib/platform/voice/` (`ort_session.dart` C-API-Anbindung des onnxruntime von sherpa-onnx, `onnx_wake_models.dart` + `wake_feature_chain.dart` = `WakeFeatureExtractor`, WP60; Live-Dienst WP50). Einlernen, Kalibrieren, Ausprobieren (WP60): Logik `app/lib/voice/wake/` (`WakeEnroller`, `WakeCalibrator`, `WakeTester`, `SecretWakeTemplateStore` verschlüsselt im SecretStore), Provider `app/lib/di/wake_providers.dart` (Schalter Whisper-Nachprüfung `wakeVerifyProvider`), Oberfläche `app/lib/ui/settings/wake/` |
| `AttestationNotifier` (WP52) | `app/lib/platform/channel_notifier.dart` | `ChannelAttestationNotifier` über `NotifyChannel.kt`; Aufrufer ist `AttestationHub` (`app/lib/di/attestation_hub.dart`) |
| `AttestationCrypto` (WP46/WP47) | `packages/wendelin_providers/lib/src/tee/attestation_crypto.dart` | `RustAttestationCrypto` in `app/lib/platform/attest/rust_attestation_crypto.dart` über das Rust-Crate `native/attest` (`flutter_rust_bridge`, ADR 0017); Kollateral von Intel PCS (`pcs_collateral_client.dart`) mit Dateicache bis `nextUpdate` (`collateral_cache.dart`); Provider `attestationCryptoProvider` in `app/lib/di/attestation_providers.dart` |
