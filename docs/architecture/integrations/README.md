# Angaben je Integration

Hier liegt für Angaben, die sich nicht aus dem Code ableiten lassen (Besonderheiten, Port-Zuordnung, Hinweise für Betrieb und Tests), **eine eigene Datei je Integration**: `docs/architecture/integrations/<id>.md` (`<id>` wie in der Registry). So entsteht beim parallelen Anlegen neuer Integrationen keine gemeinsame Zeile und kein Merge-Konflikt. Die Liste aller Integrationen mit Spec und Paketordner erzeugt `tool/gen_docs.dart`: [generated/integrations.md](../generated/integrations.md).

Die Ports der Integrationen stehen weiter in [ports.md](../ports.md); neue Ports einer neuen Integration gehören in deren eigene Datei hier.
