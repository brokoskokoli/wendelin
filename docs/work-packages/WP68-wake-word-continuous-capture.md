# WP68 – „Wendelin, mach …“ in einem Atemzug (`app/`, Kotlin-Dienst)

Abhängig von: WP64 (gleicher Sprachpfad, danach). Bezug: Wunsch Maintainer 2026-10-15, Konzept Pipeline Schritt 3 (Pre-Roll 300 ms), WP50 a (Mikrofon-Übergabe, `TriggerEvent.preRoll`), K31 (Nachprüfung ~0,9 s Nachlauf).

## Ziel
Ab dem Treffer des Wake Words wird lückenlos aufgenommen, damit man ohne Pause „Wendelin, schalte die Taschenlampe an“ sagen kann. Erkennt Stufe 1/2 das Wake Word nicht, passiert nichts.

## Inhalt
- Der Dienst puffert ab dem Kandidaten durchgehend (Ringpuffer) – auch während der Whisper-Nachprüfung und bis das Overlay das Mikrofon übernommen hat – und übergibt den gesamten Puffer ab Beginn des Wake Words als Pre-Roll. Die Overlay-Aufnahme schließt nahtlos an (keine Lücke, keine Doppelung; Messung der Übergabelücke in ms im Test/Log).
- Das Wake Word selbst wird vor dem Senden aus dem Transkript entfernt („Wendelin, …“ → „…“, auch Schreibvarianten aus K31); bleibt danach nichts übrig, wartet das Overlay wie bisher auf die Anfrage.
- VAD: Die Stille-Erkennung beginnt erst nach dem Wake Word, damit eine kurze Pause nach „Wendelin“ nicht sofort beendet.
- Bestätigungston: darf die Aufnahme nicht stören (Mute-Fenster aus WP50 b berücksichtigen; der Ton kommt nach dem Wake Word, die Aufnahme läuft weiter).
- Gesperrter Bildschirm (WP53) bleibt: nur Taschenlampen-Befehle lokal.

## Abnahmekriterien
- [ ] Tests mit eingespeistem Audio: „Wendelin schalte die Taschenlampe an“ ohne Pause → Anfrage „schalte die Taschenlampe an“; mit Pause → gleiches Ergebnis; nur „Wendelin“ → Overlay wartet; kein Wake Word → nichts.
- [ ] Test, dass zwischen Puffer und Overlay-Aufnahme keine Samples fehlen/doppelt sind.
- [ ] Emulator (separater E2E-Agent) mit synthetischer Stimme.
- [ ] Prüfpunkt in `docs/testing/m4-device.md`.

## Umsetzung (2026-10-15, Branch `wp/68-wake-continuous`)
**Wo Audio verloren ging (Analyse):** (1) `Endpointer`: Der Pre-Roll des Treffers (Wake Word + 0,9 s Nachlauf + Whisper-Zeit) lief als „Stille“ durch den Endpointer und blieb auf die letzten 300 ms gekürzt – alles, was nach „Wendelin“ während der Nachprüfung gesagt wurde, ging verloren (typisch 1,5 bis 2,5 s). (2) Zwischen Bestätigung und Overlay-Mikrofon war das Mikrofon zu (Dienst pausiert, Kotlin zeigt Sitzung, Overlay-Engine startet, Sperre prüfen, Ton, `prime()`): geschätzt 0,5 bis 1,5 s, im Emulator zu messen (`wake-gap`). (3) Der Ton wurde vor dem Mikrofonstart gespielt und das Wake Word blieb im Transkript.
**Jetzt:** `WakeWordDetection.wakeEnd/position`; `TriggerEvent.wakeEnd`; die Pipeline lässt das Wake Word aus, wertet alles danach per VAD (100 ms Rand) und die Stille-Erkennung zählt erst ab dort (`_feedPreRoll`); `stripWakeWord` (K31-Schreibvarianten, Anrede „Hey“) entfernt das Wort aus dem ersten Transkript, bleibt nichts übrig, hört die Pipeline weiter zu. Kotlin: Der Dienst behält das Mikrofon nach dem Treffer (`WakeHandoff.beginCapture/append`, `WakeMicTap` gleicht die schon unterwegs befindlichen Frames anhand der Stream-Position ab) bis das Overlay `takeWakeHandoff` ruft; das geschieht erst unmittelbar vor dem Öffnen des Overlay-Mikrofons (`VoiceController.start(takePreRoll:)`). Ton: kein Ton, wenn nach dem Wake Word schon gesprochen wird (`speechAfterWakeWord`); sonst wie bisher mit Mute-Fenster. Offen: Barge-in „Wendelin“ (WP64) liefert keinen Pre-Roll aus dem Detektor, der Mikrofonwechsel dort bleibt eine Lücke (Folgepunkt, betrifft `wake_word_barge_in.dart`/WP64b).
