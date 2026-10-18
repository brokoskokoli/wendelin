# Wendelin: Entwicklungstempo – Analyse (Stand 2026-10-18)

Datenbasis: 184 Gate-Zusammenfassungen aus `tasks/*.output` und `scratchpad/*.log` (davon 105 volle Gates mit Rust),
JSON-Bericht `scratchpad/app.json` (wp90, test/settings) und `app2.json` (laufender Voll-Lauf wp90),
`gh run list`, `git log --since=2026-10-10`, Import-Graph von `app/`. Rechner: M3 Pro mit 11 Kernen und 18 GB RAM, Last 43–45 (etwa vierfach überbucht).
Skripte: `scratchpad/speedup/{steps,slow,fails,impact}.py`.

## 1. Gate-Zeiten und langsamste Tests

| Schritt | n | Median | p90 | Max |
|---|---|---|---|---|
| test app | 177 | 191 s | 751 s | 1500 s |
| test wendelin_integrations | 147 | 127 s | 725 s | 959 s |
| test wendelin_providers | 153 | 51 s | 181 s | 385 s |
| rust test | 105 | 47 s | 187 s | 284 s |
| test evals / agent / mcp / storage / core / voice | ~150 | 25–42 s | 100–155 s | 190–250 s |
| analyze app | 177 | 22 s | 211 s | 551 s |
| rust frb (Codegen) | 105 | 13 s | 215 s | 279 s |
| rust clippy | 105 | 4 s | 112 s | 152 s |
| kotlin-unit | 134 | 0 (meist übersprungen) | 31 s | 1500 s |
| Rest (format, analyze, check_*) | | < 5 s | < 25 s | |

- **Ein volles Gate dauert unter Last 21 bis 105 Minuten** (1284–6279 s). Pro Arbeitspaket laufen 2 bis 4 davon, also **1 bis 4 Stunden Gate je WP**.
- Zum Vergleich: CI (unbelastet) braucht für das gate-Job 7 min (ubuntu, `--no-app`) und für den app-Job 9 min (macOS). Lokal und unbelastet dauerte `flutter test` am 15.10. 3:28 min. **Der Hauptfaktor ist die Rechnerlast**, nicht die Tests selbst.
- App: 143 Testdateien. Im Voll-Lauf entfällt **etwa die Hälfte der Zeit auf das Kompilieren je Testdatei** (Median „loading“ 4,4 s, Summe 436 s gegenüber 426 s Testzeit nach 76 Suiten). Jede Datei ist ein eigenes Entrypoint mit eigener Kompilierung.
- Langsamste App-Tests (unter Last, die Rangfolge ist in beiden Läufen stabil, alles `test/settings/`):
  `http_tools_screen_test` „Anlegen: Speichern registriert…“ 19–30 s, „Validierung“ 7–11 s, „Testlauf gegen MockClient“ 7 s;
  `user_integrations_screen_test` „Übersicht: Routing öffnet…“ 7–16 s; `http_bring_goldens_test` 4–12 s;
  `wake_lifecycle_test` „Kalibrieren…“ 4–12 s; `phala_setup_test` 5–12 s; `wake_word_screen_test` 5–11 s;
  `review_fixes_test` 5–9 s; `attestation_log_screen_test` 9 s; `voice_settings_test` Onboarding 3–9 s; `app_detection_test` 8,5 s;
  `bring_screen_test`, `onboarding_test`, `obsidian_screen_test`, `routing_screen_test`, `lists_and_web_test`: je 4–7 s.
  Dateisummen: http_tools_screen 46–55 s, voice_settings 38–43 s, integrations_screen 26 s, wake_service_section 23 s, routing_screen 21 s.
  Muster: viele `pumpAndSettle` (178 Aufrufe in 26 Dateien) über ganze Settings-Bäume mit echter DB (`runAsync`).

## 2. Flakes (unter Last rot, einzeln grün)

Die Namen sind nur teilweise ermittelbar, weil das 200-Zeilen-Ende bei Rot oft aus Log-Rauschen besteht (siehe 9). „loading …“-Fehler sind Kompilierfehler, keine Flakes.

| Test | Ursache | Fix |
|---|---|---|
| `wendelin_storage/test/usage_timezone_test.dart:16` (11× rot) | `Process.run(dart run probe)` kompiliert je Probe neu; 30 s reichten nicht (a747975 hebt auf 3 min) | Probe einmal in `setUpAll` mit `dart compile kernel` bauen und `.dill` starten, oder Tag `subprocess` (CI hat schon den TZ-Lauf) |
| `wendelin_agent/test/routing/conditions_test.dart:302-308` (agent 9× rot) | `Stopwatch` < 1 s unter Last | Schrittbudget bzw. Komplexitätsprüfung statt Wanduhr; sonst Tag `perf` und nur in CI |
| `app/test/screens/main_attestation_test.dart:24-33` („did not complete“) | `_settle`: 20× `runAsync(delayed 50ms)` als Wartezeit auf die echte DB | Helfer `pumpUntil(cond, timeout: 10s)` in `test/ui/helpers.dart` |
| `app/test/settings/wake_lifecycle_test.dart:121` | `runAsync(delayed 50ms)`, danach `expect(audio.isRunning)` | `pumpUntil` |
| `app/test/voice/wake/wake_barge_in_test.dart` (14 echte Delays, Frames alle 5 ms) | echte Timer und Zeitfenster | `fakeAsync` mit injizierter Uhr bzw. Ticker |
| `app/test/settings/wake_goldens_test.dart:43` | `runAsync` vor dem Golden | Bild erst nach `pumpUntil` und einem festen Frame |
| Stopwatch-Asserts: `platform/saf_vault_port_test:187`, `voice/isolate_exit_test:41`, `voice/whisper_share_test:92`, core (4), mcp (2), tools (1), providers (1) | Wanduhr | wie conditions_test |

Weitere Kandidaten mit echten Delays: app 72 in 23 Dateien (`confirm_by_voice`, `voice_controller`, `early_capture`, `capture_profile`, `record_audio_input`), wendelin_voice 23, wendelin_mcp 11.
`voice_pipeline_test` (WP81) läuft schon unter `fakeAsync`; dort war es ein echter Fehler während der Arbeit, kein Flake.
Jeder Flake kostet einen erneuten Gate-Lauf von 20 bis 70 Minuten.

## 3. Test-Impact-Auswahl (App, `--changed`)

- Ein Import-Scan (relativ und `package:wendelin/`) ist trivial machbar und dauert unter 1 s.
- Ergebnis: Der Median-Test zieht transitiv 264 der 284 lib-Dateien. Eine lib-Datei betrifft im Mittel 53 % der Testdateien.
- An den echten Änderungsmengen (8 Merges seit 15.10. und offene WPs) gemessen: **88 bis 100 von 143 Testdateien** würden laufen, die Ersparnis liegt also bei **30–38 %**. Die langsamen Settings-Tests sind fast immer dabei.
- Die Ursache sind Knoten, die fast alles importieren (Test-Env bzw. DI-Verdrahtung). Mehr Ersparnis bringt erst das Entkoppeln.
- **Lohnender:** Testdateien bündeln. Ein generiertes `test/_bundle/<bereich>_test.dart` importiert 20 bis 40 Dateien und ruft deren `main()` in Gruppen auf. Spart etwa 50 % der Kompilierzeit. Risiko: globaler Zustand und `setUpAll` in den Dateien, Goldens bleiben getrennt.
- Fazit: Impact-Auswahl als Stufe „schnell“ (nur direkt importierende Tests plus geänderte Tests) für Zwischenstände. Die volle App-Suite läuft in CI.

## 4. GitHub Actions

**Stand:** `.github/workflows/gate.yml` existiert (Jobs gate/ubuntu `--no-app`, app/macos-latest, apk). **CI ist seit dem 14.10. durchgehend rot** (60 Läufe, zuletzt 39125112614).
- Ursache: 7 Goldens mit 2876–3381 abweichenden Pixeln (0,5–0,7 %) überschreiten `ciGoldenMaxPixels = 2000` in `app/test/support/golden_tolerance.dart:20`.
- Folge: CI wird ignoriert, alle Beweislast liegt auf lokalen Voll-Gates.
- Nur `main` wird gepusht (12 Commits vor origin), und `main` ist nicht geschützt.

Nötig bzw. besser:
- **Goldens:** macOS-Runner pinnen (`macos-15`, kein `-latest`). Die Referenzbilder erzeugt CI selbst (Workflow `update-goldens` per `workflow_dispatch` lädt die PNGs als Artefakt hoch). Alternativ eine Pixelgrenze relativ zur Bildgröße. Job `goldens` auf macOS mit `--tags golden`.
- **App-Tests:** auf ubuntu mit `--exclude-tags golden,platform-sensitive`, `--coverage` und der di-Schwelle (heute prüft CI die di-Abdeckung gar nicht), 3 Shards (`--total-shards 3 --shard-index i`).
- **Pakete:** Matrix je Paket (8 Pakete + evals) plus Rust-Job (fmt/clippy/test/deny/frb). `kotlin-unit` als eigener ubuntu-Job mit `setup-java cache: gradle` (heute nur im apk-Job).
- **Caching:** `subosito/flutter-action cache: true` und `actions/cache` auf `~/.pub-cache` (Key `pubspec.lock`), `Swatinem/rust-cache` (vorhanden), `taiki-e/install-action` für cargo-deny und frb-codegen (statt `cargo install`, das bei Cache-Miss mehrere Minuten dauert), Gradle.
- **Erwartete Wandzeit:** etwa 6 bis 8 min, wenn alles parallel läuft (bisher 9 bis 12 min).
- **Kosten:** Öffentliches Repo, Standard-Runner (auch macOS) sind kostenlos und ohne Minutenlimit. Im Free-Plan laufen bis zu 20 Jobs gleichzeitig, davon 5 auf macOS. Secrets sind keine nötig (Live-Tests übersprungen).
- **Agenten:** WP-Branch pushen (`git push -u origin wp/<nr>-<slug>`, die Hooks prüfen die Identität weiter). Dann im Hintergrund **einmal** `gh run watch $(gh run list -b <branch> -c $(git rev-parse HEAD) -L1 --json databaseId -q '.[0].databaseId') --exit-status` starten. Das ergibt genau eine Benachrichtigung.
- **Push-Regel (Entscheidung des Maintainers):** Coder pushen nur `wp/*`, nie `main`. Der Merge passiert erst nach grünem CI und Review. Branch-Schutz für `main` mit Pflicht-Checks. Ungeprüfter Code wird damit öffentlich sichtbar; vertretbar bei Open Source, sollte aber bestätigt werden.
- **Lokale Regel danach:** `--changed` während der Arbeit, vor dem Commit `--changed` gegen den Merge-Base, das volle Gate übernimmt CI. Das spart 2 bis 4 lokale Voll-Gates je WP und senkt die Rechnerlast für alle.

## 5. Rust über Worktrees

- 9 `native/attest/target` mit zusammen etwa 12 GB, jeder Worktree baut kalt.
- „Blocking waiting for file lock on package cache“ ist die Sperre auf das gemeinsame `~/.cargo/registry`, nicht auf `target`.
- **sccache** (`brew install sccache`, `RUSTC_WRAPPER=sccache` in `tool/src/gate_rust.dart` und `tool/build_attest_android.sh`, `CARGO_INCREMENTAL=0`): teilt die Kompilate über alle Worktrees, ohne gemeinsames Sperren von `target`. Empfohlen.
- **Gemeinsames `CARGO_TARGET_DIR`:** parallele Builds blockieren sich gegenseitig (Build-Directory-Lock), unterschiedliche Quellstände bauen ständig neu. Nicht empfohlen.
- **Paket-Cache-Lock:** Nach einem `cargo fetch --locked` laufen die Gate-Schritte mit `--offline`, solange `Cargo.lock` gleich bleibt. Damit gibt es keine Registry-Sperre mehr.
- **Vorgebaute .so nach Quell-Hash:** `build_attest_android.sh` legt unter `~/.cache/wendelin/attest/<sha256(src, Cargo.lock, rust-toolchain.toml)>/<abi>/` ab und kopiert von dort. Die meisten WPs ändern `native/` nicht, also entfällt cargo beim APK-Bau ganz.
- **Gate:** Rust-Schritte (Median zusammen etwa 70 s, p90 über 600 s) überspringen, wenn `git rev-parse HEAD:native/attest` schon einmal grün war (siehe Gate-Cache in 8).

## 6. Konfliktpunkte bei paralleler Arbeit

Am häufigsten geänderte Dateien auf main seit 10.10. (390 Commits ohne Merges):
Gesamtkonzept 50, `docs/ARCHITECTURE.md` 33, `app/lib/voice/voice_controller.dart` 22, `agent_runner.dart` 21, `main_screen.dart` 21, `attested_provider.dart` 19, `assistant_overlay.dart` 19, `wendelin_integrations.dart` (Barrel) 18, `app/test/support/test_env.dart` 17, `assistant_overlay_test.dart` 17, `docs/work-packages/README.md` 16, `tool/gate.dart` 15, `voice_pipeline(.dart|_test)` je 15, `voice_providers.dart` 15, `AndroidManifest.xml` 14, `routes.dart`/`main.dart`/`providers.dart` je 14.

Überschneidungen der offenen WPs (wp76b, 79, 82, 88, 90, 91):
- `ARCHITECTURE.md` 4×, `trust_registry_test.dart` 3×, `docs/testing/m5-device.md` 3×, `integrations_screen_test` 3×, `user_integrations_screen_test` 3×, `wiring_test` 3×, `integration_detail_screen` 3×, `di/integrations/registry.dart` 3×, Barrel, `fakes.dart`/`testing.dart`, `test_env`, `channels.json`, Manifest je 2×.
- WP79 (132 Dateien, 25,8k Zeilen) trifft WP82 in 15 UI-Dateien.
- WP79: 3 monolithische ARB-Dateien (de 95 KB, fr 80 KB, en 71 KB, 1130 Schlüssel) plus **19k Zeilen generiertes `lib/l10n/gen/` eingecheckt**. Jeder spätere WP mit neuen Texten kollidiert damit in 3 bis 7 Dateien.

Vorschläge:
- **l10n:** Fragmente je Bereich: `app/lib/l10n/src/<bereich>/<bereich>_<de|en|fr>.arb` mit Schlüsselpräfix = Bereich. `tool/l10n_merge.dart` erzeugt `app_<lang>.arb` und `gen/`. Die erzeugten Dateien kommen nicht ins Repo oder werden per `.gitattributes merge=ours` geführt und neu erzeugt; das Gate prüft „aktuell“ wie bei frb. **Muss mit dem WP79-Merge kommen**, danach ist der Umbau teurer.
- **Registry:** schon eine Spec-Datei je Integration, ein Konflikt kostet nur 2 Zeilen. Optional `registry.dart` aus `*_spec.dart` erzeugen (sortiert, Feld `order`). Geringer Nutzen.
- **Testlisten:** `trust_registry_test.dart:63ff` baut alle Integrationen von Hand nach. Besser `builtInIntegrationsWithFakes()` in `wendelin_integrations/testing.dart`, und die Trust-Erwartung liegt je Integration neben ihren Tools. App-Tests mit Toolzahlen und „alle Integrationen“ leiten ihre Erwartung aus `builtInIntegrationSpecs` ab.
- **Golden `integrationen.png`** (6× geändert): mit fester Fake-Spec-Liste rendern statt mit der echten Registry. Neue Integrationen ändern das PNG dann nicht (PNG-Konflikte lassen sich nicht mergen).
- **Doku:** `ARCHITECTURE.md` aufteilen in einen Index (etwa 4 KB) und `docs/architecture/<bereich>.md`. Die Integrations- und Port-Tabellen erzeugt `tool/gen_docs.dart` zwischen Markern, `check_docs` prüft sie. `docs/testing/m5-device.md` wird zu `docs/testing/m5/<wp>.md` plus generiertem Index. Die Statustabelle in `work-packages/README.md` kommt aus dem Frontmatter der WP-Dateien.
- **Barrels/Exports:** ein Export pro Zeile, alphabetisch sortiert (Lint `directives_ordering`). Git merged dann fast alles automatisch.
- **frb-Dateien und Generiertes allgemein:** in `.gitattributes` als `linguist-generated merge=ours` markieren. Das Merge-Skript erzeugt sie neu.

## 7. Große Dateien

- `size_allowlist.yaml` hat nur noch 1 Eintrag (frb, 1609 Zeilen, erzeugt).
- 76 bis 78 Warnungen; Produktivcode 741 Dateien mit 114,5k Zeilen, Tests 444 Dateien mit 99,3k Zeilen.
- **Groß und oft geändert**, also am meisten von Agenten gelesen, damit die besten Kandidaten zum Aufteilen:
  - `voice_pipeline.dart` 732 Zeilen (Klasse 689) und `voice_pipeline_test.dart` **1491**, knapp unter der Fehlergrenze 1500, nach WP-Gruppen auf Dateien aufteilen.
  - `attested_provider.dart` 719 Zeilen (Klasse 673), 19 Änderungen.
  - `voice_controller.dart` 684 Zeilen, 22 Änderungen.
  - `assistant_overlay.dart` 453 Zeilen und `assistant_overlay_test.dart` 953 Zeilen, je 17 bis 19 Änderungen.
  - `agent_runner.dart` 440 Zeilen, 21 Änderungen.
- Groß, aber selten geändert: `oauth_flow` 799, `fake_mcp_server` 760, `mcp_server_source` 733, `near_verifier` 663, `http_tool_runner` 634, `tool/src/channel_check.dart` 712, `tool/self_test.dart` 603.
- Tests nahe der Grenze: `calendar_tools_test` 1124, `tool_executor_test` 1098, `voice_settings_test` 1041.

## 8. Weitere Beschleuniger

- **Lastbremse:** Das Gate holt sich einen Slot über `~/.cache/wendelin/gate.lock` (höchstens 2 Testphasen gleichzeitig) und setzt `-j` passend zu `uptime`. Bei Last 45 auf 11 Kernen laufen alle Gates 4- bis 7-mal langsamer und Timing-Tests flaken.
- **Inhaltsadressierter Gate-Cache:** je Paket ein Key aus Tree-Hash des Pakets, Hashes der Abhängigkeiten und Toolchain-Versionen. War der Key schon grün, wird der Schritt übersprungen (`~/.cache/wendelin/gate/<key>`). Das volle Gate prüft dann nur Geändertes und ist trotzdem korrekt. Ein uncommitteter Stand bekommt seinen Hash über `git stash create`.
- **Merge-Skript** `tool/merge_wp.sh <wp>`: fetch, `merge --no-ff` mit Standardnachricht, Generiertes neu erzeugen (frb, l10n, Docs-Tabellen), `--changed` gegen den alten main, push, CI abwarten. Ersetzt das manuelle Integrieren (110 Merges bisher).
- **Selbst-Mutation des Coders:** `tool/mutate.dart --file X --tests Y` mit 5 Standardmutationen (Bedingung umdrehen, ±1, Zweig entfernen, Fehler schlucken, Reihenfolge ändern); es laufen nur die betroffenen Tests. Fängt überlebende Mutationen vor dem Review ab und spart Nachbesserungsrunden (jede Runde ist ein frischer Agent mit 30k+ Grundkontext). `../james-wt/mut.sh` ist leer, das wurde also schon versucht.
- **Benachrichtigungen:** In dieser Sitzung gab es 1136 Hintergrund-Tasks. **751 davon haben unter 200 Byte Ausgabe** (`[exited with code N]`, `[killed]`, `tick`, `started`), und 10 identische Kopien desselben Gates. Jede Benachrichtigung weckt einen Agenten. Regel: genau ein Hintergrundjob je Gate- oder CI-Lauf, keine sleep- oder Monitor-Schleifen, die Ausgabe in eine Datei und nur die Zusammenfassung lesen.

## 9. Tokenverbrauch

- **Briefing, das jedes Agent dauerhaft im Kontext trägt:** CLAUDE.md 4 KB + ARCHITECTURE 32 KB + ENGINEERING 15 KB + common/coder 4,4 KB + Agentendefinition 2,5 KB ≈ 58 KB, also etwa **16–17k Tokens**. Bei 100 Aufrufen sind das 1,6M Cache-Read-Tokens nur für das Briefing.
  - Vorschlag: ARCHITECTURE wird zum Index (etwa 4 KB) plus Bereichsdateien, die nur nach Bedarf gelesen werden. Für Coder kommt ein ENGINEERING-Auszug („Gate, Tests, Größen“, etwa 3 KB) in `coder.md`.
  - Ersparnis: etwa 9 bis 10k Tokens je Agent dauerhaft, rund 1M Cache-Read je Coder-Lauf (etwa 5–7 %).
- **Gate-Ausgabe:** grün kompakt (Median 0,8 KB). **Rot etwa 22 KB (etwa 6k Tokens)**: Beim Beispiel `gate-wp82-r3.log` sind von den 200 Zeilen des App-Teils etwa 130 Zeilen `Wendelin/voice:`-Logs und etwa 60 Fortschrittszeilen. Der eigentliche Fehler fällt oft aus dem Fenster heraus, und das Agent startet dann `--verbose` oder `flutter test` einzeln (die Logs dort haben 77 bis 300 KB).
  - Fix 1: `voiceLogSink` (`app/lib/voice/voice_log.dart:16`) in `flutter_test_config.dart` puffern und nur bei Fehlschlag ausgeben.
  - Fix 2: Das Gate baut die Rot-Ausgabe aus dem JSON-Bericht: je fehlgeschlagenem Test Name, Fehler und 15 Stack-Zeilen, höchstens 60 Zeilen je Schritt. `MallocStackLogging`-Zeilen werden gefiltert.
  - Ersparnis: etwa 4 bis 5k Tokens je rotem Lauf, dazu entfallen 1 bis 2 Folgeläufe mit großer Ausgabe. Rote Läufe sind mehr als die Hälfte aller Läufe.
- **Einzeltests:** `tool/t.sh <pfad>` als Wrapper: `failures-only`, Logs aus, Ausgabe auf 80 Zeilen begrenzt. Agenten rufen nie `flutter test` roh auf.
- **Übergabeschwelle:** Kosten je Aufruf ≈ Kontextgröße. Bei Wachstum g ≈ 1,8k je Aufruf und Basis b ≈ 25k kostet ein Lauf mit 120 Aufrufen etwa 16M Cache-Read-Tokens, zwei Läufe mit je 60 Aufrufen etwa 9,5M. **Das sind rund 40 % weniger.** Vorschlag: Übergabe bei **etwa 60 Aufrufen oder etwa 120k Kontext**, die Übergabedatei höchstens 3 KB.
- **Warten:** Der Prompt-Cache lebt 5 min, ein Gate dauert 20 bis 70 min. Jedes Aufwachen nach dem Warten schreibt den Kontext neu in den Cache (150k+ mal 1,25), statt ihn günstig zu lesen.
  - Vorschlag „Gate außerhalb des Agenten“: Der Coder committet, schreibt eine Übergabe und beendet sich. Skript oder CI prüft. Bei Rot startet ein frischer, kleiner Fix-Agent nur mit der kompakten Fehlerliste.
  - Ersparnis: 2 bis 4 Wecker bei 150k+ je WP, etwa 0,5 bis 1M Tokens, und keine Leerlaufschleifen.
- **Mechanisches per Skript:** Die l10n-Migration (1130 Schlüssel, 132 Dateien; `handoff/wp79-tools/` zeigt, dass es teilweise schon so lief) gehört komplett als Codemod umgesetzt: String-Literal finden → ARB-Eintrag → Ersetzung, das Agent prüft nur den Diff. 300 Edit-Aufrufe bei 150k Kontext kosten etwa 45M Cache-Read, ein Skript braucht etwa 10 Aufrufe. Dasselbe gilt für Umbenennungen und Importumzüge (`dart fix`, sed-Batches).

## Rangfolge: (Zeitgewinn × Häufigkeit) / Aufwand

1. **CI grün machen und als volles Gate nutzen** (Goldens, Runner pinnen, wp-Branches pushen, `gh run watch`). Spart 1 bis 4 h Gate je WP und senkt die Last; Aufwand S–M.
2. **Kompakte Rot-Ausgabe plus Testlogs stumm.** Wirkt bei jedem roten Lauf; Aufwand S.
3. **Agentenablauf:** Übergabe bei 60 Aufrufen oder 120k, keine Warteschleifen, Gate außerhalb des Agenten, `tool/t.sh`. Etwa 30–40 % Tokens; Aufwand S (Doku und Skript).
4. **Flakes beheben** (6 bekannte plus `pumpUntil`) und Wanduhr-Asserts entfernen. Erspart Wiederholungsläufe; Aufwand S–M.
5. **Lastbremse plus Gate-Cache.** Aufwand M; großer Effekt bei 4 und mehr parallelen WPs.
6. **l10n-Fragmente und keine eingecheckten Generate.** Zeitkritisch wegen WP79; Aufwand M.
7. **Konfliktarme Tests, Goldens und Doku** (Testlisten, `integrationen.png`, ARCHITECTURE-Split, m5-Dateien je WP). Aufwand S–M.
8. **sccache plus .so-Cache plus offline cargo.** Aufwand S; Minuten je Rust- oder APK-Lauf.
9. **App-Tests bündeln oder Impact-Stufe.** 30–50 % der App-Testzeit; Aufwand M, Risiko globaler Zustand.
10. **Heiße große Dateien aufteilen und Merge-Skript plus Selbst-Mutation.** Laufend; Aufwand M.

## Vorgeschlagene Arbeitspakete

**WP-S1 „CI als Gate“** (`.github/workflows/gate.yml`, `golden_tolerance.dart`, Doku, Briefings)
- Umfang: macOS gepinnt nur für Goldens, ubuntu-Shards für App-Tests mit di-Abdeckung, Matrix je Paket, Rust-Job, kotlin-unit-Job, Caches, install-action, Golden-Update-Workflow. Push-Regel `wp/*` in CLAUDE.md, ENGINEERING.md und den Briefings; `tool/ci_wait.sh <branch>` (eine `gh run watch`-Benachrichtigung).
- AK: 3 grüne CI-Läufe auf main hintereinander; Wandzeit ≤ 10 min; Push eines wp-Branches löst CI aus; ein absichtlich roter Golden fällt auf; Doku nennt `--changed` lokal und volles Gate in CI.

**WP-S2 „Gate schlank und stabil“** (`tool/gate.dart`, `tool/src/gate_run.dart`, `app/test/flutter_test_config.dart`, Flake-Tests)
- Umfang: Rot-Ausgabe aus dem JSON-Bericht (höchstens 60 Zeilen je Schritt), `voiceLogSink` in Tests gepuffert, `pumpUntil`-Helfer, Fixes für die 6 Flakes aus Abschnitt 2, Stopwatch-Asserts ersetzt, Zeitzonen-Probe einmal kompiliert, `tool/t.sh`.
- AK: Rot-Ausgabe ≤ 4 KB mit Testname und Fehler sichtbar (Selbsttest); 5 volle Läufe bei Last ≥ 30 ohne Flake; kein `Stopwatch`-Assert und kein `runAsync(delayed)` mehr als Wartezeit (Gate-Check per grep).

**WP-S3 „Last und Cache“** (`tool/gate.dart`, `tool/src/gate_rust.dart`, `tool/build_attest_android.sh`)
- Umfang: Gate-Semaphor (höchstens 2), inhaltsadressierter Gate-Cache je Paket und Rust, sccache, `--offline`, `.so`-Cache nach Hash.
- AK: Ein zweites volles Gate ohne Änderung dauert unter 60 s; ein Worktree mit unverändertem `native/` ruft beim APK-Bau kein cargo auf; Selbsttests für Key-Bildung und Invalidierung.

**WP-S4 „Konfliktarm parallel“** (l10n-Tooling, Testlisten, Goldens, Doku-Generator, `.gitattributes`, `tool/merge_wp.sh`)
- Umfang: ARB-Fragmente je Bereich plus `tool/l10n_merge.dart` (abgestimmt mit WP79), `builtInIntegrationsWithFakes()`, Golden mit Fake-Liste, ARCHITECTURE-Index plus Bereiche, m5-Gerätetests je WP, erzeugte Tabellen mit Prüfung in `check_docs`, Merge-Skript.
- AK: Zwei Probe-Branches, die je eine Integration mit Texten, Trust-Eintrag und Doku-Zeile hinzufügen, mergen ohne manuellen Konflikt; Gate erkennt veraltete erzeugte Dateien.

**WP-S5 „Agentenablauf“** (nur Doku und Skripte: `docs/agents/*`, `.claude/agents/*`, `tool/mutate.dart`)
- Umfang: Übergabe bei 60 Aufrufen oder 120k, Wartepolitik (ein Hintergrundjob, keine Schleifen), Gate außerhalb des Coders, Codemod-Pflicht für mechanische Massenänderungen, Selbst-Mutation vor dem Review.
- AK: Briefings ≤ 6 KB zusammen ohne ARCHITECTURE-Volltext; `tool/mutate.dart` hat einen Selbsttest und meldet Überlebende; nach 2 WPs sinken die Tokens je WP messbar (Vergleich mit `/usage`).

Konzeptbezug: keine fachlichen Abweichungen vom Gesamtkonzept. Die Push-Regel für `wp/*` und „volles Gate in CI statt lokal“ ändern Prozessregeln (CLAUDE.md, ENGINEERING) und brauchen die Bestätigung des Maintainers.
