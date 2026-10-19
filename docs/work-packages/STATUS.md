# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`, bei jedem Start, Merge oder Verwerfen eines Pakets (Paket-Branches ändern diese Datei nicht).

Gleichzeitig laufen höchstens 2 Pakete (Rechnerlast, Maintainer 2026-10-18); bei Abwesenheit mit Freigabe mehr (2026-10-19: bis 4, je 1 Sub-Agent).

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Merge-Commit) · `verworfen`

Stand: 2026-10-19 nachts, Stefan abwesend (Rechner darf stärker ausgelastet sein, Fragen in `handoff/questions-for-stefan.md`); laufen: WP85, WP103, WP86

## Meilensteine

| Meilenstein | Pakete | Status |
| --- | --- | --- |
| M0 Gerüst, M1 Text-Agent | WP01–WP14 | erledigt |
| M2 Sprache und Assistent (+ Nachbesserungen) | WP15–WP20, WP30–WP33 | erledigt |
| M3 Routing, MCP, Erweiterung | WP21–WP29 | erledigt (Telefontest in M4 aufgegangen) |
| Refactoring R1–R6 | WP35–WP40 | erledigt |
| M4 Wake Word und TEE (+ Gerätetest-Korrekturen) | WP41–WP78, WP80 | erledigt; Rest offen: K47 (nach Stopp-Test 11.6), Test 11.7a (Stefan) |
| M5 Ausbau Android | WP76b–d, WP79, WP81–WP98, WP102–WP103 | in Arbeit (Plan `M5-PLAN.md`) |
| M6 Ausbau 2: Kamera/Bild, Stationsmodus, Wake-Word-Vergleich, Modell-Empfehlung | WP99–WP101 (Stationsmodus), Rest offen | geplant (Plan `M6-PLAN.md`, Start nach M5 mit Go) |
| M7 iOS | – | geplant |

## M5 im Detail

| Paket | Titel | Status | Offen |
| --- | --- | --- | --- |
| WP76a | Tinfoil SEV-SNP (Rust) | gemergt | Folge: rsa-Upgrade; min_tcb in WP76d |
| WP76b | Tinfoil Sigstore | gemergt cc12c9f | K59 bestätigt; Downgrade-Schutz in WP76d |
| WP76c | Tinfoil EHBP/HPKE | geplant | – |
| WP76d | Tinfoil in der App | geplant | min_tcb setzen; Downgrade-Schutz „neuestes Release“ (K59) |
| WP79 | App-Sprache | gemergt 604ff80 | K60 bestätigt; Folge: Stoppwort-Hinweis im Overlay folgt UI- statt Sprech-Sprache; Scan-Test erkennt deutsche Ein-Wort-Texte ohne Umlaut nicht |
| WP81 | Sofort vorlesen, Haken danach | gemergt | – |
| WP81b | Nächster Modellaufruf parallel zur Quittung | geplant | freigegeben Stefan 2026-10-18 |
| WP82 | GPU-Prüfung je Profil | gemergt ad50713 | Folge: AttestationStagesCard ignoriert info-Stufen |
| WP83 | NRAS-Signatur | gemergt | K56 offen |
| WP84 | Spotify | gemergt f609849 | Folge (UX): falscher OAuth-state zeigt nur „Anmeldung abgebrochen“ (AuthChannel.kt lehnt vor Dart ab) |
| WP85 | Kontakte/SMS/Anrufe | in Arbeit | – |
| WP86 | Standort/Maps | in Arbeit | – |
| WP87 | Wetter/Meer | gemergt | – |
| WP88 | Aufgaben | gemergt bb776da | K61 bestätigt; Folge: Erinnerung per Wecker/Timer, 🔁 fortschreiben; E2E-Test liegt in `../james-wt/handoff/wp88-e2e`; calendar_e2e_test sucht fest „Rückgängig · “ (auf englischem Emulator rot) |
| WP89 | Todoist/Google Tasks | geplant | kann starten (WP88 gemergt) |
| WP90 | Mediensteuerung | gemergt eb2cf31 | K65 bestätigt; Gerätetest WP90.1–7 (Audible, Ducking mit echter TTS, Zugriffsdialog) |
| WP91 | Home Assistant | gemergt 8caa7cb | K58 bestätigt; Folge: E2E-Dateien (Fake-HA, `tool/e2e_ha.sh`) übernehmen; CI-Filter: Änderung nur an `tool/check_apk.sh` startet apk-Job nicht |
| WP92a–c | Sprechererkennung | geplant | WP92c nach WP91 |
| WP93 | Wake Word im Chat | geplant | – |
| WP94 | Schnellwechsel Agent | geplant | – |
| WP95 | CI als Gate | gemergt | – |
| WP96 | Gate schlank/stabil | gemergt 9023943 | Folge: `attestation_hub.dart:82` Default isLocked für unbekannte Profile ungetestet; Absenzprüfungen in `main_attestation_test` je ~1 s Echtzeit |
| WP97 | Lastbremse/Cache | gemergt fd1b53b | zweites Gate 3,5 s, APK ohne cargo 47 s; Folge: SIGINT-Freigabe ungetestet, kein actions/cache in CI; 1 App-Test-Flake unter Last beim Merge (Wiederholung grün) |
| WP98 | Konfliktarm | gemergt 2c14825 | Folge: id-Switches in labels.dart, settings_routes.dart, integration_detail_screen.dart; `--adopt` holt von main gelöschte Schlüssel zurück; Statustabelle aus Frontmatter |
| WP102 | Spike bessere Sprache (Messung) | gemergt a3e640b | K66 offen (Wahl Stefan); Folge: Handy-Messung, WER mit echten Stimmen |
| WP103 | Bessere Sprache einbauen | in Arbeit | nach Empfehlung K66, Katalog an Stefans Wahl anpassbar |

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
