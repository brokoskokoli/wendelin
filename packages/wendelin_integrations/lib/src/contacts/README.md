# Kontakte, SMS und Anrufe (`contacts`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `contacts__navigate` | write | Navigation zu einem Kontakt in einem Schritt: sucht Kontakt und Postanschrift selbst, startet die Navigation wie `maps__navigate` (gleiche App-Wahl); Ergebnis nur Status (`ok`, `no_contact`, `no_address`, `choice_needed`, `app_unavailable`), die Adresse sieht das Modell nie; fester Satz bei `ok`; nur entsperrt; nur angeboten, solange eine Navigations-App aktiv ist |
| `contacts__find` | read | Name suchen: Nummern und Mailadressen; optional `fields` (phone, email, address, birthday, organization, keine Notizen); mehrdeutige Treffer, Nummern oder Adressen als Auswahl |
| `sms__compose` | external | SMS mit Vorschau in der App senden |
| `phone__call` | external | Anruf mit Vorschau starten |

Die Integration ist **sensibel** (`sensitive`): Kontaktdaten gehen nur an TEE-Anbieter und Claude, andere per Freigabe (bestehende Logik). Nie bei gesperrtem Gerät (`allowedWhileLocked` ist `false`, `LockGateAgentRun` lässt das Modell gar nicht laufen).

**Vorschau und Bestätigung.** `sms__compose` und `phone__call` laufen nur nach einer Bestätigung. Die App zeigt die Vorschau (`OutgoingPreviewCard`: Name aus dem Adressbuch, Nummer, bei SMS der editierbare Text) und liest sie vor („Nachricht an X: …. Soll ich sie absenden?“, „Anruf bei X. Soll ich anrufen?“). Es führt aus: Tipp auf „Absenden“/„Anrufen“ oder eine klare gesprochene Antwort (ja, bzw. „absenden“ für die SMS, „anrufen“ für den Anruf; `YesNoRecognizer.smsYesWords`/`callYesWords`, streng: höchstens zwei Wörter). „Nein“/„abbrechen“ bricht ab; Unklares führt nichts aus und fragt einmal erneut, danach nur noch Tipp. Auch im Gesprächsmodus. Hat der Nutzer den Text nach dem Vorlesen geändert, bestätigt ein gesprochenes „ja“ nicht (nur Tipp): `SmsDraftEdits` (App) hält die Änderung, das Tool sendet den Text der Vorschau. Weder Modell noch Tool-Ergebnisse können eine Bestätigung liefern.

**Audit**: Tool, Empfängername und Ergebnis, nie der Nachrichtentext (`ToolExecutor`, Test `audit_redaction_test.dart`).

**`fields` (WP164)**: Ohne `fields` genau Telefon und Mail wie bisher. Mit `fields` enthält das Ergebnis nur die angefragten Felder (Listen auch leer, Geburtstag und Firma nur wenn gespeichert); unbekannte oder leere Werte lehnt das Tool mit der Liste der erlaubten Felder ab (fail-closed). Das Laden ist zweistufig: Der Kanalaufruf `all` liefert den Suchindex (Telefon und Mail; für angefragte Zusatzfelder nur eine Presence-Abfrage ohne Inhalt, damit auch Kontakte nur mit Adresse auffindbar sind); erst für die Treffer holt `ContactsPort.details(ids, fields)` Postadresse, Geburtstag (Event-Typ Geburtstag) und Firma. Telefon und Mail werden nur herausgegeben, wenn angefragt. `address` fragt das Modell nur, wenn der Nutzer die Adresse wissen will; „Navigiere zu X“ geht über `contacts__navigate`.

**Ports**: `ContactsPort` (`hasPermission`, `all({fields})`, `details(contacts, fields)` nur für die Treffer, max. 100 IDs), `PhonePort` (`canSendSms`, `sendSms`, `call` → `CallPlacement.direct` oder `.dialer`). Fehler als `PortException`. Fakes `FakeContactsPort`, `FakePhonePort`.

**Kotlin**: `ContactsChannel` (`ContactsContract`, `SmsManager`, `ACTION_CALL`/`ACTION_DIAL`), Zeilenaufbereitung in `ContactRows`.

**Berechtigungen** (erst beim Einschalten der Integration): `READ_CONTACTS`, `SEND_SMS`, `CALL_PHONE`. Ohne `CALL_PHONE` öffnet sich der Wählbildschirm mit der Nummer; ohne `SEND_SMS` meldet das Tool den Fehler. **Plattformen**: Android.

**`contacts__navigate` (WP164 C)**: Argumente `name` (Pflicht), `choice` (1-basierte Position in der `contacts`-Liste eines `choice_needed`, gleicher `name`; der Index „(n)“ wird nie aus dem Namen gelesen), `address_label` (z. B. Privat/Arbeit; gleiche Bezeichnungen werden nummeriert, kollisionsfrei; unbeschriftete Adressen heißen „Adresse 1“, „Adresse 2“), `app` (wie bei `maps__navigate`). Die Adresse (Zeilenumbrüche werden zu „, “) geht nur an den Launcher, nie in Ergebnis, Zusammenfassung, Fehlertext, Bestätigung, Audit (`AuditArgumentsRedactor`: nur der Kontaktname) oder den gesperrten Austausch. App-Wahl und Start teilt sich das Tool mit `maps__navigate` über `NavigationStarter` (fail-closed: gewählte App oder `app_unavailable`). `ConditionalTool.offered` blendet das Tool aus, solange keine Navigations-App aktiv ist.
