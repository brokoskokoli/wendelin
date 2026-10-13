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
| `--now` | fester „heute“-Zeitpunkt, Standard `2026-11-18T09:00` (Mittwoch; bewusst nicht nahe am Beispieldatum 2026-10-15 der Tool-Beschreibungen) |
| `--time-zone` | IANA-Zone, Standard `Europe/Berlin` |
| `--include-pending` | auch Fälle mit `pending: true` laufen lassen |

Strg+C beendet den Lauf nach dem laufenden Fall: die restlichen Fälle
werden als „abgebrochen“ übersprungen, Tabelle und Teilreport
(`meta.interrupted: true`) werden trotzdem geschrieben, Exit-Code 130. Ein
zweites Strg+C bricht sofort ab.

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
| `profiles/phala-tee-small.json` | Phala/RedPill (TEE), `qwen/qwen-2.5-7b-instruct` (Preise weiterer TEE-Modelle im Profil) | `PHALA_API_KEY` |
| `profiles/fake-demo.json` | Fake-Provider mit Skript | – |

Ist `authMethod.secretRef` ein Variablenname (`ANTHROPIC_API_KEY`), gilt
dieser; sonst entscheidet der Typ (Anthropic → `ANTHROPIC_API_KEY`,
RedPill/Phala → `PHALA_API_KEY`, sonst `OPENAI_API_KEY`). Werte, die wie
Keys aussehen, lehnt der Profil-Parser ab (Key-Muster irgendwo im Wert,
Felder wie `apiKey`, `token`, `secret`, `password`, geheim wirkende
`extraHeaders` wie `Authorization` oder `Bearer …`). Die Option
`enableServerWebSearch: true` ist für Evals nicht erlaubt: ihre Gebühren
je Suche erfasst der `CostCalculator` nicht, und die Fälle prüfen
`web__search`. Zusätzliche Eval-Schlüssel:

- `catalog`: Preise für Modelle, die nicht im eingebauten Katalog stehen
  (Format von `ModelCatalog.mergeJson`, USD pro Million Tokens). Ohne Preis
  bleibt die Kosten-Spalte `?` (Phala-Modelle stehen nicht im Katalog);
  das CLI warnt dann vor dem Lauf.
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
          succeeded: true      # Standard: nur fehlerfreie Aufrufe zählen
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

Erwartete Werte weichen bewusst von den Beispielen in den
Tool-Beschreibungen ab (dort u. a. `2026-10-15T10:00`, 600 s, 90 s, 06:45,
`[1,2,3,4,5]`), damit ein Modell sie nicht zufällig richtig abschreibt
(geprüft in `test/repo_cases_test.dart`).

Zeitangaben sind relativ zum festen „heute“: `today`, `tomorrow`,
`+Nd`/`-Nd`, Wochentag `mon`…`sun` (nächster nach heute), `YYYY-MM-DD`,
jeweils optional mit ` HH:MM`.

Prädikate (mehrere Schlüssel = und):

| YAML | Bedeutung |
| --- | --- |
| `Tauchen`, `600`, `[1, 2]` | gleich (Text ohne Groß/Klein, Zahlen auch als Text, Listen ohne Reihenfolge) |
| `{contains: a}`, `{contains: [a, b]}` | enthält alle (bei Listen: je ein passendes Element); ohne Groß/Klein und Akzente |
| `{contains_any: [a, b]}` | enthält mindestens einen |
| `{matches: "regex"}` | regulärer Ausdruck |
| `{at: "+1d 10:00", tol_min: 0}` | Zeitpunkt (Model-Werte mit Offset werden in die Zone umgerechnet) |
| `{date: sat}` | nur das Datum |
| `{clock: "07:30"}` | Uhrzeit `H:MM` |
| `{min: 1, max: 5}` | Zahlenbereich |
| `{one_of: [a, b]}`, `{any_of: [p, q]}`, `{not: p}`, `{present: false}` | Kombinationen |

## Bewertung

- Ein Tool-Aufruf erfüllt eine Erwartung nur, wenn das Tool ihn **ohne
  Fehler** ausgeführt hat (`succeeded: false` je Option lässt auch
  Fehler zu).
- **passed**: alle Erwartungen erfüllt; **failed**: mit Gründen;
  **error**: der Agent ist abgebrochen (`AgentFailed`, z. B. Provider-Fehler,
  Limit); **skipped**: `pending`.
- Kontext wie in der App: relevante Gedächtnis-Einträge kommen über die
  Suche im (Fake-)Speicher in den System-Prompt; die Gerätesprache folgt
  der Fall-Sprache (`de-DE`, `fr-FR`, `en-US`).
- Bestätigungen von `external`-Tools werden automatisch mit „ja“
  beantwortet und als `confirmations` gezählt (Tabelle: Spalte
  „bestätigt“). Bestätigungen einer Eskalation unter die Datenschutzstufe
  zählt `escalationConfirmations` (Tabelle: `+nE`). Das CLI routet nicht
  privat, daher kommen sie dort derzeit nicht vor; programmatisch lässt
  sich das mit `EvalTarget(privateRequests: true, escalationPrivacy: …)`
  durchspielen.
- `gaveUp`: Der `GiveUpClassifier` des Agenten hat eine Antwort als
  „kann ich nicht“ erkannt (Eskalation mit Grund `modelGaveUp` oder
  Endantwort). `escalations`: Ziel und Grund jeder Eskalation.
- Latenz-Perzentile (nearest rank) nur über Fälle, deren Agent-Lauf
  tatsächlich stattfand (nicht über übersprungene oder nicht aufgebaute).
- Kosten über `CostCalculator` je Modellaufruf; fehlt ein Preis, ist die
  Fall-Kosten `null` und die Summe mit `+?` markiert.

## Entwicklung

Die Bewertungslogik ist eine Bibliothek (`lib/src/`) und unabhängig von
echten Providern getestet (`dart test`, Abdeckung ≥ 85 % im Gate). Der
Test `cli_test.dart` führt den Fake-Probelauf aus und prüft den Report.
Live-Läufe sind keine Tests. Probeläufe als `reports/*.local.json`;
committet werden nur dokumentierte Läufe (`reports/<datum>-<profil>.json`)
mit Auswertung in [`reports/README.md`](reports/README.md).

Der Live-Durchlauf des M1-Satzes („Trag mir morgen um 10 Tauchen ein“ mit
allen drei Live-Profilen durch die echte Agent-Schleife) und Proben zum
Verlauf mit ausgeblendeten Tool-Aufrufen (WP14) liegen in
`test/live/dod_live_test.dart`:

```sh
set -a; . ~/.wendelin-live.env; set +a
dart test test/live -t live --run-skipped
```
