# Stationsmodus (`station`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `station__start` | write | Stationsmodus öffnen (nur bei entsperrtem Telefon) |

Es gibt bewusst kein Tool zum Beenden (K62/K63): Beenden geht nur über den Button „Beenden“ in der Station nach dem Entsperren. Die Integration läuft nicht bei gesperrtem Gerät (`IntegrationSpec.allowedWhileLocked` ist `false`); das Tool prüft zusätzlich selbst `StationPort.isLocked` und lehnt ab.

**Port**: `StationPort` (`isLocked`, `start`). Fake: `FakeStationPort`, Vertrag: `stationPortContract`.

**Kotlin**: `StationChannel` (`start` öffnet `StationActivity`, `isLocked`), `StationTileService` (Schnellkachel).

**Berechtigung**: keine. **Plattformen**: Android.
