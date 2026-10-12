# WP08 – App-Verdrahtung, Hauptbildschirm, Bestätigung (`app/`)

Abhängig von: allen Paketen, WP07. Konzept-Bezug: „Oberflächen → Hauptbildschirm“, „Agent-Schleife“, „Risikostufen und Bestätigung“, „Sicherheit“.

## Inhalt
- Riverpod-Verdrahtung `app/lib/di/`: Database (drift_flutter), Repositories, `SecretStore` (flutter_secure_storage-Implementierung `SecureSecretStore`, besteht Contract-Suite aus storage im Widget-/Integrationstest mit Mock-Plattform), ToolRegistry mit Integrationen, ProviderFactory, ProviderResolver, AgentRunner, Audit-Sink-Adapter (Agent- und Tool-Events → `AuditLogRepository`), Usage/Cost, BudgetGuard.
- Plattform-Ports `app/lib/platform/`: `DeviceCalendarPort` (Paket `device_calendar` oder gleichwertig; Berechtigung erst beim Aktivieren), `FlutterClipboardPort`, `AndroidAlarmPort` (`android_intent_plus`, `AlarmClock.ACTION_SET_ALARM`/`ACTION_SET_TIMER`, `SKIP_UI`), `RepositoryMemoryPort`. Jeder Port besteht die Contract-Suite (soweit ohne Gerät möglich mit Mock-MethodChannel).
- Android: `minSdk` ≥ 26, Manifest-Berechtigungen (`READ/WRITE_CALENDAR`, `com.android.alarm.permission.SET_ALARM`, `INTERNET`), App-Name „Wendelin“, Launcher-Icons über `flutter_launcher_icons` laut DESIGN.md, Paket-ID `app.wendelin`.
- Hauptbildschirm laut `screens/hauptbildschirm`: Lockup + Einstellungen, Chips (Provider mit Datenschutzstufe, Kosten heute), Verlauf (`UserBubble`, `ToolChip`, `AssistantText`, `EscalationDivider`), Texteingabe + `MicButton` (Mikro in M1 deaktiviert mit Hinweis „Sprache kommt in M2“). Live-Streaming der Antwort.
- Bestätigung laut `screens/bestaetigung` als Bottom Sheet mit `ConfirmationCard`; Tool-Karte mit Rückgängig-Countdown 10 s (`UndoManager`).
- `AgentController` (Riverpod Notifier): hält Gesprächszustand aus `AgentEvent`s, reine Logik testbar ohne Widgets.
- Ohne eingerichteten Provider: Hinweis-Karte mit Button „Provider einrichten“ (Route kommt aus WP09; bis dahin Platzhalter).
- Demo-/Fake-Modus: Debug-Schalter nutzt `FakeLlmProvider` mit Skript für „Trag mir morgen um 10 Tauchen ein“ → `calendar__create_event`.

## Abnahmekriterien
- [ ] Widget-Test: Text senden → Fake-Provider → Tool-Call → Tool-Karte mit Rückgängig → Antwort erscheint; Undo ruft Port.
- [ ] Widget-Test: external-Tool → Bestätigungs-Sheet; „Nein“ → Tool nicht ausgeführt.
- [ ] `AgentController`-Unit-Tests für alle Event-Typen.
- [ ] Audit-Log enthält Anfrage, Routing, Tool-Call, Bestätigung, Usage (Test).
- [ ] `flutter build apk --debug` läuft durch.
- [ ] Golden des Hauptbildschirms mit Beispieldaten, Reviewer vergleicht mit PNG.
