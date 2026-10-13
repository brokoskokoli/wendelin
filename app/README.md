# Wendelin – App

Flutter-App (Android zuerst): UI, Riverpod-Verdrahtung der Pakete unter `packages/` und Plattform-Implementierungen der Ports. Entscheidungen: `docs/adr/0004-app-wiring.md`, `docs/adr/0005-settings-onboarding.md`, `docs/adr/0006-assistant-overlay.md`.

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `lib/di/` | Riverpod-Provider, Agent-Fabrik, Sitzungen, Audit, Kosten/Budget, Provider-Konfiguration, Demo-Provider, Integrations-Specs |
| `lib/agent/` | `AgentController` (Notifier) und reiner `ConversationReducer` über `AgentEvent`s |
| `lib/platform/` | Ports: `DeviceCalendarPort` (Kanal `app.wendelin/calendar` → `CalendarChannel.kt`), `FlutterClipboardPort`, `AndroidAlarmPort` (`AlarmClock`-Intents), `RepositoryMemoryPort`, `SafListFilePort` + `DocumentPicker` (Kanal `app.wendelin/files` → `FilesChannel.kt`), `SafVaultPort` + `VaultAccess` (Kanal `app.wendelin/vault` → `VaultChannel.kt`), `RepositoryNoteIndexPort`, `AssistantPlatform` (Kanal `app.wendelin/assistant` → `AssistantChannel.kt`), `SecureSecretStore` |
| `lib/voice/` | Sprache in der App: `VoiceComponents` (Schnittstelle zu WP17), `VoiceController` (Push-to-talk, Overlay, Bestätigung per Stimme), Pegelanzeige |
| `lib/ui/overlay/` | Assistenten-Overlay (Dart-Einstieg `assistantMain`, `AssistantActivity.kt`) |
| `lib/ui/design/` | Design-System (WP07) |
| `lib/ui/screens/` | Hauptbildschirm, Bestätigungs-Sheet |
| `lib/ui/settings/` | Einstellungen: Provider (Einrichtungsdialog), Integrationen, Obsidian, Listen, Web-Suche, Gedächtnis, Datenschutz und Logs, Kosten, Assistent (Standard-Assistent) |
| `lib/ui/onboarding/` | Erster Start: Sprache, Provider, Integrationen |

Neue Integration: Port in `PlatformPorts` ergänzen (echt und Demo), `IntegrationSpec` in `builtInIntegrationSpecs` eintragen.

## Demo (Debug-Build, ohne Provider)

1. `flutter run` (Android).
2. Im Onboarding „Demo ohne Provider“ wählen, oder auf der Hinweis-Karte „Demo ohne Provider starten“ tippen (oder Einstellungen → Entwicklung → Demo-Modus).
3. „Trag mir morgen um 10 Tauchen ein“ schreiben und senden: Tool-Karte „Termin angelegt“ mit „Rückgängig · 10 s“, danach die Antwort.
4. „Lösch den Termin“: Bestätigungs-Sheet, „Nein, behalten“ lässt den Termin stehen.

Im Demo-Modus hört das Mikrofon „Trag mir morgen um 10 Tauchen ein“, dann „Lösch den Termin“, dann „Ja“ (Bestätigung per Stimme); gesprochen wird nichts. Außerdem gibt es den Vault „Demo“ mit zwei Notizen und die Listen „Einkaufen“ und „SmartSSH“ (im Speicher); das Demo-Skript selbst versteht nur Termine.

Im Demo-Modus laufen alle Ports im Speicher; Kalender und Uhr des Geräts bleiben unberührt. Die Design-Galerie ist unter Einstellungen → Entwicklung erreichbar.

## Tests

`dart run tool/gate.dart app` im Repo-Root. Golden-Tests tragen den Tag `golden` (`test/ui/goldens/`, `test/screens/goldens/`, `test/overlay/goldens/`).

## Standard-Assistent (Emulator)

```
adb shell cmd role add-role-holder android.app.role.ASSISTANT app.wendelin 0
adb shell settings get secure voice_interaction_service   # app.wendelin/.WendelinVoiceInteractionService
adb shell input keyevent KEYCODE_ASSIST                     # öffnet das Overlay
```
