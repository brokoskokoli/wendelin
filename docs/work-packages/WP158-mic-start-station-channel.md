# WP158 – Robustheit: Fehler beim Mikrofonstart, Stationskanal

**Zuordnung:** Projekt-Review vom 2026-10-26 (Befunde 6 und 7).

## Befunde
- `app/lib/voice/voice_controller.dart:240`: `prepare?.call()` ohne `try`. Wirft `hasPermission`/`ensureMicrophoneAccess` (PlatformException), ist der Vorlauf schon übernommen (`taken = true`), aber weder `_failStart` noch `takeWakeHandoff` laufen; das Dienstmikrofon (keepOpen) bleibt womöglich offen. Gleiches bei `_checkLock()` → `isLocked()` (Z. 247) und `app/lib/ui/overlay/assistant_overlay.dart:282-293`. Nicht am Gerät belegt.
- `app/lib/station/station_host.dart:41-48`: `MethodChannel` außerhalb von `app/lib/platform/` (Regel `docs/ENGINEERING.md:45`), `setMethodCallHandler` nie zurückgesetzt, `_dark` nie geschlossen; ein zweiter Host ersetzt still den Handler des ersten.

## Inhalt
- Fehlerwege zuerst mit Tests reproduzieren (werfendes `prepare`/`isLocked`), dann fail-closed: `_failStart` bzw. „gesperrt annehmen“, Wake-Übergabe sauber zurückgeben.
- Stationskanal nach `app/lib/platform/` verschieben, `dispose()` mit Handler-Reset und Stream-Schluss, Test für zwei Hosts.

## Abnahmekriterien
- [ ] Je Fehlerweg ein Test, der vor dem Fix rot ist (Mutationsbeleg).
- [ ] Dienstmikrofon nach Fehler geschlossen (Test bzw. E2E-Log).
- [ ] `check_deps`/Regelprüfung grün, `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Berührt `voice_controller.dart` und Overlay: nicht gleichzeitig mit WP153 (Entsperren) und nicht mit Lieferung 2 von WP154.
