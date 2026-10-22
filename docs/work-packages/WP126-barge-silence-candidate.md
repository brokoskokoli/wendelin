# WP126 – „Stopp“ nach Warmstart: Fehlkandidat auf Stille blockiert das echte Wort

**Zuordnung:** Fehler aus WP123 (K96). Befund Orchestrator 2026-10-22: `voice_stop_word_e2e_test` grün bis ad6db5ad (WP120), rot ab ab054e98 (WP123), 3/3 rot auf main auch bei Last 3,5. `voice_barge_in_e2e_test` grün.

## Ursache (Log des roten Laufs)
- Warmstart (`app/lib/…/wake_word_barge_in.dart:140-152`, `micTailProvider`) füllt die Merkmalskette vorab; die erste Fensterbewertung kommt bei t=1 statt t=3.
- Das 1,5-s-Stille-Vorspiel von `barge.wav` (`rms=0`) bekommt `stop=0.85` > `sthr=0.70` → falscher `barge-cand` (t=1). Dessen Whisper-Prüfung (Stille + Wortanfang) → `result=no`.
- Das echte „Stopp“ (t=3, `stop=0.96`) fällt in `busy`/Abklingzeit und wird aufgeschoben (`:191-194`); die Prüfung auf dem späteren Fenster (t=4) → wieder `no`. Danach nur `skip reason=silent/stopped`, kein `barge-hit`.
- Im Alltag genauso möglich: leise Phase direkt am Antwortanfang → Fehlkandidat → echtes „Stopp“ geht verloren.

## Inhalt
1. Kandidaten auf Fenstern ohne Pegel nicht werten (Pegel-Untergrenze aus der vorhandenen `rms`-Diagnose, Wert begründen) **und** prüfen, warum Stille nach dem Warmstart einen hohen Stopp-Score bekommt (Merkmale aus Null-/Füll-Audio? Warmstart-Puffer korrekt ausgerichtet?). Ursache beheben, nicht nur maskieren.
2. Ein Prüfergebnis `no` darf ein danach eintreffendes, stärkeres Stopp nicht verschlucken: aufgeschobener Kandidat bekommt eine eigene Prüfung auf seinem Fenster (bzw. Abklingzeit nach `no` nicht für neue Kandidaten mit höherem Score).
3. Aus WP125 übernommen (gleiche Dateien): Tests für `stopOverridesWake`-Verdrahtung (`wake_barge_in.dart:194`) und Settle (`wake_word_barge_in.dart:170`), `_verify` mit alter Generation (`:219`); Provider-Test mit `take` statt `snapshot` (`wake_providers.dart:204`).

## Abnahmekriterien
- [ ] Unit-Test reproduziert das Muster (Stille-Fenster mit hohem Score, danach echtes Stopp) und ist vor dem Fix rot; Mutationsbeleg für Pegel-Grenze und Punkt 2.
- [ ] `voice_stop_word_e2e_test` und `voice_barge_in_e2e_test` je 3× grün auf dem Emulator (Befehl `docs/testing/m5/wp123.md:23`; seit WP124 Autostart, `E2E_KEEP_EMULATOR=1` für Lauf 1–2).
- [ ] Barge-in „Wendelin“ unverändert; kein früheres Schließen durch Stille.
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE. Abweichungen (neue Schwelle) melden → Konzept K96.

## Parallel-Hinweise
- WP125 läuft parallel (Tests/Fixes WP114/118/119/122, CI-Flake wake_lifecycle_test); die Barge-in-Punkte (WP113, WP123) sind hierher verschoben. WP118-Punkt `audio_playback.dart` bleibt in WP125 – dort nicht anfassen.
- Emulator: WP126 hat Vorrang; vor E2E kurz beim Orchestrator melden.
