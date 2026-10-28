# Architekturentscheidungen (ADR)

Status: **angenommen** (gilt), **teilweise überholt** (gilt mit dem Vermerk am Kopf der ADR; Verweis auf die ersetzende ADR bzw. den Konzepteintrag Kxx). Eine ADR wird nicht umgeschrieben, sondern mit einem datierten Vermerk versehen. Neue grundlegende Entscheidungen bekommen eine eigene ADR.

| ADR | Titel | Status |
|---|---|---|
| [0001](0001-modulschnitt.md) | Modulschnitt als Dart-Workspace | angenommen |
| [0002](0002-core-contracts.md) | Core-Verträge (`wendelin_core`) | angenommen |
| [0003](0003-agent-loop.md) | Agent-Schleife (`wendelin_agent`) | teilweise überholt |
| [0004](0004-app-wiring.md) | App-Verdrahtung (`app/`) | angenommen |
| [0005](0005-settings-onboarding.md) | Einstellungen und Onboarding (`app/lib/ui/settings/`, `app/lib/ui/onboarding/`) | teilweise überholt |
| [0006](0006-assistant-overlay.md) | Standard-Assistent, Overlay, Push-to-talk, Vault-Zugriff (`app/` + Kotlin) | teilweise überholt |
| [0007](0007-voice-platform.md) | Sprach-Plattform Android (`app/lib/platform/voice/`) | angenommen |
| [0008](0008-system-recognizer.md) | Lokale System-Spracherkennung (`RecognitionService` mit Whisper) | angenommen |
| [0009](0009-routing-regeln.md) | Routing-Regeln (Eskalationsketten entfallen, K28) | angenommen |
| [0010](0010-mcp-client.md) | MCP-Client (`packages/wendelin_mcp/`) | angenommen |
| [0011](0011-http-tools-netzziele.md) | HTTP-Tools und Netzziele | angenommen |
| [0012](0012-user-integrations.md) | Nutzerdefinierte Integrationen und App-Erkennung in der App | angenommen |
| [0013](0013-wake-word-dienst.md) | Wake-Word-Dienst (Android) | teilweise überholt |
| [0014](0014-tee-attestierung.md) | TEE-Attestierung: Vertrauensanker, Prüfstufen, Status | teilweise überholt |
| [0015](0015-gespraechsmodus-app.md) | Gesprächsmodus, Barge-in und Audioquelle in der App | teilweise überholt |
| [0016](0016-barge-in-gespraechsmodus.md) | Barge-in und Gesprächsmodus in der Sprach-Pipeline | teilweise überholt |
| [0017](0017-rust-pruefmodul.md) | Rust-Prüfmodul für die TEE-Attestierung (`native/attest`) | angenommen |
| [0018](0018-phala-e2ee-v2.md) | Phala-E2EE v2 verpflichtend (WP62, K37) | angenommen |
| [0019](0019-near-ai-e2ee.md) | NEAR AI Cloud als zweiter TEE-Anbieter mit E2EE inkl. Tools (WP75) | angenommen |
| [0020](0020-tinfoil.md) | Tinfoil als dritter TEE-Anbieter (SEV-SNP, EHBP, Sigstore) (WP76d) | angenommen |
| [0021](0021-engine-group-statt-engine-je-overlay.md) | Engine-Group statt Flutter-Engine je Overlay (WP145) | angenommen |
| [0022](0022-sicherheitsstufe-je-tool-und-geraet.md) | Sicherheitsstufe je Tool und je Home-Assistant-Gerät (WP154) | angenommen |
| [0023](0023-sitzungssperre-und-abfluss-schutz.md) | Sitzungssperre und Abfluss-Schutz (WP157) | angenommen |
