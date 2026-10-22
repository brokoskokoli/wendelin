# WP124 – Emulator nur während der Gerätetests

**Zuordnung:** Werkzeuge. Wunsch Maintainer 2026-10-21: „dass der End-to-End-Test immer den Emulator beendet, wenn er fertig ist, und der nächste, der ihn braucht, ihn wieder startet. Das braucht halt irgendwie eine Minute, aber jetzt aktuell läuft halt ständig der Emulator, obwohl ich ihn nicht brauche.“

## Inhalt
- `tool/e2e_android.sh` startet das AVD `Wendelin_AOSP_35` selbst, wenn kein Emulator läuft (ohne Fenster, ohne Audio, ohne Boot-Animation, `-no-snapshot-save`, feste Portnummer → Serial `emulator-5554`, bzw. Port aus `DEVICE=emulator-NNNN`), und wartet auf `sys.boot_completed` (Zeitlimit, dann Abbruch mit klarer Meldung).
- Am Ende jedes Laufs (auch bei Abbruch, im `cleanup`) wird der Emulator beendet (`adb emu kill`, kurz warten, bis er weg ist), und zwar **bevor** die Emulator-Sperre freigegeben wird.
- Ausnahme für mehrere Läufe hintereinander: `E2E_KEEP_EMULATOR=1` lässt ihn laufen; der letzte Lauf ohne die Variable beendet ihn.
- Gleichzeitige Starts: ein Start-Mutex im Sperr-Verzeichnis; wer ihn nicht bekommt, bricht sofort ab (kein Warten, wie WP110).
- Echte Geräte: nie gestartet, nie beendet. Ist nur ein echtes Gerät verbunden und kein `DEVICE` gesetzt, wird der Emulator gestartet und benutzt (statt das echte Gerät zu wählen).
- Logik in eigener Datei `tool/emulator_boot.sh` (zum Einbinden), Selbsttest mit Fake-`adb`/Fake-`emulator` in `tool/src/` im Gate-Schritt „tool self-test“.
- Doku: `docs/agents/common.md` („Geräte“), Kopf von `tool/e2e_android.sh`, `docs/ENGINEERING.md` (Zeile zur Emulator-Sperre ergänzen).

## Abnahmekriterien
- [ ] Kein Emulator läuft → Lauf startet ihn, Tests laufen, danach ist kein Emulator-Prozess mehr da.
- [ ] `E2E_KEEP_EMULATOR=1` → Emulator läuft danach weiter.
- [ ] Selbsttests (Start, kein Doppelstart, Beenden, Keep, echtes Gerät wird nicht beendet) mit Mutationsbeleg; `dart run tool/gate.dart --changed` grün, CI grün.
