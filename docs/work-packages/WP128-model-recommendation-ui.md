# WP128 – Empfohlene Modelle markieren, Nachfrage bei Ausfall

**Zuordnung:** Folge WP112 (K87). Entscheidung Maintainer 2026-10-22: in der App markieren, welches Modell empfohlen ist; dazu bei Ausfall eines Anbieters eine Nachfrage „Mit <anderem Anbieter> nochmal?“ – nie automatisch (K28 bleibt: Wendelin wechselt nie von selbst das Modell).

## Inhalt
1. **Empfehlungen an einer Stelle** (`wendelin_providers`, Katalog): je Vorlage empfohlene Modell-IDs mit Kurzbegründung (Treffer, p50) und Messdatum (Quelle `docs/notes/model-recommendation.md`): Claude `claude-haiku-5-5`, OpenAI `gpt-5-mini`, Phala `google/gemma-4-31b-it`, Tinfoil `gemma4-31b`, NEAR `Qwen/Qwen3.6-35B-A3B-FP8` (bestes bei NEAR, 51/58, 2,3 s – Begründung nennt ehrlich „schwächer als Phala/Tinfoil“); Mistral, OpenRouter, Ollama, eigener Endpunkt: keine (nicht gemessen). `suggestedModel` von Phala, Tinfoil und NEAR entsprechend korrigieren (NEAR heute glm-5.3-flash: gibt Denktext aus, p50 10,6 s).
2. **Modellschritt** (`app/lib/ui/settings/provider_setup/model_step.dart`) und Modellwechsel eines bestehenden Providers: Plakette „Empfohlen“ + Begründung, empfohlene oben, vorausgewählt, falls in der geladenen Liste; freie Wahl bleibt. Texte in ARB (de/en/fr).
3. **Nachfrage bei Ausfall:** Scheitert eine Anfrage am Anbieter (Zeitüberschreitung, 5xx, Netzwerk, TEE-Prüfung fehlgeschlagen – nicht bei Nutzerabbruch oder Budgetgrenze), bietet die App einen eingerichteten anderen Anbieter mit **mindestens gleicher Datenschutzstufe** an (Reihenfolge: empfohlene zuerst). Chat: Schaltfläche „Mit <Name> nochmal?“; Sprache: kurze Frage, „Ja“ → erneut. Neu ausgeführt wird nur der Modellaufruf; bereits ausgeführte Tools werden nie wiederholt (Hinweis im Verlauf wie bei der früheren Eskalation). Eintrag im Audit-Log. Kein passender Anbieter → nur die Fehlermeldung wie heute.
4. Konzept: Nachtrag zu K28/K87 (Orchestrator trägt ein).

## Abnahmekriterien
- [ ] Plakette und Reihenfolge per Widget-Test/Golden; Empfehlungsliste mit Test (jede ID gehört zu einer Vorlage).
- [ ] Nachfrage: Tests für Datenschutzstufe (privat → nie Cloud), keine Tool-Wiederholung, kein Angebot bei Abbruch/Budget, Sprach-„Ja“/„Nein“; Mutationsbeleg.
- [ ] E2E (Emulator, nach Freigabe Orchestrator): Fake-Provider fällt aus → Angebot → zweiter Fake antwortet.
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE; Gerätetest-Block für das laufende Testprotokoll (`docs/testing/m5/wp128.md`).
