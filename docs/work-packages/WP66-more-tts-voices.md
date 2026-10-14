# WP66 – Mehr Stimmen: je Sprache männlich und weiblich (`wendelin_voice`, `app/`)

Bezug: Wunsch des Maintainers 2026-10-15. Heute gibt es je eine Stimme für Deutsch, Französisch und Englisch.

## Inhalt
- Je Sprache (de, fr, en) mindestens eine weibliche und eine männliche Stimme (lokale TTS wie bisher, z. B. Piper/VITS über sherpa-onnx; Lizenz je Stimme prüfen und im Katalog vermerken, nur frei nutzbare Stimmen). Download bei Bedarf wie die übrigen Modelle, Größe anzeigen.
- Auswahl der Stimme in einem Untermenü unter Sprache („Stimmen“), je Sprache, mit „Probe hören“. Bisherige Auswahl wird migriert.
- Speicher: nur die gewählten Stimmen laden, ungenutzte löschbar.

## Abnahmekriterien
- [ ] Katalogtests (Prüfsummen, Lizenz, Sprache, Geschlecht), Migration der bisherigen Auswahl.
- [ ] Widget-Tests + Goldens für das Untermenü.
- [ ] Emulator (separater E2E-Agent): Stimme wechseln und Probe abspielen.
- [ ] Gate grün.
