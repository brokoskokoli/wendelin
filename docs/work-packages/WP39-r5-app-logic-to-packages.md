# WP39 – R5: App-Logik in Pakete, Abdeckung für `app/lib/di`, gemeinsamer Secret-Store (`app/lib/di`, `wendelin_integrations`, `wendelin_voice`, `wendelin_mcp`, `wendelin_storage`, `tool/gate.dart`)

Abhängig von: **WP38** (Verdrahtung entflochten; damit auch nach WP27, WP30, WP32, WP31 und WP33). Übersicht und Grundregeln: `R-refactoring.md` (verhaltensneutral). Bezug: Gutachten **H3** (Logik in `app/lib/di`, keine App-Abdeckung im Gate), **M8** (`BringSecrets`, `HttpToolSecrets`, `McpSecrets` je mit eigenem App-Adapter). ADRs: 0011 (HTTP-Tools), 0012 (nutzerdefinierte Integrationen), 0010 (MCP-Client).

Andockpunkte (Stand nach WP38, Namen können sich durch WP38 verschoben haben):
- `app/lib/di/http_tool_draft.dart` (`HttpToolDraft`, Validierung, Import/Export), `app/lib/di/http_tools.dart` (`HttpToolRepository`, `HttpToolSource`, `SecretStoreHttpToolSecrets`, `PendingHttpToolSecrets`).
- `app/lib/di/user_integrations.dart` (`UserIntegrationSource`, `IntegrationRemoval`, `UserIntegrationSync`).
- `app/lib/di/mcp/` aus WP27 (`mcp_source.dart` mit `McpDraft`, `McpServerSource`, `McpServerView`; `mcp_persistence.dart`, `mcp_secrets.dart`, `mcp_templates.dart`).
- `app/lib/di/voice_providers.dart` (`VoiceSettings`, `ModelState`, `ModelStatesNotifier` mit der Download-Zustandsmaschine, Fehlertexte).
- `app/lib/di/bring.dart` (`SecretStoreBringSecrets`), `app/lib/di/preference_models.dart` (prüfen, ob reine Wertobjekte in Pakete gehören).
- `tool/gate.dart` (App-Schritte).

## Schnitt in Teil-Merges

| Teil | Inhalt |
| --- | --- |
| a | HTTP-Tools: `HttpToolDraft`, `HttpToolRepository`, `HttpToolSource` in `wendelin_integrations/src/http_tools/` |
| b | Nutzerdefinierte Integrationen und MCP-Quelle: `UserIntegrationSync`, `IntegrationRemoval`, `UserIntegrationSource`; `McpDraft`, `McpServerSource`-Logik, Persistenz, Vorlagen nach `wendelin_mcp` |
| c | Voice: `VoiceSettings` und Download-Zustandsmaschine nach `wendelin_voice` |
| d | Gemeinsamer präfixierter Secret-Store, Abdeckungsschwelle für `app/lib/di` im Gate |

## Inhalt

**Grundsatz:** `app/lib/di` enthält danach nur noch Verdrahtung: `Provider(...)`-Definitionen, dünne Riverpod-Notifier, die an Paket-Logik delegieren, und Adapter auf Flutter-Plugins. Logik ohne Flutter-Bezug liegt in einem reinen Dart-Paket und fällt dort unter die 85-%-Regel. Die **Abhängigkeitsregeln bleiben unverändert**. Braucht ein Umzug eine neue Kante (z. B. `wendelin_integrations -> wendelin_tools`) oder ein neues Paket, entscheidet das eine ADR vor dem Umzug, und der Teil wird bis dahin zurückgestellt.

**a) HTTP-Tools**
- `HttpToolDraft` (Formularmodell, Validierung, Import/Export) und `HttpToolRepository` ziehen nach `packages/wendelin_integrations/lib/src/http_tools/`. Persistenz läuft über eine kleine Schnittstelle (z. B. `HttpToolStore`), die die App mit den Einstellungen umsetzt.
- `HttpToolSource` (Umsetzung von `UserIntegrationSource`) folgt mit Teil b, falls `UserIntegrationSource` dafür ins Paket muss, sonst bleibt nur die Verdrahtung in der App.
- Der HTTP-Tool-Editor (`app/lib/ui/settings/http_tool_editor_screen.dart`) nutzt das Draft-Modell aus dem Paket. Sein UI-Umbau gehört zu WP40.

**b) Nutzerdefinierte Integrationen und MCP**
- `UserIntegrationSource`, `IntegrationRemoval` und `UserIntegrationSync` (Lebenszyklus, Abgleich mit Registry und Einstellungen) ziehen in ein Paket, das nach den bestehenden Regeln passt (Vorschlag `wendelin_integrations/src/user/`, sofern es nur `wendelin_core`-Typen braucht; sonst ADR, siehe Grundsatz).
- Die MCP-Quelle aus WP27 wird geteilt: Logik (`McpDraft`, Konfigurationsabgleich, Tool-Cache, Löschen samt Secrets, Vorlagen, Persistenzformat) nach `packages/wendelin_mcp/lib/src/app/` o. ä., Verdrahtung und Browser-Anbindung bleiben in `app/lib/di/mcp/`. Die Nachträge aus dem WP25-Review (Neuprüfung ohne Netz, eine Quelle der Wahrheit für den Schalter, Secrets beim Löschen) bleiben erhalten und bekommen Tests im Paket.

**c) Voice**
- `VoiceSettings` (Modell, JSON) und der logische Teil von `ModelStatesNotifier` (Zustände je Modell, Übergänge Download → Prüfen → installiert/Fehler, Abbruch, Fehlertexte) ziehen nach `packages/wendelin_voice/lib/src/models/` als reine Zustandsmaschine ohne Riverpod (z. B. `ModelInstallStates` mit `Stream`/Callback). Der Riverpod-Notifier in der App delegiert nur noch.
- Standardwerte (`whisper-small` aus WP33, Bestandsregel für base) und Speicher-Freigabe (WP30) bleiben exakt erhalten.

**d) Secret-Store und Abdeckung**
- `ScopedSecretStore` in `wendelin_storage` (gleiches Paket wie `SecretStore`): `ScopedSecretStore(SecretStore inner, String prefix)` mit `read`, `write`, `delete`, `deleteAll()` (alle Schlüssel des Präfixes, über einen Schlüsselindex, falls `SecretStore` kein Auflisten kann). Contract-Suite in `lib/testing/`.
- `SecretStoreBringSecrets`, `SecretStoreHttpToolSecrets` und die MCP-Umsetzung von `McpSecrets` werden dünne Adapter darauf. `BringSecrets`, `HttpToolSecrets`, `McpSecrets` in den Paketen bleiben unverändert.
- **Wichtigste Invariante: Die gespeicherten Schlüsselnamen bleiben byte-gleich.** Vorhandene Secrets auf Geräten werden ohne Migration gefunden. Test: Kanarienwerte unter den alten Schlüsseln anlegen (Liste der Schlüssel aus dem alten Code, vor dem Umbau als Test festgeschrieben) und über die neuen Adapter lesen und löschen.
- Gate: `flutter test --coverage` für die App, Auswertung nur für `app/lib/di/` (und `app/lib/agent/`, falls die Messung dort sinnvoll ist). **Schwelle:** gemessener Wert nach dem Umzug abgerundet auf volle 5 %, mindestens 70 %. Die Schwelle steht in `tool/gate.dart` als Konstante mit Kommentar und in `ENGINEERING.md`. Die Gate-Zusammenfassung (WP35) zeigt den Wert.

## Abnahmekriterien
- [ ] Verhaltensneutral: Einstellungs-JSON, Export/Import-Format, Secret-Schlüssel, Nutzertexte, Fehlermeldungen und Download-Verhalten unverändert. Bestehende Tests ziehen mit unveränderter Erwartung um (in Paket- oder App-Tests). Goldens unverändert.
- [ ] `app/lib/di` enthält keine Klasse mit Logik über ca. 50 Zeilen mehr außer begründeten Adaptern (Liste im Bericht). `http_tool_draft.dart`, `http_tools.dart`, `user_integrations.dart` sind entfallen oder reine Verdrahtung. `voice_providers.dart` ≤ ca. 300 Zeilen. `mcp_source.dart` ≤ ca. 250 Zeilen.
- [ ] Abhängigkeitsregeln unverändert (`tool/check_deps.dart` ohne Diff), oder eine ADR für die nötige Kante liegt vor und ist vom Maintainer bestätigt.
- [ ] Abdeckung der Zielpakete ≥ 85 % und nicht niedriger als vorher. Neue App-Abdeckungsschwelle für `app/lib/di` im Gate aktiv, Wert vorher (falls messbar) und nachher im Bericht.
- [ ] `ScopedSecretStore` mit Contract-Suite. Kanarien-Test: Secrets unter den alten Schlüsseln werden gelesen und beim Entfernen einer Integration vollständig gelöscht. Keine Secrets in Einstellungen, Export, Audit- oder Debug-Log (bestehende Kanarienwert-Tests grün).
- [ ] Mutationsproben (je Teil ≥ 5) gegen verschobene Invarianten, z. B.: Draft-Validierung lässt leere URL zu, Import übernimmt Secrets, Löschen eines MCP-Servers lässt Secrets stehen, Neuprüfung nutzt Netz, Download-Fehler wird als installiert gemeldet, Präfix weicht um ein Zeichen ab, Standardmodell nicht `whisper-small`. Jede Mutation macht einen Test rot.
- [ ] Emulator (`Wendelin_AOSP_35`, expliziter Serial, vorher `ro.kernel.qemu=1` prüfen): E2E-Lauf grün, dazu ein HTTP-Tool anlegen und ausführen und einen MCP-Server gegen den Test-Server auf `10.0.2.2` einrichten (vorhandene Schritte aus WP29, falls gemergt).
- [ ] Gate grün (voll), APK baut.
- [ ] Diff je Teil ≤ ca. 1 500 Zeilen geänderter Produktivcode, reine Verschiebungen ausgewiesen.
- [ ] Messwerte vorher/nachher im Bericht: Zeilen in `app/lib/di` gesamt und je Datei, Zahl der Klassen mit Logik in `di/`, Abdeckung `app/lib/di` (nachher, vorher falls messbar), Abdeckung und Testanzahl der Zielpakete, Laufzeit der App-Tests.
- [ ] `docs/ARCHITECTURE.md` und ADR 0012 nennen die neuen Ablageorte. `ENGINEERING.md` beschreibt die Regel „`di/` nur Verdrahtung“ und die App-Abdeckungsschwelle.

Prüfliste für den Maintainer (echtes Telefon), kurz: Nach dem Update sind Bring!-Login, HTTP-Tool-Secrets und MCP-Token weiter vorhanden (keine erneute Eingabe nötig), installierte Sprachmodelle werden erkannt.
