# ADR 0012 – Nutzerdefinierte Integrationen und App-Erkennung in der App

Status: angenommen (umgesetzt, nachgezogen 2026-10-25) · 2026-10-13

## Kontext
Bis M2 sind alle Integrationen eingebaut: `IntegrationSpec` in `builtInIntegrationSpecs` (ADR 0004 §5), eine feste Menge, die beim Start registriert wird. M3 bringt zwei Wege, die der Nutzer selbst anlegt (Konzept „Erweiterungswege“): MCP-Server (WP27) und HTTP-Tools (WP28). Ihre Anzahl und ihre Tools ändern sich zur Laufzeit, sie haben Secrets, und sie können mit eingebauten Tools kollidieren. Damit WP27 und WP28 parallel arbeiten können, legt WP25 den gemeinsamen Erweiterungspunkt fest.

Außerdem verlangt das Konzept („App-Erkennung“, „Integrationen auswählen“) die Prüfung, ob die App einer Integration installiert ist, beim Start und bei jeder Rückkehr in die App.

## Entscheidungen

### 1. `UserIntegrationSource` statt weiterer Specs
Eine Quelle (`UserIntegrationSource` in `packages/wendelin_integrations/lib/src/user/`, seit WP39; die App liefert nur die Adapter `ToolRegistryUserIntegrations` und `SettingsUserIntegrationSwitches` in `app/lib/di/user_integrations.dart`) liefert mit `load()` die aktuelle Menge von `Integration`-Objekten, meldet über `changes`, dass sich etwas geändert hat, und räumt mit `deleteSecrets(IntegrationRemoval)` Secrets nach. `IntegrationRemoval` enthält die entfernte Fassung (`integration`, daraus liest die Quelle ihre Secret-Refs, z. B. `secretRef` einer MCP-Serverkonfiguration), die Namen der wirklich weggefallenen Tools (`toolNames`) und ob die ganze Integration gelöscht wurde (`whole`). Sie hat eine Art (`UserIntegrationKind.mcp`/`http`), die in der Liste als Badge „MCP“/„HTTP“ erscheint. Die Quellen stehen in `userIntegrationSourcesProvider`. WP27 und WP28 fügen dort je eine Quelle hinzu und berühren sonst weder Registry noch Liste.

Eine unveränderte Integration liefert die Quelle als **dasselbe Objekt** zurück. Ein neues Objekt gilt als geändert und wird neu registriert. Ein Vergleich der Tool-Specs reicht nicht, weil sich z. B. die URL eines HTTP-Tools ändern kann, ohne dass sich Name oder Schema ändern.

### 2. Ein gemeinsamer Abgleich (`UserIntegrationSync`)
Der Abgleich hängt an der `ToolRegistry` und wird mit ihr neu gebaut (`userIntegrationSyncProvider`). `toolRegistryReadyProvider` wartet auf seinen ersten Durchlauf, damit die erste Anfrage nach dem Start auch MCP- und HTTP-Tools sieht.

| Fall | Verhalten |
| --- | --- |
| neu | registrieren, Schalter aus `AppSettings.integrationEnabled(id)` (Neustart stellt ihn wieder her), Tool-Schalter und „sensibel“-Markierung des Nutzers anwenden |
| geändert | alte Fassung abmelden, neue mit dem aktuellen Schalter registrieren. Für weggefallene Tools (z. B. ein einzelnes HTTP-Tool gelöscht): `deleteSecrets` und Aufräum-Callbacks mit `whole: false` und genau diesen Tool-Namen |
| entfernt | abmelden, dann `source.deleteSecrets(removal)`, dann die Aufräum-Callbacks (`userIntegrationCleanupsProvider`: Tool-Schalter und Bestätigungen der Tools aus `toolNames`, Markierung, Schalterzustand), zuletzt den gespeicherten Schalter löschen. Ein fehlschlagender Schritt wird gemeldet, die übrigen laufen trotzdem. |
| Kollision | Id oder Tool-Name schon vergeben (auch von einer eingebauten Integration oder einer anderen Quelle), oder `tools__search`: abweisen (`rejected`, in der Liste „Abgewiesen: …“). Nichts wird überschrieben. Bei einer Änderung bleibt die alte Fassung registriert. |

Aufgeräumt wird nach den **tatsächlichen Tool-Namen** der entfernten Fassung, nicht nach einem Präfix: Die HTTP-Tools (WP23) nennen ihre Tools in beiden Integrationen `http` und `http_sensitive` `http__<name>`. Ein Abgleich nimmt zuerst alle entfernten und geänderten Fassungen einer Quelle heraus und registriert dann die neuen. So kann ein Tool zwischen Integrationen derselben Quelle umziehen (ein HTTP-Tool wird sensibel), ohne Namenskonflikt und ohne dass seine Einstellungen oder Secrets aufgeräumt werden.

Leert sich eine Integration kurz (z. B. zieht das einzige Tool von `http_sensitive` nach `http`), gilt sie als entfernt: Ihr Schalter und ihre Markierung sind weg. Kommt sie später zurück, startet sie ausgeschaltet. Das ist die sichere Voreinstellung, der Nutzer schaltet sie bewusst wieder ein.

**Ausnahme beim Speichern eines HTTP-Tools (WP28):** Speichert der Nutzer im Editor ein HTTP-Tool und ist die Ziel-Integration (`http` bzw. `http_sensitive`) noch nicht registriert, wird ihr Schalter vorher eingeschaltet. Das Speichern ist die ausdrückliche Einrichtung durch den Nutzer, ein neues Tool soll sofort nutzbar sein. Eine schon registrierte Integration behält den Schalter des Nutzers. Ein Import schaltet nichts ein (und setzt `autoRun` jeder importierten Definition auf `false`).

Gelöscht wird nur, was diese Instanz vorher registriert hatte. Ein Neustart, bei dem eine Quelle (noch) nichts liefert, löscht also keine Secrets. Die Quellen werden nacheinander abgearbeitet, sich überschneidende Änderungen können sich nicht vermischen.

### 3. App-Erkennung über einen Port
`AppPresencePort.isInstalled(androidPackage)` in `wendelin_integrations` (Fake und Contract-Suite dort), Android-Umsetzung `ChannelAppPresencePort` über den Kanal `app.wendelin/apps` (`AppsChannel.kt`, `PackageManager.getPackageInfo`). Sichtbar sind ab Android 11 nur Pakete aus `<queries>` des Manifests (Bring! `ch.publisheria.bring`, Obsidian `md.obsidian`, Spotify `com.spotify.music`), kein `QUERY_ALL_PACKAGES`. Ein Test hält `<queries>` und `KnownApps` gleich.

### 4. Pflicht-App oder optionale App
`IntegrationSpec.requiredApp` (`AppRequirement`: Paket, Name, Link). Die Links zeigen auf F-Droid oder die Herstellerseite, nicht auf den Play Store (K7).
- **Pflicht** (`needed`): `AppRequirementGuard` prüft die App vor der eigenen Verfügbarkeit der Integration. Fehlt sie, ist die Integration „nicht verfügbar“ (ausgegraut, „App nicht installiert“, „Im Store“). Schlägt die Abfrage fehl, zeigt die Registry „Prüfung fehlgeschlagen“ und pausiert die Tools.
- **Optional** (Obsidian-Links, später Bring!-Fallback): Die Integration bleibt nutzbar, die Zeile zeigt nur den Hinweis der Anforderung.

### 5. Neuprüfung beim Start und bei Rückkehr
Beim Start prüft der erste `registry.refresh()`. Bei jeder Rückkehr in die App ruft `StartGate` über einen `AppLifecycleListener` (`onResume`) erneut `registry.refresh()` auf. Fällt eine Pflicht-App weg, wird die Integration „nicht verfügbar · pausiert“. Ihr Schalter bleibt in der Registry und in den Einstellungen gespeichert. Kommt die App zurück, ist die Integration ohne Zutun wieder aktiv. Pausieren ist also ein Zustand, kein Schalter.

### 6. Gemeinsame UI-Stellen
Vorab angelegt, damit Welle B nicht in denselben Dateien arbeitet: Einstellungszeilen „Routing“, „MCP-Server“, „HTTP-Tools“ mit Routen (`AppRoutes.routing`, `.mcpServers`, `.httpTools`) auf Platzhalterseiten (`ComingSoonScreen`). WP26–WP28 ersetzen nur das Routenziel in `app.dart`. Die Integrationen-Seite hat „+ MCP-Server“ und „+ HTTP-Tool“ (öffnen diese Routen) und einen Abschnitt „Eigene Integrationen“. Die Detailseite findet nutzerdefinierte Integrationen über die Registry. Onboarding und Einstellungen zeigen nur Integrationen der eigenen Plattform (`selectableIntegrations`).

## Folgen
- WP27/WP28: eine Quelle implementieren und in `userIntegrationSourcesProvider` eintragen. Die Quelle löscht die Secrets beim Löschen durch den Nutzer **selbst und sofort**. `deleteSecrets(IntegrationRemoval)` des Abgleichs ist nur Nachsorge und muss mit schon gelöschten Secrets zurechtkommen: Der Abgleich wird mit der Registry neu gebaut (z. B. nach einer geänderten „sensibel“-Markierung) und kennt nur, was er selbst registriert hat; eine Löschung während eines Neuaufbaus sieht er nicht. Wiederverwendbare Fakes: `FakeUserIntegrationSource`, `FakeUserIntegrationRegistry` in `package:wendelin_integrations/fakes.dart`. Die HTTP-Quelle (`HttpToolSource`, `HttpToolRepository`) liegt in `packages/wendelin_integrations/lib/src/http_tools/`, die MCP-Quelle in `packages/wendelin_mcp/lib/src/app/`.
- WP27: `checkAvailability()`/`setupState()` laufen bei jeder Rückkehr in die App und müssen ohne Netz aus dem gespeicherten Zustand antworten; der Schalter hat genau eine Quelle der Wahrheit (`AppSettings.integrationEnabled`), siehe Nachtrag in WP27-mcp-app.md (nur im Git-Verlauf).
- Eine neue eingebaute Integration mit Fremd-App trägt `requiredApp` ein und ergänzt `KnownApps` und `<queries>`.
- `IntegrationDecorator` ist die gemeinsame Basis für Hüllen (`SensitivityOverride`, `AppRequirementGuard`). `unwrapIntegration` entfernt alle.
- Eine fehlende Antwort des App-Kanals gilt als Fehler (`PortException`), nicht als „nicht installiert“: sonst würden Integrationen grundlos pausiert. Der Cache vergisst bei einem Fehler das alte Ergebnis; eine optionale App bleibt dann ohne Hinweis nutzbar.
- Prüfung auf dem Emulator: `tool/e2e_app_presence.sh` installiert Attrappen-APKs (deklariertes Paket und nicht deklariertes Paket) und vergleicht `pm list packages` mit dem Kanalergebnis.
