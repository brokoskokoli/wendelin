# WP112: Modellempfehlung je Rolle (Live-Messung 2026-10-20/21)

Grundlage für die Standardmodelle je Rolle (normal, privat/TEE, schnell/Station, Notfall). Rohdaten: `evals/reports/2026-10-20-*.json` (ohne `.local`, das sind die Probeläufe), Kosten `evals/reports/2026-10-20-ledger.json`. Vorbild: `docs/notes/wp54-tee-eval.md`.

## Aufbau

- Entscheid Stefan 2026-10-20: live nur **30 Fälle** (`evals/cases/live30.txt`, quer über Kalender, Wecker, Aufgaben, Bring, Spotify, Wetter, Web, Notizen, Stationsmodus, Mehrschritt, Rückfragen, Ablehnung; de/en/fr). Ein Fall ist `pending` und wird übersprungen: **29 aktive Fälle x 2 Wiederholungen = 58 Läufe je Modell**. Der Gesamtsatz hat **150 Fälle** und läuft grün gegen den Fake-Provider (Gate); nur die 30 gehen gegen echte Modelle, um das Budget zu halten.
- Gleiche Bedingungen: „heute“ = Mi 18.11.2026 09:00, Zone Europe/Berlin (Standard des Runners), gleicher Prompt und gleiche Tools, Fakes für alle Integrationen. Zeitlimit je Fall 60 s.
- **Thinking aus bzw. minimal, je Anbieter**: Claude Haiku 5.5 ohne Thinking; Claude Sonnet 5.5 lehnt `thinking: disabled` ab und läuft deshalb mit `between_tools` (Adapter-Anpassung, siehe Abweichungen); `gpt-5-mini` mit `reasoningEffort: minimal`; `gpt-oss-120b` (Phala, Tinfoil) `low`; gemma, Qwen, glm, deepseek per `chat_template_kwargs` (`enable_thinking`/`thinking: false`) bzw. Phala-Reasoning-Option aus. Profile: `evals/profiles/`.
- Preise (USD je Mio. Token) stammen aus dem Modellkatalog der App (Anthropic, OpenAI) bzw. dem `catalog` des Profils (Phala/RedPill `/v1/models`, Stand 2026-10-14; Tinfoil öffentlicher `/v1/models`, `docs/notes/tinfoil-spike.md`; NEAR `/v1/models`, Stand 2026-10-20, im Profil `near-tee.json` unter `catalog`). Tinfoil und NEAR haben für die meisten Modelle keinen eigenen Cache-Preis: Cache-Lesen ist mit dem Eingabepreis gerechnet.
- Drosselung: Tinfoil lieferte beim ersten gemma4-31b-Lauf Rate-Limits (Ledger: 25 Fälle ohne Preis, 0,126 $). Der Lauf wurde mit `--pause-ms` und `--retry-rate-limit` komplett wiederholt; die Tabelle zeigt nur den Wiederholungslauf. Beide Läufe zählen in die Kosten.
- Kennzahlen: Treffer = bestandene Läufe von 58; Wilson-95-%-Intervall; Latenz = Wanduhrzeit der Agent-Schleife ohne Pausen; Tokens/Fall = Ein+Aus+Cache je Lauf; „je Befehl“ = USD je Lauf.

## Ergebnis je Modell

| Anbieter | Modell | Treffer | Wilson 95 % | p50 / p90 | Tokens/Fall | USD gesamt | USD je Befehl | Fehler |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Anthropic | `claude-haiku-5-5` | **58/58** | 93,8–100 % | 1,9 / 3,4 s | 9 413 (fast alles Cache) | 0,017 | 0,0003 | keine |
| Phala | `google/gemma-4-31b-it` | **58/58** | 93,8–100 % | 1,8 / 2,3 s | 10 686 | 0,072 | 0,0012 | keine |
| Tinfoil | `deepseek-v4-1-flash` | **58/58** | 93,8–100 % | 2,2 / 4,0 s | 11 748 | 0,291 | 0,0050 | keine |
| Tinfoil | `gemma4-31b` | 57/58 | 90,9–99,7 % | 1,9 / 2,3 s | 10 675 | 0,249 | 0,0043 | 1 falsch (`de-web-fetch-rezept`) |
| Anthropic | `claude-sonnet-5-5` | 56/58 | 88,3–99,1 % | 3,3 / 4,9 s | 9 582 | 0,321 | 0,0055 | 2 falsch (`fr-clarify-liste` beide) |
| NEAR | `z-ai/glm-5.3-flash` | 55/58 (**nur 24 ohne Reasoning-Text**, s. u.) | 85,9–98,2 % | 10,6 / 40,2 s | 6 226 | 0,016 | 0,0003 | 3 Timeouts (60 s) |
| Phala | `openai/gpt-oss-120b` | 54/58 | 83,6–97,3 % | 1,8 / 3,6 s | 4 704 | 0,043 | 0,0007 | 4 falsch (Wetter 2x, `fr-cal-vendredi`, `fr-clarify-liste`) |
| OpenAI | `gpt-5-mini` | 51/58 | 77,1–94,0 % | 2,0 / 3,4 s | 4 563 | 0,030 | 0,0005 | 7 falsch (Rückfrage Wecker 2x, Tauchen, Mehrschritt, Notizsuche, Wetter) |
| NEAR | `Qwen/Qwen3.6-35B-A3B-FP8` | 51/58 | 77,1–94,0 % | 2,3 / 3,0 s | 7 600 | 0,079 | 0,0014 | 7 falsch (u. a. Station, Aufgaben, Web) |
| Tinfoil | `gpt-oss-120b` | 50/58 | 75,1–92,8 % | 1,9 / 3,1 s | 4 673 | 0,043 | 0,0007 | 6 falsch, 2 Providerfehler (Antwort nicht lesbar) |
| NEAR | `Qwen/Qwen3.8-27B` | 49/58 | 73,1–91,6 % | 2,5 / 6,4 s | 7 393 | 0,024 | 0,0004 | 9 falsch (fr/Spotify/Web/Aufgaben) |
| Phala | `deepseek/deepseek-v4-flash-0731` | 48/58 | 71,1–90,4 % | 4,4 / 60,0 s | 6 190 | 0,071 | 0,0012 | 8 Timeouts (60 s), 2 falsch |

**Reasoning-Leck (glm-5.3-flash):** In allen 55 bestandenen Läufen steht ein `</think>` im Antworttext (Skript über `finalText` aller Reports, `</think>`/`<think>`); in 31 davon geht Reasoning-Text voraus („The user wants an alarm set …“, bis 2 500 Zeichen), in 24 nur das lose Tag. Für Sprachausgabe ist damit höchstens **24/58** brauchbar, kein Lauf ist ganz sauber. Der Scorer wertet alle 55 als bestanden. Die übrigen 11 Reports haben kein Leck, außer Qwen3.8-27B (NEAR): 1 Lauf (`de-multi-bring-aufgabe`, Antwort doppelt mit `</think>` dazwischen). Haiku, Sonnet, gpt-5-mini, Phala-, Tinfoil-Modelle und Qwen3.6: 0.

Hinweise: `fr-clarify-liste` scheitert bei 6 von 12 Modellen (auch bei Sonnet 2/2, Sonnets 56/58 gehen allein darauf zurück; bei den 12 Fehlschlägen sind 9 ein `clipboard__read`, 3 scheitern am `[?]`); das spricht eher für einen strengen oder mehrdeutigen Erwartungswert des Falls als für Modellschwäche und gehört in ein Folgepaket (Fall prüfen).

## Ist-Kosten gegen Obergrenze

Aus dem Ledger, **alle** Einträge inkl. Probeläufe (5 Fälle), Sonnet-Einzelprobe und dem abgedrosselten ersten Tinfoil-gemma-Lauf:

| Anbieter | Ist (USD) | Obergrenze (WP, EUR) |
| --- | --- | --- |
| Anthropic (Haiku, Sonnet) | 0,354 | 4,00 |
| Phala (gemma, deepseek, gpt-oss) | 0,211 | 1,50 |
| Tinfoil (gpt-oss, gemma, deepseek) | 0,753 | 1,00 |
| NEAR (glm, Qwen 3.6, Qwen 3.8) | 0,131 | 1,00 |
| OpenAI (gpt-5-mini) | 0,035 | 1,00 |
| **Summe** | **1,483 $** | **8,50 €** |

Selbst bei 1 $ = 1 € liegt jeder Anbieter unter seiner Obergrenze und die Summe weit unter 8,50 €. Tinfoil ist mit 75 % der Grenze am nächsten, wegen des Wiederholungslaufs und weil Tinfoil für gemma4 und deepseek keinen Cache-Rabatt hat (gemma4 dort 0,0043 $ je Befehl, bei Phala 0,0012 $).

## Empfehlung je Rolle

Die Intervalle der Spitzengruppe überlappen stark (58/58 gegen 56/58 und 55/58 ist bei 58 Läufen kein belastbarer Unterschied); die Reihenfolge innerhalb von Gruppen entscheidet deshalb Preis, Latenz und Datenschutz, nicht die letzte Prozentstelle.

- **Normal: `claude-haiku-5-5`.** 58/58, p50 1,9 s, mit Prompt-Cache 0,0003 $ je Befehl (rund 18x billiger als Sonnet bei gleicher bis besserer Trefferquote). Sonnet (56/58) bringt hier keinen Vorteil. Haiku ist heute der Vorschlag der Vorlage (`suggestedModel`).
- **Privat/TEE: `google/gemma-4-31b-it` über Phala/RedPill.** 58/58, 1,8 / 2,3 s, 0,0012 $. Bestätigt die Wahl aus WP54b (dort 40/40). Gleiches Modell bei Tinfoil: 57/58, gleiche Latenz, aber 3,5x teurer; kein Treffer-Unterschied außerhalb des Rauschens. `deepseek-v4-1-flash` (Tinfoil) 58/58, aber 4x teurer und langsamer.
- **Schnell/Station: `google/gemma-4-31b-it` (Phala) mit dem engsten p90 (2,3 s), ohne Cloud-Kompromiss bei Privatsphäre; ohne TEE-Zwang `claude-haiku-5-5` (p50 gleich, p90 3,4 s, billiger).** `gpt-oss-120b` ist gleich schnell, trifft aber nur 50–54/58 (Wetter, Rückfragen): nur für einfache Befehle. Latenz-Unterschiede zwischen Haiku, gemma und gpt-oss (alle p50 ≈ 1,8–2,0 s) liegen im Rauschen eines einzelnen Laufs.
- **Notfall/Fallback: anderer Anbieter als die Hauptrolle.** Hauptrolle Haiku: `gpt-5-mini` (OpenAI, 51/58, 0,0005 $) oder Phala gemma, falls TEE erlaubt ist. Hauptrolle Phala gemma: Tinfoil `gemma4-31b` (gleiches Modell, anderer Betreiber, 57/58) oder Haiku, wenn die Privatsphäre-Stufe es zulässt. Nicht empfohlen: `deepseek-v4-flash` bei Phala (8 Timeouts), `glm-5.3-flash` (p90 40 s und Reasoning-Leck in allen bestandenen Läufen, trotz 55/58 und Billigstpreis nicht sprachtauglich), Qwen 3.x (49–51/58).

**Vorschlag, nichts umgesetzt:** Die App-Standardwerte bleiben unverändert. Die Messung stützt die bestehenden Defaults (Anthropic Haiku, Phala gemma). Wer einen Fallback pro Rolle einführt (eigenes Paket), könnte `gpt-5-mini` bzw. Tinfoil `gemma4-31b` als Vorbelegung nehmen.

## Grenzen

- Nur 29 aktive Fälle x 2: Intervalle von etwa ±5 bis ±12 Punkten; Unterschiede von 1 bis 3 Läufen sind nicht belastbar. Wiederholungen derselben Fälle sind nicht unabhängig.
- Phala `deepseek-v4-flash-0731`: 8 Timeouts, bei 6 ohne `usage` (im Ledger als ohne Preis geführt). Die Kosten sind deshalb eher unterschätzt; Tinfoil gemma4 hat im ersten Lauf dasselbe Problem bei Rate-Limits (25 ohne Preis, Lauf wiederholt).
- NEAR `glm-5.3-flash`: Thinking-aus wirkt dort **nicht** (belegt: Reasoning-Text und `</think>` im Antworttext, s. o.); dazu die lange Latenz (p90 40 s). Ein Fall ohne `usage`.
- Latenz ohne Attestierung: die Evals bauen den Adapter direkt (wie WP54b); Remote-Attestierung, E2EE und Netz des Telefons kommen in der App dazu. Vergleich nur innerhalb dieser Läufe (Lastschwankungen der Gateways).
- Preise sind Listenpreise zum Messzeitpunkt; Cache-Rabatte (Anthropic, Phala-gemma) verbessern die Zahlen der Anbieter, die sie anbieten.
- Ein Lauf je Modell und Tag; Rückfrage-Fälle (`*-clarify-*`) hängen stark von der Formulierung der Erwartung ab.

## Kommandos zum Wiederholen

Keys: `set -a; . ~/.wendelin-live.env; set +a` (Werte nie ausgeben). Im Verzeichnis `evals/`; Beispiel Haiku, je Modell nur Profil und `--model` ändern:

```sh
dart run wendelin_evals:run --profile profiles/claude-haiku.json \
  --ids cases/live30.txt --repeat 2 --max-cost 1 \
  --ledger reports/2026-10-20-ledger.json --provider-cap 1 \
  --out reports/2026-10-20-claude-haiku-claude-haiku-5-5.json
# Modelle der Mehrmodell-Profile:
dart run wendelin_evals:run --profile profiles/phala-tee-small.json --model google/gemma-4-31b-it --ids cases/live30.txt --repeat 2 --max-cost 1 --ledger reports/2026-10-20-ledger.json --out reports/2026-10-20-phala-tee-small-google-gemma-4-31b-it.json
# Tinfoil mit Drosselung (Werte des gelaufenen Wiederholungslaufs):
dart run wendelin_evals:run --profile profiles/tinfoil-tee.json --model gemma4-31b --ids cases/live30.txt --repeat 2 --max-cost 0.6 --pause-ms 3000 --retry-rate-limit 30 --ledger reports/2026-10-20-ledger.json --out reports/2026-10-20-tinfoil-tee-gemma4-31b.json
# Summe je Anbieter, kein Modellaufruf:
dart run wendelin_evals:run --ledger reports/2026-10-20-ledger.json --ledger-summary
# Gesamtsatz gegen den Fake (Profil und Fallzahl vor Nutzung prüfen):
dart run wendelin_evals:run --profile profiles/fake-full.json
```

Profile: `claude-haiku`, `claude-sonnet`, `openai-mini`, `phala-tee-small`, `tinfoil-tee`, `near-tee`. Die Wiederholung kostet erneut Geld (je Modell 0,02 bis 0,3 $); `--max-cost` und `--provider-cap` (USD) begrenzen.

## Folgepunkte (nicht umgesetzt)

- Scorer: Reasoning-Leck (`</think>`/`<think>` oder Reasoning-Präfix im Antworttext) als Fehlschlag werten.
- `fr-clarify-liste` (`evals/cases/clarify.yaml:53`) ist zu streng: `clipboard__read` ist bei „Ajoute ça“ plausibel (9 der 12 Fehlschläge), die Rückfrage kommt auch ohne „?“ (3). Erwartung lockern oder Prompt ändern; Wirkung: beide Sonnet-Fehlschläge (56/58) gehen allein darauf zurück.
- `evals/cases/live30.txt:13` (`de-lists-add`) ist `pending`, der Live-Satz hat daher 29 Fälle: gegen einen aktiven Fall tauschen.

## Abweichungen fürs Konzept (zur Bestätigung durch Stefan)

1. **Live-Satz 30 statt 150 Fälle** (Entscheid Stefan 2026-10-20); die 150 laufen nur gegen den Fake.
2. **Anthropic-Adapter: Thinking `between_tools`** für Sonnet 5.5 (lehnt `disabled` ab); Haiku bleibt ohne Thinking. „Kein Thinking“ gilt für Sonnet daher nur eingeschränkt.
3. **Runner**: neue Optionen `--max-cost`, `--provider-cap`, `--ledger`, `--ids`, `--pause-ms`, `--retry-rate-limit` (nicht im Konzept).
4. Modellempfehlung je Rolle (oben) ist ein Vorschlag, keine Änderung der App-Defaults.
