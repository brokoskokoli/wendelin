# M5 – Plan (Android, Ausbau)

Festgelegt mit dem Maintainer 2026-10-18. iOS ist nach M6 verschoben. Kamera/Bild ist vorerst gestrichen. Stationsmodus und der Vergleich alternativer Wake Words kommen später. Die Empfehlung von Modellen (Evals live) wird nach diesen Paketen gemeinsam besprochen.

| Welle | Pakete | Hinweis |
| --- | --- | --- |
| 0 (läuft, M4-Rest) | WP81, WP82, WP83, WP76a–d (Tinfoil) | Korrekturen aus dem Gerätetest |
| 1 | WP79 App-Sprache, WP87 Wetter/Meer, WP84 Spotify, WP90 Mediensteuerung | WP79 früh, damit neue Texte gleich lokalisiert werden |
| 2 | WP85 Kontakte/SMS/Anrufe, WP86 Standort/Maps, WP88 Aufgaben, WP91 Home Assistant | |
| 3 | WP89a/b Todoist/Google Tasks, WP92a–c Sprechererkennung, WP93 Wake Word im Chat, WP94 Schnellwechsel | WP92c nach WP91 (gesperrt: Licht) |

Ablauf je Paket wie in M4: Coder (Sonnet, eigener Worktree) → Review (Opus) → Nachbesserung (frischer Agent) → E2E-Agent (Emulator) → Merge. Höchstens etwa 4 Coder gleichzeitig. Vor jedem neuen Paket das Wochenlimit prüfen (< 95 %).
