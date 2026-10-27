# WP164 – Kontakte: Felder gezielt abfragen, Navigation zu Kontakt, Waze

**Zuordnung:** Wunsch des Maintainers vom 2026-10-27 (Gerätetest).

## Befund
- `contacts__find` (`packages/wendelin_integrations/lib/src/contacts/contacts_tools.dart:26`) liefert nur Telefonnummern und Mailadressen. Der Kanal fragt nur `Phone` und `Email` ab (`app/android/app/src/main/kotlin/app/wendelin/ContactsChannel.kt:123-146`, `MIMETYPE IN (?, ?)`).
- Folge: „Navigiere zu <Kontakt>“ findet den Kontakt, aber keine Adresse; Geburtstage sind nicht lesbar.

## Wunsch (Maintainer, sinngemäß)
- Der ganze Kontakt soll lesbar sein (Postanschrift, Geburtstag usw.), aber **nicht** standardmäßig komplett zurückgegeben werden. Das Modell gibt an, welche Felder es braucht (z. B. „Kontakt <Name> mit Telefonnummer“ oder „mit Adresse“), und das Tool liefert nur diese.
- Ziel: „Navigiere zu <Kontakt>“ → Adresse aus dem Adressbuch → `maps__navigate`.

## Inhalt
- `contacts__find` bekommt einen Parameter `fields` (Liste, z. B. `phone`, `email`, `address`, `birthday`, `organization`, `note`?, …; Auswahl mit Begründung, sensible Felder wie Notizen nur, wenn wirklich sinnvoll). Ohne Angabe: wie heute nur Telefon und Mail (kein Verhaltenswechsel für sms/phone).
- Kanal: zusätzliche MIME-Typen (`StructuredPostal`, `Event` mit Typ Geburtstag, ggf. `Organization`) nur, wenn angefragt; Daten nur für die Treffer laden.
- Tool-Beschreibung so, dass das Modell für Navigation `address` anfragt und die Adresse an `maps__navigate` gibt; mehrere Adressen → `choice_needed` wie bei Nummern.
- Kontaktdaten sind fremde Daten im Sinne des Prompt-Schutzes (Kennzeichnung wie bei anderen Lesewerkzeugen); keine Kontaktdaten in Logs (Dev-Log-Schwärzung prüfen).
- Gesperrt gilt weiter die Stufe des Werkzeugs (Standard C für `read`).
- Keine echten Namen oder Adressen in Tests, Doku oder Commits (Fixtures synthetisch, z. B. „Anna Meier“).

## Teil B – Waze als zweite Navigations-App (Wunsch Maintainer 2026-10-27)
- Waze als eigene, antippbare Integration neben Google Maps (Integrationsliste, an/aus, Hinweis falls nicht installiert). Kein Schlüssel und kein Konto nötig: Waze nimmt Deep Links `https://waze.com/ul?q=<Ziel>&navigate=yes` (bzw. `ll=<lat>,<lng>`), Paket `com.waze`. Am Gerät prüfen, ob `q=` mit Adresse direkt die Navigation startet oder erst eine Auswahl zeigt.
- Erlaubte Launch-Schemata erweitern (`LocationPick.isAllowedLaunch`, `app/android/app/src/main/kotlin/app/wendelin/LocationPick.kt:46`), Paket-Sichtbarkeit (`<queries>`) im Manifest.
- Welche App navigiert: eine Einstellung „Navigations-App“ (Google Maps / Waze), Standard die zuerst eingerichtete bzw. installierte; der Nutzer kann im Befehl eine App nennen („mit Waze“).
- Gleiche Werkzeugform wie bei Maps (eigene Tools `waze__navigate` oder ein gemeinsames Navigations-Tool mit App-Wahl; die Paket-Sitzung entscheidet und begründet, mit Rücksicht auf die Tool-Auswahl des Modells).

## Teil C – Navigation zu einem Kontakt in einem Schritt (Wunsch Maintainer 2026-10-27)
- Neues Werkzeug (z. B. `navigate_to_contact`, Argument nur `name`, optional `app`, optional `address_label` für Privat/Arbeit): sucht im Adressbuch den Kontakt, nimmt dessen Postanschrift und startet die Navigation. Die Adresse geht **nicht** an das Modell.
- Rückgabe nur ein Status: `ok` (Navigation gestartet), `no_contact`, `no_address`, `choice_needed` (mehrere Kontakte bzw. Adressen; nur Namen und Bezeichnungen wie „privat“/„Arbeit“, keine Adressen). Das Modell entscheidet daraus, was es sagt bzw. fragt.
- Bei `ok` keine Modellantwort nötig: fester Bestätigungssatz (Muster `ConfirmationSentence`, z. B. „Navigation zu <Name> gestartet.“) bzw. keine Sprachausgabe, wie bei anderen Werkzeugen mit festem Satz.
- Gesperrt: Merkmal „wirkt nur entsperrt“ aus WP163 Teil B (gemerkter Aufruf, nach dem Entsperren ausführen). Stufe des Werkzeugs gilt; Standard wie `maps__navigate`.

## Abnahmekriterien
- [ ] Tests: ohne `fields` unverändert; mit `address`/`birthday` genau diese Felder, keine anderen (Mutationsbeleg); mehrere Adressen → Auswahl.
- [ ] Kanaltest bzw. E2E auf dem Emulator mit synthetischem Kontakt (Adresse, Geburtstag).
- [ ] „Navigiere zu <Kontakt>“ ergibt im Agententest `contacts__find(fields: address)` → `maps__navigate(destination: <Adresse>)`.
- [ ] Teil B: Waze-Integration antippbar, Deep Link mit Ziel (Test der erzeugten URI), Navigations-App wählbar; fehlt Waze, klare Meldung.
- [ ] Teil C: `navigate_to_contact` gibt keine Adresse an das Modell (Test), Status ok/no_contact/no_address/choice_needed, fester Satz bei ok (Mutationsbeleg).
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp164.md` (Waze installiert; Navigation zu Kontakt mit Maps und Waze); `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Start erst nach dem Merge von WP163 (Teil B dort führt das Merkmal „wirkt nur entsperrt“ ein und ändert `maps__navigate` gesperrt; Teil B/C hier bauen darauf auf).
- WP163 Teil B ändert das Verhalten von `maps__navigate` gesperrt (Executor/Overlay), nicht die Werkzeug-Argumente. WP159 (gemergt) hat Hinweise für SMS-Berechtigung in den Kontakte-Einstellungen eingebaut. l10n nur eigene Schlüssel.
