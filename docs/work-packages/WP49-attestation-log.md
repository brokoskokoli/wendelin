# WP49 – Prüfprotokoll-Speicher (`packages/wendelin_storage`)

Abhängig von: – (sofort startbar; Feldliste aus diesem Dokument, Abgleich mit WP46 im Review). Andockpunkte: Tabellen `packages/wendelin_storage/lib/src/db/tables.dart`, Datenbank/Migration `src/db/database.dart`, Repositories `src/repositories/repositories.dart` (Muster: `AuditLog` mit `purgeOlderThan`), Schema-Tests `test/drift/`. Bezug: Konzept „Prüfprotokoll (UI)“, K9 d („Alles löschen“ entfernt Verläufe und Prüfprotokoll, Aufbewahrungsfrist).

## Inhalt
- Tabelle `AttestationLog`: Zeit, Provider-Profil-ID, Modell, Art (`session`/`receipt`), Sitzungs- bzw. Nachrichten-/Schritt-ID, Quittungs-ID, `workload_keyset_digest`, `workload_id` (optional), Commit, Compose-Hash bzw. Image-Digest, Gesamtstatus, Stufenergebnisse (JSON: Stufe → ok/fehlt/fehler + Kurzgrund), TCB-Status. **Keine** Prompt- oder Antwortinhalte, keine Rohquittung (nur Hashes und IDs).
- Repository `AttestationLogRepository`: `add`, `forSession`, `forStep`, `latest`, `purgeOlderThan`, `deleteAll`, `exportJson()` (stabiles Format mit Versionsfeld).
- Migration mit Schema-Test (alte → neue Version), Einbindung in „Alles löschen“ und die Aufbewahrungsfrist.
- Port für die App/den Agent (`AttestationLogSink`), damit WP46 b/WP52 schreiben können, ohne die Tabelle zu kennen.

## Abnahmekriterien
- [ ] Schema-/Migrationstest unter `test/drift/` (Daten bleiben erhalten).
- [ ] Repository-Tests: Filter, Reihenfolge, Purge, `deleteAll`, Export (Golden-JSON).
- [ ] Ein Test zeigt, dass keine Inhalte gespeichert werden (Felder aus dem Export geprüft).
- [ ] „Alles löschen“ entfernt das Prüfprotokoll (Test).
- [ ] Gate grün.
