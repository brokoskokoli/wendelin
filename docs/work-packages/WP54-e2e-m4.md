# WP54 – End-to-End M4: Emulator, Geräte-Testanleitung, Demo

Abhängig von: allen M4-Paketen. Vorbild: WP29 (`WP29-e2e-m3.md`), `tool/e2e_android.sh`, `docs/testing/m2-device.md`. Andockpunkte: `tool/e2e_android.sh` (Host-Aufträge in `files/e2e/host-request`), `WavAudioInput`, Debug-Überschreibungen `app/lib/debug/`, Evals `evals/`.

## Inhalt
- E2E-Modus Wake Word in `tool/e2e_android.sh` (nur `emulator-`-Serial, `ro.kernel.qemu=1`): Rolle setzen, Dienst einschalten, `KEYCODE_SLEEP`, WAV-Folge einspeisen („Wendelin“ + Frage, „Wendelin“ + „Taschenlampe an“ bei Sperre, Folgefrage im Gesprächsmodus, „Stopp“ während der Ausgabe). Emulator-Neustart mit Rolle und Prüfung `wake-start source=vis`.
- E2E TEE: Phala-Profil mit Fixture-Transport (grün, manipuliert rot). Optional live mit `WENDELIN_LIVE` (kleinstes TEE-Modell, ≤ 20 Tokens).
- Eval: TEE-Modelle aus `is_tee` gegen den Befehlssatz (Trefferquote, Latenz, Kosten), Grundlage für das Phala-Standardmodell (K8 g).
- `docs/testing/m4-device.md`: Prüflisten aus WP42, WP47, WP48, WP50–WP53 zusammengeführt, mit Logfiltern (`Wendelin/voice`, `Wendelin/attest`) und Messwert-Tabellen zum Ausfüllen.
- Demo-Anleitung im README (Wake Word, Gesprächsmodus, Phala mit Prüfstatus, Taschenlampe bei Sperre).

## Abnahmekriterien
- [ ] Emulatorlauf vollständig grün, Laufzeit und Messwerte (PSS Hintergrund, Treffer 10/10, Neustart) im Bericht.
- [ ] Fixture-TEE-Lauf grün/rot wie erwartet. Live-Lauf (falls Key vorhanden) grün, Kosten im Bericht.
- [ ] Eval-Ergebnis für TEE-Modelle als Notiz unter `docs/notes/`.
- [ ] `docs/testing/m4-device.md` vollständig. Die Definition of Done aus `M4.md` ist Punkt für Punkt belegt oder als Handytest offen markiert.
- [ ] Gate grün, APK baut, `tool/check_apk.sh` grün.
