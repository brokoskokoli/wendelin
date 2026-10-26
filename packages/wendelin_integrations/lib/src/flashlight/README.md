# Taschenlampe (`flashlight`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `flashlight__on` | write | Taschenlampe einschalten |
| `flashlight__off` | write | Taschenlampe ausschalten |
| `flashlight__toggle` | write | Zustand umkehren |

Keine Nachfrage, nicht sensibel, alle Datenschutzstufen, kein Netz. Undo stellt den vorherigen Zustand her; war der Zustand schon der gewünschte, gibt es kein Undo. Die Ergebnisse enthalten nur den eigenen Zustand (`TrustedContentSource`).

**Port**: `TorchPort` (`isAvailable`, `state`, `set`). Fehlerfälle werfen `PortException` mit Kurztext: keine Blitz-LED (`unsupported`), Kamera belegt, Thermik-Sperre (`unavailable`); das Tool meldet sie als Tool-Fehler. Die Integration selbst gilt immer als verfügbar, damit die Fehlermeldung bei fehlender LED in der Tool-Karte erscheint. Fake: `FakeTorchPort`, Vertrag: `torchPortContract`.

**Kotlin**: `TorchChannel` (`CameraManager.setTorchMode`, `registerTorchCallback`; der Zustand folgt auch der Systemkachel).

**Berechtigung**: keine (`CAMERA` wird für `setTorchMode` nicht gebraucht). **Plattformen**: Android.

**Gesperrtes Gerät (WP53)**: `IntegrationSpec.allowedWhileLocked` (App) ist hier `true` gesetzt; `LockGateAgentRun` (WP53) führt „Taschenlampe an/aus“ bei Sperre lokal aus, ohne Modell (`matchLockedCommand`).

**Stufe (WP154 L2, ADR 0022)**: `flashlight__on` und `__off` haben Standard **A** (`DefaultLevelTool`), `__toggle` C; gesperrt läuft damit nur A, sonst „Entsperren nötig“. Der Nutzer kann jedes Tool umstellen (D: auch der lokale Befehl wird gesperrt verweigert). Ein Modelllauf gesperrt entsteht erst, wenn über die beiden lokalen Befehle hinaus ein Tool erlaubt ist.
