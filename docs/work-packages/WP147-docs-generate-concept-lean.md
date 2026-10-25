# WP147 – Doku generieren, Konzept schlank, Review-Messung

**Zuordnung:** Architekturanalyse vom 2026-10-19, Maßnahmen 7, 10, 11 und 14. Auftrag des Maintainers vom 2026-10-25. Teil B (Archiv einmal ausführen, Konzepttext nachziehen, ADR-Status) macht der Orchestrator nach dem Merge; dieses Paket liefert Werkzeuge und Checks.

## Ist-Stand
- `tool/cleanup_wt.sh:132` löscht `handoff/<wp>-*`, also auch die Urteilsdateien `<wp>-review*.md`. `tool/review_stats.dart` findet danach nichts und meldet „0 gültig“. `docs/work-packages/REVIEW.md:31` schreibt den Ablageort `../james-wt/handoff/` vor. Der Orchestrator kopiert die Urteile bisher von Hand nach `../james-wt/reviews/` (dort liegen schon rund 90 Dateien).
- `tool/gen_docs.dart` erzeugt bereits `docs/architecture/generated/packages.md` und `integrations.md` sowie den Index der Gerätetests, `--check` meldet Veraltetes. `tool/check_docs.dart` prüft Pfadangaben in Backticks.
- `docs/architecture/ports.md` und `channels.md` pflegen Tabellen von Hand; `channels.md` doppelt die Daten aus `app/channels.json`.
- Das Konzept (`Voice Agent App – Gesamtkonzept.md`) hat rund 130 KB, der größte Teil ist das Änderungsprotokoll. 23 K-Einträge sind `offen`.

## Inhalt
### A1 Review-Messung reparieren
- Urteile liegen dauerhaft unter `../james-wt/reviews/<wp>-review*.md`. `REVIEW.md:31` und den Standardordner von `review_stats` anpassen. Der Reviewer schreibt direkt dorthin.
- `cleanup_wt.sh` nimmt `reviews/` aus und löscht keine Urteilsdateien (auch nicht im alten Ort `handoff/<wp>-review*.md`, falls dort noch eines liegt; dann nach `reviews/` verschieben statt löschen).
- Selbsttest (in den vorhandenen Selbsttests der Skripte): Nach `cleanup_wt --apply` bleibt das Urteil erhalten und `review_stats` zählt es als gültig.
- Die vorhandenen Dateien in `reviews/` zählen danach mit (Bestand, ggf. mit Hinweis auf ungültige Köpfe statt Abbruch).

### A2 Doku generieren statt pflegen (Erweiterung von `tool/gen_docs.dart`, Prüfung über `--check` bzw. `check_docs`)
- **Ports:** Tabelle aus allen `abstract interface class *Port|*Api|*Secrets|*Store` mit Paket, Datei und Implementierern (Klassen mit `implements`/`extends`, Fakes getrennt markiert) → `docs/architecture/generated/ports.md`. `ports.md` behält nur die Erklärungen und verweist auf die erzeugte Tabelle.
- **Kanäle:** Tabelle aus `app/channels.json` → `generated/channels.md`. Die von Hand gepflegte Tabelle in `channels.md` entfällt, der Text verweist darauf.
- **Bezeichner-Check:** CamelCase-Bezeichner in Backticks unter `docs/architecture/` müssen im Code vorkommen (Dart, Kotlin, Rust). Bestand, der nicht passt, über eine Allowlist (nur abbauen); echte Altlasten in der Doku lieber gleich korrigieren.

### A3 Konzept schlank (Werkzeug und Checks; den Konzepttext ändert nur der Orchestrator)
- `tool/concept_archive.dart`: verschiebt bestätigte K-Einträge (Status `bestätigt …`) in `docs/concept-changelog/M<n>.md` (Meilenstein aus dem Eintrag bzw. Datum; Regel im Kopf des Werkzeugs begründen). Im Konzept bleiben die offenen und zurückgestellten Einträge und ein Verweis auf das Archiv. Ohne `--apply` nur Vorschau. Idempotent.
- Check: Jede bestätigte K-Nummer kommt im Konzepttext als „(Knn)“ oder in einer ADR vor. Bestand über Allowlist, nur abbauen.
- Check: Der K-Status in `docs/work-packages/STATUS.md` stimmt mit dem Konzept überein (soweit STATUS K-Status nennt).
- Alle Checks laufen im Gate (`--changed`, wenn Konzept, STATUS, `docs/` oder das Werkzeug geändert sind).

## Abnahmekriterien
- [ ] A1: Selbsttest belegt, dass ein Urteil nach `cleanup_wt` erhalten bleibt und gezählt wird; `review_stats` auf dem echten Bestand zählt > 0 gültige Urteile (Zahl im Bericht).
- [ ] A2: `generated/ports.md` enthält auch die M5-Ports (Contacts, Location, MediaControl, Todoist, GoogleTasks …); `generated/channels.md` ersetzt die Tabelle in `channels.md`; `gen_docs --check` und der Bezeichner-Check laufen im Gate.
- [ ] A3: `concept_archive.dart` mit Vorschau und `--apply`, Tests; beide K-Checks im Gate. Probelauf in einer Kopie: Das Konzept ist danach unter 60 KB (Zahl im Bericht). Der echte Lauf auf main ist Sache des Orchestrators.
- [ ] Je Check ein Negativtest mit Mutationsbeleg.
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Nicht im Paket
- Inhaltliche Änderungen am Konzepttext und das Ausführen von `concept_archive --apply` auf main (Teil B, Orchestrator).
- ADR-Status (Teil B).

## Parallel-Hinweise
- Kein anderes Paket läuft gerade. Basis ist main nach WP146. Das Konzept und STATUS.md nicht im Branch ändern (Konflikte mit dem Orchestrator); Allowlists und Testdaten gehören in `tool/`.
