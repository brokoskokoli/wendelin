# WP164 – Kontakte: Postanschrift, Geburtstag und weitere Felder gezielt abfragen

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

## Abnahmekriterien
- [ ] Tests: ohne `fields` unverändert; mit `address`/`birthday` genau diese Felder, keine anderen (Mutationsbeleg); mehrere Adressen → Auswahl.
- [ ] Kanaltest bzw. E2E auf dem Emulator mit synthetischem Kontakt (Adresse, Geburtstag).
- [ ] „Navigiere zu <Kontakt>“ ergibt im Agententest `contacts__find(fields: address)` → `maps__navigate(destination: <Adresse>)`.
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp164.md`; `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- WP163 Teil B ändert das Verhalten von `maps__navigate` gesperrt (Executor/Overlay), nicht die Werkzeug-Argumente. WP159 (gemergt) hat Hinweise für SMS-Berechtigung in den Kontakte-Einstellungen eingebaut. l10n nur eigene Schlüssel.
