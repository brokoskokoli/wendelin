# WP201 – „Ohne Nachfrage“ für MCP-Tools trotz Inhalten desselben Servers

**Zuordnung:** Gerätetest v0.1.8-rc3 durch den Maintainer, 2026-11-14, MCP-Server fürs Smart Home. Für `set_device` (Annotation `destructiveHint:false`, Stufe `write`) ist „Ohne Nachfrage“ gewählt, trotzdem fragt jeder Aufruf nach, sogar das lesende `list_devices`.
**Konzept:** K156 (offen), Präzisierung von ADR 0023.

## Befund
- `packages/wendelin_tools/lib/src/policy/risk_policy.dart:347–365`: Nach fremden Inhalten (`foreignContent`) wird jedes Tool ohne `NoNetworkTarget` bestätigt; die gewählte Stufe hebt das nicht auf.
- `packages/wendelin_agent/lib/src/run/tool_round.dart:320–330`: Jedes nicht vertrauenswürdige Ergebnis setzt `_state.untrustedSeen = true`; MCP-Ergebnisse und das Ergebnis von `tools__search` mit MCP-Beschreibungen zählen dazu. `run_start.dart:55` übernimmt den Zustand aus dem Gesprächskontext, die Markierung gilt also für den Rest des Gesprächs.
- Logcat: `tools__search` → `list_devices` mit `confirm-start` (02:30:49), danach jeder `set_device`-Aufruf mit `confirm-start`.

## Inhalt (Entscheidung Maintainer: „Gleicher Server ist ok“)
- Fremde Inhalte bekommen eine **Herkunft** (MCP-Server-ID; `tools__search` mit Beschreibungen eines Servers → dieser Server; alles andere, z. B. Websuche, Mail, HTTP-Tools, Anbieter-Blöcke, unbekannt → „fremd/unbekannt“). Fail-closed: Ohne sichere Zuordnung gilt „unbekannt“.
- Die Mindest-Bestätigung nach fremden Inhalten entfällt für ein MCP-Tool nur dann, wenn **alle** bisher gesehenen fremden Inhalte von **demselben** Server stammen. Sonst bleibt sie wie heute.
- Die Herkunft wird über das Gespräch hinweg so getragen wie heute `untrustedSeen` (Kontext, Neustart der Engine, Overlay), auch in der Sitzungssperre (gesperrte Sitzung + fremde Inhalte → Netz-Tools verweigert, wie heute; prüfen, ob „nur derselbe Server“ dort ebenfalls ausgenommen werden darf, und begründen).
- Andere Schutzstufen bleiben unberührt: „Alle Tools bestätigen“, Stufen-Overrides, gesperrtes Gerät, `external`-Sperre, gesprochener Text im Prüfmodus.
- Die Anzeige im Tool-Blatt bleibt richtig (fragt nicht nach), und wenn wegen fremder Inhalte doch gefragt wird, nennt die Bestätigungskarte den Grund (kurz, ohne Inhalte).
- ADR 0023 um einen Abschnitt zur Herkunft ergänzen.

## Abnahmekriterien
- [ ] Roter Test vor dem Fix: MCP-Server X, Tool mit „Ohne Nachfrage“, nach einem Ergebnis von X wird heute bestätigt.
- [ ] Danach: Nach Inhalten nur von X läuft das Tool von X ohne Nachfrage; nach Inhalten von Y (anderer Server) oder Websuche/Mail/unbekannt wird bestätigt; ein Tool von Y nach Inhalten von X wird bestätigt.
- [ ] `tools__search` mit Beschreibungen nur von X zählt als Herkunft X; gemischte Beschreibungen zählen als gemischt.
- [ ] Herkunft übersteht Gesprächsfortsetzung bzw. Engine-Neustart (Test).
- [ ] Mutationsbelege.
- [ ] Gerätetest-Block `docs/testing/m5/wp201.md`.

## Parallel
- WP200 (identischen Fehlaufruf nicht wiederholen) ändert `tool_round.dart` (`repeatedFailure`, ab :340). Hier `_invoke` bzw. `untrustedSeen` (:280–330): abstimmen, vor dem Merge main holen.
