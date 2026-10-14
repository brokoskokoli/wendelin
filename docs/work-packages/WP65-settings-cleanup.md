# WP65 – Einstellungen aufräumen, Passwortmanager, Kalibrierung (`app/`)

Bezug: freier Gerätetest des Maintainers 2026-10-15.

## Inhalt
1. **Passwortmanager:** Alle Schlüssel-/Passwortfelder (u. a. Bring!, Anbieter-API-Keys, `app/lib/ui/design/secret_field.dart`, `credentials_step.dart`, `bring_screen.dart`) lösen auf Android die Autofill-Vorschläge des Passwortmanagers aus (Leiste über der Tastatur). Dazu passende `autofillHints` (password/username/email), `AutofillGroup` wo Nutzername+Passwort zusammengehören, `TextInput.finishAutofillContext` beim Speichern, keine Tastatur-Flags, die Autofill verhindern. Prüfen, warum es heute nicht greift (z. B. `enableSuggestions:false`/`autocorrect` ok, aber fehlende Hints oder `keyboardType`).
2. **Prüfprotokoll in ein Untermenü:** Die zwei Stellen, an denen das Prüfprotokoll groß inline erscheint, zeigen stattdessen eine kurze Zeile/Karte mit Status und Button „Prüfprotokoll ansehen“, der eine eigene Seite öffnet.
3. **Kalibrierung/Ausprobieren ohne Modell:** Vor dem Start von Einlernen, Kalibrieren und „Jetzt ausprobieren“ prüfen, ob die nötigen Modelle (Wake-Word-Merkmale, Whisper für die Nachprüfung) geladen sind. Wenn nicht: klare Meldung („Dafür muss zuerst das Sprachmodell geladen werden“) mit Button zum Laden, statt einer kryptischen Fehlermeldung. Button ist bis dahin deaktiviert oder führt zum Laden.
4. **Doppelte Einträge:** Obsidian, Listen, Websuche und Gedächtnis erscheinen nur noch unter „Integrationen“, nicht zusätzlich im Hauptmenü der Einstellungen.

## Abnahmekriterien
- [ ] Widget-Tests: Felder tragen Autofill-Hints; Prüfprotokoll nur über den Button; Kalibrieren ohne Modell zeigt Hinweis + Laden-Button; Hauptmenü ohne die vier Einträge, Integrationen mit ihnen. Goldens aktualisiert (macOS).
- [ ] Prüfpunkte in `docs/testing/m4-device.md` (Autofill mit Passwortmanager auf dem Gerät).
- [ ] Gate grün.
