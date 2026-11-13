# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`, bei jedem Start, Merge oder Verwerfen eines Pakets (Paket-Branches ändern diese Datei nicht). Gemergte Pakete stehen nicht mehr einzeln hier (siehe `git log`, Pakettexte unter `docs/work-packages/`).

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` · `verworfen`

Parallelität: bis zu 4 Paket-Sitzungen, je 1 Sub-Agent (AGENTS.md); Standard 2, solange der Maintainer am Rechner ist.

Stand: 2026-10-30; läuft: keiner; Release v0.1.6 (4ce2d167).

## Meilensteine

| Meilenstein | Inhalt | Pakete | Status |
| --- | --- | --- | --- |
| M0–M1 | Gerüst, Text-Agent | WP01–WP14 | erledigt |
| M2 | Sprache und Assistent (+ Nachbesserungen) | WP15–WP20, WP30–WP33 | erledigt |
| M3 | Routing, MCP, Erweiterung | WP21–WP29 | erledigt |
| R1–R6 | Refactoring | WP35–WP40 | erledigt |
| M4 | Wake Word und TEE (+ Gerätetest-Korrekturen) | WP41–WP78, WP80 | erledigt; Rest: K47 (nach Stopp-Test 11.6), Test 11.7a (Maintainer) |
| M5 | Ausbau Android: Kontakte/SMS/Anrufe, Maps/Waze, Standort, Wetter, Aufgaben (Todoist/Google Tasks), Spotify und Mediensteuerung, Bring!, Home Assistant mit Sicherheitsstufen A–D, Sprechererkennung, Weckwort-Modell v8a + Prüfer B, Tinfoil/TEE in der App, App-Sprache, bessere Sprachmodelle und Stimmen, Overlay gesperrt (Entsperren, Aktionen danach), Stopp/Barge-in, Entwicklermodus mit Weckwort-Archiv, Leitplanken/CI | WP76a–d, WP79, WP81–WP98, WP102–WP168 | **erledigt** (abgeschlossen mit Release v0.1.0, 2026-10-28) |
| M6 | Ausbau 2: Stationsmodus (WP99 Kern gemergt, WP158 Stationskanal), Wake-Word-Vergleich (WP106, WP111, WP121, WP133, WP137 gemergt), Modell-Empfehlung (WP112 gemergt); offen nur mit Go: WP100/WP101, WP132, WP138; Kamera/Bild gestrichen (Maintainer 2026-10-28) | WP99–WP101, WP106, WP111, WP112 | teilweise erledigt (Plan `M6-PLAN.md`) |
| M7 | iOS | – | geplant |

## Laufende und offene Pakete

| Paket | Titel | Status | Offen |
| --- | --- | --- | --- |
| WP100 | Stationsmodus: Gespräch, Wiedergabe, Kacheln (braucht WP90, WP92) | geplant | nur mit Go |
| WP101 | Stationsmodus: Ruhezeiten, Bluetooth, Wecker-Ansage | geplant | nur mit Go |
| WP132 | Zwei Build-Varianten frei/Store (Vorbereitung), K103 | geplant | nur mit Go, nach WP131 und Gesamttest |
| WP138 | Kompakt-Modus: kleines Sprach-Overlay mit Kreis und Haken | geplant | Idee Maintainer 2026-10-23; nur nach Gespräch und Go |
| WP169 | GitHub-Repo auf Stand v0.1.0: Lizenz GPL-3.0-or-later, README en/de, Screenshots, Homepage | gemergt 83c5b70e | Dazu: 44 STT-Test-WAVs durch Piper-Stimmen ersetzt (Maintainer). Folgepunkte: Integrationsnamen nur deutsch (displayName in wendelin_integrations); Sprechsprache-Default fest 'de' erledigt durch WP174; make_stt_fixtures nicht deterministisch; `app/tool/stt_wer.dart`/`stt_measure.sh` kaputt (dart:ui); release.yml nutzt CHANGELOG nicht; nur dunkles Theme; Social Preview hochladen und Search Console (Maintainer) |
| WP170 | Doku bereinigen: Widersprüche, Veraltetes, Doppelungen, Erledigtes löschen | gemergt b3e6ce97 | K127–K137 bestätigt (2026-10-29) und archiviert; offen: Lint-Hook vor dem Commit (P6) |
| WP171 | Weckwort: Stufe 2 immer Prüfer B, Rückfall auf installiertes Modell, Hinweis statt stillem Verwerfen | gemergt 8d2d699d | K138/K139 offen. Gerätetest `docs/testing/m5/wp171.md` (Benachrichtigungs-Tipp, Akku/fbLoads, Schatten-Fälle); Akku-Messung nur bei Auffälligkeit; `wake_align_test.dart:428` flaky unter Last; Overlay `start-failed reason=no-models` im E2E-Aufbau klären |
| WP172 | Overlay schließt nach dem Zuhören ohne Äußerung, Weckwort wieder bereit | gemergt 12e05a0c | K140 offen. Ursache: Overlay reagierte nicht auf idle, Weckwort pausiert bis overlayClosed. Gerätetest `docs/testing/m5/wp172.md` (echtes Weckwort, Resume, TTS); Soll: 2 nahezu äquivalente Mutationen; Sprachstart beim Modell-Laden von Tastatur nicht abgebrochen (`voice_controller.dart:203-210`) |
| WP173 | Einstellungen umbauen: Routing unter Anbieter, „Erweiterte Einstellungen“, Sprache/Aktivierungswort getrennt, Modell oben | gemergt 955fbe2b | K141 offen, K139 angepasst. Gerätetest `docs/testing/m5/wp173.md`; Folgepunkte: Modell-Anzeigenamen im Katalog nicht lokalisiert; wake_service_e2e WAKE_RUNS=10 hing einmal; click-tile ohne add-tile startete Station einmal nicht |
| WP174 | Einrichtungsassistent beim ersten Start | gemergt 7efb9d62 | K142 offen. Kein E2E (Maintainer testet selbst): Gerätetest `docs/testing/m5/wp174.md`. Folgepunkte: Aktivierungswort-Engine fest 'de' (`device_wake_parts.dart:32`); Systemsprachwechsel erst nach Neustart; Personalisierung ohne Primärknopf; mehrere Systemsprachen → erste unterstützte |
| WP177 | Weckwort: Wählbare Stufe-2-Prüfer (Prüfer B und Spracherkennungsmodell mit ODER-Logik) | gemergt 79e989f1 | K143 bestätigt (2026-10-29). |
| WP178 | Durchgehender Audio-Ringpuffer (5–6 s) für Mikrofon und Weckwort | gemergt 1ac966a0 | K144 offen. CI grün, Review FREIGABE. |
| WP180 | Zentrale Audio-Aufnahme und Ringpuffer im Dienst | gemergt b648dbaf | ADR 0024, K145 offen. CI grün, Review FREIGABE. |
| WP181 | Release 0.1.3 | gemergt 248a801c | Release v0.1.3 veröffentlicht. |
| WP182 | Overlay schließt nicht während Ansage oder 10-Sekunden-Rückgängig-Fenster | gemergt d0a0c136 | K146 offen. Gerätetest docs/testing/m5/wp182.md |
| WP183 | Release 0.1.4 | gemergt c9989220 | Release v0.1.4 veröffentlicht. |
| WP184 | Zentrale Audio-Anbindung vervollständigen (Multi-Subscriber, kein Mic-Busy bei Follow-Up, sauberer Vorlauf ohne Weckwort-Doppeltranskription) | gemergt 498f5c47 | K147 offen. CI grün, Review FREIGABE. |
| WP185 | Release 0.1.5 | gemergt 12a1eb08 | Release v0.1.5 veröffentlicht. |
| WP186 | Overlay hält Bildschirm aktiv (FLAG_KEEP_SCREEN_ON) und schließt nicht vor Ende des Follow-Up-Fensters | gemergt 5de1eae7 | K148 offen. CI grün, Review FREIGABE. |
| WP187 | Release 0.1.6 | gemergt 4ce2d167 | Release v0.1.6 veröffentlicht. |
| WP188 | Audio-Einstellungen: Mikrofon und Ausgabe wählen | gemergt 69a95ef4 | K149 offen. Review FREIGABE, CI grün. Offen: E2E (AVD Wendelin_AOSP_35 leer seit 2026-11-04, Test in james-wt/e2e-keep/wp188), Gerätetest `docs/testing/m5/wp188.md`, Verdrahtungstests `RecognizerAudio.kt:157`, `AudioPlaybackChannel.kt:133,146`; Latenz AudioTrack/Datei-Synthese ungemessen; Gerätewahl wirkt ab dem nächsten Clip; reine SCO-Ausgänge nicht wählbar; BLUETOOTH_CONNECT auf Android 12+ am Gerät bestätigen. |
| WP189 | Weckwort-Vorlauf nicht mehr doppelt (Tap-Position je Listener-Strom) | gemergt 570ca5b5 | Bugfix zu WP180 (seit v0.1.3): Der Tap gab nach jedem Treffer 3 s alten Ton samt Weckwort zurück („nicht verstanden“ bzw. Phantomwörter). Review FREIGABE (Runde 2), CI grün. Offen: Gerätetest (`captured` ≈ 100–300 ms, volles Zuhören nach dem Weckwort); prüfen, ob `wakeEndMargin` (WP184, 350 ms) wieder auf 100 ms kann. |
| WP191 | Hinweisbegriffe: Listen und HA sicher drin, Gerätesynonyme, höhere Obergrenze | gemergt 13d18d8c | K150. Ursache belegt (Kontakte zuerst, Schnitt bei 64). Rang Agent > Liste > Raum > Entität > Synonym > Kontakt, Synonyme de/en/fr, maxTerms 128 (Messung: ab 200 Fehleinfügung). Offen: Gerätetest `docs/testing/m5/wp191.md`; bei Bonus 1.0 kaum Wirkung messbar (Recall 1/20), ggf. Folgemessung mit echten Aufnahmen; goldens-Job in CI 2× nach 15 min abgebrochen (beobachten). |
| WP192 | Push-to-Talk: Mikrofon-Button gedrückt halten | gemergt d38984fe | K151, K152. Haltegrenze 450 ms, Obergrenze 2 min mit Hinweis, lange Aufnahmen in 25-s-Segmenten. Offen: E2E (AVD fehlt) und Gerätetest `docs/testing/m5/wp192.md`; Nahtstellen-WER und Latenz bei 2 min ungemessen; Loslassen vor Mikrofonstart verliert das Gesagte (Folgepunkt: Primed-Puffer); Soll: Pipeline-Test für `VoicePipeline.unhold()`. |
| WP193 | Release-Kandidat 0.1.8 | gemergt bb3c98a6 | Tag v0.1.8-rc1 (WP191, WP192). Versionskonstanten `wendelinAppVersion` und `devArchiveAppVersion` müssen beim Versionssprung mit. |
| WP194 | Start: Mikrofon zuerst, „Ich höre zu“, sobald es läuft | gemergt e3000caa | K153. Anzeige „Ich höre zu“ ab dem ersten Mikrofonblock (`micLive`), Pegel schon während des Ladens; Push-to-Talk-Loslassen greift erst nach dem Nachspielen des Puffers (Ursache belegt). `_startAfterLoading` (Whisper/Silero fehlen) öffnet bewusst kein Mikrofon. Offen: Gerätetest `docs/testing/m5/wp194.md` (mic-ready-Zahlen vorher/nachher), E2E (`../james-wt/e2e-keep/wp194_mic_first_e2e_test.dart`) sobald AVD neu angelegt; Soll: Diagnosezeile bei wartendem Loslassen; Hooks prüfen den Trailer von Merge-Commits nicht (nur CI). |
| WP195 | Nichts gehört: nach 5 s still mit Stopp-Ton beenden | gemergt 9e69ba06 | K154. 5 s ab erstem Mikrofonblock für jede erste Runde (auch Weckwort, Station); synthetischer Stopp-Ton (kein Asset), folgt „Bestätigungston“, still in Station-Ruhezeit; Overlay „Nichts gehört.“, schließt nach 1200 ms. Offen: Gerätetest `docs/testing/m5/wp195.md` (Ton nicht abgeschnitten?); Soll: Gegentest sofortiges Schließen bei anderen Hinweisen (`overlay_idle_close.dart:155`); Frage: Bestätigungston in Ruhezeiten. |
| WP196 | Langes Transkript kleiner anzeigen | gemergt a0609f67 | K155. Nur im Overlay (Chat-Blase ist schon 16 px, Station nutzt das Overlay); Stufen 26 / 18,2 / 16 px, Hysterese 10 %; Untergrenze Body 16 px bleibt (Maintainer 2026-11-13). Offen: Gerätetest `docs/testing/m5/wp196.md`; Soll: irreführender Kommentar „55 %“ in `app_theme.dart:288`. |
| WP197 | Bestätigungston beachtet die Ruhezeiten des Stationsmodus | in Arbeit | Entscheidung Maintainer 2026-11-13 (Folgefrage WP195). |

## Offen

### Gerätetests beim Maintainer

Aktuell rc11 bis rc13 = Release v0.1.0 (Testprotokoll-Blöcke T31-WP158 bis T31-WP165), dazu noch offen (laut „Nächste Schritte“ bisher):
- T30-WP153, T29-WP155/-WP156/-WP157, T28-WP151/-WP154; T27-WP149/-WP150, T26-WP148 (prüfen: ob noch offen)
- `docs/testing/m5/`: wp153, wp155, wp156, wp157, wp159 (A1–A3, B1–B4), wp160 ((d) Falschannahme-Rate), wp161, wp163, wp164, wp165, wp166 (C1–C5, Chromecast), wp151, wp154, wp149, wp150, wp148
- Gerätetest Stationsmodus (Helligkeit/Umgebungslicht) nach WP158
- Älteres, nur nach Prüfung: WP90.1–7, WP91, WP107.2/.4, WP108, WP113, WP114, WP119, WP120, WP135, WP136, WP140–WP146 (jeweils `docs/testing/m5/wpNNN.md`) (prüfen)
- Test 11.7a und K47 (nach Stopp-Test 11.6), siehe M4

### Offene Konzeptänderungen (Status offen, Änderungsprotokoll im Konzept)

K138 offen, K139 offen, K140 offen, K141 offen, K142 offen, K144 offen, K145 offen. K115 ist zurückgestellt.

### Bekannte Folgepunkte und Backlog

- Tinfoil: rsa-Upgrade (WP76a), Turin-Pinning, min_tcb, echte SNP-Bindung im Live-Pfad, Emulator-Lauf der attest-Contract-Suite (WP76d); kein Release-Cache über Speicher hinaus (GitHub ohne Token 60/h)
- Wake Word: Negativ-Aufnahme mit Fernseher (≥ 1,5 h), weitere Sprecher/Räume (WP106, WP121, WP129); HW-Kopf/Training und Prüfseite Weckwort-Archiv (K115); trennendes HW-Modell (WP142); B-Schwelle bei Rauschen (WP143); near-miss-Rate am Handy (WP155)
- Python-Tests in `tool/train_wake_word/` laufen in keinem CI-Job (WP111, WP137); words_measure-Schutz für eigene Modelle (WP137)
- wake_continuous_e2e (WP68-Altlast: silence.wav nicht kopiert, Timeout bei WAKE_RUNS>1)
- Engine-Fix für Stille-Embeddings (sfloor≈0,85), stopOverridesWake umgeht Pegel-Gate (WP126); Hauptwort-Ähnlichkeit in Stille nach Warmstart (WP126) (prüfen)
- Ungetestete Stellen: `wake_barge_in.dart:194`, `wake_word_barge_in.dart:170`, `:219` (WP113); `voice_answer_text.dart:10` (WP114); `audio_playback.dart:65` (WP118); `WakeConflictWatcher.kt:61`; `wake_providers.dart:204` (WP123) (prüfen)
- Weckwort-Rest vor dem Befehl (wake-strip), zwei Parakeet-Instanzen (~2 GB) möglich (WP146); Restzuwachs ~3,9 MB/Overlay in Impeller-GLES, echte Geräte ungeprüft (WP145)
- Spotify: Playlist-Ursache nur per Fixture, `spotify_session.dart:177` toter Doku-Verweis, MediaSessionPick zählt BUFFERING/CONNECTING als spielend (WP161); Fortschritt toter Geräte nur per Fake (WP166); falscher OAuth-state zeigt nur „Anmeldung abgebrochen“ (WP84)
- Sperre/Stufen: Store-_merge nicht atomar, Sperrtexte ohne l10n (WP157); Einträge gesperrter Läufe im Transkript, kollidierende Tool-Call-Ids (WP163); Undo nach gesperrtem Lauf unter Sitzung „locked“ (WP154); `attestation_hub.dart:82` Default isLocked ungetestet (WP96)
- Kontakte: Kontakte-Integration zeigt „Aktiv“ auch ohne SMS (WP159); Sortierschlüssel `ContactsChannel.kt:178`, doppelte Bezeichnungen `contacts_tools.dart:586` (WP164); Kontaktänderungen erreichen den Erkenner erst bei Resume (WP85)
- Texte/l10n: „Wake Word“ in `wake_de.arb:101-102`, `wake_classifier_catalog.dart:61` (WP156); Agent-Fehlertexte nur deutsch (WP150); Überschrift `voice_licenses_screen.dart:21` (WP162); `AppRoutes.httpToolNew` ohne Aufrufer (WP152); Leerzustand providersNone ohne Test (WP116)
- Gate lokal: `dart test` löst Pakete neu auf und findet das Flutter-SDK nicht („integration_test from sdk“), weil `.dart_tool/package_config.json` älter als `pubspec.lock` ist und `flutter pub get` sie bei gleichem Inhalt nicht neu schreibt (3× beim Merge, WP167/WP172/WP169; Zwischenlösung `touch`) – Gate soll `FLUTTER_ROOT` setzen bzw. vorher `flutter pub get` und Zeitstempel prüfen; Commit-Hook prüft check_sizes nicht (WP172)
- E2E auf main rot (Befund WP169 2026-10-28, mit alten und neuen WAVs gleich): voice_note D1 (de-05, `voice_note_e2e_test.dart:106`), overlay_e2e, overlay_fresh_conversation („Expected length 2“), voice_barge_in; wp140_voice ohne WAVs unter `wake-e2e/` – Kandidat für ein E2E-Reparaturpaket
- Tests/Gate: Goldens zeigen Material-Icons als Kästchen (WP154); E2E „SemanticsHandle active“ rot am Testende (WP163); E2E-Messung „während Antwort 2“ (WP165); lokales Gate fand `directives_ordering`/`prefer_const` nicht, erst CI (WP158, WP167); Commit-Hooks führen kein Gate aus (WP159); SIGINT-Freigabe, kein actions/cache (WP97)
- Build/Release: Debug-Fallback-Warnung in `check_apk.sh`, versionCode-Anstieg, Tag-Schutzregel `v*` (WP131); CI-Filter: nur `tool/check_apk.sh` startet apk-Job nicht (WP91); `cleanup_wt.sh` löscht Urteilsdateien (WP110)
- Modelle/Messung: Scorer-Leck `</think>`, `fr-clarify-liste`, `live30.txt` (WP112); Fallback je Rolle als eigenes Paket; STT-Messung mit echten Aufnahmen (K99)
- Stationsmodus optimieren (Wunsch Maintainer 2026-10-29): weitere Informationen anzeigen, z. B. Wetter; die Titelleiste oben soll verschwinden – Kandidat für ein Paket (M6)
- Sonstiges: Stoppwort-Hinweis folgt UI- statt Sprech-Sprache (WP79); Erinnerung per Wecker/Timer (WP88); Spotify in Akku-Ausnahme (MIUI friert ein, WP161); Lücke im Handy-Log 18:58–19:01 (WP160)

## Nächste Schritte

0. v0.1.8-rc2 (WP191, WP192, WP194, WP195, WP196) auf Gerät testen (Blöcke im Testprotokoll); K150–K155 bestätigen lassen; CHANGELOG für WP194–WP196 vor dem Release 0.1.8 nachtragen; Emulator-AVD neu anlegen (E2E WP192, WP194).
1. Release 0.1.6 auf Gerät testen; WP188 per Gerätetest `docs/testing/m5/wp188.md` prüfen.
1a. Emulator-AVD `Wendelin_AOSP_35` neu anlegen (Abbild seit 2026-11-04 leer), danach offene E2E nachholen.
2. Konzeptänderungen bestätigen lassen: K138, K139, K140, K141, K142, K144, K145, K146, K147, K148, K149 (Status: offen).
5. Danach nur mit Go (M6): Prüfseite Weckwort-Archiv (dann Hey-Pflicht K115 und Training mit eigenem HW-Kopf), WP100/WP101, STT-Messung (K99), WP132, WP138.
