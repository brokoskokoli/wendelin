# WP113 – „Stopp“ während der Antwort mit Gegenprüfung (`app/`, Sprache)

**Zuordnung:** M5-Nachtest (Gerätetest 2026-10-20, `~/ai/wendelin-testing/ergebnisse-2026-10-20.md` T20-B.1). Bezug: K47 (WP80). Entscheid Stefan 2026-10-21: Kandidat mit niedriger Schwelle wird vom großen Erkenner gegengeprüft, wie beim Wake Word (K84).

## Befund (Gerät, Xiaomi 15T Pro)
- Aufschlag +0,05 (`sthr=0.95`): „Stopp“ erreicht nie die Schwelle (gemessen 0,72–0,94, einmal 0,95 ohne `barge-hit`).
- Aufschlag 0,00 (`thr=0.85 sthr=0.90`): ständige Fehlabbrüche, 3× `keyword-wake` knapp an der Schwelle (sim 0,85–0,86).
- **Fehler:** zweimal lag `stop` 0,94/0,95 über `sthr`, gewertet wurde trotzdem `wake` (00:24:26, 00:24:54).
- „Stopp“ geht laut Stefan auch nicht, wenn Wendelin gerade nicht spricht.
- Die Anzeige zeigt nicht, dass Wendelin während der Ausgabe mithört.

## Inhalt
1. **Wertung beheben:** Liegen Stopp und Wake beide über ihrer Schwelle, gilt die Regel aus K47 bzw. ein eindeutiger, getesteter Vorrang (Stopp vor Wake während der Ausgabe). Regressionstest mit den Werten aus dem Log.
2. **Zwei Stufen:** Stufe 1 (Vorlagen-/Keyword-Modell) mit niedrigerer Schwelle liefert einen Kandidaten. Stufe 2 prüft den Audioausschnitt mit dem großen Erkenner (wie `wake-cand` → `wake-verify`) auf „Stopp“ bzw. „Wendelin“, sprachabhängig (de/en/fr: Stopp/Stop/Arrête, je nach vorhandener Liste). Die eigene Ausgabe filtern: AEC plus Abgleich mit dem gerade vorgelesenen Text (ein Wort, das gerade vorgelesen wird, zählt nicht).
3. **Schwellen:** Standardwerte so wählen, dass ein Kandidat mit gemessenen 0,72–0,94 durchkommt; Stufe 2 verhindert die Fehlabbrüche. Werte und Begründung in `docs/notes/` (kurz).
4. **„Stopp“ außerhalb der Ausgabe:** klären, was erwartet ist (laut Konzept K47), und dokumentieren bzw. beheben.
5. **Anzeige:** Während der Ausgabe ein sichtbares „hört mit“ (z. B. Ring am Wellen-Knopf), Texte über ARB (de/en/fr).
6. **Log:** `barge-cand`/`barge-verify` mit Werten, ohne Inhalt außer dem erkannten Schlüsselwort.

## Abnahmekriterien
- [ ] Regressionstest für den Wertungsfehler (Mutationsbeleg).
- [ ] Unit-Tests für Kandidat → Gegenprüfung → Treffer/Verwerfen, Eigen-Echo-Filter.
- [ ] E2E auf dem Emulator (bestehende `voice_stop_word_e2e_test`/`voice_barge_in_e2e_test` erweitert), Gerätetest-Datei `docs/testing/m5/wp113.md`.
- [ ] Gate `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Sprach-Controller-Paket: läuft **nicht** gleichzeitig mit WP114. Parallel laufen WP112 (`evals/`), WP115 (`tar_bz2.dart`, STT-Adapter-Log) und WP116 (Einstellungsseiten). Einstiegsstellen: `app/lib/voice/wake/wake_barge_in.dart`, `app/lib/voice/wake/barge_meter.dart`, `packages/wendelin_voice/lib/src/pipeline/`.
