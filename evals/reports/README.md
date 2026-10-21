# Eval-Reports

Dokumentierte Live-Läufe von `dart run wendelin_evals:run`, Dateiname
`<datum>-<profil>[-<modell>].json`. Die Reports enthalten keine Keys, nur
Fälle, Tool-Aufrufe, Antworten, Tokens und Kosten. Lokale Probeläufe
gehören nach `*.local.json` (von Git ausgenommen).

## 2026-10-13 – Abschluss M1 (WP11)

Aufruf je Profil (im Verzeichnis `evals/`, Keys aus `~/.wendelin-live.env`):

```sh
dart run wendelin_evals:run --profile profiles/<profil>.json --limit 10 --out reports/2026-10-13-<profil>.json
# weitere Phala-Modelle für K8 g:
dart run wendelin_evals:run --profile profiles/phala-tee-small.json --model <modell> --limit 10 --out reports/2026-10-13-phala-<modell>.json
```

`--limit 10` nimmt die ersten zehn Fälle, das sind die deutschen Kalender-,
Wecker- und Timer-Fälle (u. a. „Trag mir morgen um 10 Tauchen ein“,
Löschen mit Bestätigung, Verschieben, ganztägig, freie Zeit). Französisch,
Englisch, Gedächtnis, Zwischenablage und Web sind in diesem Lauf **nicht**
enthalten. „Heute“ ist fest Mi 18.11.2026 09:00 Europe/Berlin.

| Profil | Modell | Treffer | p50 | p90 | Tokens | Kosten gesamt | je Anfrage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| claude-haiku | `claude-haiku-5-5` | **10/10** | 2,1 s | 2,7 s | 99 610 (davon 93 561 Cache-Lesen) | 0,0025 $ | 0,00025 $ |
| openai-mini | `gpt-5-mini` | 9/10 | 3,3 s | 7,3 s | 46 980 | 0,0103 $ | 0,0010 $ |
| phala-tee-small | `qwen/qwen-2.5-7b-instruct` | 5/10 | 2,1 s | 2,3 s | 65 399 | 0,0066 $ | 0,0007 $ |
| phala-tee-small | `openai/gpt-oss-120b` | 8/10 | 3,0 s | 4,0 s | 43 577 | 0,0075 $ | 0,0008 $ |
| phala-tee-small | `google/gemma-4-31b-it` | **10/10** | 2,2 s | 3,6 s | 120 660 | 0,0140 $ | 0,0014 $ |

Kosten nach `CostCalculator`: Anthropic/OpenAI aus dem eingebauten
Katalog, Phala aus der Preisliste von RedPill (`/v1/models`, Stand
2026-10-13), im Profil `phala-tee-small.json` unter `catalog` hinterlegt.
Für Modelle ohne eigenen Cache-Preis (qwen-2.5-7b, gpt-oss-120b) ist
Cache-Lesen mit dem vollen Eingabepreis angesetzt. Claude Haiku ist trotz
vieler Tokens am günstigsten, weil fast alles aus dem Prompt-Cache
kommt (K8 e).

Fehlschläge:

- `gpt-5-mini`, `de-cal-frei` („Wann habe ich morgen Nachmittag eine Stunde Zeit?“):
  Rückfrage nach dem Zeitraum statt Kalenderabfrage.
- `qwen-2.5-7b`: Wochentage falsch aufgelöst („Freitag“ → Dienstag,
  „Samstag“ → heute; Mo/Mi/Fr → `[2, 4, 6]`), erfundene Termin-Id beim
  Löschen, Verschieben ohne Tool-Aufruf.
- `gpt-oss-120b`: `de-cal-heute` meldet „keine Einträge“ trotz Termin,
  `de-cal-loeschen` listet nur und löscht nicht (keine Bestätigung).

## Live-Durchlauf M1 (2026-10-13)

DoD-Satz „Trag mir morgen um 10 Tauchen ein“ durch die echte
Agent-Schleife mit Fake-Kalenderport (`test/live/dod_live_test.dart`,
„heute“ = Mi 18.11.2026):

| Profil | Modell | Ergebnis | Latenz | Modellaufrufe | Kosten |
| --- | --- | --- | --- | --- | --- |
| claude-haiku | `claude-haiku-5-5` | ✓ `calendar__create_event` „Tauchen“, 2026-11-19T10:00 | 2,5 s | 2 | 0,00072 $ |
| openai-mini | `gpt-5-mini` | ✓ dasselbe | 4,8 s | 2 | 0,00113 $ |
| phala-tee-small | `qwen/qwen-2.5-7b-instruct` | ✓ dasselbe | 2,7 s | 2 | ≈ 0,0007 $ (nachgerechnet, Preise damals noch nicht im Profil) |

Im Emulator (`app/integration_test/live_e2e_test.dart`, AOSP ohne Google
Play, echte App, echter Gerätekalender): Claude Haiku `claude-haiku-5-5` ✓,
Termin morgen 10:00 im lokalen Kalender, Tool-Karte mit „Rückgängig“,
Rückgängig entfernt ihn, Aufruf und Rückgängig im Audit-Log; 4,9 s bis zur
Antwort, 2 Modellaufrufe, 0,00051 $.

WP14-Proben (Verlauf, wie `AgentRunner._messagesFor` ihn baut) – beide
Anbieter akzeptieren ihn ohne Fehler:

| Probe | `claude-haiku-5-5` | `gpt-5-mini` |
| --- | --- | --- |
| ausgeblendeter Tool-Aufruf (Tool nicht in der Liste, Argumente `{}`, Ergebnis ausgeblendet) | ✓ 0,00017 $ | ✓ 0,00046 $ |
| ohne Tools: Aufruf/Ergebnis als Text, zwei Nutzernachrichten hintereinander | ✓ 0,00005 $ | ✓ 0,00017 $ |

## Empfehlung Phala-Standardmodell (K8 g)

**`google/gemma-4-31b-it` (TEE)** statt `qwen/qwen-2.5-7b-instruct`: 10/10
gegenüber 5/10 bei ähnlicher Latenz, rund 0,0014 $ je Anfrage (doppelt so
teuer wie qwen, aber weiter unter 1/5 Cent). `qwen-2.5-7b` beherrscht
Tool-Calls formal, löst aber relative Daten und Wochentage zu oft falsch auf
– für einen Kalenderassistenten nicht tragbar. `gpt-oss-120b` liegt
dazwischen. `glm-5.3-flash` wurde nicht gemessen (Reasoning lässt sich auf
RedPill nicht abschalten, K8 g). Vor der Umstellung sollte ein voller Lauf
(alle 40 Fälle, auch fr/en, Gedächtnis, Web) die Wahl bestätigen.

## 2026-10-20/21 – Modellempfehlung (WP112)

Live-Lauf `cases/live30.txt` (29 aktive Fälle x 2 = 58 Läufe) für 12 Modelle von 5 Anbietern, Thinking aus bzw. minimal; Reports `2026-10-20-<profil>-<modell>.json`, Kosten aller Läufe in `2026-10-20-ledger.json` (Summe 1,48 $). Auswertung, Empfehlung je Rolle und Kommandos: `docs/notes/model-recommendation.md`.
