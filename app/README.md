# Wendelin – App

Flutter-App (Android zuerst): UI, Riverpod-Verdrahtung der Pakete unter `packages/` und Plattform-Implementierungen der Ports. Entscheidungen: `docs/adr/0004-app-wiring.md`.

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `lib/di/` | Riverpod-Provider, Agent-Fabrik, Sitzungen, Audit, Kosten/Budget, Provider-Konfiguration, Demo-Provider, Integrations-Specs |
| `lib/agent/` | `AgentController` (Notifier) und reiner `ConversationReducer` über `AgentEvent`s |
| `lib/platform/` | Ports: `DeviceCalendarPort` (Kanal `app.wendelin/calendar` → `CalendarChannel.kt`), `FlutterClipboardPort`, `AndroidAlarmPort` (`AlarmClock`-Intents), `RepositoryMemoryPort`, `SecureSecretStore` |
| `lib/ui/design/` | Design-System (WP07) |
| `lib/ui/screens/` | Hauptbildschirm, Bestätigungs-Sheet, vorläufige Einstellungen |

Neue Integration: Port in `PlatformPorts` ergänzen (echt und Demo), `IntegrationSpec` in `builtInIntegrationSpecs` eintragen.

## Demo (Debug-Build, ohne Provider)

1. `flutter run` (Android).
2. Auf der Hinweis-Karte „Demo ohne Provider starten“ tippen (oder Einstellungen → Entwicklung → Demo-Modus).
3. „Trag mir morgen um 10 Tauchen ein“ schreiben und senden: Tool-Karte „Termin angelegt“ mit „Rückgängig · 10 s“, danach die Antwort.
4. „Lösch den Termin“: Bestätigungs-Sheet, „Nein, behalten“ lässt den Termin stehen.

Im Demo-Modus laufen alle Ports im Speicher; Kalender und Uhr des Geräts bleiben unberührt. Die Design-Galerie ist unter Einstellungen → Entwicklung erreichbar.

## Tests

`dart run tool/gate.dart app` im Repo-Root. Golden-Tests tragen den Tag `golden` (`test/ui/goldens/`, `test/screens/goldens/`).
