# WP157 – Sicherheit: Sperre nach roter Quittung je Unterhaltung, Netz-Lesewerkzeuge nach fremden Inhalten

**Zuordnung:** Projekt-Review vom 2026-10-26 (Befunde 2 und 5, Bericht außerhalb des Repos). Entscheidungen Maintainer 2026-10-26: Sperre echt umsetzen; Rückfrage für lesende Werkzeuge mit Netzziel nach fremden Inhalten (K122).

## Befunde
- **Sperre nach Rot:** Das Konzept (Abschnitt Tool-System, K44/K46/K70) sagt, nach roter Quittung sind `external`-Tools für den Rest der Sitzung gesperrt. `RiskPolicy.lockExternal` (`packages/wendelin_tools/lib/src/policy/risk_policy.dart:103`) wird nirgends aufgerufen; es sperrt nur `AttestedProvider._lock` im Speicher einer Engine (`packages/wendelin_providers/lib/src/tee/attested_provider.dart:575-584`). Overlay-Neuaufbau (eigene Provider, `assistant_overlay.dart:225-239`, `attestation_hub.dart:108`) oder Neustart heben sie vermutlich auf; bei `pinChanged` gibt es keine Sperre.
- **Abfluss über Lesewerkzeuge:** Nach nicht vertrauenswürdigen Ergebnissen (`untrustedSeen`, `packages/wendelin_agent/lib/src/run/tool_round.dart:316-323`) laufen `read`-Werkzeuge mit Netzziel (HTTP-GET-Tools `http_tool_definition.dart:17-23`, MCP `readOnlyHint` `wendelin_mcp/lib/src/tools/risk.dart:14`, Websuche `web_integration.dart:117`) ohne Rückfrage; eingeschleuste Anweisungen können private Daten (z. B. Termine) als Parameter hinausschicken.

## Inhalt
1. **Analyse zuerst:** Verlust der Sperre beim Neuaufbau mit einem Test belegen (rot → Overlay neu → external-Tool läuft?). `pinChanged` einordnen.
2. **Sperre je Unterhaltung:** Bei roter Quittung (und `pinChanged`) wird die Unterhaltung (Sitzungs-ID) für `external`-Tools gesperrt, persistiert über Engine-Neuaufbau und App-Neustart, bis die Sitzung endet oder der Nutzer „neu prüfen“ wählt. Eine Stelle (Runner/Policy), `lockExternal` nutzen oder ersetzen; toter Code raus.
3. **Netz-Lesewerkzeuge:** Werkzeuge kennzeichnen, die Daten nach außen tragen können (Netzziel: HTTP-Tools, MCP, Websuche, ggf. weitere; fail-closed: unbekannt = Netz). Nach `untrustedSeen` werden sie im selben Lauf auf Bestätigung gehoben (Karte zeigt Ziel und Argumente). Verträglich mit den Stufen aus WP154 (Stufe D bzw. Bestätigung gewinnt; kein Abschwächen über Stufe A möglich – im Paket mit ADR begründen).
4. **Was als fremder Inhalt zählt** (Maintainer 2026-10-26, ersetzt für diese Quellen die heutige Regel „alles ohne `TrustedContentSource` ist nicht vertrauenswürdig“, `packages/wendelin_core/lib/src/tools/tool.dart`, WP41):
   - Notizen und Listen (Obsidian, Listen/Aufgaben, Einkaufsliste) gelten als sicher.
   - Websuche ist immer unsicher (fest, nicht abschaltbar).
   - HTTP-GET-Tools und MCP-Server bekommen je Tool bzw. Server einen Haken „Kann unsichere Inhalte enthalten“. Eigene Dienste, die nur Bekanntes liefern, kann der Nutzer als sicher markieren. Im Zweifel bleibt der Haken gesetzt, das ist auch der Standard.
   - Für die übrigen Integrationen leitet das Paket die Einordnung her und listet sie im Bericht (Kalender, Kontakte, HA, Wetter …). Vorschlag: eigene bzw. strukturierte Daten sind sicher, frei formulierte Texte Dritter (z. B. Kalendereinladungen, HA-Namen) prüfen.
5. ADR „Sitzungssperre und Abfluss-Schutz“.

## Abnahmekriterien
- [ ] Test belegt den alten Fehler (rot vor dem Fix), danach Sperre über Overlay-Neuaufbau und Neustart (Tests, Mutationen).
- [ ] Nach fremden Inhalten verlangt ein HTTP-GET/MCP-read/Websuche-Aufruf eine Bestätigung; ohne fremde Inhalte unverändert (Tabellentest).
- [ ] ADR, Abweichungen im Bericht (K122 vom Orchestrator).
- [ ] `--changed` grün, CI grün, Review FREIGABE (Schwerpunkt Sicherheit).

## Parallel-Hinweise
- Berührt `risk_policy.dart`, ToolExecutor und Agent-Runner wie WP154: nach WP154 starten.
