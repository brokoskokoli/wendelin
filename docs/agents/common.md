# Gemeinsame Regeln (alle Rollen)

- **Identität:** Committen darf nur `Stefan Richter <16724498+brokoskokoli@users.noreply.github.com>`. Die Nachricht endet mit genau diesen Trailern, unabhängig vom eigenen Modell: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` und `Claude-Session: https://claude.ai/code/session_01FAxzEqTunm3yHrEthnFhUT` (der Hook lehnt andere Co-Autoren ab). Nie `--no-verify`, nie Identitäts-Overrides. Das Repo ist öffentlich: keine Secrets, keine privaten Daten.
- **Arbeitsort:** nur der zugewiesene Worktree unter `../james-wt/`. Andere Worktrees, `../james-device-test` und fremde Prozesse (kein `pkill`) fasst du nicht an. Temporäre Dateien legst du nur im Scratchpad-Ordner aus dem Auftrag ab.
- **Lesen:** zuerst `docs/ARCHITECTURE.md` (Karte), dann gezielt mit `grep -n` und `sed -n` bzw. Read mit Bereich. Ganze große Dateien liest du nicht. Bestehende Dateien änderst du mit Edit.
- **Gate:** `dart run tool/gate.dart --changed` während der Arbeit. Die Ausgabe ist kompakt; bei Rot steht dort der Fehler mit Datei und Zeile.
- **Geräte:** nur ein Emulator `Wendelin_AOSP_35` mit explizitem Serial `emulator-xxxx`, über `tool/android_device.sh`. Vorher `adb devices`. Niemals ein echtes Gerät, niemals `E2E_ALLOW_DEVICE`. Ist der Emulator belegt oder läuft ein fremder, wartest du nicht: Melde den Gerätetest als offen.
- **Warten:** Lange Läufe (Gate, Build, Emulator, CI) startest du im Hintergrund. Pollen nicht im Sekundentakt.
- **Konzept:** Abweichungen trägst du nicht selbst ein, sondern meldest sie im Bericht.
- **Bericht:** höchstens 10 bis 15 Zeilen, Belege als Datei:Zeile.
