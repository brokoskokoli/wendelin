# Wendelin

Persönlicher Sprachassistent für Android (später iOS): lokal transkribieren, frei wählbares LLM über eigene API-Keys, Tool-Aufrufe auf dem Handy oder über MCP-Server. Die App führt Tools aus, nie das Modell. Schreibende Aktionen lassen sich kurz rückgängig machen, Aktionen mit Außenwirkung (`external`, z. B. Termin löschen) fragen immer nach, und jede Anfrage steht im Prüfprotokoll (Audit-Log) auf dem Gerät.

- Konzept: [`Voice Agent App – Gesamtkonzept.md`](Voice%20Agent%20App%20%E2%80%93%20Gesamtkonzept.md)
- Design: [`docs/design/DESIGN.md`](docs/design/DESIGN.md)
- Regeln für Beiträge: [`docs/ENGINEERING.md`](docs/ENGINEERING.md)
- Arbeitspakete: [`docs/work-packages/`](docs/work-packages/README.md)
- Architekturentscheidungen: [`docs/adr/`](docs/adr/)

## Status

**M1 (Text-Agent auf Android) ist erreicht** (2026-10-13): „Trag mir morgen um 10 Tauchen ein“ funktioniert per Text mit Claude Haiku (`claude-haiku-5-5`) und einem OpenAI-kompatiblen Modell (`gpt-5-mini`, außerdem Phala TEE). Der Termin landet im Gerätekalender, die Tool-Karte zeigt „Rückgängig“, alles steht im Audit-Log. Belege: Gerätetests auf einem AOSP-Emulator ohne Google Play (`app/integration_test/`), Live-Durchlauf (`evals/test/live/`), Modell-Eval ([`evals/reports/`](evals/reports/README.md)).

M1 umfasst: Anthropic- und OpenAI-kompatible Adapter, Provider-Einrichtung mit Verbindungstest, Agent-Schleife mit Bestätigungen und Eskalation, Integrationen Kalender, Zwischenablage, Wecker/Timer, Gedächtnis, Web (Abruf, Suche mit eigenem Suchdienst) und Listen (Markdown-Dateien über die Android-Dateiauswahl), Einstellungen, Onboarding, Kosten und Audit-Log.

Als Nächstes: M2 (Sprache, Assistent-Overlay, Obsidian), siehe [`docs/work-packages/M2.md`](docs/work-packages/M2.md).

## Aufbau

```
packages/wendelin_core          Verträge: Nachrichtenformat, Provider-, Tool-, Agent-Interfaces
packages/wendelin_providers     Anthropic- und OpenAI-kompatible Adapter, Modellkatalog, Kosten
packages/wendelin_tools         ToolRegistry, ToolExecutor, Risikostufen, Undo
packages/wendelin_agent         Agent-Schleife, Kontext, Limits, Eskalation
packages/wendelin_storage       drift/SQLite: Verlauf, Gedächtnis, Audit-Log, Kosten
packages/wendelin_integrations  Kalender, Zwischenablage, Wecker, Gedächtnis, Web, Listen (über Ports)
app/                            Flutter-App: UI, Verdrahtung, Android-Kanäle (Kalender, Dateien)
evals/                          Modell-Evals (Dart-CLI) und Live-Tests
tool/                           Gate, Prüfskripte, Gerätetests
```

Die Pakete unter `packages/` sind reines Dart ohne Flutter; Gerätezugriff geht über Ports, die die App implementiert. Details und Abhängigkeitsregeln: [`docs/ENGINEERING.md`](docs/ENGINEERING.md).

## Entwickeln und Gate

Voraussetzungen: Flutter 3.47 / Dart 3.13, Android SDK (API 35).

```sh
flutter pub get
dart run tool/gate.dart        # Format, Analyse, Tests, Abdeckung ≥ 85 %, Abhängigkeitsregeln, Secret-Scan
dart run tool/gate.dart --no-app   # ohne Flutter-App (wie der Ubuntu-Job in CI)
```

Das Gate muss vor jedem Commit grün sein. GitHub Actions (`.github/workflows/gate.yml`) führt es bei jedem Push aus: die Pakete auf Ubuntu, die App (Analyse und Widget-/Golden-Tests) auf macOS.

Weitere Prüfungen (lokal, brauchen Android-SDK bzw. Emulator):

```sh
tool/check_apk.sh              # Release-APK: keine GMS-/Firebase-Klassen, Backup aus, nur erwartete Berechtigungen
tool/e2e_android.sh            # Gerätetests app/integration_test/ auf dem verbundenen Emulator
```

`tool/e2e_android.sh` legt bei Bedarf einen lokalen Kalender an, erteilt die Kalender-Berechtigung per `adb shell pm grant` und bestätigt den Speichern-Dialog der Dateiauswahl. Getestet wird auf einem AVD mit AOSP-Image ohne Google Play:

```sh
sdkmanager "system-images;android-35;default;arm64-v8a"
avdmanager create avd -n Wendelin_AOSP_35 -k "system-images;android-35;default;arm64-v8a"
emulator -avd Wendelin_AOSP_35 -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect &
tool/e2e_android.sh
```

Live-Tests gegen echte APIs tragen `@Tags(['live'])` und laufen nur auf Wunsch mit Keys aus der Umgebung (siehe [`evals/README.md`](evals/README.md)).

## Demo-Anleitung M1

### 1. APK bauen und installieren

```sh
flutter pub get
cd app
flutter build apk --debug      # Debug: mit Demo-Modus; für den Alltag: --release
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Oder direkt `flutter run` mit angeschlossenem Gerät bzw. laufendem Emulator. Mindestversion ist Android 8.0 (API 26). Die App braucht keine Google Play Services.

### 2. Ohne Key ausprobieren (nur Debug-Build)

Im Onboarding „Demo ohne Provider“ wählen. Ein Skript-Provider beantwortet „Trag mir morgen um 10 Tauchen ein“ und „Lösch den Termin“; Kalender und Listen liegen dabei nur im Speicher.

### 3. Provider einrichten

Im Onboarding (Schritt „Sprachmodell“) oder unter Einstellungen → Provider:

1. Vorlage wählen: **Claude** (Anthropic), **OpenAI**, **Phala (RedPill)** (TEE), OpenRouter, Mistral, Tinfoil, Ollama oder eigener Endpunkt.
2. API-Key eingeben und **Verbindung testen**: der Key geht direkt in den sicheren Speicher (Android Keystore), die Modellliste wird geladen.
3. Modell wählen, z. B. `claude-haiku-5-5` oder `gpt-5-mini`, und **Modell prüfen** (prüft Tool-Calls und Streaming).
4. **Speichern**. Der Provider-Chip oben im Hauptbildschirm zeigt das Ziel.

Danach unter „Was darf Wendelin?“ bzw. Einstellungen → Integrationen den **Kalender** einschalten; Android fragt erst jetzt nach der Kalender-Berechtigung. Auf Geräten ohne Kalender-Konto braucht es einen lokalen Kalender (z. B. in der Kalender-App „Lokaler Kalender“ anlegen).

### 4. Beispielsätze

| Satz | Erwartung |
| --- | --- |
| Trag mir morgen um 10 Tauchen ein | Tool-Karte „Termin angelegt“ mit „Rückgängig · 10 s“, Termin im Gerätekalender |
| Was steht morgen in meinem Kalender? | Liste der Termine |
| Wann habe ich morgen Nachmittag eine Stunde Zeit? | Freie Zeiten |
| Lösch den Termin Tauchen | Bestätigungs-Sheet „Termin löschen?“ – erst „Ja, löschen“ löscht |
| Weck mich morgen um halb sieben | Wecker in der Uhr-App (ohne Uhr-App ist die Integration nicht verfügbar) |
| Stell einen Timer auf 12 Minuten | Timer |
| Merk dir, dass ich keinen Koriander mag | Eintrag im Gedächtnis (Einstellungen → Gedächtnis) |
| Setz Milch auf die Einkaufsliste | Eintrag in der Markdown-Liste (vorher unter Einstellungen → Listen eine Datei wählen) |

Kosten (heute, in USD) stehen im Chip neben dem Provider, Details unter Einstellungen → Kosten. Das Prüfprotokoll mit jeder Anfrage, jedem Tool-Aufruf, jeder Bestätigung und jedem „Rückgängig“ steht unter Einstellungen → Datenschutz und Logs.

## Ohne Google Play Services (K7)

Wendelin läuft auf entgoogelten Geräten (z. B. LineageOS ohne GApps, GrapheneOS): keine Abhängigkeit von `com.google.android.gms` oder Firebase, Kalender über `CalendarContract`, Dateien über das Storage Access Framework, Wecker über AOSP-Intents (der Benachrichtigungs-Fallback ohne Uhr-App ist noch offen). Geprüft mit `tool/check_apk.sh` und den Gerätetests auf einem AOSP-Image ohne Google Play.

## Lizenzhinweise

- Schriften: **Instrument Sans** und **IBM Plex Mono** unter der SIL Open Font License 1.1, gebündelt in `app/assets/fonts/` mit Lizenztexten (`OFL-*.txt`) und Herkunft (`SOURCES.txt`). Die App registriert die Texte beim Start in der Flutter-`LicenseRegistry` (eine Lizenzseite in den Einstellungen fehlt noch).
- Alle weiteren Abhängigkeiten sind Dart-/Flutter-Pakete von pub.dev unter ihren eigenen Lizenzen.
