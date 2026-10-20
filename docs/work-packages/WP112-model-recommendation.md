# WP112 – Modell-Empfehlung (Eval, Live-Messung)

**Zuordnung:** M6, „Empfehlung von Modellen“. Baut auf WP54b (`docs/notes/wp54-tee-eval.md`) und den Evals vom 13./14.10. auf. Entscheidungen Stefan 2026-10-20: „nicht das größte Modell, nicht irgendwie ein Thinking-Model, sondern halt einfach ein normales Modell, was halt aber schon größer ist, nicht das kleinste“; Budget freigegeben: alle 5 Anbieter, zusammen höchstens 8,50 €; Start parallel zu WP111.

Ergebnis ist eine Notiz `docs/notes/model-recommendation.md` mit Zahlen und einer Empfehlung je Rolle. App-Code nur, wenn die Empfehlung Standardwerte in Profilen ändert (dann als eigener, kleiner Commit).

## Inhalt

### 1. Testfälle
- Satz auf etwa **150 Fälle** erweitern (de ~70, en ~40, fr ~40), die die M5-Integrationen abdecken: Kalender, Aufgaben (Google Tasks), Bring, Spotify, Wetter, Web, Wecker/Timer, Notizen, Stationsmodus (`station__start`), Mehrschritt-Fälle, Rückfragen, Ablehnung gefährlicher Aktionen.
- Nur synthetische Inhalte (öffentliches Repo), Fakes für alle Integrationen; die Live-Kosten entstehen nur beim Modell.
- Bestehende Fälle unter `evals/cases/` erweitern (nicht duplizieren); Fälle je Integration in eigene Dateien, damit spätere Pakete konfliktfrei ergänzen.

### 2. Modelle und Anbieter (Obergrenze je Anbieter, hart)
| Anbieter | Modelle | Obergrenze |
|---|---|---|
| Anthropic (direkt) | Claude Haiku, Claude Sonnet (ohne Thinking) | 4,00 € |
| Phala/RedPill (TEE) | gemma-4-31b, deepseek-v4-flash, gpt-oss-120b (reasoning low) | 1,50 € |
| Tinfoil (TEE) | angebotene offene Modelle (z. B. gpt-oss-120b) | 1,00 € |
| NEAR AI (TEE) | angebotene offene Modelle | 1,00 € |
| OpenAI (Vergleich) | ein mittleres Modell, ohne Reasoning bzw. minimal | 1,00 € |

Keine Thinking-/Reasoning-Modi, keine größten Modelle. Tinfoil braucht ein neues Profil; NEAR hat jetzt einen eigenen Key (`NEAR_AI_API_KEY`) und wird diesmal separat gemessen.

### 3. Messung
- Jeder Fall 2× je Modell (Stabilität). Kennzahlen: Treffer (mit Wilson-Intervall), Fehlertypen, p50/p90-Latenz, Tokens, Kosten je Fall und hochgerechnet je Befehl.
- Empfehlung je Rolle: **normal** (Standard), **privat/TEE**, **schnell/Station** (Latenz), **Notfall/Fallback**.
- Erst kleiner Probelauf (≤ 5 Fälle je Modell), dann voller Lauf.

## Umsetzungshinweise
- Runner `evals/` erweitern: **Kostengrenze** (`--max-cost <€>` je Lauf; bricht ab, sobald die laufende Summe sie erreicht; Test mit Fake-Provider) und eine Gesamtbilanz je Anbieter in `reports/`. Ohne funktionierende Grenze kein Live-Lauf.
- Keys nur aus `~/.wendelin-live.env`, nie ausgeben/loggen/committen. Live-Tests getaggt, standardmäßig übersprungen. Reports ohne Keys/Header.
- Preise aus den Modell-Katalogen der Anbieter (Datum notieren).
- Kein Emulator, kein Training; lokale Last gering.

## Abnahmekriterien
- [ ] ~150 Fälle in de/en/fr, laufen grün gegen den Fake-Provider.
- [ ] Kostengrenze im Runner mit Test (Mutationsbeleg); Gesamtkosten aller Live-Läufe ≤ 8,50 €, je Anbieter unter der Obergrenze; Ist-Kosten in der Notiz.
- [ ] Notiz mit Tabelle je Modell (Treffer, Wilson, Latenz, Kosten) und Empfehlung je Rolle; Kommandos zum Wiederholen.
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Läuft neben WP111 (berührt nur `tool/train_wake_word/`, `tool/kws_measure.py`, `docs/notes/`). WP112 berührt `evals/` und `docs/notes/model-recommendation.md`; keine Überschneidung.
