# WP10 – Modell-Evals (`evals/`)

Dart-CLI. Abhängig von: core, providers, tools, agent, integrations (mit Fake-Ports). Konzept-Bezug: „Teststrategie → Modell-Eval“.

## Inhalt
- `evals/cases/*.yaml`: 40 typische Befehle (de ~20, fr ~10, en ~10) mit erwarteten Tool-Calls (Tool-Name + Argument-Prädikate, z. B. `start` = morgen 10:00 ±0, `title` enthält „Tauchen“) bzw. erwarteter Textantwort ohne Tool. Fester „heute“-Zeitpunkt pro Lauf.
- `dart run evals:run --profile <json> [--model ...] [--cases filter]` – lässt die echte Agent-Schleife mit Fake-Ports laufen (Bestätigungen automatisch „ja“), misst Trefferquote, Latenz (p50/p90), Tokens, Kosten; Ausgabe als Tabelle + JSON-Report.
- Bewertungslogik als Bibliothek mit Unit-Tests (Prädikate, Aggregation), unabhängig von echten Providern; Test-Lauf mit `FakeLlmProvider`.

## Abnahmekriterien
- [ ] Bewertungslogik getestet (≥ 85 %).
- [ ] Probelauf mit Fake-Provider erzeugt Report.
- [ ] README mit Beispielaufruf; Live-Lauf benötigt Key per Env-Variable.
