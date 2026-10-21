# WP125 – Sammelpaket: Soll-Befunde aus den Reviews WP113–WP123

**Zuordnung:** Folgepunkte (STATUS.md, Spalte „Offen“). Go Stefan 2026-10-22 („starte noch ein paar weitere Pakete, nicht zu viel“). Kein neues Verhalten, nur Tests, kleine Fixes und Doku. Je Punkt ein Commit.

## Inhalt
1. **WP113:** Tests für die `stopOverridesWake`-Verdrahtung (`wake_barge_in.dart:194`) und das Settle (`wake_word_barge_in.dart:170`); `_verify` mit alter Generation (`:219`) prüfen/absichern.
2. **WP114:** `answerText`-Abbruch beim Modell-Laden (`voice_answer_text.dart:10`) testen; überlebende Mutanten M3/M5/M6/M8 aus `../james-wt/reviews/wp114-review*.md` mit Tests schließen.
3. **WP118:** Rennen erstes Play + Stopp (`audio_playback.dart:65`) beheben bzw. absichern; Besitzer-Token bei `dispose`; Test für `WakeConflictWatcher.kt:61` (Kotlin-Unit).
4. **WP119:** Test „`endSession` räumt gemerkte Sprache auf“.
5. **WP122:** Test für `AgentDone.fixed`; Satz „schon vorhanden“ (`confirmation_texts` de:30/34, en:45/48, fr:53/56) prüfen; Doku `fixed_confirmation.dart:20`; toten Schlüssel `lists_write_tools.dart:47` entfernen.
6. **WP123:** Provider-Test mit `take` statt `snapshot` (`wake_providers.dart:204`).
7. **CI-Flake** `wake_lifecycle_test` (UnmountedRefException): Ursache finden und beheben (kein Retry, kein Allowlist-Eintrag).

Details zu den Befunden: Review-Urteile in `../james-wt/reviews/wpNNN-review*.md`.

## Abnahmekriterien
- [ ] Jeder Punkt erledigt oder begründet als „kein Handlungsbedarf“ im Bericht; jeder neue Test mit Mutationsbeleg.
- [ ] Keine Verhaltensänderung für den Nutzer außer dem Fix in Punkt 3 (falls nötig) – sonst als Abweichung melden.
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE. E2E nur, falls Punkt 3 das Audio-Verhalten ändert (`voice_stop_word`/`voice_barge_in`, Emulator vorher beim Orchestrator anfragen).

## Parallel-Hinweise
- Parallel läuft WP121 (`tool/train_wake_word/`, `docs/notes/`) – keine Überschneidung.
- Ein E2E-Agent des Orchestrators nutzt gerade den Emulator (WP123-Nachweis). Bis dessen Ende kein E2E.
