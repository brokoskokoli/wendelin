# WP40 – R6: Plattformkanäle prüfbar machen, große Einstellungs-Screens aufteilen (`app/android`, `app/lib/platform`, `app/lib/ui/settings`, `tool/`)

Abhängig von: **WP30** und **WP32** (beide ändern Kotlin: `WendelinVoiceSessionService`, `AssistantActivity`, `RecognizerSwitch`, `AssistantChannel`; WP32 außerdem die Einstellungs-Screens und den Baustein `SecretField`), **WP27** (neuer `AuthChannel.kt`, `OAuthRedirectActivity.kt`), dazu WP35. Sinnvoll nach WP38/WP39, weil dann `app/lib/di` und die HTTP-Tool-Logik schon umgezogen sind. Übersicht und Grundregeln: `R-refactoring.md` (verhaltensneutral). Bezug: Gutachten **M6** (Kanäle stringbasiert, Kotlin ohne Unit-Tests), **M7** (große UI-Zustandsklassen und `build()`-Methoden). ADRs: 0004 (App-Verdrahtung), 0007 (Sprach-Plattform); **ADR 0013** ist für dieses Paket reserviert (nur falls Pigeon bzw. Codegenerierung).

Andockpunkte: Dart-Kanäle in `app/lib/platform/` (`channel_network_status.dart`, `channel_app_presence_port.dart`, `document_text_import.dart`, `device_calendar_port.dart`, `screen_protection.dart`, `saf_list_file_port.dart`, `saf_vault_port.dart`, `assistant_platform.dart`, `recognizer/recognizer_host.dart`, Auth-Kanal aus WP27), Kotlin unter `app/android/app/src/main/kotlin/app/wendelin/` (`AppsChannel`, `AssistantChannel`, `AuthChannel`, `CalendarChannel` 356 Z., `FilesChannel`, `NetworkChannel`, `VaultChannel` 328 Z., `WindowChannel`, Recognizer), `app/android/app/build.gradle(.kts)`, `app/lib/ui/settings/http_tool_editor_screen.dart` (`_EditorState` 650 Z.), `provider_setup_screen.dart` (`_ProviderSetupState` 322 Z.), `obsidian_screen.dart` (`_ObsidianState` 220 Z.), lange `build()`-Methoden (`ui/design/compositions.dart`, `ui/overlay/assistant_overlay.dart`, `integration_detail_screen.dart`, `voice_screen.dart`, `privacy_screen.dart`).

## Schnitt in Teil-Merges

| Teil | Inhalt |
| --- | --- |
| a | Kanal-Manifest und Gate-Check |
| b | Kotlin-Logik in reine Klassen, JVM-Unit-Tests |
| c | Einstellungs- und Editor-Screens aufteilen, lange `build()`-Methoden zerlegen (soweit nicht durch WP32 erledigt) |

## Inhalt

**a) Kanal-Manifest und Gate-Check (M6 Variante B)**
- `app/channels.json` (oder `.yaml`): je Kanal Name, Dart-Datei, Kotlin-Datei, Methoden mit Argumentschlüsseln und Art der Rückgabe (Wert, Liste, Map, nichts), Richtung (Dart→Kotlin oder Kotlin→Dart, z. B. Recognizer-Rückrufe), dazu EventChannels, falls vorhanden.
- `tool/check_channels.dart` (reines Dart, < 1 s, ohne Android-SDK, Gate-Schritt): liest das Manifest und prüft in beide Richtungen per Textanalyse:
  - Dart: Kanalkonstanten, `invokeMethod('<name>'`, `invokeMapMethod`/`invokeListMethod`, Argument-Maps (Schlüssel), `setMethodCallHandler`-Fälle.
  - Kotlin: Kanalnamen, `"<name>" ->` in `when (call.method)`, `call.argument<…>("<key>")`, `invokeMethod("<name>"` für Rückrufe.
  - Fehler bei: Methode nur auf einer Seite, Argumentschlüssel nur auf einer Seite, Kanal ohne Manifest-Eintrag, Manifest-Eintrag ohne Code. Die Fehlermeldung nennt Datei und Zeile.
  - Tests mit kleinen Beispieldateien (ein absichtlich umbenannter Methodenname auf einer Seite wird erkannt).
- Die Kanalnamen bleiben unverändert. Dart-Konstanten (`channelName`, `vaultChannelName` …) werden, wo sinnvoll, in `app/lib/platform/channels.dart` gesammelt.

**b) Kotlin-Logik testbar machen**
- Logik ohne Android-Abhängigkeit aus den Kanälen in reine Kotlin-Klassen ziehen, z. B. `CalendarRowMapper` (Cursor-Werte → Map, Zeitzonen, Wiederholung), Vault-Pfadauflösung (SAF-Dokument-IDs → relative Pfade, Namensregeln), Argumentprüfung je Kanal, Auswertung in `RecognizerSwitch` (Komponentenvergleich, falls WP32 das nicht schon getan hat), OAuth-Redirect-Prüfung aus WP27 (`state`, Schema).
- JVM-Unit-Tests unter `app/android/app/src/test/kotlin/` mit JUnit (ohne Robolectric, wo möglich), über `./gradlew :app:testDebugUnitTest`.
- Gate: eigener Schritt `kotlin-unit`, der nur läuft, wenn das Android-SDK gefunden wird (`ANDROID_HOME` bzw. `~/Library/Android/sdk`). Ohne SDK steht er in der Zusammenfassung als „übersprungen (kein Android-SDK)“, nicht als grün. Die Laufzeit wird gemessen; ist sie zu lang für jeden Lauf, läuft der Schritt nur bei `--changed` mit Kotlin-Änderungen und im vollen Gate. Entscheidung und Messwert im Bericht.
- **Optional, nur mit ADR 0013 und Bestätigung des Maintainers:** Pigeon für die beiden großen Kanäle (Kalender, Vault). Codegenerierung ist laut `ENGINEERING.md` bisher außer drift ausgeschlossen. Ohne Bestätigung entfällt dieser Punkt.

**c) Einstellungs- und Editor-Screens (M7)**
- Vor dem Start prüfen, was WP32 bereits aufgeteilt hat (`SecretField`, Provider-Einrichtung, Obsidian). Nur der Rest ist Teil dieses Pakets.
- `http_tool_editor_screen.dart`: in Abschnitte unter `ui/settings/http_tool_editor/` teilen (z. B. `source_section.dart`, `auth_section.dart`, `args_section.dart`, `test_run_panel.dart`). `_EditorState` hält nur noch den Zustand und delegiert an das Draft-Modell aus WP39.
- `provider_setup_screen.dart` und `obsidian_screen.dart`: Zustandslogik und Abschnitte trennen, sodass keine Zustandsklasse > 250 Zeilen hat.
- `build()`-Methoden > 80 Zeilen in benannte Unter-Widgets zerlegen (`compositions.dart`, `assistant_overlay.dart`, `integration_detail_screen.dart`, `voice_screen.dart`, `privacy_screen.dart`, soweit noch vorhanden). Semantics-Labels, Keys für Tests und Touch-Ziele bleiben gleich.

## Abnahmekriterien
- [ ] Verhaltensneutral: Kanalnamen, Methodennamen, Argumentschlüssel, Rückgabewerte und Nutzertexte unverändert. Widget-Tests grün ohne geänderte Erwartung, **Goldens unverändert** (`git diff --stat main...HEAD -- '*.png'` leer, kein `--update-goldens`). Bestehende `androidTest`-Tests unverändert.
- [ ] Manifest deckt alle Kanäle ab (Liste im Bericht, Anzahl Methoden je Kanal). `check_channels.dart` im Gate, < 1 s, mit Tests. Eine absichtlich nur auf einer Seite umbenannte Methode bzw. ein umbenannter Argumentschlüssel lässt das Gate rot werden (lokal vorgeführt, nicht committet, im Bericht).
- [ ] JVM-Unit-Tests für die herausgezogenen Kotlin-Klassen, mindestens Kalender-Mapping, Vault-Pfadauflösung und Argumentprüfung. Gate-Schritt `kotlin-unit` läuft mit SDK, ohne SDK als „übersprungen“ markiert.
- [ ] Kotlin: `CalendarChannel.kt` und `VaultChannel.kt` je ≤ ca. 200 Zeilen, Logik in getesteten Klassen.
- [ ] Screens: keine Zustandsklasse > 250 Zeilen, keine `build()`-Methode > 80 Zeilen in `app/lib/ui` (oder begründet auf der Größen-Allowlist mit Verweis). Allowlist-Einträge aus WP35 für diese Dateien entfernt.
- [ ] Mutationsproben (je Teil ≥ 5): z. B. Methodenname auf einer Seite geändert (Check rot), Kalender-Mapping vertauscht Start/Ende, Vault-Pfad ohne Unterordner, Redirect ohne `state`-Prüfung, Abschnitt des Editors speichert Feld nicht ins Draft, Secret-Feld ohne `obscureText`. Jede Mutation macht einen Test oder den Check rot.
- [ ] Emulator (`Wendelin_AOSP_35`, expliziter Serial `DEVICE=emulator-xxxx`, vorher `ro.kernel.qemu=1` prüfen; kein `E2E_ALLOW_DEVICE`): `tool/e2e_android.sh` grün (Kalender anlegen, Vault/Obsidian lesen und schreiben, Overlay, Erkenner), weil Kotlin sich ändert. `tool/check_apk.sh` grün.
- [ ] Gate grün (voll), APK baut.
- [ ] Diff je Teil ≤ ca. 1 500 Zeilen geänderter Produktivcode (Dart und Kotlin `main`), reine Verschiebungen ausgewiesen.
- [ ] Messwerte vorher/nachher im Bericht: Zahl der geprüften Kanäle und Methoden (vorher 0), Zahl der Kotlin-Unit-Tests (vorher 0), Zeilen `CalendarChannel.kt`/`VaultChannel.kt`, größte Zustandsklasse und längste `build()`-Methode in `app/lib/ui`, Laufzeit der neuen Gate-Schritte.
- [ ] `docs/ARCHITECTURE.md` (Abschnitt „Plattformkanäle“, Checkliste „neuer Kotlin-Kanal“) und `ENGINEERING.md` (Manifest-Pflicht, Kotlin-Unit-Tests) nachgeführt.

Prüfliste für den Maintainer (echtes Telefon), kurz: Kalendereintrag anlegen und rückgängig machen, Tagesnotiz ergänzen, HTTP-Tool-Editor öffnen und speichern, Overlay per Power-Taste.
