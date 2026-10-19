# WP104 – Liegengebliebene Gerätetests übernehmen (`app/integration_test`, `tool/`)

**Zuordnung:** M5 (Aufräumen).

Bezug: Folgepunkte aus WP86, WP88, WP91 und WP81b (STATUS.md). Mehrere E2E-Agenten haben Tests geschrieben, die nicht ins Repo kamen, weil das Skript eine Vorbereitung nicht konnte.

## Inhalt
1. **Standort (WP86):** `location_e2e_test.dart` übernehmen; `tool/e2e_android.sh` erteilt dafür ACCESS_FINE/COARSE_LOCATION (`pm grant`) und setzt die Position (`adb emu geo fix`).
2. **Aufgaben (WP88):** `tasks_saf_e2e_test.dart` übernehmen.
3. **Home Assistant (WP91):** `ha_e2e_test.dart`, `app/tool/ha_test_server.dart`, `tool/e2e_ha.sh` übernehmen (lokaler Fake-Server, keine echten Geräte).
4. **Sprachneutral:** `calendar_e2e_test.dart:181` sucht fest „Rückgängig · “ und ist auf englischem Emulator rot; Texte über l10n bzw. Key suchen. Weitere feste deutsche Texte in `app/integration_test/` ebenso.
5. **Reihenfolge-Flake (WP81b):** `overlay_e2e_test.dart` war direkt nach `overlay_tee_speak_e2e_test.dart` in derselben Skriptsitzung rot. Ursache finden (Restzustand?) und beheben oder Zurücksetzen zwischen Dateien.

Quellen außerhalb des Repos (nur lesen, nicht löschen): `../james-wt/handoff/wp86-location_e2e_test.dart`, `../james-wt/handoff/wp88-e2e/`, `../james-wt/handoff/wp91-e2e/`.

## Abnahmekriterien
- [ ] Alle übernommenen Tests laufen auf `Wendelin_AOSP_35` grün über `tool/e2e_android.sh` (Standort, Aufgaben, HA, Kalender auf de **und** en).
- [ ] `overlay_tee_speak` gefolgt von `overlay_e2e` in einem Lauf grün (zweimal wiederholt).
- [ ] Keine echten Daten, keine Keys; Gate grün.
