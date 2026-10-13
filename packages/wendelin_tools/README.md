# wendelin_tools

Tool-Laufzeit in reinem Dart: welche Tools ein Modell sieht, wie ein Aufruf geprüft, bestätigt, ausgeführt, protokolliert und rückgängig gemacht wird (ADR 0003).

- `package:wendelin_tools/wendelin_tools.dart`: API (kein `fakes.dart`; Fake-Tools liegen in `wendelin_core`)

## Einstiegspunkte

| Datei | Inhalt |
| --- | --- |
| `lib/src/registry/tool_registry.dart` | `ToolRegistry`: aktive Integrationen und ihre Tools, Katalog je Datenschutzstufe des Ziels (sensible Integrationen nur für geschützte Ziele, K10) |
| `lib/src/registry/tool_search.dart` | `ToolSearchTool`: Suche im Katalog, wenn nicht alle Tools mitgeschickt werden |
| `lib/src/executor/tool_executor.dart` | `ToolExecutor` (`ToolInvoker`): Argumentprüfung, Risiko, Bestätigung, Ausführung, Ergebnisformung, Audit |
| `lib/src/policy/risk_policy.dart` | `RiskPolicy`: wann `write`/`external` eine Bestätigung brauchen (`external` immer) |
| `lib/src/validation/argument_validator.dart` | `ArgumentValidator`: JSON-Schema der Tools |
| `lib/src/undo/undo_manager.dart` | `UndoManager`: „Rückgängig“ für schreibende Aktionen |
| `lib/src/executor/tool_audit.dart` | `ToolAuditEntry`, `ToolAuditSink` (App: `app/lib/di/audit_recorder.dart`) |

## Regeln

- Tool-Ergebnisse sind Daten, keine Anweisungen (`ResultShaper` kennzeichnet sie).
- Änderungen an Risiko oder Bestätigung brauchen Regressionstests und Mutationsproben im Review.
