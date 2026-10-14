# WP54b: Eval der TEE-Modelle (2026-10-14)

Ziel: Grundlage für das Phala-Standardmodell (K8 g). Alle TEE-Modelle laufen über RedPill (`api.redpill.ai`, `is_tee: true`); NEAR AI hat keinen eigenen Key und ist nur Upstream des Gateways, also nicht separat gemessen.

## Aufbau

- Profil `evals/profiles/phala-tee-small.json` (Preise aus `/v1/models` vom 2026-10-14 ergänzt: deepseek-v4-flash, qwen3.6-35b-a3b, qwen3.8-27b, llama-3.3-70b).
- Satz: alle 40 aktiven Fälle (de 20, fr 10, en 10; 2 Listen-Fälle `pending`), „heute“ = Mi 18.11.2026, Aufruf `dart run wendelin_evals:run -p profiles/phala-tee-small.json -m <modell> -o reports/2026-10-14-phala-full-<modell>.json`.
- Seit M4 verlangt `ProviderFactory` für RedPill die native Attestierungs-Verdrahtung. Die Evals messen das Modell, nicht die Attestierung: `buildProvider` (`evals/lib/src/cli.dart`) baut für solche Profile den `OpenAiChatAdapter` direkt, mit `aci_verified: true` im Request wie in der App. Die Latenz enthält deshalb keine Attestierung. Test: `evals/test/cli_test.dart`.
- Latenz ist Wanduhrzeit der Agent-Schleife (mehrere Modellaufrufe je Fall) und lag heute deutlich über den Werten vom 13.10. (Last auf dem Gateway); Vergleich nur innerhalb dieses Laufs.

## Ergebnis

| Modell | Treffer | p50 | p90 | Tokens | Kosten (40 Fälle) | je Anfrage |
| --- | --- | --- | --- | --- | --- | --- |
| `google/gemma-4-31b-it` | **40/40** | 4,7 s | 12,4 s | 278 634 | 0,032 $ | 0,0008 $ |
| `z-ai/glm-5.3-flash` | 39/40 | 8,8 s | 24,5 s | 259 929 | 0,019 $ | 0,0005 $ |
| `deepseek/deepseek-v4-flash-0731` | 39/40 | 4,0 s | 7,1 s | 256 877 | 0,040 $ | 0,0010 $ |
| `openai/gpt-oss-120b` | 36/40 | 3,2 s | 6,3 s | 170 333 | 0,028 $ | 0,0007 $ |
| `qwen/qwen3.6-35b-a3b` | 35/40 | 4,7 s | 9,8 s | 272 718 | 0,033 $ | 0,0008 $ |
| `meta-llama/llama-3.3-70b-instruct` | 17/40 (abgebrochen) | 2,8 s | 15,0 s | 413 461 | 0,83 $+ | – |

Fehlschläge:

- gemma: keine.
- glm-5.3-flash: ein englischer Fall; Reasoning, daher langsam (Reasoning ist auf RedPill nicht abschaltbar).
- deepseek-v4-flash: `de-cal-frei` (freie Zeit, Antwort mit zwei Möglichkeiten statt der erwarteten).
- gpt-oss-120b: `de-cal-ganztag`, `de-cal-frei`, `de-cal-verschieben`, `en-cal-delete` (listet nur, ändert/löscht nicht).
- qwen3.6-35b-a3b: Löschen und Verschieben ohne Aufruf, Wecker/Timer ohne Tool-Aufruf (3 Fälle).
- llama-3.3-70b: nur 17/40, viele Fälle ohne Tool-Aufruf, die französischen Fälle brachen mit Providerfehler ab; ohne Cache-Preis und mit sehr langem Prompt je Aufruf ca. 15 000 Tokens, daher teuer (siehe Abweichung). Ungeeignet.

## Empfehlung (K8 g)

**`google/gemma-4-31b-it` bleibt Phala-Standardmodell**: einziges Modell mit 40/40 über alle drei Sprachen und alle Kategorien, 0,0008 $ je Anfrage. Der Wert bestätigt die Wahl aus der 10-Fälle-Messung vom 13.10. Schwäche ist der lange Schwanz der Latenz (p90 12 s). Falls das im Gerätetest stört: `deepseek/deepseek-v4-flash-0731` (39/40, p50 4,0 s, p90 7,1 s, 0,001 $) als Alternative; `glm-5.3-flash` ist am billigsten, aber mit p50 8,8 s zu langsam für Sprache. `qwen-2.5-7b`, `gpt-oss-120b`, `qwen3.6-35b-a3b` und llama fallen wegen unzuverlässiger Tool-Aufrufe (Löschen, Verschieben, Wecker) aus. Je Modell nur ein Lauf; Einzelfälle schwanken (Stichprobe 40).

## Kosten und Abweichung

Gesamtkosten dieser Läufe etwa 0,98 $ (ohne llama etwa 0,15 $). Der Llama-Lauf hat das Budget von 0,50 € überschritten: ca. 0,83 $ bei 17 ausgewerteten Fällen (2 $/M Token Ein- und Ausgabe, kein Cache, 15 000 Tokens je Aufruf). Das ließ sich vorab nicht ohne Teilmessung sehen; künftig bei teuren Modellen mit `--limit 5` starten.
