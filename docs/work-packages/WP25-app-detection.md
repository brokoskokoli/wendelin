# WP25 – App-Erkennung und Erweiterungspunkt für nutzerdefinierte Integrationen (`app/` + Kotlin)

Abhängig von: bestehendem Code (WP08/WP09/WP18). Keine Abhängigkeit zu anderen M3-Paketen, deshalb in Welle A. Andockpunkte: `IntegrationSpec`/`builtInIntegrationSpecs` (`app/lib/di/integration_specs.dart`), `PlatformPorts` (`app/lib/platform/platform_ports.dart`), `IntegrationActivator`, `ToolRegistry.refresh/registerIntegration/unregister`, `Availability.storeUrl`, `IntegrationTile` (Zustand „nicht installiert“), `<queries>` in `app/android/app/src/main/AndroidManifest.xml`, `AppLifecycleListener` (Muster aus `main_screen.dart`). Konzept-Bezug: „Tool-System → App-Erkennung“, „Zustand einer Integration“, „Integrationen auswählen“, „Onboarding“, K7, ADR 0004 §5.

## Inhalt
- **Port** `AppPresencePort { Future<bool> isInstalled(String androidPackage); }` in `wendelin_integrations` (neue Datei unter `src/common/`, Fake + Contract-Suite) – die einzige Änderung an einem reinen Paket; Android-Umsetzung über einen eigenen Kanal (`PackageManager.getPackageInfo`, Kotlin, minimal).
- **Manifest**: `<queries><package …/>` für die bekannten Pakete (Bring! `ch.publisheria.bring`, Obsidian `md.obsidian`, Spotify `com.spotify.music` für später), kein `QUERY_ALL_PACKAGES`.
- **Zuordnung** `IntegrationSpec.requiredApp` (Paketname, Store-Link: F-Droid bzw. Herstellerseite statt Play-Store-Pflicht, K7). Integrationen, die eine App **brauchen**, werden ohne sie „nicht verfügbar“ (ausgegraut, Link); solche, für die die App nur optional ist (Bring!-Fallback, Obsidian-Links), zeigen nur einen Hinweis.
- **Neuprüfung** beim Start und bei Rückkehr in die App (`AppLifecycleListener` → `ToolRegistry.refresh()`); fällt eine App weg, wird die Integration pausiert (Zustand, nicht Schalter löschen).
- **Erweiterungspunkt für nutzerdefinierte Integrationen** (ADR 0012): `UserIntegrationSource` in `app/lib/di/` – eine Quelle liefert eine dynamische Menge von `Integration`-Objekten (MCP-Server, HTTP-Tools), meldet Änderungen, und ein gemeinsamer Abgleich registriert/entfernt sie in der `ToolRegistry`, stellt den gespeicherten Schalterzustand wieder her und räumt beim Löschen Secrets über eine Callback-Liste auf. WP27 (MCP) und WP28 (HTTP-Tools) hängen sich nur noch mit je einer Quelle an.
- **Gemeinsame UI-Stellen vorab anlegen**, damit Welle B nicht in denselben Dateien arbeitet: Einstellungsübersicht mit Zeilen „Routing“, „MCP-Server“, „HTTP-Tools“ (Routen auf Platzhalterseiten „kommt in M3“), Integrationen-Seite mit den Knöpfen „+ MCP-Server“ und „+ HTTP-Tool“ laut Design `integrationen`, Abschnitt für nutzerdefinierte Integrationen in der Liste (Kennzeichnung „MCP“/„HTTP“).
- **Onboarding**: Schritt „Integrationen auswählen“ zeigt nur Integrationen der Plattform, fehlende Apps ausgegraut mit „App nicht installiert“ (Konzept „Integrationen auswählen“).
- Keine Google-Dienste: keine Play-Store-Abfrage, keine Play-Core-/GMS-Bibliothek.

## Abnahmekriterien
- [ ] `AppPresencePort`: Fake + Contract-Suite in `wendelin_integrations`; Kanal-Umsetzung besteht die Suite mit Mock-Kanal.
- [ ] Widget-Tests: Integration mit fehlender Pflicht-App ausgegraut mit Link; App kommt hinzu → nach Lifecycle-„resumed“ verfügbar; App fällt weg → pausiert, Schalter bleibt gespeichert.
- [ ] `UserIntegrationSource` mit Fake-Quelle getestet: hinzufügen, ändern (Tools neu), entfernen (Registry leer, Secrets-Aufräumen aufgerufen), Neustart stellt Schalter wieder her, Tool-Namenskollision wird abgewiesen statt zu überschreiben.
- [ ] Golden der Integrationen-Seite gegen `docs/design/screens/integrationen@1x.png` (inkl. „+ MCP-Server“, „+ HTTP-Tool“, Zustand „App nicht installiert“).
- [ ] Emulator (`Wendelin_AOSP_35`, nur explizites Serial `emulator-xxxx`, siehe M3.md): Prüfung per adb, dass `<queries>` greift (z. B. Test-APK mit Paketnamen installieren/deinstallieren oder `pm list packages` gegen Kanalergebnis).
- [ ] `tool/check_apk.sh` weiter grün (keine GMS-/Firebase-Klassen); Gate grün, APK baut.
- [ ] ADR 0012.
