# ADR 0001 – Modulschnitt als Dart-Workspace

Status: angenommen · 2026-10-12

## Kontext
Das Konzept verlangt „alles ist ein Plugin“, austauschbare Provider/Tools und gute Testbarkeit. Die Projektstruktur im Konzept legt alles in `app/lib/…`. Dadurch hängt jeder Test am Flutter-SDK, und Grenzen (z. B. „keine Provider-Typen außerhalb der Adapter“) sind nur Konvention.

## Entscheidung
Die Kernlogik liegt in reinen Dart-Paketen eines Pub-Workspaces (`packages/wendelin_*`), die Flutter-App in `app/` verdrahtet sie nur und liefert UI und Plattform-Implementierungen.

- `wendelin_core` enthält nur Verträge (Nachrichtenformat, `LlmProvider`, `Tool`, `Integration`, `AgentRun`, Events) und Fakes.
- Alle anderen Pakete hängen nur von `core` ab, nie voneinander. Die Agent-Schleife kennt Tools und Provider ausschließlich über Core-Interfaces (`ToolCatalog`, `ToolInvoker`, `LlmProvider`).
- Gerätezugriff über Ports in `wendelin_integrations`; Implementierung in `app/lib/platform/`.
- `tool/check_deps.dart` erzwingt die Regeln im Gate.

## Folgen
- Jedes Paket ist mit `dart test` einzeln test- und austauschbar; Contract-Suites sichern, dass Fakes und echte Implementierungen dasselbe Verhalten haben.
- Eine gemeinsame `pubspec.lock` (Workspace) – parallele Arbeit erfolgt in getrennten Git-Worktrees.
- Abweichung von der Ordnerstruktur im Konzept (`app/lib/core` → `packages/wendelin_core` usw.); fachlicher Zuschnitt bleibt gleich.
