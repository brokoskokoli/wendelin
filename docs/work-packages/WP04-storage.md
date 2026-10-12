# WP04 – Storage (`packages/wendelin_storage`)

Abhängig von: `wendelin_core`, `drift`, `sqlite3` (Tests: `NativeDatabase.memory()`), Dev: `drift_dev`, `build_runner`. Konzept-Bezug: „Persistenz“, „Gedächtnis im Detail“, „Logging“, „Kosten“, „Sitzungen“.

Datenbank-Konstruktor nimmt einen `QueryExecutor` entgegen (App liefert `drift_flutter`, Tests In-Memory). Generierte Dateien (`*.g.dart`) werden eingecheckt.

## Tabellen
- `sessions(id, startedAt, lastActivityAt, title?)`
- `messages(id, sessionId, seq, role, contentJson, createdAt, profileId?, modelId?)` – Inhalt über core-JSON-Serialisierung.
- `memory_entries(id, body, category {person, preference, fact, project}, source, createdAt, lastUsedAt)` + FTS5-Tabelle (Trigger zur Synchronisation).
- `audit_log(id, at, kind {request, routing, toolCall, confirmation, escalation, usage, verification, error}, sessionId?, payloadJson)`
- `provider_profiles(id, json)` – serialisiertes `ProviderProfile` **ohne** Secrets.
- `usage_records(id, at, sessionId, profileId, modelId, inputTokens, outputTokens, cachedTokens, cacheWriteTokens, costMicros)` – alle vier Zähler von `Usage` (K5).
- `settings(key, valueJson)`

## Repositories (öffentliche API, keine drift-Typen nach außen)
- `ConversationRepository`: Sitzung anlegen/finden (`currentOrNew(now, inactivity: 5 min)`), Nachrichten anhängen, letzte N Züge laden, Volltextsuche optional.
- `MemoryRepository`: `save`, `update`, `forget`, `list`, `search(query, limit: 5)` (FTS5 bm25-Ranking, `lastUsedAt` aktualisieren), `exportMarkdown()`. **Schutzregel**: Texte mit Kreditkartennummer (Luhn-geprüft), IBAN-Muster oder „Passwort/PIN: …“ werden abgelehnt (`SensitiveContentException`).
- `AuditLogRepository` mit `record(AuditEntry)` (storage hängt nicht von wendelin_tools ab; der Adapter von `ToolAuditSink` auf dieses Repository liegt in der App), `query(filter)`, `purgeOlderThan(Duration)` (Standard 30 Tage), `exportJson()`, `clear()`. Redaktion: Felder, deren Schlüssel nach Secret aussehen (`api_key`, `authorization`, `token`, `password`), werden vor dem Speichern durch `***` ersetzt.
- `ProviderProfileRepository`: CRUD, Default-Profil setzen.
- `UsageRepository`: `record`, `totalsByDay/Month(profileId?)`, `monthToDateCostMicros(profileId)` für Budgetprüfung.
- `SettingsRepository`: typisierte Get/Set mit JSON.
- `SecretStore` (abstract interface: `read`, `write`, `delete`, `listKeys`) + `InMemorySecretStore` + Contract-Suite unter `lib/testing.dart` (die App-Implementierung mit flutter_secure_storage muss sie bestehen).

## Abnahmekriterien
- [ ] Schema-Version 1 mit Migrationstest-Gerüst (drift `schema dump` eingecheckt).
- [ ] FTS5-Suche liefert relevante Einträge zuerst (Test mit ≥ 10 Einträgen).
- [ ] Redaktion und Schutzregel getestet (inkl. Luhn-gültig/ungültig).
- [ ] Retention-Purge und Export getestet.
- [ ] Keine drift-Typen in der öffentlichen API.
- [ ] Gate grün, Abdeckung ≥ 85 % (generierte Dateien ausgenommen).
