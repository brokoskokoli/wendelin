# WP123 – Stopp sofort ab Antwortbeginn (Barge-in ohne Aufwärm-Lücke), E2E stabil

**Zuordnung:** M6, Folge aus WP113/WP120 (Stopp-E2E rot auf main). Diagnose 2026-10-21: `barge-diag sim=-1` heißt „kein Merkmalsfenster fertig“, nicht „nicht erkannt“ (`app/lib/voice/wake/barge_meter.dart:25,37,115`, `onWindow` nur aus `packages/wendelin_voice/lib/src/wake/candidate_wake_engine.dart:147`).

## Befunde
1. **Echte Geräte:** Beim Start des Barge-Listeners leert `reset()` die Merkmalskette (`app/lib/voice/wake/wake_barge_in.dart` ~133). Die Kette braucht ~2,1 s Audio (76 Mel-Frames + 16 Embeddings, `app/lib/platform/voice/wake_feature_chain.dart:34-37,94`), bevor sie bewertet. Ein „Stopp“ in den ersten ~2 s der Antwort wird nicht erkannt.
2. **Emulator/Test:** `WavAudioInput` liefert per `Timer.periodic` je Tick genau einen 20-ms-Frame (`app/lib/platform/voice/wav_audio_input.dart` ~120). Unter Last kommen nur 7–27 statt 50 Frames/s an; das Wort im WAV wird nie erreicht.

## Inhalt
- **Warmstart:** Die Kette beim Start des Barge-Listeners nicht kalt beginnen, z. B. mit einem Ringpuffer der letzten ~2 s Mikrofon-Audio vorfüllen bzw. die Kette aus der Wake-/Folgefenster-Erkennung weiterlaufen lassen. Dabei kein Echo der eigenen Antwort als Vorlauf (Antwort beginnt erst nach dem Vorlauf). Stopp-Schwellen, Gegenprüfung und Echo-Filter (K90) unverändert.
- **WavAudioInput holt auf:** Im Tick so viele Frames liefern, wie nach Stopwatch fällig sind (verhält sich wie gepuffertes Mikrofon). Kein Wanduhr-Assert in Tests (check_flaky).
- **Diagnose:** `barge-diag` bekommt `win=<Anzahl Fenster>`, damit „kein Fenster“ von „nicht erkannt“ unterscheidbar ist.

## Abnahmekriterien
- [ ] Test (fakeAsync): Nach Start des Barge-Listeners wird ein Fenster spätestens nach ≤ 0,3 s Audio bewertet (statt ~2,1 s); Mutationsbeleg (Warmstart aus → rot).
- [ ] Test: `WavAudioInput` liefert bei verpassten Ticks die fälligen Frames nach.
- [ ] `voice_stop_word_e2e_test` und `voice_barge_in_e2e_test` grün auf emulator-5554, 3 Läufe in Folge (bei Last ≤ ~8 ausführen; Last im Bericht).
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE; Gerätetest `docs/testing/m5/wp123.md` (Stopp direkt nach Antwortbeginn, 10×).

## Parallel-Hinweise
- WP122 (Agent-Schleife, Bestätigungsvorlagen) und WP121 (tool/train_wake_word, docs/notes, CPU-Last) laufen. WP123 berührt `app/lib/voice/wake/`, `app/lib/platform/voice/wav_audio_input.dart`, `wake_feature_chain.dart`, `packages/wendelin_voice/lib/src/wake/`, die zwei E2E-Tests.
