# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`, bei jedem Start, Merge oder Verwerfen eines Pakets (Paket-Branches ändern diese Datei nicht).

Gleichzeitig laufen höchstens 2 Pakete (Rechnerlast, Maintainer 2026-10-18); bei Abwesenheit mit Freigabe mehr (2026-10-19: bis 4, je 1 Sub-Agent).

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Merge-Commit) · `verworfen`

Stand: 2026-10-22 (Standard 2 Sitzungen, mit Freigabe bis 4; Freigabe 4 gilt für ~5 h ab 03:00); läuft: WP137; Test-APK 954e065 beim Maintainer; als Nächstes: WP100/WP101, WP92c nach Gerätetest wp92a/b, STT-Messung nach Aufnahmen (K99), Scorer-Fix Reasoning-Leck

## Meilensteine

| Meilenstein | Pakete | Status |
| --- | --- | --- |
| M0 Gerüst, M1 Text-Agent | WP01–WP14 | erledigt |
| M2 Sprache und Assistent (+ Nachbesserungen) | WP15–WP20, WP30–WP33 | erledigt |
| M3 Routing, MCP, Erweiterung | WP21–WP29 | erledigt (Telefontest in M4 aufgegangen) |
| Refactoring R1–R6 | WP35–WP40 | erledigt |
| M4 Wake Word und TEE (+ Gerätetest-Korrekturen) | WP41–WP78, WP80 | erledigt; Rest offen: K47 (nach Stopp-Test 11.6), Test 11.7a (Maintainer) |
| M5 Ausbau Android | WP76b–d, WP79, WP81–WP98, WP102–WP110 | in Arbeit (Plan `M5-PLAN.md`) |
| M6 Ausbau 2: Kamera/Bild, Stationsmodus, Wake-Word-Vergleich, Modell-Empfehlung | WP99–WP101 (Stationsmodus), Rest offen | in Arbeit: WP99 (Go Maintainer 2026-10-19, vor WP92c); Rest geplant (Plan `M6-PLAN.md`) |
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
| WP85 | Kontakte/SMS/Anrufe | gemergt 314deb6 | K69 bestätigt (3 Fragen an Maintainer, u. a. diktierter Text im Anfrage-Audit → evtl. eigenes Paket); Sprachbestätigung nur per Unit-/Widget-Test, Gerätetest `docs/testing/m5/wp85.md`; Kontaktänderungen erreichen den Erkenner erst bei Resume/Aktivierung |
| WP86 | Standort/Maps | gemergt f595fa0 | K67 bestätigt (Wetter-Position bei „keine Mindeststufe“, Frage an Maintainer); Gerätetest WP86.5 (geo: mit Karten-App, Google-Maps-Fall); E2E-Test liegt in `../james-wt/handoff/wp86-location_e2e_test.dart` (braucht Grant/geo fix im e2e-Skript) |
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
| WP102 | Spike bessere Sprache (Messung) | gemergt a3e640b | K66 bestätigt (Wahl Maintainer); Folge: Handy-Messung, WER mit echten Stimmen |
| WP103 | Bessere Sprache einbauen | gemergt ff07cbd | K66/K68 bestätigt (Maintainers Modell-/Stimmenwahl, Katalog anpassbar); Gerätetest `docs/testing/m5/wp103.md` (RAM/RTF/Akku/Wärme); Kontaktnamen als Hinweis-Begriffe brauchen Neubau des contactNamesProvider durch WP85; Wake-Dienst ohne Hinweis-Begriffe |
| WP104 | Liegengebliebene Gerätetests übernehmen | gemergt 3b45204b | K76 bestätigt; Folge: Mutationslauf zeigt keine Zeilennummer; fest deutsche Tests (tee_gpu, wake_enroll, voice_voices, voice_robustness) nur mit de; Liste `docs/testing/m5/wp104.md` |
| WP105 | Folgepunkte Audit und Texte | gemergt f02332ef | Kachel-Fehlerzeile/Retry-Hinweise nur generisch (Fehlerart+Dienst), Meldungen ans Modell deutsch; Fehlerart durch onError/Registry → WP108; Gerätetest `docs/testing/m5/wp105.md` |
| WP106 | Spike Wake Word Stationsmodus | gemergt 2e06c48e | K80 bestätigt; Notiz `docs/notes/wake-word-station-spike.md`; Empfehlung Station: v7/v9 M0,5 + persönliches Feintuning + Parakeet-Hotword 2,0, CAM++ nur TV-Filter; offen: mehr Sprecher/Räume, ≥1,5 h Negativ, Gerätemessung RAM/Akku; Modelle jetzt `~/wendelin-fixtures/models` |
| WP107 | Bring! nur Tokens | gemergt cfab3c1e | K75 bestätigt (ergänzt); Gerätetest WP107.2 (falsches Passwort) und WP107.4 (Update von Vorversion) offen, `docs/testing/m5/wp107.md` |
| WP108 | Fehlerart bis zur Integrationskachel | gemergt 55953025 | K78 bestätigt; „Erfolg setzt Fehlerart zurück“ app-seitig nur für Todoist/Spotify getestet (Bring!, Google Tasks, HA nur auf Paketebene); Gerätetest `docs/testing/m5/wp108.md` |
| WP109 | Leitplanken (Regelquelle, main-Schutz, Größen-Ratsche, Aufräumskript) | gemergt d758e3c4 | K79 bestätigt; Teil B (Ruleset, Aufräumen, Skill) erledigt; neue Merge-Folge: merge_wp.sh → amend → STATUS → --changed → `WENDELIN_PUSH_MAIN=1 git push` → `cleanup_wt.sh --apply`; parallele Pakete müssen Größen-Baseline anpassen, wenn sie Warn-Dateien ändern; lokales Gate flakte unter Last (app), Nachlauf grün |
| WP110 | Agenten-Leitplanken und CI-Entlastung (Claude-Hooks, Coder-Checkliste, docs-only-CI, Emulator-Sperre) | gemergt 2ff0fe8f | K81 offen; beim Merge kotlin-unit rot (`bash bash gradlew`, wenn das JDK schon passt), vom Orchestrator behoben 9c7ffbc7; Folge: cleanup_wt.sh löscht die Urteilsdateien `<wp>-review*.md` mit (sollen für die Quote „erstes Review sauber“ erhalten bleiben; bis dahin sichert der Orchestrator sie vor dem Merge nach `james-wt/reviews/`); Guard-Restlücken in ENGINEERING.md (fängt pre-push ab) |
| WP111 | Vergleich alternativer Wake Words („Hey Wendelin“, microWakeWord, sherpa-KWS) | gemergt fcf956d9 | K83 offen; synthetisch: Zielwerte von keinem Wort erreicht, Empfehlung bei „Wendelin“ bleiben (v7 M0,3 + Parakeet-Hotword 2); Abweichungen: Testclips macOS-Systemstimmen statt Piper, persönliches Feintuning nicht neu gemessen, ohne CAM++-Stufe, Python-Selbsttests `tool/train_wake_word/test_measure.py` nicht im Gate; Folge: Teil B echte Aufnahmen (Folgepaket), Soll Re-Review (Test pick_neg-Aufruf `station_measure.py:215`, `requirements-mww.txt`), Kandidaten aus Klang-Recherche (Okay Wendelin, Hey Wendelino, Hey Kasimir) für späteren Vergleich |
| WP112 | Modell-Empfehlung (150 Evals de/en/fr, 5 Anbieter, Empfehlung je Rolle) | gemergt d6ba4602 | K87 offen; Kosten 1,48 $ (alle unter Obergrenze); Folge: Scorer soll Reasoning-Leck (`</think>`) als Fehlschlag werten, `fr-clarify-liste` zu streng, `live30.txt` enthält pending `de-lists-add`, Soll: CLI-Test Ledger-Budgetübergabe; Fallback je Rolle als eigenes Paket möglich |
| WP113 | „Stopp“ während der Antwort mit Gegenprüfung, Anzeige „hört mit“ | gemergt e7e17b9b | K90 (Stopp gewinnt, Schwellen, Gegenprüfung 0,8 s, Echo-Filter); Gerätetest docs/testing/m5/wp113.md; Soll: stopOverridesWake-Verdrahtung wake_barge_in.dart:194 und Settle wake_word_barge_in.dart:170 ungetestet, _verify alte Generation :219 |
| WP114 | Gesperrtes Handy: Overlay bleibt nach dem Entsperren, harmlose Aktionen ohne Entsperren | gemergt 82a0afe0 | K92; Gerätetest docs/testing/m5/wp114.md (Z.5-Ursache über Log locked-cmd, Home beim Entsperren); Soll: answerText-Abbruch beim Modell-Laden (voice_answer_text.dart:10), Mutanten M3/M5/M6/M8 |
| WP115 | Große Modelle streamend entpacken (Parakeet v3), erkannte Sprache loggen | gemergt 781af471 | keine Abweichung; neue Logzeilen model-unpack(-ed/-failed), stt-lang; Gerätetest `docs/testing/m5/wp115.md`; Soll: Tests `a/b` dann `a` → corrupt, doppelte Datei → ok, Doc install() `model_installer.dart:84-86` (io-Ausnahme), io-Test mit chmod 555 scheitert als root |
| WP116 | Einstellungsseiten: Überschriften, Info-Texte, Links | gemergt 75a243b6 | keine Abweichung (WText.sectionTitle, InfoBox, LinkButton; Varianten von Maintainer gewählt); Gerätetest `docs/testing/m5/wp116.md`; Soll: Leerzustand providersNone ohne Test/Golden |
| WP117 | Weitere deutsche Stimmen (Ramona, Eva) | gemergt 49fca790 | K86; Lizenz M-AILABS (BSD-artig, Attribution) statt CC0; Soll: Stimmen später in eigene Datei auslagern (check_sizes) |
| WP118 | Antwort als Gesprächston (bessere Echo-Unterdrückung), Schalter | gemergt 983346c4 | K93; Gerätetest docs/testing/m5/wp118.md; Stopp-E2E an/aus offen (Stopp-E2E auf main rot, siehe Nächste Schritte); Soll: Rennen erstes Play+Stopp (audio_playback.dart:65), Besitzer-Token bei dispose, WakeConflictWatcher.kt:61 ohne Test |
| WP119 | Nächster Wecker auslesen, Tools vorab mitschicken | gemergt fb246094 | K91; Gerätetest docs/testing/m5/wp119.md; Soll: Test endSession räumt gemerkte Sprache auf |
| WP120 | Antwortzeit vermessen, Pausen beim Vorlesen, früher vorlesen | gemergt ad6db5ad | K95; Gerätetest docs/testing/m5/wp120.md (10 Befehle, p50/p90); kein Schnell-Anbieter-Vergleich (kein Key); Stopp-E2E siehe Nächste Schritte |
| WP121 | Wake Words mit echten Aufnahmen vergleichen (fair) | gemergt f5f59f2e | K98; Empfehlung bei „Wendelin“ bleiben; Folge: Negativ-Aufnahme mit Fernseher (≥ 1,5 h), weitere Sprecher, sherpa-Spalten WP106/WP111 neu rechnen |
| WP122 | Feste Bestätigungssätze statt zweitem Modellaufruf | gemergt 4f596e66 | K97; Gerätetest T21-WP122; Soll: Test AgentDone.fixed, Satz „schon vorhanden“ (confirmation_texts de:30/34 en:45/48 fr:53/56), Doku fixed_confirmation.dart:20, toter Schlüssel lists_write_tools.dart:47; CI-Flake wake_lifecycle_test (UnmountedRefException) |
| WP123 | Stopp sofort ab Antwortbeginn (Barge-in-Warmstart), Stopp-E2E stabil | gemergt ab054e98 | K96; E2E voice_stop_word/voice_barge_in je 3× offen (Last 15–18); Gerätetest T21-WP123; Soll: Provider-Test take statt snapshot (wake_providers.dart:204) |
| WP124 | Emulator startet bei Bedarf, wird nach jedem E2E-Lauf beendet (E2E_KEEP_EMULATOR=1 für Serien) | gemergt 909738c1 | Wunsch Maintainer 2026-10-21; echter Lauf torch_e2e grün |
| WP125 | Sammelpaket Soll-Befunde WP114/118/119/122, CI-Flake wake_lifecycle_test | gemergt (ed38ba1e) | E2E stop_word/barge_in grün; Punkte 1/6 in WP126; dazu: answerText bricht beim Modell-Laden ab (WP114), WakeServiceNotifier prüft ref.mounted nach awaits (Flake-Ursache). Folgepunkt: WakeConflictWatcher.refresh und releaseAll in dispose ohne Robolectric ungetestet |
| WP126 | „Stopp“ nach Warmstart: Fehlkandidat auf Stille blockiert echtes Wort (Fehler aus WP123) | gemergt (d8c908dd) | K106; E2E stop_word/barge_in je 3× grün. Folgepunkte: (a) Stille-Embeddings scoren hoch (sfloor≈0,85), stopOverridesWake umgeht das Pegel-Gate der Engine – nur abgefangen, Engine-Fix offen; (b) Hauptwort-Ähnlichkeit in Stille 0,82–0,83 > thr 0,75: „Wendelin“ könnte nach Warmstart auf Stille auslösen (seit WP123) → in WP129 prüfen |
| WP127 | Öffentliches Repo ohne Namen/Anwesenheit/lokale Pfade, Sperre (check_privacy, privacy-guard) | gemergt 51917089 | Entscheidung Maintainer 2026-10-22; Historie bleibt |
| WP128 | Empfohlene Modelle markieren, Nachfrage bei Ausfall | gemergt 20c94d8b | K100, K104; Soll: retry_offer_card_test prüft „Stufe“ → findsNothing nicht (Mutant M4); Gerätetest docs/testing/m5/wp128.md |
| WP129 | Trainiertes Wake-Word-Modell (v8a statt v7, K105) in der App, zweistufig | gemergt (727548e8) | Katalog-Eintrag Platzhalter bis Modell aus WP137 (clean); offen: Vorlagen-Weg leiser Raum, Parakeet-RAM/Laufzeit am Handy, Negativ-Aufnahme mit Fernseher |
| WP130 | Wake-Word-Modell v8 (mehr Stimmen, Varianten, harte Negative) | gemergt (8f85b96c) | K105; Empfehlung v8a (Stufe 1 allein: Wendelin 80/77 %, Hey Wendelin 93/90 % bei 2 FA/h; v7 braucht dafür Stufe 2). Folgepunkte: M-AILABS-Lizenz vor Release-Asset belegen; Test „--allow-truncated fehlt im Volllauf“; cv_extract erkennt Abschneiden an Header-Grenze nicht (CV-Shard nicht gepinnt); v8c (hidden 256) zurückgestellt |
| WP131 | Release-Signatur und automatischer APK-Build auf GitHub (Tag → Release) | gemergt (0501df86) | K109; Probe-Release geprüft (Signer CN=Wendelin, nicht Debug), ohne Secrets rot. Folgepunkte: Debug-Fallback-Warnung in check_apk.sh greift kaum (apksigner auf CN=Android Debug prüfen); versionCode-Anstieg ungeprüft; Tag-Schutzregel v* empfohlen; erster echter Tag v0.1.0 + Dispatch-Probe probe_missing_secrets auf main |
| WP132 | Zwei Build-Varianten frei/Store (Vorbereitung) | geplant | K103; nur mit Go, nach WP131 und Gesamttest |
| WP133 | Wake Word: Nutzen von Stufe 2, v8a gegen v8c nur synthetisch | gemergt (5dca4d8d) | K110; Empfehlung v8a, Stufe 1 ab 0,98, ≥ 0,999 direkt, 0,98–0,999 prüft hw2 (Ausschnitt 2,0/0,9 s). Folgepunkte: wortspezifischer Prüfer statt hw2 (Go Maintainer); c-syn vs a-syn mit mehreren Seeds; mehr Sprecher; Notiz :470 zwei Ungenauigkeiten |
| WP134 | Stopp-Wort ausbauen, Vorlagen-Vergleich für „Wendelin“ zentrieren | gemergt (2d3ceecc) | K107, K112; offen: Handtests wp134 (Stopp mittendrin unterbricht nicht, Neueinlernen), Mindest-Recall des Kalibrators bei starkem Hintergrund, Timeout für hängendes am instrument in e2e_android.sh |
| WP135 | Smart Home schneller: Geräteliste, Synonyme, feste Bestätigung, Schnellweg ohne KI, Rollo ohne Rückfrage | gemergt (c5ffc7f2) | K108, K111; offen: Gerätetest am Handy (Latenz nachher, Geräte neu freigeben), Rollo ohne Rückfrage nur Unit-Test, WP122-Ausfall bei gemischten Runden |
| WP136 | Parakeet (NeMo) lädt nach dem Download nicht | gemergt (dc113dc1) | Ursache: oberste Ordnerebene im Archiv; offen: Gerätetest Teil A am Handy (Fehlergerät ohne Neu-Download), Wiederaufnahme nach Download-Abbruch |
| WP137 | Wake Word: v8c mit echten Aufnahmen, wortspezifischer Prüfer statt Parakeet, Aufnahme-Anleitung | in Arbeit | K110; Go Maintainer 2026-10-23 |
| WP138 | Kompakt-Modus: kleines Sprach-Overlay mit Kreis und Haken | geplant | Idee Maintainer 2026-10-23; nur nach Gespräch und Go |
| WP140 | Einlernen mit Inhaltsprüfung, unsichere Erkennung verwerfen, Ja/Nein robuster | gemergt (b9b857a9) | K114; offen: „Hey Wendelin“-Ausschnitt endet nach 440 ms Pause, Moduswechsel bzw. letzte Stimme löschen bei laufendem Dienst → „an“ ohne Zuhören, Erwartung „Kandidat“ in wake_enroll_e2e (schon vorher rot), e2e_android.sh spielt Parakeet nicht ein, Gerätetest am Handy |
| WP141 | Wake Word: nach dem ersten Treffer bis 0,8 s weiter beobachten | gemergt (d25ec9dd) | K110-Nachtrag; offen: Versatzprobe des WP137-Prüfers vor dem Einbau, Ausreißer-Check verwirft im E2E 1/15 Einlern-Aufnahmen (WP140-Folgepunkt), Gerätetest leiser gedehnter Ruf und Latenz |

Empfehlung von Modellen: M6 (gemeinsam mit Maintainer besprechen).

## Nächste Schritte

Reihenfolge M5 (bestätigt Maintainer 2026-10-19), je Schritt höchstens 2 Paket-Sitzungen; Pakete am Sprach-Controller (WP81b, WP92, WP93, WP103) nie gleichzeitig:

0. erledigt: WP98, WP102; Merge ab jetzt mit `tool/merge_wp.sh <branch> [--squash]`, Paket-Anleitung `docs/work-packages/WP98-migration.md`
1. WP97 Lastbremse/Cache, WP85 Kontakte/SMS/Anrufe
2. WP103 Bessere Sprache einbauen, WP86 Standort/Maps
3. WP81b Modellaufruf parallel zur Quittung, WP76c Tinfoil EHBP/HPKE
4. WP76d Tinfoil in der App (Downgrade-Schutz K59), WP89 Todoist/Google Tasks
5. WP92a→b→c Sprechererkennung, WP94 Schnellwechsel
6. WP93 Wake Word im Chat

Danach M6 (nur mit Go): WP99, dann WP100/WP101 (`M6-PLAN.md`). Pakete mit Alt-Commits per Squash mergen.

Wartet auf Maintainer: K47 nach Stopp-Test 11.6, Test 11.7a, Gerätetests WP90.1–7 und WP91.
