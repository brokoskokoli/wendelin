# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`, bei jedem Start, Merge oder Verwerfen eines Pakets (Paket-Branches ändern diese Datei nicht).

Gleichzeitig laufen höchstens 2 Pakete (Rechnerlast, Maintainer 2026-10-18).

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Merge-Commit) · `verworfen`

Stand: 2026-10-18, main `3f77d58`

## Meilensteine

| Meilenstein | Pakete | Status |
| --- | --- | --- |
| M0 Gerüst, M1 Text-Agent | WP01–WP14 | erledigt |
| M2 Sprache und Assistent (+ Nachbesserungen) | WP15–WP20, WP30–WP33 | erledigt |
| M3 Routing, MCP, Erweiterung | WP21–WP29 | erledigt (Telefontest in M4 aufgegangen) |
| Refactoring R1–R6 | WP35–WP40 | erledigt |
| M4 Wake Word und TEE (+ Gerätetest-Korrekturen) | WP41–WP78, WP80 | erledigt; Rest offen: K47 (nach Stopp-Test 11.6), Test 11.7a (Stefan) |
| M5 Ausbau Android | WP76b–d, WP79, WP81–WP98 | in Arbeit (Plan `M5-PLAN.md`) |
| M6 iOS, Stationsmodus, Kamera | – | geplant |

## M5 im Detail

| Paket | Titel | Status | Offen |
| --- | --- | --- | --- |
| WP76a | Tinfoil SEV-SNP (Rust) | gemergt | Folge: rsa-Upgrade; min_tcb in WP76d |
| WP76b | Tinfoil Sigstore | wartet | pausiert (Rechnerlast, max. 2 Pakete), Review läuft weiter, sobald frei |
| WP76c | Tinfoil EHBP/HPKE | geplant | – |
| WP76d | Tinfoil in der App | geplant | min_tcb setzen |
| WP79 | App-Sprache | wartet | wartet auf Merge WP82; danach Provider-Screens, Goldens je Sprache |
| WP81 | Sofort vorlesen, Haken danach | gemergt | – |
| WP81b | Nächster Modellaufruf parallel zur Quittung | geplant | freigegeben Stefan 2026-10-18 |
| WP82 | GPU-Prüfung je Profil | Review | Fix fertig, Merge steht aus |
| WP83 | NRAS-Signatur | gemergt | K56 offen |
| WP84 | Spotify | Review | – |
| WP85 | Kontakte/SMS/Anrufe | geplant | – |
| WP86 | Standort/Maps | geplant | – |
| WP87 | Wetter/Meer | gemergt | – |
| WP88 | Aufgaben | wartet | Review steht aus (HEAD 38e09e9) |
| WP89 | Todoist/Google Tasks | geplant | nach WP88 |
| WP90 | Mediensteuerung | wartet | Review und E2E (Player-App auf Emulator) stehen aus |
| WP91 | Home Assistant | Review | – |
| WP92a–c | Sprechererkennung | geplant | WP92c nach WP91 |
| WP93 | Wake Word im Chat | geplant | – |
| WP94 | Schnellwechsel Agent | geplant | – |
| WP95 | CI als Gate | gemergt | – |
| WP96 | Gate schlank/stabil | wartet | pausiert (Rechnerlast, max. 2 Pakete) |
| WP97 | Lastbremse/Cache | geplant | – |
| WP98 | Konfliktarm | geplant | nach WP79 |

Danach: Empfehlung von Modellen (gemeinsam mit Stefan besprechen).

## Nächste Schritte

Für eine neue Orchestrator-Sitzung (Stand 2026-10-18 abends, vor dem Neustart des Rechners):

1. **Pausierte Pakete fortsetzen:** WP76b, WP96 und ggf. WP84/WP91 aus `../james-wt/handoff/wpNN-session.md`, je in einer neuen Paket-Sitzung (`start-wp-session.sh`). Gleichzeitig höchstens 2.
2. **WP79** fortsetzen (Übergabe `../james-wt/handoff/wp79.md`), danach WP98 (l10n-Fragmente).
3. **WP88** und **WP90** ins Review (HEAD in der Tabelle).
4. Danach WP81b, WP97, WP76c/d und die M5-Wellen 2 und 3.

Wartet auf Stefan: K48–K56 bestätigen (Liste am 2026-10-18 geschickt), K47 nach Stopp-Test 11.6, Test 11.7a.
