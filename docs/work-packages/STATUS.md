# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`, bei jedem Start, Merge oder Verwerfen eines Pakets (Paket-Branches ändern diese Datei nicht).

Gleichzeitig laufen höchstens 2 Pakete (Rechnerlast, Maintainer 2026-10-18); bei Abwesenheit mit Freigabe mehr (2026-10-19: bis 4, je 1 Sub-Agent).

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Merge-Commit) · `verworfen`

Stand: 2026-10-20 nachmittags, Stefan da; läuft: WP113, WP116; als Nächstes: WP114 (nach WP113), WP111 Teil B (nach Aufnahmen), Sonnet-Probe, WP92c (nach Gerätetest wp92a/b), WP100/WP101 (Stationsmodus Welle 2)

## Meilensteine

| Meilenstein | Pakete | Status |
| --- | --- | --- |
| M0 Gerüst, M1 Text-Agent | WP01–WP14 | erledigt |
| M2 Sprache und Assistent (+ Nachbesserungen) | WP15–WP20, WP30–WP33 | erledigt |
| M3 Routing, MCP, Erweiterung | WP21–WP29 | erledigt (Telefontest in M4 aufgegangen) |
| Refactoring R1–R6 | WP35–WP40 | erledigt |
| M4 Wake Word und TEE (+ Gerätetest-Korrekturen) | WP41–WP78, WP80 | erledigt; Rest offen: K47 (nach Stopp-Test 11.6), Test 11.7a (Stefan) |
| M5 Ausbau Android | WP76b–d, WP79, WP81–WP98, WP102–WP110 | in Arbeit (Plan `M5-PLAN.md`) |
| M6 Ausbau 2: Kamera/Bild, Stationsmodus, Wake-Word-Vergleich, Modell-Empfehlung | WP99–WP101 (Stationsmodus), Rest offen | in Arbeit: WP99 (Go Stefan 2026-10-19, vor WP92c); Rest geplant (Plan `M6-PLAN.md`) |
| M7 iOS | – | geplant |

## M5 im Detail

| Paket | Titel | Status | Offen |
| --- | --- | --- | --- |
| WP76a | Tinfoil SEV-SNP (Rust) | gemergt | Folge: rsa-Upgrade; min_tcb in WP76d |
| WP76b | Tinfoil Sigstore | gemergt cc12c9f | K59 bestätigt; Downgrade-Schutz in WP76d |
| WP76c | Tinfoil EHBP/HPKE | gemergt 06498bc | K71 bestätigt; echte SNP-Bindung im Live-Pfad und Emulator-Lauf der attest-Contract-Suite in WP76d |
| WP76d | Tinfoil in der App | gemergt c19b0966 | K73 bestätigt; Folge: Turin-Pinning, rsa-Upgrade (WP76a); kein Release-Cache über Speicher hinaus (GitHub ohne Token 60/h) |
| WP79 | App-Sprache | gemergt 604ff80 | K60 bestätigt; Folge: Stoppwort-Hinweis im Overlay folgt UI- statt Sprech-Sprache; Scan-Test erkennt deutsche Ein-Wort-Texte ohne Umlaut nicht |
| WP81 | Sofort vorlesen, Haken danach | gemergt | – |
| WP81b | Nächster Modellaufruf parallel zur Quittung | gemergt 135dbbd | K70 bestätigt; Ersparnis am Emulator ~0,4 s bis erster Text, ~0,9 s bis fertig; Tool-Runden gegen echtes TEE-Gateway ungetestet (Fixture ohne Tool-Calls); overlay-Reihenfolge-Flake behoben (WP104: Phala-Hinweis aus loadRuleSet) |
| WP81c | Parallele Runde sofort vorlesen | gemergt 07c67ba9 | K70 ergänzt; Einzelsatz vor Toolcall wird erst bei ToolCallStarted gesprochen (Splitter); E2E-Build braucht JAVA_HOME auf Android-Studio-JBR |
| WP82 | GPU-Prüfung je Profil | gemergt ad50713 | Folge: AttestationStagesCard ignoriert info-Stufen |
| WP83 | NRAS-Signatur | gemergt | K56 bestätigt |
| WP84 | Spotify | gemergt f609849 | Folge (UX): falscher OAuth-state zeigt nur „Anmeldung abgebrochen“ (AuthChannel.kt lehnt vor Dart ab) |
| WP85 | Kontakte/SMS/Anrufe | gemergt 314deb6 | K69 bestätigt (3 Fragen an Stefan, u. a. diktierter Text im Anfrage-Audit → evtl. eigenes Paket); Sprachbestätigung nur per Unit-/Widget-Test, Gerätetest `docs/testing/m5/wp85.md`; Kontaktänderungen erreichen den Erkenner erst bei Resume/Aktivierung |
| WP86 | Standort/Maps | gemergt f595fa0 | K67 bestätigt (Wetter-Position bei „keine Mindeststufe“, Frage an Stefan); Gerätetest WP86.5 (geo: mit Karten-App, Google-Maps-Fall); E2E-Test liegt in `../james-wt/handoff/wp86-location_e2e_test.dart` (braucht Grant/geo fix im e2e-Skript) |
| WP87 | Wetter/Meer | gemergt | – |
| WP88 | Aufgaben | gemergt bb776da | K61 bestätigt; Folge: Erinnerung per Wecker/Timer, 🔁 fortschreiben; E2E-Test liegt in `../james-wt/handoff/wp88-e2e`; calendar_e2e_test sucht fest „Rückgängig · “ (auf englischem Emulator rot) |
| WP89 | Todoist/Google Tasks | gemergt b4777882 | K72 bestätigt; Gerätetest mit echten Konten `docs/testing/m5/wp89.md` (WP89.1–15); Live-Tests ungelaufen (keine Tokens); Audit-Titel tasks__ und deutsche Resttexte → WP105 |
| WP90 | Mediensteuerung | gemergt eb2cf31 | K65 bestätigt; Gerätetest WP90.1–7 (Audible, Ducking mit echter TTS, Zugriffsdialog) |
| WP91 | Home Assistant | gemergt 8caa7cb | K58 bestätigt; E2E Fake-HA als run_ha in e2e_android.sh (WP104); Folge: CI-Filter: Änderung nur an `tool/check_apk.sh` startet apk-Job nicht |
| WP92a–c | Sprechererkennung | WP92a gemergt e46f48c7; WP92b gemergt 3145db56; 92c geplant | K74, K77 bestätigt (2 Fragen: Datenlizenz CAM++, Schwelle); Gerätetest mit echten Stimmen `docs/testing/m5/wp92a.md` und `wp92b.md` (echte STT/Pipeline nur in Unit-Tests) vor 92c; e2e_android.sh deinstalliert die App am Ende |
| WP93 | Wake Word im Chat | gemergt 7a722cba | keine Abweichung; „App im Hintergrund/Sperre → Overlay“ nur Unit-/JVM-Test, Handprüfpunkt `docs/testing/m5/wp93.md`; Folge: voice_controller `trigger` bleibt nach einem Zug auf wakeWord stehen; Gate kotlin-unit lokal nur mit JAVA_HOME=openjdk@21 (JDK 23/27 rot) → WP110 |
| WP94 | Schnellwechsel Agent | gemergt 112d4be | keine Abweichung; Gerätecheck WP94.1/.7/.8 (Vibration, TTS-Abbruch, TalkBack); Restlücke: startet zwischen setDefault und newTopic eine Anfrage (Overlay), bleibt der Chat stehen (kein Verlaufsleck) |
| WP95 | CI als Gate | gemergt | – |
| WP96 | Gate schlank/stabil | gemergt 9023943 | Folge: `attestation_hub.dart:82` Default isLocked für unbekannte Profile ungetestet; Absenzprüfungen in `main_attestation_test` je ~1 s Echtzeit |
| WP97 | Lastbremse/Cache | gemergt fd1b53b | zweites Gate 3,5 s, APK ohne cargo 47 s; Folge: SIGINT-Freigabe ungetestet, kein actions/cache in CI; 1 App-Test-Flake unter Last beim Merge (Wiederholung grün) |
| WP98 | Konfliktarm | gemergt 2c14825 | Folge: id-Switches in labels.dart, settings_routes.dart, integration_detail_screen.dart; `--adopt` holt von main gelöschte Schlüssel zurück; Statustabelle aus Frontmatter |
| WP102 | Spike bessere Sprache (Messung) | gemergt a3e640b | K66 bestätigt (Wahl Stefan); Folge: Handy-Messung, WER mit echten Stimmen |
| WP103 | Bessere Sprache einbauen | gemergt ff07cbd | K66/K68 bestätigt (Stefans Modell-/Stimmenwahl, Katalog anpassbar); Gerätetest `docs/testing/m5/wp103.md` (RAM/RTF/Akku/Wärme); Kontaktnamen als Hinweis-Begriffe brauchen Neubau des contactNamesProvider durch WP85; Wake-Dienst ohne Hinweis-Begriffe |
| WP104 | Liegengebliebene Gerätetests übernehmen | gemergt 3b45204b | K76 bestätigt; Folge: Mutationslauf zeigt keine Zeilennummer; fest deutsche Tests (tee_gpu, wake_enroll, voice_voices, voice_robustness) nur mit de; Liste `docs/testing/m5/wp104.md` |
| WP105 | Folgepunkte Audit und Texte | gemergt f02332ef | Kachel-Fehlerzeile/Retry-Hinweise nur generisch (Fehlerart+Dienst), Meldungen ans Modell deutsch; Fehlerart durch onError/Registry → WP108; Gerätetest `docs/testing/m5/wp105.md` |
| WP106 | Spike Wake Word Stationsmodus | gemergt 2e06c48e | K80 bestätigt; Notiz `docs/notes/wake-word-station-spike.md`; Empfehlung Station: v7/v9 M0,5 + persönliches Feintuning + Parakeet-Hotword 2,0, CAM++ nur TV-Filter; offen: mehr Sprecher/Räume, ≥1,5 h Negativ, Gerätemessung RAM/Akku; Modelle jetzt `~/wendelin-fixtures/models` |
| WP107 | Bring! nur Tokens | gemergt cfab3c1e | K75 bestätigt (ergänzt); Gerätetest WP107.2 (falsches Passwort) und WP107.4 (Update von Vorversion) offen, `docs/testing/m5/wp107.md` |
| WP108 | Fehlerart bis zur Integrationskachel | gemergt 55953025 | K78 bestätigt; „Erfolg setzt Fehlerart zurück“ app-seitig nur für Todoist/Spotify getestet (Bring!, Google Tasks, HA nur auf Paketebene); Gerätetest `docs/testing/m5/wp108.md` |
| WP109 | Leitplanken (Regelquelle, main-Schutz, Größen-Ratsche, Aufräumskript) | gemergt d758e3c4 | K79 bestätigt; Teil B (Ruleset, Aufräumen, Skill) erledigt; neue Merge-Folge: merge_wp.sh → amend → STATUS → --changed → `WENDELIN_PUSH_MAIN=1 git push` → `cleanup_wt.sh --apply`; parallele Pakete müssen Größen-Baseline anpassen, wenn sie Warn-Dateien ändern; lokales Gate flakte unter Last (app), Nachlauf grün |
| WP110 | Agenten-Leitplanken und CI-Entlastung (Claude-Hooks, Coder-Checkliste, docs-only-CI, Emulator-Sperre) | gemergt 2ff0fe8f | K81 offen; beim Merge kotlin-unit rot (`bash bash gradlew`, wenn das JDK schon passt), vom Orchestrator behoben 9c7ffbc7; Folge: cleanup_wt.sh löscht die Urteilsdateien `<wp>-review*.md` mit (sollen für die Quote „erstes Review sauber“ erhalten bleiben; bis dahin sichert der Orchestrator sie vor dem Merge nach `james-wt/reviews/`); Guard-Restlücken in ENGINEERING.md (fängt pre-push ab) |
| WP111 | Vergleich alternativer Wake Words („Hey Wendelin“, microWakeWord, sherpa-KWS) | gemergt fcf956d9 | K83 offen; synthetisch: Zielwerte von keinem Wort erreicht, Empfehlung bei „Wendelin“ bleiben (v7 M0,3 + Parakeet-Hotword 2); Abweichungen: Testclips macOS-Systemstimmen statt Piper, persönliches Feintuning nicht neu gemessen, ohne CAM++-Stufe, Python-Selbsttests `tool/train_wake_word/test_measure.py` nicht im Gate; Folge: Teil B echte Aufnahmen (Folgepaket), Soll Re-Review (Test pick_neg-Aufruf `station_measure.py:215`, `requirements-mww.txt`), Kandidaten aus Klang-Recherche (Okay Wendelin, Hey Wendelino, Hey Kasimir) für späteren Vergleich |
| WP112 | Modell-Empfehlung (150 Evals de/en/fr, 5 Anbieter, Empfehlung je Rolle) | gemergt d6ba4602 | K87 offen; Kosten 1,48 $ (alle unter Obergrenze); Folge: Scorer soll Reasoning-Leck (`</think>`) als Fehlschlag werten, `fr-clarify-liste` zu streng, `live30.txt` enthält pending `de-lists-add`, Soll: CLI-Test Ledger-Budgetübergabe; Fallback je Rolle als eigenes Paket möglich |
| WP113 | „Stopp“ während der Antwort mit Gegenprüfung, Anzeige „hört mit“ | in Arbeit | Gerätetest 2026-10-20 T20-B.1; K84 |
| WP114 | Gesperrtes Handy: Overlay bleibt nach dem Entsperren, harmlose Aktionen ohne Entsperren | geplant (nach WP113, Sprach-Controller) | T20-Z.5/Z.6; K85 |
| WP115 | Große Modelle streamend entpacken (Parakeet v3), erkannte Sprache loggen | gemergt 781af471 | keine Abweichung; neue Logzeilen model-unpack(-ed/-failed), stt-lang; Gerätetest `docs/testing/m5/wp115.md`; Soll: Tests `a/b` dann `a` → corrupt, doppelte Datei → ok, Doc install() `model_installer.dart:84-86` (io-Ausnahme), io-Test mit chmod 555 scheitert als root |
| WP116 | Einstellungsseiten: Überschriften, Info-Texte, Links | in Arbeit | T20-0.9 |
| WP117 | Weitere deutsche Stimmen (Ramona, Eva) | gemergt 49fca790 | K86; Lizenz M-AILABS (BSD-artig, Attribution) statt CC0; Soll: Stimmen später in eigene Datei auslagern (check_sizes) |

Empfehlung von Modellen: M6 (gemeinsam mit Stefan besprechen).

## Nächste Schritte

Reihenfolge M5 (bestätigt Stefan 2026-10-19), je Schritt höchstens 2 Paket-Sitzungen; Pakete am Sprach-Controller (WP81b, WP92, WP93, WP103) nie gleichzeitig:

0. erledigt: WP98, WP102; Merge ab jetzt mit `tool/merge_wp.sh <branch> [--squash]`, Paket-Anleitung `docs/work-packages/WP98-migration.md`
1. WP97 Lastbremse/Cache, WP85 Kontakte/SMS/Anrufe
2. WP103 Bessere Sprache einbauen, WP86 Standort/Maps
3. WP81b Modellaufruf parallel zur Quittung, WP76c Tinfoil EHBP/HPKE
4. WP76d Tinfoil in der App (Downgrade-Schutz K59), WP89 Todoist/Google Tasks
5. WP92a→b→c Sprechererkennung, WP94 Schnellwechsel
6. WP93 Wake Word im Chat

Danach M6 (nur mit Go): WP99, dann WP100/WP101 (`M6-PLAN.md`). Pakete mit Alt-Commits per Squash mergen.

Wartet auf Stefan: K47 nach Stopp-Test 11.6, Test 11.7a, Gerätetests WP90.1–7 und WP91.
