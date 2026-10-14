# Power-Taste nach längerer Pause (WP56), Diagnose 2026-10-14

Emulator `Wendelin_AOSP_35` (AOSP 35), Release-APK, Assistenten-Rolle gesetzt, Auslöser `KEYCODE_ASSIST`.

| Szenario | Ergebnis |
|---|---|
| Baseline | Overlay nach ca. 1 s, `session-new → session-show → overlay-create` |
| `am kill` (Prozess bleibt, Dienst gebunden) | ok |
| `am crash` (Prozess weg, System bindet neu) | ok, neuer Prozess, Overlay ca. 1 s |
| `am force-stop` | ok, AOSP bindet den Dienst neu |
| Bucket `rare`, `restricted` (zusätzlich Prozess weg) | ok |
| `am set-inactive true` | ok |
| Doze (`deviceidle force-idle`) | auf dem Emulator nicht verfügbar („not enabled“) |

Kaltstart: `overlay-create` bis erstes Bild 1,4 s (Engine bereit nach 0,2 s).

## Befund
Auf AOSP lässt sich das Verhalten nicht nachstellen. Der Kaltstart-Pfad der Sitzung ist unauffällig (kein stilles Warten, Retry greift nach 3 s). Die wahrscheinlichste Ursache ist Vermutung 1: HyperOS beendet den Prozess und bindet den `VoiceInteractionService` ohne „Autostart“ und mit Akkusparer nicht neu. Nach dem Öffnen der App läuft der Prozess wieder und der Dienst ist gebunden, daher geht es danach. Das ist nur am Gerät prüfbar (`tool/diag_assistant_idle.sh`, Testanleitung `docs/testing/wp56-device.md`).

## Umgesetzt
- Natives Platzhalter-Fenster „Wendelin startet …“ im Overlay bis zum ersten Flutter-Bild; Log `overlay-engine-ready`, `overlay-first-frame`.
- Einstellungen → Assistent → „Zuverlässig öffnen“: Akku-Optimierung (Knopf `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), App-Standby-Bucket `rare`/`restricted`, Checkliste je Hersteller (Xiaomi, Samsung, OnePlus, Huawei) mit Deep-Link nur, wenn die Seite per `resolveActivity` erreichbar ist. Bausteine (`BatteryChannel`, `BatteryPlatform`, `BatteryHints`) sind für WP50 wiederverwendbar.
