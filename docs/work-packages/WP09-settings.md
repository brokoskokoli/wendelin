# WP09 – Einstellungen und Onboarding (`app/lib/ui/settings/`, `app/lib/ui/onboarding/`)

Abhängig von: WP08. Konzept-Bezug: „Einrichtung (Dialog pro Provider)“, „Einstellungen“-Tabelle (Bereiche Provider, Integrationen, Gedächtnis, Datenschutz und Logs, Kosten, Assistent), „Integrationen auswählen“, „Berechtigungen“. Für Screens ohne Entwurf (Provider-Einrichtung, Übersicht, Gedächtnis, Kosten, Onboarding) gelten die Bausteine und Grundregeln aus DESIGN.md.

## Inhalt
- Einstellungsübersicht (Liste der Bereiche).
- **Provider**: Liste der Profile mit `ProviderChip`; Einrichtungsdialog in Schritten: Vorlage wählen → Key einfügen (Link zur Key-Seite; Key geht direkt in `SecretStore`, nie in State-Logs) bzw. Base-URL → Verbindungstest (`test()`), Modelle laden, Standardmodell wählen, Fähigkeits-Check → optional Budget/Warnschwelle, Datenschutzstufe. Default-Profil setzen; Eskalationskette (geordnete Liste von Profilen).
- **Integrationen** laut `screens/integrationen`: alle Integrationen mit Zustand, Schalter, „Einrichten“ fragt Berechtigung erst jetzt an (mit Erklärung davor), einzelne Tools an/aus, Risikostufe pro Tool (nur verschärfen bei external), Markierung sensibel.
- **Gedächtnis**: Einträge listen, bearbeiten, löschen, Export Markdown.
- **Datenschutz und Logs**: Aufbewahrung (Standard 30 Tage), Audit-Log-Ansicht (Filter nach Art), Export JSON (Share-Sheet), alles löschen (mit Bestätigung).
- **Kosten**: heute / Monat pro Provider aus `UsageRepository`.
- **Assistent**: Name des Nutzers, Persönlichkeits-Zusatz.
- **Onboarding** (beim ersten Start): Sprache, erster Provider (gleicher Dialog), Integrationen wählen. Whisper-Download und Standard-Assistent erst M2 (Schritt ausgeblendet).

## Abnahmekriterien
- [ ] Widget-Tests je Screen; Provider-Dialog mit Fake-Provider: Test erfolgreich/fehlgeschlagen, Modelle laden, Speichern legt Profil + Secret getrennt ab (Test prüft: Key nicht in DB).
- [ ] Integrationen-Golden gegen PNG vom Reviewer geprüft.
- [ ] Berechtigungsanfrage erst bei Aktivierung (Test mit Fake-Permission-Port).
- [ ] `flutter analyze`/`flutter test` grün, `flutter build apk --debug` läuft.
