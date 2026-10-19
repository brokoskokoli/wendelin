# Kontakte, SMS und Anrufe (`contacts`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `contacts__find` | read | Name suchen: Nummern und Mailadressen; mehrdeutige Treffer als Auswahl |
| `sms__compose` | external | SMS mit Vorschau in der App senden |
| `phone__call` | external | Anruf mit Vorschau starten |

Die Integration ist **sensibel** (`sensitive`): Kontaktdaten gehen nur an TEE-Anbieter und Claude, andere per Freigabe (bestehende Logik). Nie bei gesperrtem Gerät (`allowedWhileLocked` ist `false`, `LockGateAgentRun` lässt das Modell gar nicht laufen).

**Vorschau und Bestätigung.** `sms__compose` und `phone__call` laufen nur nach einer Bestätigung. Die App zeigt die Vorschau (`OutgoingPreviewCard`: Name aus dem Adressbuch, Nummer, bei SMS der editierbare Text) und liest sie vor („Nachricht an X: …. Soll ich sie absenden?“, „Anruf bei X. Soll ich anrufen?“). Es führt aus: Tipp auf „Absenden“/„Anrufen“ oder eine klare gesprochene Antwort (ja, bzw. „absenden“ für die SMS, „anrufen“ für den Anruf; `YesNoRecognizer.smsYesWords`/`callYesWords`, streng: höchstens zwei Wörter). „Nein“/„abbrechen“ bricht ab; Unklares führt nichts aus und fragt einmal erneut, danach nur noch Tipp. Auch im Gesprächsmodus. Hat der Nutzer den Text nach dem Vorlesen geändert, bestätigt ein gesprochenes „ja“ nicht (nur Tipp): `SmsDraftEdits` (App) hält die Änderung, das Tool sendet den Text der Vorschau. Weder Modell noch Tool-Ergebnisse können eine Bestätigung liefern.

**Audit**: Tool, Empfängername und Ergebnis, nie der Nachrichtentext (`ToolExecutor`, Test `audit_redaction_test.dart`).

**Ports**: `ContactsPort` (`hasPermission`, `all`), `PhonePort` (`canSendSms`, `sendSms`, `call` → `CallPlacement.direct` oder `.dialer`). Fehler als `PortException`. Fakes `FakeContactsPort`, `FakePhonePort`.

**Kotlin**: `ContactsChannel` (`ContactsContract`, `SmsManager`, `ACTION_CALL`/`ACTION_DIAL`), Zeilenaufbereitung in `ContactRows`.

**Berechtigungen** (erst beim Einschalten der Integration): `READ_CONTACTS`, `SEND_SMS`, `CALL_PHONE`. Ohne `CALL_PHONE` öffnet sich der Wählbildschirm mit der Nummer; ohne `SEND_SMS` meldet das Tool den Fehler. **Plattformen**: Android.
