# Checklisten „Feature → Dateien“

**Neue eingebaute Integration**
1. Ordner `packages/wendelin_integrations/lib/src/<name>/` mit Integration, Tools und ggf. Port; `README.md` im Ordner (Tools, Risiko, Berechtigungen).
2. Einstiegspunkt `packages/wendelin_integrations/lib/<name>.dart` (Exporte mit `show`) und **eine** Zeile in `wendelin_integrations.dart`; Fakes und Contract in `fakes.dart`/`testing.dart` (nur anhängen).
3. Port-Implementierung in `app/lib/platform/`, Feld in `PlatformPorts`.
4. `IntegrationSpec` in eigener Datei `app/lib/di/integrations/<name>_spec.dart` (eigene Provider über `prepare`, nicht über `IntegrationDeps`) und **eine** Zeile in `app/lib/di/integrations/registry.dart`; Einrichtungsseite ggf. in `app/lib/ui/settings/integration_routes.dart` (und `setupPageFor` in `settings_routes.dart`).
5. Texte als Fragment `app/lib/l10n/src/<name>/<name>_{de,en,fr}.arb` (eigener Ordner reicht), Berechtigung ggf. in `AndroidManifest.xml`.
6. Vertrauensdatei `app/test/trust/<id>.json`, Integrationsdoku `docs/architecture/integrations/<id>.md`, Gerätetests `docs/testing/m5/<wp>.md` (Überschrift `# WPnn Titel`).
7. Tests im Paket; danach `tool/regen_generated.sh` (l10n, Tabellen, m5-Index) und die erzeugten Dateien mitcommitten.

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
2. `ProviderType` (`packages/wendelin_core/lib/src/provider/provider_type.dart`), `ProviderFactory`, Vorlage in `packages/wendelin_providers/lib/src/catalog/provider_template.dart`; Empfehlungen (Modell-ID, Treffer, p50, Messdatum) nur dort in `modelRecommendations` (WP128, Quelle `docs/notes/model-recommendation.md`), die Anzeige im Modellschritt `app/lib/ui/settings/provider_setup/model_step.dart`.
3. Einrichtung in `app/lib/ui/settings/provider_setup_screen.dart` und `app/lib/di/provider_setup.dart`.

**Smart Home: Gerät/Prompt/Abgleich (WP135)**
1. Wortlisten Gerätetyp/Aktion je Sprache: `packages/wendelin_core/lib/src/tools/ha_words/{de,en,fr}.dart` (`ha_words.dart`); Auflösung `ha_context.dart` (`_byTypeAndRoom`).
2. Feste Bestätigung: `ha_call_tools.dart` (`_fixed`, `confirmationKeys`), Texte `confirmation_texts/{de,en,fr}.dart`.
3. Geräteliste im Prompt: `PromptContributor` (`wendelin_core/lib/src/tools/prompt_contributor.dart`) von `HaCallDeviceTool`, Inhalt `ha_prompt.dart`; Sammeln `ContextBuilder._sections`, Filter je Ziel `run/model_call.dart` (`_basePrompt`).
4. Abgleich mit Home Assistant: `ha_sync.dart` (`haReconcile`, `haSyncStore`), `HaContext.syncIfDue`, Start in `app/lib/di/integrations/ha_spec.dart`, „Neu laden“ in `app/lib/ui/settings/ha_screen.dart`, Zeitstempel `ha.synced` in `app/lib/di/home_assistant.dart`.
5. Schnellweg (D): Erkennung `ha_fast_path.dart` (`HaFastPath`, Wörter `HaWords.neutral`), Port `FastPath` in `wendelin_core/lib/src/tools/fast_path.dart`, Ausführung `wendelin_agent/lib/src/run/fast_path_step.dart` (Einschub in `agent_runner.dart` `_loop`), Verdrahtung `app/lib/di/agent_factory.dart`/`agent_providers.dart`, Schalter `AppSettings.haFastPath` und `ha_screen.dart`.
6. Rollo ohne Rückfrage (E): `HaEntity.noConfirm`/`deviceClass`, `haCoverIsQuiet` in `ha_policy.dart`, `ha_call_tools.dart`, Undo `ha_undo.dart`, Schalter `ha_device_sections.dart`.
