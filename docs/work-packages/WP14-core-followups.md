# WP14 – Core-Folgepunkte aus WP06/WP08

Abhängig von: WP08 gemergt. Kleine, paketübergreifende Verbesserungen, die bei der Verdrahtung aufgefallen sind.

1. **Risikostufe in der Bestätigung**: `ConfirmationNeeded` (core, ToolInvoker) und `ConfirmationRequired` (AgentEvent) tragen die *effektive* Risikostufe aus der `RiskPolicy`-Entscheidung (inkl. verschärfter Overrides). ToolExecutor (WP03) befüllt sie, AgentRunner reicht sie durch, App zeigt sie statt `tool.risk`.
2. **Tool-Katalog je Ziel**: Der Agent bekommt statt eines festen Katalogs eine Funktion `catalogFor(PrivacyLevel)` und wählt den Katalog passend zum aktuellen Ziel (auch nach Eskalation), damit TEE-/lokale Ziele sensible Tools nutzen können, während Standard-Ziele sie nicht sehen. Tool-Calls zu Tools, die das aktuelle Ziel nicht sehen durfte, werden abgelehnt.
3. **Optionale Setup-Schritte**: `SetupStep.optional`; die Registry behandelt eine Integration mit nur offenen optionalen Schritten als aktiv (Beispiel web: ohne Suchdienst nur `web__fetch`). Die Web-Integration bietet dann nur die Tools an, die ohne den Schritt funktionieren.
4. **describeForConfirmation mit Kontext** (Wunsch WP06): asynchrone Vorbereitung `Future<String> prepareConfirmation(args, ctx)` mit Default auf `describeForConfirmation`, damit der Kalender Titel/Zeit live nachschlagen kann und der Termin-Cache entfallen kann.

## Abnahmekriterien
- [ ] Je Punkt Tests in den betroffenen Paketen, Contract-Suites angepasst, ADR 0002 ergänzt.
- [ ] Gate grün über alle Pakete und app.
