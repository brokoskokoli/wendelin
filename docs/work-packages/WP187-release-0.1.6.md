# WP187 – Release 0.1.6

**Zuordnung:** Auftrag Maintainer 2026-10-30.

## Inhalt
- Version auf `0.1.6+7` anheben (`app/pubspec.yaml`, `wendelinAppVersion` in `app/lib/di/weather.dart`, `devArchiveAppVersion` in `app/lib/voice/dev_archive.dart`).
- `CHANGELOG.md` für Version 0.1.6 pflegen (Änderungen aus K148 und WP186: `FLAG_KEEP_SCREEN_ON` in `AssistantActivity` gegen vorzeitigen Display-Timeout im gesperrten Zustand, Schutz des 5-Sekunden-Follow-Up-Zuhörfensters in `overlay_idle_close.dart`).
- `STATUS.md` nachziehen.

## Abnahmekriterien
- [x] Version in `app/pubspec.yaml` ist `0.1.6+7`.
- [x] Konstanten `wendelinAppVersion` und `devArchiveAppVersion` stimmen mit pubspec überein.
- [x] `tool/release_check.sh version v0.1.6` ist erfolgreich.
- [x] Tests grün, Gate grün, CI grün.
