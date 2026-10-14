# Nutzerdefinierte Integrationen (`UserIntegrationSource`, `UserIntegrationSync`)

Seit WP39 im Paket (vorher `app/lib/di/user_integrations.dart`), Entscheidungen in [ADR 0012](../../../../../docs/adr/0012-user-integrations.md).

- `UserIntegrationSource`, `UserIntegrationKind`, `IntegrationRemoval`, `IntegrationCleanup` (`user_integration.dart`): die Schnittstelle, die MCP-Server und HTTP-Tools umsetzen.
- `UserIntegrationSync` (`user_integration_sync.dart`): hält eine Registry im Gleichschritt mit den Quellen (neu, geändert, entfernt, abgewiesen; Aufräumen nach dem Entfernen).
- Ports, die die App umsetzt: `UserIntegrationRegistry` (App: `ToolRegistryUserIntegrations` auf dem `ToolRegistry`) und `UserIntegrationSwitches` (App: `SettingsUserIntegrationSwitches`, Schlüssel `integration.<id>.enabled`).
- Fakes: `FakeUserIntegrationSource`, `FakeUserIntegrationRegistry` (dieselben `ArgumentError`-Meldungen wie die App-Registry), `FakeUserIntegrationSwitches` in `package:wendelin_integrations/fakes.dart`.
