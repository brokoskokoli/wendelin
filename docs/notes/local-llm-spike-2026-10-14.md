# WP57 – Spike: lokales Sprachmodell (2026-10-14)

Messung mit dem vorhandenen Eval-Set (40 aktive Fälle: de 20, fr 10, en 10; zwei `pending` übersprungen) durch die echte Agent-Schleife, Modelle über Ollama 0.40.2 (OpenAI-kompatibel, `evals/profiles/ollama-local.json`, Privacy `local`). Aufruf: `tool/local_llm_eval.sh <modell>…`, Auswertung `dart run tool/local_llm_report.dart evals/reports/*ollama*.local.json`. Die Modelle liegen in `~/.ollama`, nicht im Repo. Der System-Prompt samt Tool-Katalog hat rund 2,4 k Token.

"Komplex" (10 Fälle, Definition in `tool/local_llm_report.dart`): Löschen mit Bestätigung, Web, Verschieben, freie Zeiten, Wiederholungs-Wecker, ganztägig. Das Eval-Set hat keine echten mehrstufigen Dialoge mit Rückfragen; "komplex" ist hier "mehrere Argumente oder Schritte ableiten".

## Ergebnis (voller Katalog)

| Modell (GGUF, Q4) | Größe | Lizenz* | gesamt | einfach (30) | komplex (10) | de | fr | en | Latenz p50/p90 (Mac) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Qwen3-4B-Instruct-2507 Q4_K_M | 2,5 GB | Apache 2.0 | 27/40 (68 %) | 22 (73 %) | 5 (50 %) | 55 % | 90 % | 70 % | 1,7 s / 6,7 s |
| Gemma 4 E2B (ollama `gemma4:e2b`, 7,5 GB, vermutlich nicht Q4) | 7,5 GB (LiteRT-LM-Datei 2,6 GB) | Apache 2.0 | 27/40 (68 %) | 23 (77 %) | 4 (40 %) | 55 % | 80 % | 80 % | 4,9 s / 14,8 s |
| Phi-4-mini 3.8B (ollama `phi4-mini`) | 2,5 GB | MIT | 7/40 (18 %) | 7 (23 %) | 0 | 15 % | 20 % | 20 % | 0,9 s / 5,2 s |

Zum Vergleich Cloud (`evals/reports/2026-10-13-*`, nur die ersten 10 Fälle): Claude Haiku und Gemma-4-31B (Phala) 10/10.
*Lizenz laut Modellseiten und Presse, vor produktiver Nutzung an der Primärquelle prüfen. Gewichte gehören nie ins Repo; der Nutzer lädt sie selbst.

Fehlerbilder: Gemma und Qwen **behaupten die Aktion ohne Tool-Aufruf** (je 9 Fälle, z. B. "Ich habe den Zahnarzttermin eingetragen", ohne `calendar__create_event`; Bestätigungs-Löschen wird nie angefragt). Falsche Argumente bei relativen Zeiten ("Freitag 14:30" wird 07:30, "halb sieben" wird 07:30, "Samstag" wird Freitag). Gemma ruft einmal `web__search` für "Hauptstadt von Frankreich". Phi-4-mini ruft fast nie ein Tool auf (31 Fälle ohne Aufruf). Erfundene Tool-Namen traten nicht auf. Einzelne Fehlschläge sind Wortlaut-Treffer (Antwort "hundertachtzig" statt 180, weil der Prompt Sprechstil verlangt), nicht echte Fehler.

## Variante reduzierter Katalog (nur calendar, alarms, memory, clipboard; ohne Web)

Ohne die 3 Web-Fälle (37 Fälle): Qwen voll 24/37, reduziert 26/37 (p50 1,5 s statt 1,7 s); Gemma voll 24/37, reduziert 23/37 (p50 5,6 s statt 4,7 s). Der Gewinn ist klein und liegt im Rauschen (eine Wiederholung je Variante, Sampling-Temperatur des Providers). Der Prompt-Anteil des Katalogs ist gering (Eingabe je Fall 4,8 k auf 4,6 k Token). Kürzere Prompts allein heben die Quote nicht auf Cloud-Niveau.

## Laufzeit auf dem Telefon

- **Emulator: offen.** `emulator-5580` (Wendelin_AOSP_35) war während des Spikes durch einen fremden `tool/e2e_android.sh`-Lauf belegt; zudem hat das AVD nur 2,5 GB RAM, das reicht für ein 4B-Modell (2,3 GB Gewichte) nicht. Für die Messung braucht es ein AVD mit mind. 6 GB und einen eigenen Slot. Bis dahin gilt nur die Schätzung.
- **Mac-Näherung** (llama-bench, Qwen3-4B Q4_K_M, 4 Threads, Mac unter hoher Last, Load ≈ 12, ohne Aussagekraft für absolute Werte; Backend ließ sich nicht auf reine CPU zwingen): Prefill ≈ 35 t/s (512 Token), Generierung ≈ 16 t/s; RSS des Bench-Prozesses ≈ 4,9 GB (inkl. Mac-Puffer, nicht übertragbar).
- **Schätzung Xiaomi 15T Pro** (Dimensity 9400+, CPU/GPU, Q4): Qwen3-4B Prefill grob 40 bis 120 t/s, Generierung 8 bis 15 t/s. Ein Prompt von 2,4 k Token braucht ohne Cache also 20 bis 60 s, mit KV-Cache des stabilen Prompt-Teils nur den neuen Teil (< 1 s). RAM: Gewichte 2,3 GB + KV-Cache (4k Kontext ≈ 0,3 bis 0,5 GB) = rund 2,8 bis 3 GB PSS. Das sprengt das Ziel K14 c (≤ 1,1 GB nur für Sprache) um das Dreifache; es müsste also zwingend entladen werden, wenn Whisper läuft. Gemma 4 E2B: LiteRT-LM-Datei 2,6 GB, Herstellerangaben (Galaxy S26 Ultra, CPU) Prefill ≈ 557 t/s, Generierung ≈ 47 t/s; deutlich schneller, aber auf einem anderen SoC und mit der Google-Laufzeit gemessen.
- **Prüfliste für das echte Gerät:** (1) `llama-bench`/`llama-cli` arm64 per `adb push` nach `/data/local/tmp`, Modell `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`; (2) `-p 2400 -n 64 -t 4` und `-t 6` messen, danach mit `--prompt-cache` zweiten Lauf; (3) `dumpsys meminfo` PSS während der Generierung und mit gleichzeitig geladenem Whisper; (4) Temperatur/Drosselung nach 5 Läufen; (5) Akku: Verbrauch eines 10-Befehle-Laufs (`dumpsys batterystats`); (6) Eval-Set gegen `llama-server` auf dem Gerät (`adb forward`), dann Trefferquote prüfen; (7) Gemma 4 E2B `.litertlm` mit LiteRT-LM-CLI vergleichen.

## Einbindung (nur Bewertung)

- **llama.cpp (FFI/Plugin):** volle Kontrolle, GGUF, Grammatik-/JSON-Constraint (würde die falschen Argument-Formate und fehlenden Aufrufe teils auffangen), KV-Cache/Prompt-Cache, keine Play-Services. APK-Zuwachs rund 5 bis 10 MB je ABI (nur arm64) plus Modell als Download. Aufwand hoch (NDK-Build, Isolate, Streaming), erfüllt K7.
- **LiteRT-LM (Nachfolger von MediaPipe LLM Inference, das nur noch gepflegt wird):** Gemma-4-Modelle als `.litertlm`, schnell (GPU/NPU), eingebautes Function Calling, Google-Referenz. Reine Bibliothek ohne Play-Pflicht, aber Modelle in Google-Format, Android-spezifisch, jüngere Reife. AICore/Gemini Nano nicht nutzen (Play-Services, K7).
- **Rolle im Routing:** Eigene Datenschutzstufe `lokal` oberhalb TEE (Daten verlassen das Gerät nie), Offline-Rückfall und Standardweg für wenige einfache Befehle (Timer, Wecker, Liste, Notiz, Zwischenablage). Bei Unsicherheit (kein Tool-Aufruf trotz Aktionsverb, Schema-Fehler, Kalender mit relativen Zeiten) Eskalation an TEE/Cloud über den vorhandenen Eskalationspfad. Die Erkennung "Aktion behauptet, aber kein Tool aufgerufen" muss hart in den Agenten, sonst lügt das lokale Modell.

## Empfehlung

- **Lokal: ja, aber nur als schmale Rolle, nicht als Default.** 68 % Trefferquote (de 55 %) sind für Kalender mit relativen Zeiten zu schlecht. Realistisch: Offline-Modus und Datenschutzstufe `lokal` für Timer, Wecker, Notiz, Zwischenablage, Listen (dort Qwen und Gemma treffen am besten), mit Eskalation bei Unsicherheit. Ein Versuch lohnt erst mit Constrained Decoding (JSON-Schema/Grammatik) und deutschem Few-Shot-Prompt; das vorab im Eval prüfen.
- **Modell:** Qwen3-4B-Instruct-2507 Q4_K_M (Apache 2.0, 2,5 GB, 2,5× schneller als Gemma auf dem Mac, beste Quote in fr und komplex); Gemma 4 E2B als Gegenkandidat für LiteRT-LM (kleiner und auf dem Telefon vermutlich schneller; hier nur in der großen Ollama-Variante gemessen). Phi-4-mini scheidet aus.
- **Einbindungsweg:** zuerst Eval-Verbesserung (Grammatik, Prompt) und Gerätemessung (Prüfliste), dann llama.cpp-Plugin als Port `LocalLlmPort` hinter dem `LlmProvider`-Interface (Provider-Typ `local`), Modell als optionaler Download.

## Konzeptvorschläge (zur Bestätigung durch den Maintainer)

1. Datenschutzstufe `lokal` (über TEE) und Provider-Typ `local` im Routing.
2. Agent: Schutz gegen "Aktion behauptet ohne Tool-Aufruf" bei schwachen Modellen (Aktionsverb + keine Tool-Calls = Eskalation).
3. K14 c: RAM-Budget "lokales LLM entlädt Whisper und umgekehrt" (gemeinsam ≤ 3 GB, nicht gleichzeitig).
4. Eval-Set um echte Mehrschritt- und Rückfrage-Fälle erweitern (aktuell nur Einzelaufrufe) und Wiederholungsläufe (Streuung).

## Entscheidung des Maintainers (2026-10-14)
Lokale Sprachmodelle werden nicht weiter verfolgt (Trefferquote und Latenz reichen nicht). Die Konzeptvorschläge oben entfallen; Eval-Profil und Skripte bleiben als Messwerkzeug erhalten.
