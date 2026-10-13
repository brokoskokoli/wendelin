# WP26 – Regel-Editor, Eskalationsketten und Routing-Verdrahtung (`app/`)

Abhängig von: WP21 (Regel-Engine), WP25 (Einstellungszeile und Route „Routing“). Andockpunkte: `ProviderConfig`/`isPrivate` (`app/lib/di/provider_config.dart`), `profiles.dart` (heute globale `AppSettings.escalationChain`), `AgentFactory`, `RuleTile` (`app/lib/ui/design/rule_tile.dart`), `PrivacyChip`, `EscalationDivider`. Konzept-Bezug: „Routing und Eskalation → Regel-Editor“, „Einstellungen → Routing“, Design `screens/routing.html`/PNG und `DESIGN.md` Zeile „Routing“.

## Inhalt
- **Verdrahtung**: `RuleBasedProviderResolver` ersetzt `DefaultProviderResolver`; Regeln als JSON in den Einstellungen (`SettingKey.json`, keine DB-Migration), Migration der globalen Kette beim ersten Start (Funktion aus WP21). Das bisherige `isPrivate` (Schlüsselwort „privat“) wird zur vorbelegten Regel „Privat“ (nur angelegt, wenn ein Profil ab `tee` existiert, sonst deaktiviert mit Hinweis).
- **Netzstatus** für die Bedingung `network`: kleiner Kotlin-Kanal über `ConnectivityManager` (kein GMS) als `NetworkState`-Quelle; Fake für Tests.
- **Routing-Seite** laut Design: Testfeld mit Ergebnis-Chip („Regel 1 greift → Claude API · Opus“, über `explain` aus WP21), `ReorderableListView` mit `RuleTile` (Ziehgriff, Name, Bedingung in Mono, Ziel mit Datenschutz-Symbol), passende Regel mit Kobalt-Rahmen, Default-Regel gestrichelt und fest am Ende, Eskalationskette, Filled-Button „+ Regel“.
- **Regel bearbeiten**: Name, aktiv, Ziel (Profil + Modell), `stripTrigger`, Bedingungen per Baukasten (Typ wählen, Werte eingeben, `und`/`oder`/`nicht` verschachteln; Tiefe in der UI auf 2 begrenzt, tiefere Bäume aus Import werden angezeigt und bleiben erhalten). Warnungen aus `RuleSetIssue` sichtbar (z. B. „privat“-Regel mit Standard-Ziel, gelöschtes Profil, ungültige Regex).
- **Eskalationsketten pro Profil**: Profil wählen, Kette sortieren, Datenschutzstufe je Glied sichtbar; Hinweis, wenn ein Glied unter der Stufe des Profils liegt (Rückfrage zur Laufzeit).
- **Import/Export** der Regeln als JSON (Teilen-Dialog bzw. Datei, wie bestehender Export); Import zeigt eine Vorschau und ersetzt erst nach Bestätigung.
- **Gespräch**: `Routed` zeigt die Regel im ProviderChip bzw. als Meta-Zeile; „an … übergeben“ wie bisher.

## Abnahmekriterien
- [ ] Golden der Routing-Seite gegen `docs/design/screens/routing@1x.png` (Testfeld, Kobalt-Rahmen, gestrichelte Default-Regel, Kette, „+ Regel“).
- [ ] Widget-Tests: Regel anlegen/bearbeiten/löschen, Drag-and-drop ändert Reihenfolge und Ergebnis des Testfelds, Default nicht verschiebbar, Warnungen angezeigt, Import-Vorschau mit Abbrechen.
- [ ] Integrationstest mit Fake-Providern: „Claude, wie spät ist es?“ läuft über das Claude-Profil (`Routed.reason` = Regelname, Präfix beim Modell entfernt, im Verlauf erhalten); Satz ohne Präfix → Default; „privat“-Regel setzt die Datenschutz-Untergrenze (Eskalation darunter fragt nach).
- [ ] Migration: bestehende globale Kette und „privat“-Verhalten nach Update unverändert (Test mit gespeicherten M2-Einstellungen).
- [ ] Netzstatus-Kanal mit Mock-Kanal getestet; Regel „offline“ greift im Widget-Test bei Fake-Netz „offline“.
- [ ] Audit-Log enthält die Routing-Entscheidung mit Regelname, ohne Secrets.
- [ ] Touch-Ziele ≥ 44, Semantics-Labels für Ziehgriff und Regeln.
- [ ] Gate grün, APK baut.
