# Gerätetests (Übersicht)

- `m5/`: aktuelle Prüflisten je Arbeitspaket (`m5/<wp>.md`), Index in [m5/README.md](m5/README.md) (erzeugt). Hier gehören neue Anleitungen hin (auch für M6). Jede Datei trägt als zweite Zeile `> Stand: gültig`, `> Stand: teilweise überholt (…)` oder `> Stand: überholt durch WPnn` (prüft `check_docs`, der Index zeigt den Stand).
- Pakete ohne Gerätebezug bekommen keine Anleitung; das Paket nennt „Gerätetest: nicht nötig (Grund)“ in seiner Paketdatei.
- [m4-device.md](m4-device.md): große Gesamtliste für M3 und M4, Stand vor WP134/WP165 (Stopp-Wort und Gesprächston entfallen); als Nachschlagewerk, nicht mehr als Ablauf.
- Kopfvermerk in einer Anleitung („überholt“, „teilweise überholt“) gilt: Punkte, die „Stopp“ oder Gesprächston nennen, werden nicht geprüft.
- Ausführung: Befehle am Telefon führt nur der Maintainer aus; Emulator-Läufe macht der E2E-Agent (`tool/e2e_android.sh`).
