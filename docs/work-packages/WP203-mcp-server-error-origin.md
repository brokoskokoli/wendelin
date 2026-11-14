# WP203 – Fehlermeldung eines MCP-Servers zählt als Inhalt desselben Servers

**Zuordnung:** Gerätetest v0.1.9-rc1 durch den Maintainer, 2026-11-14. „Ohne Nachfrage“ für `set_device`. Das Modell rät zuerst einen falschen Gerätenamen („Licht“, „Rollo“). Der Server antwortet mit einem Fehler („Gerät nicht gefunden“), und der zweite Aufruf mit dem richtigen Namen fragt wieder nach (Logcat 18:28:45 und 18:34:09, `confirm-start` vor n=3).
**Konzept:** K156 präzisieren (Entscheidung Maintainer „Gleicher Server ist ok“, 2026-11-14).

## Befund
- ADR 0023, Regel zur Herkunft: „Ein Fehlertext eines MCP-Tools gilt als `unknown` (kann ein Client-Fehler sein).“ Test `app/test/agent/same_server_origin_test.dart:186` legt das fest.
- Eine Fehlermeldung, die der Server selbst liefert (`tools/call` mit `isError: true`, im Umschlag `<mcp_result server="…" error="true">`), stammt aber genauso sicher vom Server X wie ein Erfolg.

## Inhalt
- **Vom Server gemeldete Fehler** (Ergebnis von `tools/call` mit `isError`) eines Tools von X tragen die Herkunft X.
- **Vom Client erzeugte Fehler** (Zeitüberschreitung, Netz, Protokoll, Sitzung, Validierung in Wendelin, Abbruch) bleiben `unknown`, fail-closed. Die Unterscheidung kommt aus dem Code, nicht aus dem Text. Ein Text kann nicht vortäuschen, vom Server zu stammen; prüfen und belegen.
- ADR 0023 und K156 anpassen. Den Test `:186` aufteilen: Server-Fehler X → X ohne Nachfrage; Client-Fehler → fragt nach.

## Abnahmekriterien
- [ ] Roter Test vor dem Fix: Server-Fehler von X, dann Tool von X mit „Ohne Nachfrage“: heute wird gefragt.
- [ ] Danach: ohne Nachfrage; Client-Fehler (Timeout, Netz) eines Tools von X → fragt; Server-Fehler von Y → Tool von X fragt.
- [ ] TEE-Quittung bleibt Pflicht (bestehender Test grün), Sitzungssperre unverändert.
- [ ] Mutationsbelege.
- [ ] Gerätetest-Block `docs/testing/m5/wp203.md`.

## Parallel
- Keins aktiv.
