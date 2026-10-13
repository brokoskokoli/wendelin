# WP21 – Routing-Regeln und Eskalationsketten (`packages/wendelin_agent/lib/src/routing/`)

Abhängig von: core, agent (bestehend). Andockpunkt: `ProviderResolver`/`Resolution`/`DefaultProviderResolver` in `wendelin_agent/lib/src/provider_resolver.dart` (heute: ein Default-Ziel, eine globale Kette, `isPrivate`-Callback aus `app/lib/di/provider_config.dart`). Konzept-Bezug: „Routing und Eskalation“ (Regeln vor dem Start, Bedingungen, Eskalation, Datenschutz-Grenze, Regel-Editor: Speicherung als JSON), K8 (d), K10 (a–c), Teststrategie „Routing: Tabellentests Satz → erwartete Regel“. Rein Dart, keine App-Dateien.

## Inhalt
- **Modell**: `RoutingRule { id, name, enabled, condition, target: { profileId, modelId }, stripTrigger }`; Reihenfolge der Liste = Priorität (erste passende gewinnt), Default-Regel fest am Ende. `RuleSet { rules, defaultTarget, chains: Map<profileId, List<target>> }` (Eskalationskette **pro Profil** laut Konzept; die heutige globale Kette wird beim Laden zur Kette des Default-Profils, Migrationsfunktion mit Test).
- **Bedingungen** als `sealed class Condition` mit `and`/`or`/`not` und einer `ConditionType`-Registry (Name → Decoder/Encoder), damit neue Typen ohne Umbau dazukommen:
  `keyword`, `prefix`, `regex` (auf dem normalisierten Transkript: Groß/Klein, Umlaute, Satzzeichen am Anfang wie „Claude, …“), `language`, `sttConfidence < x`, `inputLength > n`, `hasImage`, `network` (online/offline/metered), `timeWindow` (Wochentage + Uhrzeit, über Mitternacht), `needsTool` (Kategorie, z. B. `obsidian.edit`), `privacy` (markiert die Route als privat).
- **Auswertung** über `RoutingContext { UserInput input, DateTime now, NetworkState network, ToolCategoryMatcher matcher }`; Uhr und Netz injiziert (kein `DateTime.now()`). `needsTool` über ein Interface `ToolCategoryMatcher` mit Standardimplementierung per Schlüsselwortlisten (de/fr/en) je Kategorie `<integration>` bzw. `<integration>.read|edit` – kein Modellaufruf.
- **`stripTrigger`**: entfernt das auslösende Präfix/Schlüsselwort aus dem Text, der ans Modell geht („Claude, trag … ein“ → „trag … ein“); der angezeigte und gespeicherte Nutzertext bleibt unverändert. Liefert der Resolver dafür den bereinigten Text (`Resolution.effectiveText` o. ä.), ohne `UserInput` zu verändern.
- **`RuleBasedProviderResolver implements ProviderResolver`**: wählt die erste passende aktive Regel, sonst Default; `Resolution.reason` = Regelname (landet über `Routed` im Audit-Log). Regeln mit gelöschtem oder deaktiviertem Zielprofil werden übersprungen und als Warnung gemeldet (`RuleSetIssue`). Eskalation läuft die Kette **des Profils der gewählten Route**; Datenschutz-Untergrenze bei `privacy`-Route = Stufe des Regelziels, bleibt über alle Eskalationen gleich (K8 d), Bestätigung unterhalb über das bestehende `EscalationConfirmationRequired`.
- **„nochmal mit …“**: `UserInput.requestEscalation` bleibt; zusätzlich Erkennung eines Zielnamens („nochmal mit Claude“, „encore avec …“, „again with …“) über Profilnamen bzw. Aliase der Regeln → direktes Ziel statt nächstem Kettenglied (gleiche Datenschutzprüfung).
- **Prüfwerkzeug für das Testfeld**: `explain(RuleSet, RoutingContext)` liefert gewählte Regel, Ziel, ggf. übersprungene Regeln mit Grund – Grundlage für das Testfeld im Editor (WP26).
- **Validierung**: Regex nur bis 200 Zeichen, ungültige Regex → Regel ungültig (nicht Absturz); Eingabetext für Regex auf 2 000 Zeichen begrenzt (Laufzeitschutz); `privacy`-Regel mit Ziel unter `tee` → Warnung `RuleSetIssue.privacyTargetTooWeak`.
- **JSON**: Import/Export des `RuleSet` mit Schema-Version, unbekannte Bedingungstypen → verständlicher Fehler, Rundreise verlustfrei; enthält nur Profil-Ids, keine Secrets.
- ADR 0009 „Routing-Regeln“ (Normalisierung, `needsTool` ohne Modell, `stripTrigger` nur für den Modelltext, Kette pro Profil, Migration der globalen Kette).

## Abnahmekriterien
- [ ] Tabellentests „Satz → erwartete Regel“ mit ≥ 30 Fällen (de/fr/en), mindestens die Konzeptbeispiele: Präfix „Claude“/„Fable“, „privat“, offline, `needsTool = obsidian.edit`, Default; inkl. Groß/Klein, Satzzeichen, Präfix mitten im Satz (greift nicht), deaktivierte Regel.
- [ ] Jeder Bedingungstyp einzeln tabellengetestet, dazu `and`/`or`/`not` verschachtelt; `timeWindow` über Mitternacht und Wochentagsgrenze mit Fake-Uhr.
- [ ] `stripTrigger` getestet: Modelltext bereinigt, gespeicherter Text unverändert, leerer Rest („Claude.“) ergibt keine leere Anfrage (Originaltext bleibt).
- [ ] Eskalation: Kette pro Profil, Privacy-Floor über mehrere Eskalationen gleich, Ziel unter Floor nur mit Bestätigung, „nochmal mit Claude“ springt zum benannten Ziel; bestehende Agent-Tests (`DefaultProviderResolver`) bleiben grün.
- [ ] Migration „globale Kette → Kette des Default-Profils“ getestet.
- [ ] JSON-Rundreise (Property-artig über erzeugte Regelbäume) und Fehlerfälle (unbekannter Typ, kaputte Regex, fehlende Felder).
- [ ] `explain` liefert übersprungene Regeln mit Grund (Tabellentest).
- [ ] Fakes (`FakeToolCategoryMatcher`, feste `NetworkState`) unter `lib/testing/`, exportiert über `package:wendelin_agent/fakes.dart`.
- [ ] ADR 0009; Gate grün, Abdeckung `wendelin_agent` ≥ 85 %.
