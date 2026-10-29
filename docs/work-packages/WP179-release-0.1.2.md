# WP179 – Release 0.1.2

**Zuordnung:** Auftrag Maintainer 2026-10-29.

## Inhalt
- Version auf `0.1.2+3` anheben (`app/pubspec.yaml`, `wendelinAppVersion` in `app/lib/di/weather.dart`, `devArchiveAppVersion` in `app/lib/voice/dev_archive.dart`).
- `CHANGELOG.md` für Version 0.1.2 pflegen (Änderungen aus WP177 und WP178).
- `STATUS.md` nachziehen.

## Abnahmekriterien
- [x] Version in `app/pubspec.yaml` ist `0.1.2+3`.
- [x] Konstanten `wendelinAppVersion` und `devArchiveAppVersion` stimmen mit pubspec überein.
- [x] `tool/release_check.sh version v0.1.2` ist erfolgreich.
- [x] Tests grün, Gate grün, CI grün.
