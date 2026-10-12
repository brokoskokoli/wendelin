# Wendelin

Persönlicher Sprachassistent für Android (später iOS): lokal transkribieren, frei wählbares LLM über eigene API-Keys, Tool-Aufrufe auf dem Handy oder über MCP-Server. Die App führt Tools aus, nie das Modell.

- Konzept: [`Voice Agent App – Gesamtkonzept.md`](Voice%20Agent%20App%20%E2%80%93%20Gesamtkonzept.md)
- Design: [`docs/design/DESIGN.md`](docs/design/DESIGN.md)
- Regeln für Beiträge: [`docs/ENGINEERING.md`](docs/ENGINEERING.md)
- Arbeitspakete: [`docs/work-packages/`](docs/work-packages/README.md)
- Architekturentscheidungen: [`docs/adr/`](docs/adr/)

## Status

In Arbeit: Meilensteine M0 (Gerüst) und M1 (Text-Agent auf Android).

## Aufbau

```
packages/wendelin_core          Verträge: Nachrichtenformat, Provider-, Tool-, Agent-Interfaces
packages/wendelin_providers     Anthropic- und OpenAI-kompatible Adapter, Modellkatalog, Kosten
packages/wendelin_tools         ToolRegistry, ToolExecutor, Risikostufen, Undo
packages/wendelin_agent         Agent-Schleife, Kontext, Limits, Eskalation
packages/wendelin_storage       drift/SQLite: Verlauf, Gedächtnis, Audit-Log, Kosten
packages/wendelin_integrations  Kalender, Zwischenablage, Wecker, Gedächtnis, Web (über Ports)
app/                            Flutter-App
evals/                          Modell-Evals
```

## Entwickeln

```
flutter pub get
dart run tool/gate.dart        # Format, Analyse, Tests, Abdeckung, Abhängigkeitsregeln, Secret-Scan
```
