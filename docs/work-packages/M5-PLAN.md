# M5 – Plan (Android, Ausbau)

Festgelegt mit dem Maintainer 2026-10-18 (K48). M5 ist nur Android. Kamera/Bild, Stationsmodus, Vergleich alternativer Wake Words und die Empfehlung von Modellen kommen in M6, iOS in M7.

| Welle | Pakete | Hinweis |
| --- | --- | --- |
| 0 (läuft, M4-Rest) | WP81, WP82, WP83, WP76a–d (Tinfoil) | Korrekturen aus dem Gerätetest |
| S (Beschleunigung, vorrangig) | WP95 CI als Gate, WP96 Gate schlank/stabil, WP97 Lastbremse/Cache, WP98 konfliktarm (l10n-Fragmente mit WP79) | Analyse `docs/notes/dev-speedup-analysis.md`; Coder pushen `wp/*` (Maintainer 2026-10-18) |
| 1 | WP79 App-Sprache, WP87 Wetter/Meer, WP84 Spotify, WP90 Mediensteuerung | WP79 früh, damit neue Texte gleich lokalisiert werden |
| 2 | WP85 Kontakte/SMS/Anrufe, WP86 Standort/Maps, WP88 Aufgaben, WP91 Home Assistant | |
| 3 | WP89a/b Todoist/Google Tasks, WP92a–c Sprechererkennung, WP93 Wake Word im Chat, WP94 Schnellwechsel | WP92c nach WP91 (gesperrt: Licht) |

Ablauf je Paket wie in M4: Coder (Sonnet, eigener Worktree) → Review (Opus) → Nachbesserung (frischer Agent) → E2E-Agent (Emulator) → Merge. Höchstens etwa 4 Coder gleichzeitig. Vor jedem neuen Paket das Wochenlimit prüfen (< 95 %).
- WP102 Spike bessere Sprache (Messung), danach WP103 Einbau (K64, 2026-10-19).
- WP104 liegengebliebene Gerätetests übernehmen (Standort, Aufgaben, HA, sprachneutrale Texte, overlay-Reihenfolge-Flake), 2026-10-19.
