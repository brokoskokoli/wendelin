# Feste Bestätigungssätze je Sprache (WP122)

`de.dart`, `en.dart`, `fr.dart`: je Sprache eine Datei mit den Vorlagen
(`templates`, Schlüssel `<bereich>.<aktion>`, Platzhalter `{name}`) und den
Formaten für Aufzählung („A, B und C“), Dauer, Wochentage und Termin. Ein
Tool mit `FixedConfirmationTool` liefert im `ToolOutcome.fixed` Schlüssel und
Werte aus seinem **Ergebnis**; `renderConfirmation` baut den Satz in der
Sprache der Anfrage. Fehlt Sprache oder Vorlage, antwortet das Modell.

## Regeln
- `<key>#one` ist die Einzahl, gewählt über den Wert `count` (`int`).
- Jede Sprache führt **dieselben** Schlüssel (Test `fixed_confirmation_test.dart`),
  und jeder Schlüssel eines Tools (`confirmationKeys`) steht in jeder Sprache.
- Nur Sätze für eindeutige Aktionen mit klarem Ergebnis; nie für Lese-Tools.
- Neue Sprache: Datei kopieren, in `fixed_confirmation.dart` unter
  `confirmationLanguages` eintragen.
