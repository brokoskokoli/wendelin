# WP107 – Bring! speichert nur Tokens, kein Passwort (`wendelin_integrations`, `app/`)

**Zuordnung:** M5 (Nachbesserung Bring!-Integration). Wunsch Stefan 2026-10-19 (über die Sitzung „wendelin-75“), zeitnah.

## Live-Befund 2026-10-19 (Stefans Konto, ein Login, Liste unverändert)
- Access-Token: JWT, 7 Tage (`expires_in=604799`). Refresh-Token: JWT, `exp` 2076-10-06 (~50 Jahre).
- `POST v2/bringauth/token` liefert denselben Refresh-Token (keine Rotation) und einen neuen Access-Token (7 Tage); der alte Access-Token gilt danach weiter.
- JWT-Claims: brn, email, exp, privateUuid, roles, sub.
- Nicht getestet: ob eine Passwortänderung bei Bring! den Refresh-Token ungültig macht.

## Inhalt
1. **Einstellungen:** einmal Login mit E-Mail und Passwort, danach nur `BringAuth` (uuid, Tokens, Standardliste) im SecretStore; Passwort (und E-Mail) nach dem Login verwerfen.
2. **BringSession** (`packages/wendelin_integrations/lib/src/bring/bring_session.dart`, ~Z. 118–128): Fallback „neuer Login mit gespeicherten Zugangsdaten“ streichen. Refresh-Token abgelehnt (permissionDenied) → Fehlerzustand „Bitte neu anmelden“; der vorhandene Knopf „Erneut verbinden“ führt zum Login.
3. **Setup-Schritt `bring_login`** gilt als erledigt, wenn eine Sitzung gespeichert ist (nicht mehr bei vorhandenen Zugangsdaten).
4. **Migration:** vorhandene `bring.password` und `bring.email` löschen; vorhandene Sitzung bleibt gültig.
5. **Aufräumen:** BringCredentials/BringSecrets, Fakes, Contract-Tests, README unter `packages/wendelin_integrations/lib/src/bring/`, `app/lib/di/bring.dart`, UI-Texte de/en/fr (l10n-Fragment), ggf. Tests in `wendelin_storage`/`wendelin_mcp`, die die alten Schlüssel nennen.

## Abnahmekriterien
- [ ] Tests: nach Login kein Passwort/keine E-Mail im SecretStore; Refresh abgelehnt → „Bitte neu anmelden“ ohne Login-Versuch; Migration löscht Altschlüssel und behält Sitzung; Setup-Schritt nach Sitzung erledigt. Mutationsbelege.
- [ ] Keine Tokens in Logs/Audit/Export. Gate grün; Gerätetest-Datei `docs/testing/m5/wp107.md` (Login, Neustart, „Erneut verbinden“).
