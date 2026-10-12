# ADR 0004 – App-Verdrahtung (`app/`)

Status: vorgeschlagen · 2026-10-13

## Kontext
WP08 verdrahtet die reinen Dart-Pakete in der Flutter-App: Datenbank, Secrets, Plattform-Ports, Tool-Registry, Provider, Agent-Schleife, Audit-Log und Hauptbildschirm. Einige Punkte lassen Konzept und Paket-ADRs offen.

## Entscheidungen

### 1. Riverpod-Provider statt Service-Container
Jeder Baustein ist ein eigener Provider in `app/lib/di/providers.dart`. `main.dart` überschreibt nur Datenbank (`drift_flutter`), Starteinstellungen und Geräteinfo (Locale, IANA-Zone). Tests überschreiben Ports, Uhr, Secrets und `storedProviderConfigProvider`. Fehlerhafte Provider werden nicht automatisch wiederholt (`retry: null`), Fehler werden angezeigt.

### 2. Ein `AgentRunner` pro Anfrage
`AgentFactory` baut je Anfrage einen Runner für die aktuelle Sitzung. Der Tool-Katalog gilt für die **schwächste** Datenschutzstufe aller Ziele (Standardprofil und Eskalationskette): Die Agent-Schleife tauscht den Katalog bei einer Eskalation nicht, so kann ein sensibles Tool nie an ein Ziel unter der eingestellten Mindeststufe gehen. Gedächtnis-Einträge kommen nur in den System-Prompt, wenn dieser Katalog `memory__search` enthält (Integration aktiv und für die Stufe erlaubt).

### 3. `AgentController` = reiner Reducer + Seiteneffekte
`ConversationReducer` bildet Nutzernachricht, `AgentEvent`s und Undo-Updates rein funktional auf den `ConversationState` ab (ohne Widgets testbar). Text-Abschnitte folgen ADR 0002 §8: Tool-Events und `AgentTextReset` beenden einen Abschnitt, `Escalated` nicht (der Reset nach einer Eskalation verwirft die ersetzte Antwort, ADR 0003 §4). Der Notifier ergänzt Sitzung, Audit, Kostenbuchung, Undo-Registrierung und Antworten auf Bestätigungen. Ein weggewischtes Bestätigungs-Sheet gilt als „Nein“.

### 4. Eigener Kalender-Kanal statt `device_calendar`
`DeviceCalendarPort` spricht über den Kanal `app.wendelin/calendar` mit `CalendarChannel.kt` (direkt `CalendarContract`, Berechtigungsanfrage über die Activity). `device_calendar` (letzte Version 2024-09) ist für AGP 9/Kotlin 2.4 ein Risiko und bringt eigene Zeitzonen-Typen mit. Der Kanal macht nur einfache Abfragen; Überlappungsfilter (halboffen), Standardkalender und deutsche Fehlermeldungen liegen in Dart und sind mit einer Kanal-Attrappe gegen `calendarPortContract` getestet.

### 5. Erweiterungspunkt für Integrationen
`IntegrationSpec` (Bau, Berechtigungsanfrage beim Einschalten, Aufräumen bei Sitzungsende) und `PlatformPorts` (Geräte-Ports, echt oder Demo). Eine neue Integration (z. B. WP12 Listen) ergänzt einen Port in `PlatformPorts` und eine Spec in `builtInIntegrationSpecs`; Registry, Einstellungen, Sitzungsende und Demo-Modus übernehmen sie von dort.

### 6. Berechtigungen erst beim Einschalten
`IntegrationActivator.setEnabled` fragt die Berechtigung der Integration an, schaltet sie in der Registry und speichert den Schalter. Beim Start wird nichts angefragt; eine abgelehnte Berechtigung zeigt „Einrichtung nötig“, `setUp` fragt erneut.

### 7. Demo-Modus nur im Debug-Build
`DemoLlmProvider` spielt je Antwort einen `FakeLlmProvider`-Zug („Trag mir morgen um 10 Tauchen ein“ → `calendar__create_event`, „Lösch den Termin“ → `calendar__delete_event`). Ports sind dann In-Memory-Fakes, alle Integrationen aktiv; das Gerät wird nicht berührt. In Release-Builds ist der Schalter wirkungslos.

### 8. Kosten in USD
Preise und Budgets sind Mikro-USD (ADR 0002). Der Kosten-Chip zeigt „heute 0,03 $“ statt „€“ wie im Entwurf, weil es keine Umrechnung gibt.

## Folgen
- WP09 schreibt Profile, Eskalationskette (`AppSettings.escalationChain`), Kalenderwahl und Schalter und invalidiert danach `storedProviderConfigProvider`. Die Platzhalter-Einstellungen (`SettingsPlaceholderScreen`) werden ersetzt.
- Der native Kalender-Code ist nur über die Kanal-Attrappe getestet; der Gerätetest folgt in WP11 (AOSP-Emulator).
