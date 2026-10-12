# Wendelin-Evals (`wendelin_evals`)

Modell-Eval nach dem Gesamtkonzept („Teststrategie → Modell-Eval“): typische
Sprachbefehle laufen durch die **echte Agent-Schleife** (`AgentRunner`,
`ToolRegistry`, `ToolExecutor`, eingebaute Integrationen) mit **Fake-Ports**
(Kalender, Zwischenablage, Wecker, Gedächtnis, Websuche und -abruf ohne
Netz). Gemessen werden Trefferquote, Latenz (p50/p90), Tokens und Kosten,
gesamt und pro Sprache. Grundlage für die Wahl des Default-Modells.

## Aufruf

Im Verzeichnis `evals/`:

```sh
# Offline-Probelauf mit dem FakeLlmProvider (kein Key, kein Netz)
dart run wendelin_evals:run --profile profiles/fake-demo.json --out reports/fake.local.json

# Live gegen Claude Haiku (Key nur aus der Umgebung)
set -a; . ~/.wendelin-live.env; set +a
dart run wendelin_evals:run --profile profiles/claude-haiku.json --limit 5 --out reports/haiku.local.json
```

| Option | Bedeutung |
| --- | --- |
| `--profile, -p` | Profil-JSON (Pflicht, siehe unten) |
| `--model, -m` | anderes Modell als `defaultModel` |
| `--cases, -c` | Filter, kommagetrennt: Sprache (`de`), Kategorie (`calendar`) oder Teil der Fall-Id (`tauchen`, ab 3 Zeichen) |
| `--cases-dir` | Verzeichnis mit `*.yaml` (Standard `cases`) |
| `--limit, -n` | höchstens n Fälle |
| `--out, -o` | JSON-Report schreiben (`reports/*.local.json` ist von Git ausgenommen) |
| `--now` | fester „heute“-Zeitpunkt, Standard `2026-10-14T09:00` (Mittwoch) |
| `--time-zone` | IANA-Zone, Standard `Europe/Berlin` |
| `--include-pending` | auch Fälle mit `pending: true` laufen lassen |

Ausgabe: eine Zeile je Fall (Status, ms, Tokens, Kosten in Mikro-USD,
Hinweise wie `aufgegeben`/`eskaliert(...)` und der erste Fehlgrund), danach
eine Tabelle pro Sprache und gesamt. Der JSON-Report enthält dieselben
Daten plus alle Tool-Aufrufe mit Argumenten und die Endantwort je Fall.

## Profile und Keys

Ein Profil ist ein `ProviderProfile`-JSON wie in der App, **ohne Keys**.
Der API-Key kommt ausschließlich aus einer Umgebungsvariable:

| Profil | Typ | Variable |
| --- | --- | --- |
| `profiles/claude-haiku.json` | Anthropic, `claude-haiku-5-5` | `ANTHROPIC_API_KEY` |
| `profiles/openai-mini.json` | OpenAI, `gpt-5-mini` | `OPENAI_API_KEY` |
| `profiles/phala-tee-small.json` | Phala/RedPill (TEE), `qwen/qwen-2.5-7b-instruct` | `PHALA_API_KEY` |
| `profiles/fake-demo.json` | Fake-Provider mit Skript | – |

Ist `authMethod.secretRef` ein Variablenname (`ANTHROPIC_API_KEY`), gilt
dieser; sonst entscheidet der Typ (Anthropic → `ANTHROPIC_API_KEY`,
RedPill/Phala → `PHALA_API_KEY`, sonst `OPENAI_API_KEY`). Werte, die wie
Keys aussehen, lehnt der Profil-Parser ab. Zusätzliche Eval-Schlüssel:

- `catalog`: Preise für Modelle, die nicht im eingebauten Katalog stehen
  (Format von `ModelCatalog.mergeJson`, USD pro Million Tokens). Ohne Preis
  bleibt die Kosten-Spalte `?` (Phala-Modelle stehen nicht im Katalog).
- `escalationModels`: stärkere Modelle desselben Profils als
  Eskalationskette. Ohne Kette wird nicht eskaliert, „kann ich nicht“ wird
  trotzdem im Report vermerkt.
- `script`: nur für `type: fake`, Pfad zum Fake-Skript (relativ zum Profil).

## Fälle (`cases/*.yaml`)

40 aktive Fälle (de 20, fr 10, en 10) zu Kalender (u. a. „Trag mir morgen
um 10 Tauchen ein“), Wecker/Timer, Gedächtnis, Zwischenablage, Web, reinen
Textfragen, Smalltalk ohne Tool und je einem `external`-Löschen pro
Sprache. `lists.yaml` enthält zwei Fälle für die Listen-Integration (K6),
die bis zu deren Merge `pending: true` sind.

```yaml
language: de
cases:
  - id: de-cal-tauchen
    category: calendar
    prompt: Trag mir morgen um 10 Tauchen ein
    setup:                     # optional: Zustand der Fake-Ports
      events: [{id: evt-1, title: Zahnarzt, start: "+1d 15:00", end: "+1d 16:00"}]
      clipboard: "Text"
      memory: [{text: "Mag keinen Koriander", category: preference}]
      search_results: [{title: T, url: "https://example.org", snippet: S}]
    expect:
      calls:                   # jeder Eintrag muss von einem Aufruf erfüllt werden
        - tool: calendar__create_event
          args:
            title: {contains: Tauchen}
            start: {at: "+1d 10:00"}
        - any_of:              # Alternativen
            - tool: calendar__find_free_slots
            - tool: calendar__list_events
      no_tools: true           # statt calls: gar kein Tool erlaubt
      forbid: [calendar__delete_event]
      exact: false             # true: keine weiteren Tools
      confirmed: true          # eine Bestätigung muss angefragt worden sein
      text: {contains: "391"}  # Prädikat auf die Endantwort
    pending: false
```

Zeitangaben sind relativ zum festen „heute“: `today`, `tomorrow`,
`+Nd`/`-Nd`, Wochentag `mon`…`sun` (nächster nach heute), `YYYY-MM-DD`,
jeweils optional mit ` HH:MM`.

Prädikate (mehrere Schlüssel = und):

| YAML | Bedeutung |
| --- | --- |
| `Tauchen`, `600`, `[1, 2]` | gleich (Text ohne Groß/Klein, Zahlen auch als Text, Listen ohne Reihenfolge) |
| `{contains: a}`, `{contains: [a, b]}` | enthält alle (bei Listen: je ein passendes Element) |
| `{contains_any: [a, b]}` | enthält mindestens einen |
| `{matches: "regex"}` | regulärer Ausdruck |
| `{at: "+1d 10:00", tol_min: 0}` | Zeitpunkt (Model-Werte mit Offset werden in die Zone umgerechnet) |
| `{date: sat}` | nur das Datum |
| `{clock: "07:30"}` | Uhrzeit `H:MM` |
| `{min: 1, max: 5}` | Zahlenbereich |
| `{one_of: [a, b]}`, `{any_of: [p, q]}`, `{not: p}`, `{present: false}` | Kombinationen |

## Bewertung

- **passed**: alle Erwartungen erfüllt; **failed**: mit Gründen;
  **error**: der Agent ist abgebrochen (`AgentFailed`, z. B. Provider-Fehler,
  Limit); **skipped**: `pending`.
- Bestätigungen (`external`-Tools, Eskalation unter die Datenschutzstufe)
  werden automatisch mit „ja“ beantwortet und gezählt.
- `gaveUp`: Der `GiveUpClassifier` des Agenten hat eine Antwort als
  „kann ich nicht“ erkannt (Eskalation mit Grund `modelGaveUp` oder
  Endantwort). `escalations`: Ziel und Grund jeder Eskalation.
- Kosten über `CostCalculator` je Modellaufruf; fehlt ein Preis, ist die
  Fall-Kosten `null` und die Summe mit `+?` markiert.

## Entwicklung

Die Bewertungslogik ist eine Bibliothek (`lib/src/`) und unabhängig von
echten Providern getestet (`dart test`, Abdeckung ≥ 85 % im Gate). Der
Test `cli_test.dart` führt den Fake-Probelauf aus und prüft den Report.
Live-Läufe sind keine Tests; Reports mit echten Läufen nicht committen.
