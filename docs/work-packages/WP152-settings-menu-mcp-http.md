# WP152 – Hauptmenü: MCP-Server und HTTP-Tools nur unter Integrationen

**Zuordnung:** Wunsch des Maintainers vom 2026-10-26 (reine UI-Änderung).

## Ist-Stand
- `app/lib/ui/settings/settings_screen.dart:24-25` zeigt „MCP-Server“ und „HTTP-Tools“ als eigene Zeilen im Einstellungs-Hauptmenü. Beide sind auch unter „Integrationen“ verlinkt (`integration_routes.dart`, `integrations_screen.dart`). Der Kommentar Z. 13–14 („Platzhalter bis WP26–WP28“) ist veraltet.

## Inhalt
- Beide Zeilen aus `SettingsScreen.areas` entfernen. Die Routen bleiben (Aufruf aus „Integrationen“, Deep-Links, Tests).
- Prüfen, dass jeder Weg aus dem Hauptmenü (Suche, Goldens, Widget-Tests, Onboarding-Verweise) weiter funktioniert; nicht mehr genutzte Texte (`areaMcpDetail`, `areaHttpToolsDetail`) entfernen, falls sie sonst niemand nutzt (alle Sprachen).
- Kommentar aktualisieren.

## Abnahmekriterien
- [ ] Hauptmenü ohne die beiden Zeilen (Widget-Test, Golden auf macOS aktualisiert).
- [ ] „Integrationen“ öffnet MCP-Server und HTTP-Tools wie bisher (Test).
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Klein; berührt nur Einstellungen. Kann neben WP147/WP148 laufen (WP148 ändert die App-Sprache-Seite, nicht das Hauptmenü).
