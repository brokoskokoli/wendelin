# Integration `contacts` (WP85)

Kontakte suchen, SMS mit Vorschau und Anruf mit Bestätigung. Spec `app/lib/di/integrations/contacts_spec.dart`, Tools in `packages/wendelin_integrations/lib/src/contacts/`. Sensibel, nie bei gesperrtem Gerät (`allowedWhileLocked: false`).

| Kanal (`app.wendelin/…`) | Dart | Kotlin |
| --- | --- | --- |
| contacts | `app/lib/platform/channel_contacts_port.dart` | `ContactsChannel.kt` (`ContactRows.kt`) |

Senden und Anrufen geschehen erst nach Bestätigung per Tipp oder Sprache; der Entwurfsspeicher `app/lib/di/sms_drafts.dart` ist derselbe für Oberfläche und Tool. Die Berechtigung (Kontakte, SMS, Anruf) wird beim Einschalten erfragt. Ergebnisse echoen Namen aus dem Adressbuch und sind nicht vertrauenswürdig (`app/test/trust/contacts.json`). Das Audit enthält den Empfängernamen, nie den Nachrichtentext.

`contacts__find` nimmt optional `fields` (phone, email, address, birthday, organization; Standard phone und email, keine Notizen); Kanalargument `fields`, Details im Paket-README. `contacts__navigate` (WP164 C) startet die Navigation zu einem Kontakt, ohne dass das Modell die Adresse sieht (nur Status); Verfügbarkeit: Kontakte-Integration an und mindestens eine Navigations-App aktiv (`ConditionalTool`). Dev-Log: Ergebnisse stehen im Entwicklermodus wie Telefonnummern unverändert im Log (gekürzt auf 300 Zeichen), Adressen und Geburtstage werden nicht gesondert geschwärzt.
