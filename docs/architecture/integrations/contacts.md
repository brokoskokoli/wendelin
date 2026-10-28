# Integration `contacts` (WP85)

Kontakte suchen, SMS mit Vorschau und Anruf mit Bestätigung. Spec `app/lib/di/integrations/contacts_spec.dart`, Tools in `packages/wendelin_integrations/lib/src/contacts/`. Sensibel, nie bei gesperrtem Gerät (`allowedWhileLocked: false`).

| Kanal (`app.wendelin/…`) | Dart | Kotlin |
| --- | --- | --- |
| contacts | `app/lib/platform/channel_contacts_port.dart` | `ContactsChannel.kt` (`ContactRows.kt`) |

Senden und Anrufen geschehen erst nach Bestätigung per Tipp oder Sprache; der Entwurfsspeicher `app/lib/di/sms_drafts.dart` ist derselbe für Oberfläche und Tool. Die Berechtigung (Kontakte, SMS, Anruf) wird beim Einschalten erfragt. Ergebnisse echoen Namen aus dem Adressbuch und sind nicht vertrauenswürdig (`app/test/trust/contacts.json`). Das Audit enthält den Empfängernamen, nie den Nachrichtentext.

`contacts__find` nimmt optional `fields` (phone, email, address, birthday, organization; Standard phone und email, keine Notizen); Kanalargument `fields`, Details im Paket-README. `contacts__navigate` (WP164 C) startet die Navigation zu einem Kontakt, ohne dass das Modell die Adresse sieht (nur Status); Verfügbarkeit: Kontakte-Integration an und mindestens eine Navigations-App aktiv (`ConditionalTool`). Dev-Log: Ergebnisse von `contacts__find` (Namen, Nummern, Mails, Adressen, Geburtstag, Firma) werden auch im Entwicklermodus nicht geloggt, nur Anzahl und `choice_needed` (`DevAgentTrace._logResult` in `app/lib/voice/dev_agent_log.dart`, Test `app/test/dev/dev_log_test.dart`); die Suchanfrage (Argument) bleibt sichtbar. Auswahl ohne Schleife: gleiche Adress-Bezeichnungen werden eindeutig nummeriert („Privat 1“, „Privat 2“; `address_label`), gleiche Kontaktnamen tragen einen Index („Anna Meier (1)“) nur zur Anzeige; gewählt wird im Folgeaufruf mit `choice` (1-basierte Position, gleicher `name`), der Name wird nicht geparst. Zweistufiges Laden: Suchindex mit Presence-Abfrage (`all`), Zusatzfelder (Adresse, Geburtstag, Firma) per `details{ids,fields}` nur für die Treffer (max. 100 IDs, sonst `bad_args`). Der Feldfilter für das Modell ist `ContactEntry.toJsonFor`, auch gegen einen Port, der mehr liefert als angefragt.
