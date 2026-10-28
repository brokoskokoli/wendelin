# Kontakte, SMS und Anrufe (`contacts`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `contacts__find` | read | Name suchen: Nummern und Mailadressen; optional `fields` (phone, email, address, birthday, organization, keine Notizen); mehrdeutige Treffer, Nummern oder Adressen als Auswahl |
| `sms__compose` | external | SMS mit Vorschau in der App senden |
| `phone__call` | external | Anruf mit Vorschau starten |

Die Integration ist **sensibel** (`sensitive`): Kontaktdaten gehen nur an TEE-Anbieter und Claude, andere per Freigabe (bestehende Logik). Nie bei gesperrtem Gerät (`allowedWhileLocked` ist `false`, `LockGateAgentRun` lässt das Modell gar nicht laufen).

**Vorschau und Bestätigung.** `sms__compose` und `phone__call` laufen nur nach einer Bestätigung. Die App zeigt die Vorschau (`OutgoingPreviewCard`: Name aus dem Adressbuch, Nummer, bei SMS der editierbare Text) und liest sie vor („Nachricht an X: …. Soll ich sie absenden?“, „Anruf bei X. Soll ich anrufen?“). Es führt aus: Tipp auf „Absenden“/„Anrufen“ oder eine klare gesprochene Antwort (ja, bzw. „absenden“ für die SMS, „anrufen“ für den Anruf; `YesNoRecognizer.smsYesWords`/`callYesWords`, streng: höchstens zwei Wörter). „Nein“/„abbrechen“ bricht ab; Unklares führt nichts aus und fragt einmal erneut, danach nur noch Tipp. Auch im Gesprächsmodus. Hat der Nutzer den Text nach dem Vorlesen geändert, bestätigt ein gesprochenes „ja“ nicht (nur Tipp): `SmsDraftEdits` (App) hält die Änderung, das Tool sendet den Text der Vorschau. Weder Modell noch Tool-Ergebnisse können eine Bestätigung liefern.

**Audit**: Tool, Empfängername und Ergebnis, nie der Nachrichtentext (`ToolExecutor`, Test `audit_redaction_test.dart`).

**`fields` (WP164)**: Ohne `fields` genau Telefon und Mail wie bisher. Mit `fields` enthält das Ergebnis nur die angefragten Felder (Listen auch leer, Geburtstag und Firma nur wenn gespeichert); unbekannte oder leere Werte lehnt das Tool mit der Liste der erlaubten Felder ab (fail-closed). Der Kanal liest Postadresse, Geburtstag (Event-Typ Geburtstag) und Firma nur, wenn angefragt; Telefon- und Mailzeilen bestimmen weiter, welche Kontakte es gibt, werden aber nur herausgegeben, wenn angefragt. Für „Navigiere zu X“ fragt das Modell `address` und gibt die Adresse an `maps__navigate`.

**Ports**: `ContactsPort` (`hasPermission`, `all({fields})`), `PhonePort` (`canSendSms`, `sendSms`, `call` → `CallPlacement.direct` oder `.dialer`). Fehler als `PortException`. Fakes `FakeContactsPort`, `FakePhonePort`.

**Kotlin**: `ContactsChannel` (`ContactsContract`, `SmsManager`, `ACTION_CALL`/`ACTION_DIAL`), Zeilenaufbereitung in `ContactRows`.

**Berechtigungen** (erst beim Einschalten der Integration): `READ_CONTACTS`, `SEND_SMS`, `CALL_PHONE`. Ohne `CALL_PHONE` öffnet sich der Wählbildschirm mit der Nummer; ohne `SEND_SMS` meldet das Tool den Fehler. **Plattformen**: Android.
