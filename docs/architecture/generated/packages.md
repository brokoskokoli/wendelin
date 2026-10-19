<!-- ERZEUGT von tool/gen_docs.dart (tool/regen_generated.sh). Nicht von Hand ändern. -->

# Pakete und ihre Abhängigkeiten (erzeugt)

Aus `packages/*/pubspec.yaml`: Beschreibung und Abhängigkeiten auf andere Workspace-Pakete. Die Regeln prüft `tool/check_deps.dart`; wichtige Typen stehen in [packages.md](../packages.md).

| Paket | Beschreibung | Hängt ab von |
| --- | --- | --- |
| `wendelin_agent` | Wendelin agent package. | `wendelin_core` |
| `wendelin_core` | Wendelin core package. | – |
| `wendelin_integrations` | Wendelin integrations package. | `wendelin_core` |
| `wendelin_mcp` | Wendelin MCP client (Streamable HTTP, Legacy-SSE, OAuth 2.1) and its mapping onto the tool system. | `wendelin_core`, `wendelin_integrations` |
| `wendelin_providers` | Wendelin providers package. | `wendelin_core` |
| `wendelin_storage` | Wendelin storage package. | `wendelin_core` |
| `wendelin_tools` | Wendelin tools package. | `wendelin_core` |
| `wendelin_voice` | Wendelin voice core – pipeline, endpointing, speech text, TTS selection, model catalog and download (pure Dart). | `wendelin_agent`, `wendelin_core` |
