# WP03 – Tool-Laufzeit (`packages/wendelin_tools`)

Abhängig von: `wendelin_core`. Konzept-Bezug: „Tool-System“ (Registry, Risikostufen, Bestätigung, Tool-Auswahl bei vielen Tools), „Sicherheit → Prompt-Injection“.

## Inhalt
- `ToolRegistry implements ToolCatalog`
  - `registerIntegration(Integration)`, `unregister(id)`, Integrationen aktivieren/deaktivieren, einzelne Tools an/aus, Status je Integration (`IntegrationStatus`) aus Verfügbarkeit + Setup + Aktivierung + Fehlerzustand.
  - Validiert Tool-Namen (`isValidToolName`), lehnt Duplikate ab.
  - `activeSpecs()` liefert nur Tools aktiver, eingerichteter Integrationen, stabil sortiert (für Prompt Caching).
  - Filter nach Datenschutz: `activeSpecsFor(PrivacyLevel)` – Tools sensibler Integrationen nur an Provider ≥ eingestellter Mindeststufe.
  - Ab einer Schwelle (Standard 30 aktive Tools) liefert `activeSpecs()` nur das Meta-Tool `tools__search` + Kategorien; `tools__search` gibt passende Specs zurück und schaltet sie für die Sitzung frei.
  - `Stream<void> changes` für die UI.
- `RiskPolicy` – Standard pro Stufe (read: frei, write: frei mit Undo, external: immer bestätigen), Override pro Tool (nur **verschärfen** für external; read/write können auf „bestätigen“ gesetzt werden), `lockExternal(sessionId)` (für TEE-Fehlschlag), Ergebnis `PolicyDecision { allow, confirm, deny(reason) }`.
- `ArgumentValidator` – JSON-Schema-Teilmenge: `type` (object, string, number, integer, boolean, array), `properties`, `required`, `enum`, `items`, `minimum/maximum`, `minLength/maxLength`, `format: date-time` (ISO 8601), `additionalProperties: false`. Liefert lesbare Fehlermeldung fürs Modell.
- `ToolExecutor implements ToolInvoker`
  - Für jeden Call: unbekanntes Tool → Fehler-Outcome; ungültiges JSON → Fehler-Outcome mit Hinweis; Schema-Validierung; Policy; ggf. `ConfirmationNeeded` und auf Antwort warten (Ablehnung → Outcome „Nutzer hat abgelehnt“, `isError: false`); Ausführung mit Timeout (Standard 20 s); Exceptions → `isError` mit lesbarer Meldung, kein Stacktrace ans Modell.
  - Unabhängige Calls parallel; Reihenfolge der Ergebnisse = Reihenfolge der Calls. Bestätigungen werden nacheinander angefragt (nie zwei Karten gleichzeitig).
  - Ergebnis-Kürzung: Text > N Zeichen (Standard 8000) wird gekürzt und mit `[gekürzt: x von y Zeichen]` markiert.
  - Tool-Ergebnisse werden in eine Datenhülle gesetzt (`<tool_data>…</tool_data>`-artige Kennzeichnung), damit das Modell sie als Daten behandelt.
  - Audit-Hook: `ToolAuditSink`-Interface (callId, tool, args, Entscheidung, Status, Dauer) – Implementierung kommt aus Storage/App.
- `UndoManager` – hält `UndoAction`s 10 s (über `Clock`/Timer injizierbar), `undo(callId)`, verfällt danach, Stream für Countdown.

## Abnahmekriterien
- [ ] external-Tool wird ohne Bestätigung **nie** ausgeführt, auch wenn Policy-Override es versucht zu lockern (Test).
- [ ] Gesperrte Session (`lockExternal`) → external `deny`.
- [ ] Parallelität nachgewiesen (zwei 100-ms-Tools < 180 ms mit Fake-Clock oder echter Zeit), Bestätigungen sequenziell.
- [ ] Tabellentests ArgumentValidator (≥ 25 Fälle).
- [ ] Meta-Tool-Modus ab Schwelle getestet.
- [ ] Gate grün, Abdeckung ≥ 85 %.
