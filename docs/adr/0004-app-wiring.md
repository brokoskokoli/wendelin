# ADR 0004 – App-Verdrahtung (`app/`)

Status: angenommen (umgesetzt, nachgezogen 2026-10-25; mit Vermerk) · 2026-10-13

**Vermerk 2026-10-28:** `AppSettings.escalationChain` (Folgen, WP09) ist entfallen (K28, ADR 0009: Eskalationsketten gibt es nicht mehr).

## Kontext
WP08 verdrahtet die reinen Dart-Pakete in der Flutter-App: Datenbank, Secrets, Plattform-Ports, Tool-Registry, Provider, Agent-Schleife, Audit-Log und Hauptbildschirm. Einige Punkte lassen Konzept und Paket-ADRs offen.

## Entscheidungen

### 1. Riverpod-Provider statt Service-Container
Jeder Baustein ist ein eigener Provider in `app/lib/di/providers.dart`. `main.dart` überschreibt nur Datenbank (`drift_flutter`), Starteinstellungen und Geräteinfo (Locale, IANA-Zone). Tests überschreiben Ports, Uhr, Secrets und `storedProviderConfigProvider`. Fehlerhafte Provider werden nicht automatisch wiederholt (`retry: null`), Fehler werden angezeigt.

### 2. Ein `AgentRunner` pro Anfrage
`AgentFactory` baut je Anfrage einen Runner für die aktuelle Sitzung. Jeder Modellaufruf bekommt den Tool-Katalog der Datenschutzstufe des **aktuellen** Ziels (`AgentRunner.catalogFor` → `ToolRegistry.catalogFor`), auch nach einer Eskalation (WP14). TEE- oder lokale Ziele können sensible Tools nutzen, Standard-Ziele sehen sie nicht. Ihre Calls darauf lehnt die Schleife ab und protokolliert sie im Audit-Log (`denied`). Der `ToolExecutor` bekommt mit `ToolContext.privacyLevel` die Stufe des aufrufenden Ziels und sucht nur in deren Katalog, auch `tools__search`; ohne Stufe gilt die schwächste Stufe der Kette. Argumente, Ergebnisse und die daraus entstandenen Antworten sensibler Tools sind für Ziele ohne diese Tools ausgeblendet, im laufenden Lauf wie im Verlauf. Das gilt bis zur nächsten Nutzernachricht auch für Calls sichtbarer Tools, deren Argumente das Ergebnis zitieren könnten. Enthält der laufende Lauf solche Ergebnisse, fragt die App vor jeder Eskalation zu einem Ziel ohne diese Tools nach, auch ohne private Route; „Nein“ beendet die Anfrage. Geschützte Abschnitte früherer Läufe sind ausgeblendet und lösen keine Rückfrage aus. Restrisiko: Was der Nutzer selbst in seine Nachricht kopiert, geht an das Ziel, wie jeder Nutzertext. Gedächtnis-Einträge stehen im System-Prompt, und den bekommt jedes Ziel der Kette. Sie kommen deshalb nur hinein, wenn der Katalog der **schwächsten** Stufe `memory__search` enthält.

### 3. `AgentController` = reiner Reducer + Seiteneffekte
`ConversationReducer` bildet Nutzernachricht, `AgentEvent`s und Undo-Updates rein funktional auf den `ConversationState` ab (ohne Widgets testbar). Text-Abschnitte folgen ADR 0002 §8: Tool-Events und `AgentTextReset` beenden einen Abschnitt, `Escalated` nicht (der Reset nach einer Eskalation verwirft die ersetzte Antwort, ADR 0003 §4). Der Notifier ergänzt Sitzung, Audit, Kostenbuchung, Undo-Registrierung und Antworten auf Bestätigungen. Ein weggewischtes Bestätigungs-Sheet gilt als „Nein“. „Rückgängig“ ändert das Gerät nach dem Aufruf und steht deshalb als eigener `toolCall`-Eintrag (`undo: true`, Status) im Audit-Log (WP11).

### 4. Eigener Kalender-Kanal statt `device_calendar`
`DeviceCalendarPort` spricht über den Kanal `app.wendelin/calendar` mit `CalendarChannel.kt` (direkt `CalendarContract`, Berechtigungsanfrage über die Activity). `device_calendar` (letzte Version 2024-09) ist für AGP 9/Kotlin 2.4 ein Risiko und bringt eigene Zeitzonen-Typen mit. Der Kanal macht nur einfache Abfragen; Überlappungsfilter (halboffen), Standardkalender und deutsche Fehlermeldungen liegen in Dart und sind mit einer Kanal-Attrappe gegen `calendarPortContract` getestet.

### 5. Erweiterungspunkt für Integrationen
`IntegrationSpec` (Bau, Berechtigungsanfrage beim Einschalten, Aufräumen bei Sitzungsende) und `PlatformPorts` (Geräte-Ports, echt oder Demo). Eine neue Integration ergänzt einen Port in `PlatformPorts` und eine Spec in `builtInIntegrationSpecs`; Registry, Einstellungen, Sitzungsende und Demo-Modus übernehmen sie von dort. `IntegrationSpec.isSupported` blendet Integrationen ohne Port aus. Listen (WP12) sind so eingehängt: im Demo-Modus mit `FakeListFilePort` und den Listen „Einkaufen“ und „SmartSSH“, auf dem Gerät erst mit dem SAF-Port und den Listen-Einstellungen aus WP09.

### 6. Berechtigungen erst beim Einschalten
`IntegrationActivator.setEnabled` fragt die Berechtigung der Integration an, schaltet sie in der Registry und speichert den Schalter. Beim Start wird nichts angefragt; eine abgelehnte Berechtigung zeigt „Einrichtung nötig“, `setUp` fragt erneut.

### 7. Demo-Modus nur im Debug-Build
`DemoLlmProvider` spielt je Antwort einen `FakeLlmProvider`-Zug („Trag mir morgen um 10 Tauchen ein“ → `calendar__create_event`, „Lösch den Termin“ → `calendar__delete_event`). Ports sind dann In-Memory-Fakes, alle Integrationen aktiv; das Gerät wird nicht berührt. In Release-Builds ist der Schalter wirkungslos.

### 8. Kein Android-Backup
`allowBackup="false"`, `dataExtractionRules` (Cloud-Backup und Geräteumzug schließen alle Bereiche aus) und `fullBackupContent` für Android 6–11. Die Datenbank enthält Verläufe, Audit-Log und Gedächtnis und darf das Gerät nicht verlassen (Konzept „Sicherheit“). Die Secrets sind an den Keystore gebunden und wären nach einer Wiederherstellung ohnehin unlesbar; `flutter_secure_storage` würde sie dann verwerfen. Geprüft in `app/test/app/android_manifest_test.dart`.

### 9. Registrierung abwarten
Integrationen werden synchron registriert, ihre Verfügbarkeits- und Einrichtungsprüfung läuft asynchron. `toolRegistryReadyProvider` wartet auf `registry.refresh()`; jede Anfrage wartet darauf, bevor `AgentFactory.create` den Katalog baut. Sonst sähe die erste Anfrage nach dem Start noch keine aktiven Tools.

### 10. Risikostufe im Bestätigungs-Sheet
`ConfirmationRequired` trägt keine Risikostufe. Bis das Folgepaket sie in core ergänzt, leitet das Sheet sie aus der `RiskPolicy` ab: Jeder Aufruf, für den die Policy eine Bestätigung verlangt, wird als `external` angezeigt (auch ein vom Nutzer verschärftes `write`-Tool).

### 11. Kosten in USD
Preise und Budgets sind Mikro-USD (ADR 0002). Der Kosten-Chip zeigt „heute 0,03 $“ statt „€“ wie im Entwurf, weil es keine Umrechnung gibt.

### 12. Registry und Barrels (WP38)
Neue eingebaute Integrationen ändern höchstens drei gemeinsame Stellen: eine Exportzeile in `packages/wendelin_integrations/lib/wendelin_integrations.dart` (Einstiegspunkt `lib/<name>.dart` mit den `show`-Listen), eine Zeile in `app/lib/di/integrations/registry.dart` und bei eigener Einstellungsseite eine Zeile in `app/lib/ui/settings/integration_routes.dart` (plus `AppRoutes`-Name). Alles andere liegt in eigenen Dateien: `app/lib/di/integrations/<name>_spec.dart` definiert den `IntegrationSpec`. Was nur diese Integration braucht (Provider, z. B. Suchdienst, Bring!-Konto), liest die Spec in `IntegrationSpec.prepare(ref)`; es läuft in `integrationDepsProvider` (Änderungen bauen die Integrationen neu) und kommt über `IntegrationDeps.extra<T>(id)` in `create`/`isSupported`. `IntegrationDeps` enthält nur Gemeinsames (Ports, Gerät, HTTP-Client, Fehlerzustand). `providers.dart` ist ein reines Re-Export-Barrel über `core_providers.dart`, `integration_providers.dart` und `agent_providers.dart`; neue Provider kommen in die Bereichsdatei oder eine Feature-Datei. Der Start liegt in `bootstrap/`, die Route-Tabelle setzt `ui/routes.dart` aus `general_routes.dart` und `integration_routes.dart` zusammen.

## Folgen
- WP09 schreibt Profile, Eskalationskette (`AppSettings.escalationChain`), Kalenderwahl und Schalter und invalidiert danach `storedProviderConfigProvider`. Die Platzhalter-Einstellungen (`SettingsPlaceholderScreen`) werden ersetzt.
- Der native Kalender-Code ist zusätzlich auf einem AOSP-Emulator ohne Google Play getestet (WP11, `app/integration_test/calendar_e2e_test.dart`).
