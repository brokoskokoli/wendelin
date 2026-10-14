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
