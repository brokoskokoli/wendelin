# WP57 – Spike: lokales Sprachmodell auf dem Handy (Messung, Entscheidung)

Abhängig von: – (sofort, kein App-Code). Bezug: Wunsch des Maintainers 2026-10-14. Ergebnis: Notiz `docs/notes/local-llm-spike-<datum>.md`; wiederverwendbare Messskripte unter `tool/` bzw. `evals/`. Produktivcode kommt nicht auf `main`.

## Fragen
1. **Reicht ein kleines lokales Modell für typische Befehle?** Kandidaten (aktuelle Versionen recherchieren, Stand 2026): Gemma (kleinste Varianten mit Tool-Calling), Qwen (≈1,5–4 B), ggf. ein weiteres (z. B. Llama/Phi/SmolLM). Quantisierung Q4/Q5 (GGUF).
   - Messung mit dem vorhandenen Eval-Set (`evals/`, `dart run wendelin_evals:run`) über eine OpenAI-kompatible lokale Schnittstelle auf dem Mac (`ollama` ist installiert; alternativ `llama-server` aus llama.cpp). Kennzahlen: Trefferquote Tool-Aufrufe (richtiges Tool, richtige Argumente), getrennt nach Sprache (de/fr/en) und Kategorie (einfach: Timer/Wecker/Liste/Notiz/Termin; komplex: mehrstufig, Rückfragen), Halluzinationen von Tools, Antwortqualität kurz.
   - Varianten: voller Tool-Katalog vs. reduzierter Katalog für lokal (nur Kern-Integrationen), System-Prompt-Länge.
2. **Laufzeit auf dem Telefon (abgeschätzt/gemessen):** Prefill-Zeit für unseren System-Prompt (Tokenzahl messen), Tokens/s Generierung, RAM (PSS) neben Whisper (Ziel K14 c: ≤ 1,1 GB aktiv nur für Sprache – lokales LLM käme dazu), Modellgröße/Download. Emulator `Wendelin_AOSP_35` (arm64, nur explizites `emulator-xxxx`) mit llama.cpp-CLI per `adb push` als grobe Messung; Prüfliste für den Maintainer auf dem echten Gerät (Xiaomi 15T Pro).
3. **Einbindung (nur Bewertung):** llama.cpp über FFI/Plugin vs. LiteRT/MediaPipe (K7: keine Play-Services-Pflicht prüfen), APK-Zuwachs, Prompt-Cache (KV-Cache für den stabilen Prompt-Teil), Rolle im Routing (eigene Datenschutzstufe „lokal“ über TEE; Offline-Ziel; Eskalation bei Unsicherheit).
4. **Lizenzen** der Modelle (öffentliches Repo, private Nutzung, Weitergabe der Gewichte nicht über das Repo).

## Regeln
- Modelle nur außerhalb des Repos (`~/wendelin-models/llm/`), nie committen. Downloads in eigenen leeren Ordner.
- Keine Live-Keys nötig; Cloud-Vergleichswerte aus vorhandenen Eval-Reports (`evals/reports/`) nehmen, keine neuen Live-Läufe.
- Rechenlast: Messläufe begrenzen (ein Modell zur Zeit), keine anderen Agenten-Gates blockieren.

## Abnahmekriterien
- [ ] Tabelle: Modell × (Trefferquote gesamt/einfach/komplex, de/fr/en, Latenz Mac, Größe, Lizenz).
- [ ] Prefill/Generierung/RAM auf dem Emulator für das beste Modell; Prüfliste für das Gerät.
- [ ] Empfehlung: lokal ja/nein, welches Modell, welcher Aufgabenbereich, Einbindungsweg, nötige Konzeptänderungen (als Vorschlag).
