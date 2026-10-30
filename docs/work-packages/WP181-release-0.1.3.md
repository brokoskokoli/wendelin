# WP181 – Release 0.1.3

**Zuordnung:** Auftrag Maintainer 2026-10-29 / 2026-10-30.

## Inhalt
- Version auf `0.1.3+4` anheben (`app/pubspec.yaml`, `wendelinAppVersion` in `app/lib/di/weather.dart`, `devArchiveAppVersion` in `app/lib/voice/dev_archive.dart`).
- `CHANGELOG.md` für Version 0.1.3 pflegen (Änderungen aus ADR 0024 und WP180: Zentrale Audioaufnahme, Ringpuffer, Multi-Subscriber, Fix für Mikrofon-Konflikte und Sprecher-Einlernen).
- `STATUS.md` nachziehen.

## Abnahmekriterien
- [x] Version in `app/pubspec.yaml` ist `0.1.3+4`.
- [x] Konstanten `wendelinAppVersion` und `devArchiveAppVersion` stimmen mit pubspec überein.
- [x] `tool/release_check.sh version v0.1.3` ist erfolgreich.
- [x] Tests grün, Gate grün, CI grün.
