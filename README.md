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

**M2 (Sprache und Assistent) ist in Abnahme.** Ziel: Der lange Druck auf die Power-Taste öffnet Wendelin als Standard-Assistent, und ein gesprochener Befehl ergänzt eine Notiz im Obsidian-Vault. Gemergt sind:

- Sprach-Kern `wendelin_voice` (Pipeline, Endpointing, TTS-Auswahl, Modellkatalog und Download; WP15),
- Obsidian-Integration mit Vault-Port, Notiz-Tools, Tagesnotiz und Volltext-Index (WP16),
- Sprach-Plattform: Whisper und Silero VAD lokal über sherpa-onnx, Aufnahme, System-TTS mit sherpa-Fallback, Modell-Download (WP17, ADR 0007),
- Standard-Assistent mit Overlay, Push-to-talk im Hauptbildschirm, Vault über die Dateiauswahl (WP18, ADR 0006),
- lokale System-Spracherkennung (`RecognitionService` mit Whisper) für andere Apps (WP20, ADR 0008): aktiv nur, solange Wendelin die Assistenten-Rolle hält; die Einstellung „Als Spracherkennung für andere Apps anbieten“ ist standardmäßig an und abschaltbar.

Der End-to-End-Nachweis auf dem Emulator steht (WP19): Eine WAV statt des Mikrofons, Whisper base und small lokal, das Overlay über `KEYCODE_ASSIST` und eine byte-genau ergänzte Tagesnotiz im Test-Vault, dazu ein Live-Durchlauf mit Claude Haiku ([`docs/notes/m2-e2e-2026-10-13.md`](docs/notes/m2-e2e-2026-10-13.md)). Offen ist der Test auf einem echten Telefon nach [`docs/testing/m2-device.md`](docs/testing/m2-device.md). Pakete und Stand: [`docs/work-packages/M2.md`](docs/work-packages/M2.md).

## Aufbau

```
packages/wendelin_core          Verträge: Nachrichtenformat, Provider-, Tool-, Agent-Interfaces
packages/wendelin_providers     Anthropic- und OpenAI-kompatible Adapter, Modellkatalog, Kosten
packages/wendelin_tools         ToolRegistry, ToolExecutor, Risikostufen, Undo
packages/wendelin_agent         Agent-Schleife, Kontext, Limits, Eskalation
packages/wendelin_storage       drift/SQLite: Verlauf, Gedächtnis, Audit-Log, Kosten
packages/wendelin_integrations  Kalender, Zwischenablage, Wecker, Gedächtnis, Web, Listen, Obsidian, Bring!, HTTP-Tools (über Ports)
packages/wendelin_voice         Sprach-Kern: Pipeline, Endpointing, VAD/STT/TTS-Schnittstellen, Modell-Download
packages/wendelin_mcp           MCP-Client (Streamable HTTP, Legacy-SSE, OAuth 2.1) und Abbildung auf das Tool-System
app/                            Flutter-App: UI, Verdrahtung, Android-Kanäle (Kalender, Dateien, Sprache, Assistent)
evals/                          Modell-Evals (Dart-CLI) und Live-Tests
tool/                           Gate, Prüfskripte, Gerätetests
```

Die Pakete unter `packages/` sind reines Dart ohne Flutter; Gerätezugriff geht über Ports, die die App implementiert. Wo was liegt (Ports, Datenfluss einer Anfrage, Plattformkanäle, Checklisten): [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Regeln und Abhängigkeiten: [`docs/ENGINEERING.md`](docs/ENGINEERING.md).

## Entwickeln und Gate

Voraussetzungen: Flutter 3.47 / Dart 3.13, Android SDK (API 35).

```sh
flutter pub get
dart run tool/gate.dart        # Format, Analyse, Tests, Abdeckung ≥ 85 %, Abhängigkeiten, Secrets, Größen, Doku-Pfade, Selbsttests
dart run tool/gate.dart --no-app   # ohne Flutter-App (wie der Ubuntu-Job in CI)
dart run tool/gate.dart --changed  # Zwischenstand: nur geänderte Pakete und ihre Abhängigen
dart run tool/gate.dart --help     # alle Schalter
```

Die Ausgabe ist kompakt (eine Zeile je Schritt, bei Fehlern das Ende der Ausgabe des Schritts, am Ende eine Tabelle mit Dauer und `GATE GRÜN`/`GATE ROT`); `--verbose` zeigt alles.

Das Gate muss vor jedem Commit grün sein. GitHub Actions (`.github/workflows/gate.yml`) führt es bei jedem Push aus: die Pakete auf Ubuntu, die App (Analyse und Widget-/Golden-Tests) auf macOS.

Weitere Prüfungen (lokal, brauchen Android-SDK bzw. Emulator):

```sh
tool/check_apk.sh              # Release-APK: keine GMS-/Firebase-Klassen, Backup aus, nur erwartete Berechtigungen und exportierte Komponenten
tool/check_apk.sh --self-test  # Selbsttest des Prüfskripts mit Attrappen (ohne SDK, auch im Gate)
bash tool/android_device.sh --self-test  # Geräteauswahl mit Fake-adb: 0/1/2 Geräte, DEVICE/ANDROID_SERIAL (auch im Gate)
tool/e2e_android.sh            # Gerätetests app/integration_test/ auf dem verbundenen Emulator
WENDELIN_MODELS=<dir> tool/e2e_android.sh      # dazu Sprache und Assistent (M2, WP19)
WENDELIN_MODELS=<dir> tool/e2e_recognizer.sh   # System-Spracherkennung (androidTest, WP20)
tool/whisper_timing.sh [--clear]               # Whisper-Laufzeit auf dem eigenen Telefon aus logcat
```

`tool/e2e_android.sh` läuft nur auf Emulatoren (ein echtes Gerät nur mit `E2E_ALLOW_DEVICE=1`; bei mehreren Geräten `DEVICE` oder `ANDROID_SERIAL` setzen), legt bei Bedarf einen lokalen Kalender an, erteilt die Kalender-Berechtigung per `adb shell pm grant` und bestätigt den Speichern-Dialog der Dateiauswahl. Mit `WENDELIN_MODELS` (Ordner mit `whisper-base/`, `whisper-small/`, `silero-vad/` aus dem Modellkatalog) kopiert es zusätzlich Modelle und WAVs per `run-as` in die App, wählt den Test-Vault in der Ordnerauswahl, setzt die Assistenten-Rolle und öffnet das Overlay. Tests, die eine zweite Engine starten (Overlay), laufen über Android-Instrumentierung. Getestet wird auf einem AVD mit AOSP-Image ohne Google Play:

```sh
sdkmanager "system-images;android-35;default;arm64-v8a"
avdmanager create avd -n Wendelin_AOSP_35 -k "system-images;android-35;default;arm64-v8a"
emulator -avd Wendelin_AOSP_35 -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect &
tool/e2e_android.sh
```

Live-Tests gegen echte APIs tragen `@Tags(['live'])` und laufen nur auf Wunsch (`dart test -t live --run-skipped`) mit Keys aus der Umgebung; ohne Key überspringt sich ein Test selbst (siehe [`evals/README.md`](evals/README.md)).

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

## Demo-Anleitung M2

Sprache und Assistent auf dem Telefon. Die ausführliche Fassung mit Checkliste ist [`docs/testing/m2-device.md`](docs/testing/m2-device.md).

1. **Installieren und Provider einrichten** wie bei M1 (für den Alltag `flutter build apk --release --split-per-abi`, dann `app-arm64-v8a-release.apk`).
2. **Spracherkennung laden:** Im Onboarding-Schritt „Spracherkennung laden“ oder unter Einstellungen → Sprache Whisper wählen und laden, am besten im WLAN. Zur Wahl stehen „base“ (161 MB, schnell) und „small“ (376 MB, für Deutsch und Französisch deutlich genauer). Dazu kommt Silero VAD (0,6 MB). Nichts davon steckt im APK.
3. **Mikrofon:** Beim ersten Tipp auf das Mikrofon erklärt Wendelin, wozu er es braucht, dann fragt Android.
4. **Standard-Assistent:** Einstellungen → Assistent → „Als Standard-Assistent setzen“ → „Wendelin“ wählen. Bei Bedarf in Android das lange Drücken der Power-Taste auf „Digitaler Assistent“ stellen.
5. **Vault:** Einstellungen → Obsidian → „Vault-Ordner wählen“ (Android-Ordnerauswahl), Tagesnotizen eintragen (Ordner, Datumsformat wie in Obsidian, Vorlage), „Index aufbauen“.
6. **Ausprobieren:** Power-Taste lang drücken und sagen:

| Satz | Erwartung |
| --- | --- |
| Ergänze in meiner Tagesnotiz, dass ich den Zahnarzt angerufen habe. | Overlay über der aktuellen App, Karte „Tagesnotiz …: …“ mit „Rückgängig · 10 s“, neue Zeile in der Tagesnotiz |
| Was steht in meiner Notiz Wendelin-Test? | Wendelin liest vor, ohne Rückfrage |
| Ersetze in meiner Notiz Wendelin-Test den Abschnitt Status durch erledigt. | Bestätigung mit Zeilen-Diff, Wendelin fragt „Soll ich das tun? Ja oder nein?“, „Ja“ ersetzt |
| Note dans mon journal que la réunion est reportée. | wie oben auf Französisch (Gesprochene Sprache vorher auf „Français“ oder „Automatisch“) |
| Append to my daily note that the meeting moved to Friday. | wie oben auf Englisch |

„Stopp“ beendet, solange Wendelin zuhört. Ein Tipp beendet jederzeit. Auf dem gesperrten Telefon zeigt das Overlay nur „Gerät entsperren“. Als Standard-Assistent ist Wendelin auch die Spracheingabe anderer Apps (Einstellungen → Assistent, abschaltbar).

## Ohne Google Play Services (K7)

Wendelin läuft auf entgoogelten Geräten (z. B. LineageOS ohne GApps, GrapheneOS): keine Abhängigkeit von `com.google.android.gms` oder Firebase, Kalender über `CalendarContract`, Dateien über das Storage Access Framework, Wecker über AOSP-Intents (der Benachrichtigungs-Fallback ohne Uhr-App ist noch offen), Spracherkennung lokal mit Whisper, Sprachausgabe über System-TTS mit sherpa-onnx als Ausweichlösung. Geprüft mit `tool/check_apk.sh` und den Gerätetests auf einem AOSP-Image ohne Google Play.

## Lizenzhinweise

- Schriften: **Instrument Sans** und **IBM Plex Mono** unter der SIL Open Font License 1.1, gebündelt in `app/assets/fonts/` mit Lizenztexten (`OFL-*.txt`) und Herkunft (`SOURCES.txt`). Die App registriert die Texte beim Start in der Flutter-`LicenseRegistry` (eine Lizenzseite in den Einstellungen fehlt noch).
- Alle weiteren Abhängigkeiten sind Dart-/Flutter-Pakete von pub.dev unter ihren eigenen Lizenzen.
