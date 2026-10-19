# Checklisten „Feature → Dateien“

**Neue eingebaute Integration**
1. Ordner `packages/wendelin_integrations/lib/src/<name>/` mit Integration, Tools und ggf. Port; `README.md` im Ordner (Tools, Risiko, Berechtigungen).
2. Einstiegspunkt `packages/wendelin_integrations/lib/<name>.dart` (Exporte mit `show`) und **eine** Zeile in `wendelin_integrations.dart`; Fakes und Contract in `fakes.dart`/`testing.dart` (nur anhängen).
3. Port-Implementierung in `app/lib/platform/`, Feld in `PlatformPorts`.
4. `IntegrationSpec` in eigener Datei `app/lib/di/integrations/<name>_spec.dart` (eigene Provider über `prepare`, nicht über `IntegrationDeps`) und **eine** Zeile in `app/lib/di/integrations/registry.dart`; Einrichtungsseite ggf. in `app/lib/ui/settings/integration_routes.dart` (und `setupPageFor` in `settings_routes.dart`).
5. Texte in `app/lib/ui/screens/labels.dart`, Berechtigung ggf. in `AndroidManifest.xml`.
6. Tests im Paket, Verdrahtung in `app/test/di/wiring_test.dart`.

**Neue Einstellungsseite**
1. Screen in `app/lib/ui/settings/` (Gerüst `settings_page.dart`).
2. Routenname in `app/lib/ui/routes.dart` (`AppRoutes`), Route in `app/lib/ui/settings/general_routes.dart` (allgemeine Seiten) bzw. `integration_routes.dart` (Seite einer Integration), Eintrag in `app/lib/ui/settings/settings_screen.dart`.
3. Gespeicherte Werte in `app/lib/di/preferences.dart` bzw. `app/lib/di/preference_models.dart`.
4. Widget- und Golden-Test unter `app/test/settings/` (Goldens nur auf macOS aktualisieren).

**Neuer Kotlin-Kanal**
1. Kotlin-Klasse in `app/android/app/src/main/kotlin/app/wendelin/`, registriert in `WendelinActivity.kt` (Basis von `MainActivity.kt` und `AssistantActivity.kt`).
2. Dart-Seite in `app/lib/platform/` mit Kanalname als Konstante in `app/lib/platform/channels.dart`, Test mit Mock-Handler unter `app/test/platform/`.
3. Kanal und alle Methoden in `app/channels.json` eintragen (sonst ist `tool/check_channels.dart` rot), Zeile in der Tabelle oben.
4. Logik ohne Android-Typen in eine reine Kotlin-Klasse (wie `CalendarRows.kt`, `VaultTree.kt`, Argumente über `ChannelArgs.kt`) mit JUnit-Test unter `app/android/app/src/test/kotlin/app/wendelin/`.

**Neue Provider-Art**
1. Adapter unter `packages/wendelin_providers/lib/src/<adapter>/` (Wire-Format nur dort), Contract-Suite `llmProviderContract` aus `wendelin_core`.
2. `ProviderType` (`packages/wendelin_core/lib/src/provider/provider_type.dart`), `ProviderFactory`, Vorlage in `packages/wendelin_providers/lib/src/catalog/provider_template.dart`.
3. Einrichtung in `app/lib/ui/settings/provider_setup_screen.dart` und `app/lib/di/provider_setup.dart`.
