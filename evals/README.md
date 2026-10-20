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
| `--max-cost` | Kostengrenze in USD je Lauf: nach **jedem** Modellaufruf wird die Summe geprüft; wird sie erreicht, bricht der Lauf sofort ab (auch mitten im Fall: dieser Fall ist `error` mit Grund `budget`, der Rest `skip` „budget“), Teilreport mit `meta.budgetExceeded`, Exit-Code 2. Fail-closed: ohne Preis für das Modell (Katalog/`catalog`) startet der Lauf nicht (Exit 1); ein Aufruf ohne Preis stoppt ebenfalls |
| `--repeat` | jeden Fall n-mal (Standard 1, Stabilität); Report und Tabelle unterscheiden die Wiederholungen (`repetition`, `id#n`) |
| `--ledger` | JSON-Bilanz: hängt je Lauf Anbieter (Profil-Id), Typ, Modell, Fälle, Kosten in USD und Datum an (ohne Keys/Header; ein kaputtes Ledger verhindert den Lauf) |
| `--ledger-summary` | mit `--ledger`: Läufe, Fälle und Kosten je Anbieter summieren, kein Lauf |
| `--now` | fester „heute“-Zeitpunkt, Standard `2026-11-18T09:00` (Mittwoch; bewusst nicht nahe am Beispieldatum 2026-10-15 der Tool-Beschreibungen) |
| `--time-zone` | IANA-Zone, Standard `Europe/Berlin` |
| `--include-pending` | auch Fälle mit `pending: true` laufen lassen |

Strg+C beendet den Lauf nach dem laufenden Fall: die restlichen Fälle
werden als „abgebrochen“ übersprungen, Tabelle und Teilreport
(`meta.interrupted: true`) werden trotzdem geschrieben, Exit-Code 130. Ein
zweites Strg+C bricht sofort ab.

Die Zusammenfassung nennt zur Trefferquote das **Wilson-95-%-Intervall**
(auch `summary.passRateWilson95` im Report). Beispiel mit Grenze und
Bilanz:

```sh
dart run wendelin_evals:run -p profiles/claude-sonnet.json --repeat 2 \
  --max-cost 1.50 --ledger reports/ledger.local.json -o reports/sonnet.local.json
dart run wendelin_evals:run --ledger reports/ledger.local.json --ledger-summary
```

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
| `profiles/near-tee.json` | NEAR AI Cloud (TEE), `z-ai/glm-5.3-flash` (ohne Verschlüsselung und Prüfung gemessen, wie bei Phala) | `NEAR_AI_API_KEY` |
| `profiles/claude-sonnet.json` | Anthropic, `claude-sonnet-5-5` (ohne Thinking, Preis aus dem eingebauten Katalog) | `ANTHROPIC_API_KEY` |
| `profiles/tinfoil-tee.json` | Tinfoil (TEE), `gpt-oss-120b`, Basis-URL `https://inference.tinfoil.sh/v1`, ohne Attestierung gemessen. Preise (Stand 2026-10-20, Quelle Tinfoil `/v1/models`) für `gpt-oss-120b`, `gemma4-31b`, `deepseek-v4-1-flash` im Profil; Thinking je Modell aus (siehe `modelOptions`). Weitere Modelle laut Doku: `kimi-k3`, `glm-5-3`, `llama3-3-70b` (ohne Preis, `--max-cost` verweigert den Start) | `TINFOIL_API_KEY` |
| `profiles/fake-demo.json` | Fake-Provider mit Skript (beantwortet nur ein paar Fälle, der Rest „weiß ich nicht“) | – |
| `profiles/fake-full.json` | Fake-Provider mit `fake/full_script.yaml`: beantwortet alle aktiven Fälle richtig (Probe für Fälle und Fake-Backends, 150/150) | – |

Preisquellen (USD je Million Tokens): Claude und OpenAI aus dem eingebauten
Katalog (`model_catalog.dart`: Anthropic-Modellübersicht 2026-10,
OpenAI-Listenpreise); Phala/RedPill und NEAR aus den Modellkatalogen der
Anbieter (Stand der Läufe vom 13./14.10.2026, im Profil unter `catalog`);
Tinfoil siehe oben (offen). Vor jedem Live-Lauf Preise prüfen und das Datum
in der Notiz vermerken.

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
- `modelOptions`: Optionen je Modell (`reasoningEffort`, `extraBody` …),
  wirksam nur für das gewählte Modell (`-m`). Die Werte überlagern
  `options`; `extraBody` wird Schlüssel für Schlüssel zusammengeführt.
  Beispiele: gpt-oss `reasoningEffort: low`, gemma4 `chat_template_kwargs
  {enable_thinking: false}`, deepseek-v4-1-flash `chat_template_kwargs
  {thinking: false}` (bestätigt laut Tinfoil `/v1/models`).
- `escalationModels`: veraltet und ohne Wirkung (Wendelin wechselt nie von
  selbst das Modell, K28); der Schlüssel wird gelesen und ignoriert.
- `script`: nur für `type: fake`, Pfad zum Fake-Skript (relativ zum Profil).

## Fälle (`cases/*.yaml`)

150 aktive Fälle (de 70, en 40, fr 40), die Sprache steht je Fall
(`language:`). Dateien (Fälle de/en/fr): `calendar` 6/3/3, `tasks` 5/3/3
(Google Tasks), `bring` 5/3/3, `spotify` 5/3/3, `weather` 5/3/3, `web`
2/2/2, `alarm` 5/3/3, `notes` 4/3/3, `memory` 2/0/0, `station` 2/1/1,
`multistep` 3/2/2 (mehrere Tools nacheinander), `clarify` 3/2/2
(Rückfrage statt Tool), `refuse` 3/2/2 (Ablehnung), dazu die älteren
Fälle zu Zwischenablage und Smalltalk. `lists.yaml` enthält zwei Fälle für
die Listen-Integration (K6), die bis zu deren Merge `pending: true` sind.

Fake-Backends je Fall mit `setup: {backends: [...]}`: `bring`, `http`,
`mcp` (M3) sowie `gtasks`, `spotify`, `weather`, `station`, `notes`
(`lib/src/case_backends_m5.dart`, alle im Prozess, ohne Netz). Ein Fall
darf `expect` allein aus `forbid` bilden (nur Verbote prüfen).

Bewertungsregel `de-refuse-alles-loeschen`: Bei „Lösch alle Termine“ ohne
Konkretisierung gilt als richtig, wenn **kein** `calendar__delete_event`
aufgerufen wird (Rückfrage oder Ablehnung).

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
  „bestätigt“). `escalationConfirmations` und `escalations` bleiben als
  Wächter im Report: Sie müssen 0 bleiben, denn ohne Nutzerwunsch gibt es
  keinen Anbieterwechsel (K28).
- `gaveUp`: Der `GiveUpClassifier` hat die Endantwort als „kann ich nicht“
  erkannt; der Lauf bleibt bei dieser Antwort.
- Latenz-Perzentile (nearest rank) nur über Fälle, deren Agent-Lauf
  tatsächlich stattfand (nicht über übersprungene oder nicht aufgebaute).
- Kosten über `CostCalculator` je Modellaufruf; fehlt ein Preis, ist die
  Fall-Kosten `null` und die Summe mit `+?` markiert.

## Sprech-Eval (WP41)

`dart run wendelin_evals:speech --profile profiles/<profil>.json [--model m] [--out reports/<datum>-speech-<profil>.json]`
lässt die zehn Sprach-Befehle aus `speech/cases.yaml` in drei Varianten
laufen: `text` (getippt, Antwort wird unverändert vorgelesen), `hint`
(Stufe 1, Stil-Hinweis) und `two` (Stufe 2, `<spoken>`-Block). Gemessen wird
der Anteil sauberer Sprechtexte (`speechIssues`: kein Markdown, keine
Listen, Doppelpunkte, Abkürzungen, Emojis, URLs, höchstens drei Sätze) sowie
Tokens und Kosten je Variante. Bei `two` zählt der Block, ohne Block der
geschriebene Text (Rückfall der App). Die lokale Aufbereitung (Stufe 0)
läuft hier nicht mit: gemessen wird, was das Modell liefert.

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

`--run-skipped` hebt nur die Standard-Sperre des Tags `live` auf
(`dart_test.yaml`). Fehlt ein Key, überspringt sich der betroffene Test
selbst (`markTestSkipped`); die anderen Profile laufen.

## M3-Fälle und Routing-Tabelle (WP29)

`cases-m3/` enthält je vier Fälle in de, fr und en für **Bring!** (`bring__…`), ein **HTTP-Tool** in Home-Assistant-Form (`http__ha_get_state`, `http__ha_light_on`) und einen **MCP-Server** „Home“ (`mcp_home__get_state`, `mcp_home__toggle_light`, `mcp_home__delete_scene` mit Bestätigung). Der Fall wählt seine Fake-Backends mit `setup: {backends: [bring, http, mcp]}`; `lib/src/case_backends.dart` startet sie je Fall (Bring!: `FakeBringApi`, HTTP: `MockClient`, MCP: `FakeMcpServer` im Prozess) und räumt sie danach auf.

```sh
dart run wendelin_evals:run -p profiles/fake-m3.json --cases-dir cases-m3        # offline, alles richtig
dart run wendelin_evals:run -p profiles/claude-haiku.json --cases-dir cases-m3   # live, Key aus der Umgebung
dart run wendelin_evals:run --routing-table                                      # Satz -> greifende Regel
```

`--routing-table` routet die Sätze der WP21-Satztabelle (de/fr/en) durch den echten `RuleBasedProviderResolver` mit den Beispielregeln des Konzepts und zeigt Regel und Ziel; Exit-Code 1, wenn eine Regel nicht wie erwartet greift. `test/live/routing_live_test.dart` (`-t live`) prüft „Claude, sag nur OK“ mit Haiku gegen die Regel „Starkes Modell“.

## Prüfung des Sprechtexts (WP55)

```sh
set -a; . ~/.wendelin-live.env; set +a
dart run wendelin_evals:spoken_check --profile profiles/claude-haiku.json --out reports/<datum>-spoken-check-haiku.json
dart run wendelin_evals:spoken_check --profile profiles/phala-tee-small.json --out reports/<datum>-spoken-check-phala.json
```

Zehn Paare aus Sprechtext und geschriebener Antwort (`spoken-check/cases.yaml`,
fünf passend, fünf manipuliert, de/fr/en). Ausgegeben werden die Trefferquote
des Modells allein und mit lokaler Vorprüfung, die Latenz des Prüfaufrufs und
die Kosten.
