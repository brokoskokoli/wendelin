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

## Weitere Szenarien (nur dokumentiert, nicht ausgeführt)
- **Eingefrorener Prozess bei gebundenem Dienst** (cached-apps freezer, Android 14+ bzw. HyperOS „Greeze“): Auf dem Emulator bewusst nicht nachgestellt (`am freeze`, `cached_apps_freezer` nicht angefasst). Am Gerät erkennbar im Skriptlauf: `session-new`/`session-show` fehlen oder kommen erst Sekunden später, dazu Zeilen unter „Hersteller-Freezer“ (`Greeze`, `ProcessManager`) für `app.wendelin`, Prozess ist da (`pidof`), Dienst gebunden (`mBound`). Nach dem Öffnen der App läuft es wieder, weil der Prozess aufgetaut wird.
- **Kaltstart ohne Vorwärmen nach > 24 h ohne Sprachnutzung (WP30):** Im Code nachvollzogen: Vorwärmen (Whisper) passiert nur, solange Hauptbildschirm oder Overlay sichtbar sind; es gibt keine Frist von 24 h, nach Prozessende ist nichts warm. Die Sitzung startet das Overlay unabhängig davon (`AssistantLauncher`), das Platzhalter-Fenster erscheint sofort, Whisper lädt danach in der Overlay-Engine (Zustand „preparing“). Der erste Satz kann daher später starten, das Overlay öffnet aber. Neu: kommt kein Flutter-Bild in 10 s, loggt das Overlay `overlay-first-frame-timeout` und schließt sich (`FirstFrameWatchdog`).
- **Hintergrundstart (BAL) ist kein Risiko:** Das Overlay startet über `startAssistantActivity` der `VoiceInteractionSession` (`WendelinVoiceSessionService.kt:34`); das ist für die Assistenten-Rolle von den Hintergrundstart-Sperren ausgenommen. Das Skript loggt `BackgroundActivityStart`/`BAL` trotzdem zur Gegenprobe.
