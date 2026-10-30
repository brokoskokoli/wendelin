# WP185 – Release 0.1.5

**Zuordnung:** Auftrag Maintainer 2026-10-30.

## Inhalt
- Version auf `0.1.5+6` anheben (`app/pubspec.yaml`, `wendelinAppVersion` in `app/lib/di/weather.dart`, `devArchiveAppVersion` in `app/lib/voice/dev_archive.dart`).
- `CHANGELOG.md` für Version 0.1.5 pflegen (Änderungen aus K147 und WP184: Multi-Subscriber für zentrales Audio, kein Mic-Busy bei Follow-Up nach Ansage, sauberer Wake-Vorlauf ohne vorzeitiges Silence-Abschneiden im gesperrten Modus).
- `STATUS.md` nachziehen.

## Abnahmekriterien
- [x] Version in `app/pubspec.yaml` ist `0.1.5+6`.
- [x] Konstanten `wendelinAppVersion` und `devArchiveAppVersion` stimmen mit pubspec überein.
- [x] `tool/release_check.sh version v0.1.5` ist erfolgreich.
- [x] Tests grün, Gate grün, CI grün.
