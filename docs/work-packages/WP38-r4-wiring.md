# WP38 – R4: Verdrahtung entflechten (`wendelin_integrations` Barrels, `app/lib/di`, App-Einstieg)

Abhängig von: **WP27, WP30, WP32 und WP31** (alle gemergt), dazu WP35. Übersicht und Grundregeln: `R-refactoring.md` (verhaltensneutral). Bezug: Gutachten **H2** (Verdrahtungs-Hotspots: Barrel in 9 WPs geändert, `main.dart` 7, `fakes.dart`/`testing.dart`/`integration_specs.dart`/`routes.dart`/`app.dart`/`test_env.dart` je 6, `providers.dart` 5 und von 40 Dateien importiert), **N7** (Ordnerlogik in `app/lib`). ADRs: 0004 (App-Verdrahtung), 0012 (nutzerdefinierte Integrationen).

Andockpunkte: `packages/wendelin_integrations/lib/wendelin_integrations.dart` (`show`-Listen), `…/lib/fakes.dart`, `…/lib/testing.dart`, `app/lib/di/providers.dart` (35 von 87 Providern, `integrationDepsProvider`, `integrationsProvider`, `toolRegistryProvider`), `app/lib/di/integration_specs.dart` (`IntegrationDeps`, `IntegrationSpec`-Liste), `app/lib/main.dart`, `app/lib/app.dart`, `app/lib/ui/routes.dart`, `app/lib/ui/screens/labels.dart`, `app/test/support/test_env.dart`, `app/test/di/wiring_test.dart`.

**Warum erst jetzt:** WP27 (MCP-Quelle, `providers.dart`, `integration_specs.dart`), WP30 (`main.dart`, `app.dart`, Lebenszyklus), WP32 (`routes.dart`, Einstellungen) und WP31 (Hauptbildschirm, Overlay) ändern genau diese Dateien. WP29 darf parallel laufen. Arbeitet es gleichzeitig an `test_env.dart` oder `app/integration_test/`, stimmen sich beide über den Orchestrator ab.

## Schnitt in Teil-Merges

| Teil | Inhalt |
| --- | --- |
| a | Barrels je Integration in `wendelin_integrations` (rein paketintern plus Importe) |
| b | `providers.dart` aufteilen, `integration_specs` als Registry |
| c | `main.dart`, `app.dart`, `routes.dart`, `test_env.dart` entlasten |

## Inhalt

**a) Barrel je Integration**
- Je Integration ein Einstiegspunkt: `package:wendelin_integrations/calendar.dart`, `…/clipboard.dart`, `…/alarm.dart`, `…/memory.dart`, `…/web.dart`, `…/lists.dart`, `…/obsidian.dart`, `…/bring.dart`, `…/http_tools.dart`, `…/apps.dart` (nach Stand `main`), dazu `…/common.dart` für gemeinsame Typen (Ports, Matching, `net_scope` aus WP36). Die `show`-Listen wandern in diese Dateien.
- `wendelin_integrations.dart` exportiert nur noch diese Einstiegspunkte, **eine Zeile je Integration**, alphabetisch. Bestehende Importe `package:wendelin_integrations/wendelin_integrations.dart` funktionieren unverändert.
- Dasselbe für `fakes.dart` und `testing.dart`: je Integration eine Datei unter `lib/fakes/` bzw. `lib/testing/` (sofern vorhanden), die Sammeldateien exportieren sie zeilenweise.
- Gleiches Muster für `wendelin_mcp`, falls dessen Barrel ebenfalls `show`-Listen hat, die mehrere WPs ändern.

**b) `providers.dart` und Registry**
- `providers.dart` wird nach Bereich geschnitten, z. B. `di/core_providers.dart` (Uhr, IDs, Storage, Startup, Gerät, Secrets, HTTP, URL-Launcher, Demo-Modus, Ports), `di/integration_providers.dart` (Specs, Deps, Integrationen, installierte Apps, Registry, nutzerdefinierte Integrationen, Activator), `di/agent_providers.dart` (Risiko, Undo, Audit, Sitzung, Provider-Konfiguration, Factory, Kosten). `providers.dart` bleibt als **reines Re-Export-Barrel**, sodass sich die 40 Importe nicht ändern müssen. Neue Dateien importieren gezielt den Bereich.
- `integration_specs.dart` wird zur **Registry mit einer Datei je Integration**: `di/integrations/calendar_spec.dart`, `…/bring_spec.dart`, `…/obsidian_spec.dart`, `…/mcp_spec.dart` usw. Jede Datei definiert ihren `IntegrationSpec` und, falls nötig, ihre eigenen Abhängigkeiten. Die Registry-Liste `di/integrations/registry.dart` ist eine Liste mit einer Zeile je Integration.
- `IntegrationDeps` sammelt heute integrationsspezifische Felder (`bringApi`, `bringSecrets`, `webSearch`). Diese wandern in die Spec der jeweiligen Integration (z. B. die Spec liest ihre Provider selbst über `Ref` oder bekommt einen eigenen Deps-Typ). `IntegrationDeps` behält nur Gemeinsames (Ports, Gerät, HTTP-Client, Fehlermeldung). Eine neue Integration ändert `IntegrationDeps` nicht mehr.
- Ziel für eine **neue Integration**: höchstens drei geänderte gemeinsame Stellen (Barrel-Zeile, Registry-Zeile, ggf. Route/Label-Zeile), alles andere in eigenen Dateien. Vorher sind es laut Gutachten sieben.

**c) Einstieg, Routen, Testumgebung**
- `main.dart`: Start in benannte Schritte (`bootstrap/…`: Storage öffnen, Startup-Einstellungen, Overrides bauen, Fehlerbehandlung) zerlegen. `main.dart` ≤ ca. 60 Zeilen, ohne integrationsspezifischen Code.
- `app.dart`: Lebenszyklus-Reaktionen (Neuprüfung bei Rückkehr, Overlay-Engine, Vorwärmen aus WP30) als Liste registrierter Beobachter statt Einzelaufrufen, sodass ein neues Paket einen Beobachter anlegt statt `app.dart` zu ändern.
- `routes.dart`: Routen je Bereich (z. B. `ui/settings/settings_routes.dart`, Integrationsrouten aus der Registry bzw. aus der Integrations-Spec). `routes.dart` setzt sie nur zusammen. Routennamen bleiben gleich.
- `labels.dart`: Prüfen, ob integrationsspezifische Bezeichnungen in die Spec gehören. Falls ja, umziehen, Texte byte-gleich.
- `test/support/test_env.dart`: Builder mit Overrides je Bereich (`withIntegrations(…)`, `withVoice(…)`, `withMcp(…)`), aus mehreren kleinen Dateien unter `test/support/env/`. Bestehende Aufrufe funktionieren unverändert oder werden mechanisch umgestellt.
- ADR 0004 bekommt einen Abschnitt „Registry und Barrels“ mit der Regel, wie neue Integrationen andocken. `docs/ARCHITECTURE.md`: Checkliste „neue Integration“ und „neue Einstellungsseite“ nachführen. `docs/work-packages/README.md`: Hotspot-Liste (aus WP35) um die entschärften Dateien kürzen.

## Abnahmekriterien
- [ ] Verhaltensneutral: Nutzertexte, Routennamen, Provider-Verhalten, Reihenfolge der Integrationen in der UI und im Tool-Katalog unverändert. Alle Tests grün ohne geänderte Erwartung, Goldens unverändert (`git diff --stat main...HEAD -- '*.png'` leer). `wiring_test.dart` unverändert grün.
- [ ] Barrel: `wendelin_integrations.dart` ≤ 30 Zeilen, keine `show`-Liste mehr darin. Je Integration ein Einstiegspunkt, ebenso für Fakes und Testing.
- [ ] `providers.dart` ist ein Re-Export-Barrel ohne eigene Provider-Definition. Keine Bereichsdatei > 300 Zeilen.
- [ ] Registry: eine Datei je Integration, `IntegrationDeps` ohne integrationsspezifische Felder. **Probe:** Eine Beispiel-Integration (nur im Test, z. B. `test/di/registry_probe_test.dart` mit einer Fake-Spec) lässt sich mit höchstens drei Zeilen in gemeinsamen Dateien anmelden. Der Bericht listet die Stellen.
- [ ] `main.dart` ≤ ca. 60 Zeilen, `app.dart` ohne Einzelaufrufe je Feature, `routes.dart` setzt nur Bereiche zusammen.
- [ ] Mutationsproben (je Teil ≥ 5) gegen verschobene Invarianten, z. B.: Demo-Modus liefert echte Ports, deaktivierte Integration landet in der Registry, sensible Markierung (`toolPrefsProvider.sensitive`) wird nicht angewandt, Reihenfolge der Registry vertauscht, Override in `test_env` greift nicht, Lebenszyklus-Beobachter nicht registriert. Jede Mutation macht einen Test rot.
- [ ] Emulator (`Wendelin_AOSP_35`, expliziter Serial `DEVICE=emulator-xxxx`, vorher `ro.kernel.qemu=1` prüfen): bestehender E2E-Lauf `tool/e2e_android.sh` grün (Start, Text-Anfrage, Overlay), weil `main.dart` und `app.dart` sich ändern.
- [ ] Gate grün (voll), APK baut.
- [ ] Diff je Teil ≤ ca. 1 500 Zeilen geänderter Produktivcode, reine Verschiebungen ausgewiesen.
- [ ] Messwerte vorher/nachher im Bericht: Zeilen von Barrel, `fakes.dart`, `testing.dart`, `providers.dart`, `integration_specs.dart`, `main.dart`, `app.dart`, `routes.dart`, `test_env.dart`; Zahl der Provider je Datei; Zahl gemeinsamer Stellen für eine neue Integration (vorher 7); Importe von `providers.dart`.

Prüfliste für den Maintainer (echtes Telefon), kurz: App startet, Einstellungen → Integrationen zeigt dieselben Einträge in derselben Reihenfolge, Overlay per Power-Taste kommt.
