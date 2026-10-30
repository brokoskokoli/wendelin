# WP183 – Release 0.1.4

**Zuordnung:** Auftrag Maintainer 2026-10-30.

## Inhalt
- Version auf `0.1.4+5` anheben (`app/pubspec.yaml`, `wendelinAppVersion` in `app/lib/di/weather.dart`, `devArchiveAppVersion` in `app/lib/voice/dev_archive.dart`).
- `CHANGELOG.md` für Version 0.1.4 pflegen (Änderungen aus K146 und WP182: Overlay schließt nicht während Sprachausgabe/Ansage oder während des 10-Sekunden-Rückgängig-Fensters; schließt automatisch danach).
- `STATUS.md` nachziehen.

## Abnahmekriterien
- [x] Version in `app/pubspec.yaml` ist `0.1.4+5`.
- [x] Konstanten `wendelinAppVersion` und `devArchiveAppVersion` stimmen mit pubspec überein.
- [x] `tool/release_check.sh version v0.1.4` ist erfolgreich.
- [x] Tests grün, Gate grün, CI grün.
