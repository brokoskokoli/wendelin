# WP92a Sprechererkennung

Voraussetzung: Emulator oder Gerät, Mikrofon erlaubt, Netz für den Modelldownload (CAM++, ca. 28 MB).

- [ ] **Standard aus**: Einstellungen → Sprache → „Sprechererkennung“. *Erwartet*: Schalter aus, Hinweis „Die Stimme ist keine sichere Anmeldung …“; ohne Schalter wird kein Modell geladen und die Sprachpipeline läuft wie vorher (Speicher/Latenz unverändert).
- [ ] **Modell laden**: Zeile „Sprechererkennung (CAM++)“ → Laden. *Erwartet*: Fortschritt, danach „Installiert“; „Person einlernen“ erst dann bedienbar (vorher „Lade zuerst das Modell.“). Auch in der Lizenzliste unter Sprache.
- [ ] **Person einlernen**: Namen eingeben, fünf Sätze vorlesen. *Erwartet*: je Satz Hinweis bei zu leise/zu früh/nichts gehört (Wiederholung desselben Satzes), am Ende „Eingelernt“ mit Gleichmäßigkeit, schwächstem Satz und Schwelle. Zweite Person ebenso (andere Stimme).
- [ ] **Erkennung**: Schalter an, Sprachbefehl von Person 1, dann Person 2, dann unbekannte Person. *Erwartet*: Bekannte Sprecher werden als solche erkannt (sichtbar erst mit 92b; bis dahin über das Diagnosefeld `Transcript.speaker`, kein Embedding in Logs); Fremde und sehr kurze Äußerungen (< 1 s) ergeben „unbekannt“. Die Antwortzeit steigt nicht merklich (Erkennung läuft parallel zur STT).
- [ ] **Falsche Einlern-Eingaben**: Zweite Person liest einzelne Sätze mit. *Erwartet*: Fehlermeldung „nicht nach derselben Person“, nichts gespeichert.
- [ ] **Löschen**: Papierkorb bei einer Person → Bestätigung → Person weg. Datenschutz → „Verläufe und Protokoll löschen“ → „Alles löschen“ entfernt alle Personen.
- [ ] **Speicher**: im Leerlauf (Release nach der Wartezeit) fällt der Speicher auf den Stand ohne Sprechermodell; aktiv ≤ ~1,1 GB (Metrikseite).
- [ ] **Nichts im Klartext**: `adb backup` ist abgelehnt (`allowBackup=false`); `adb shell run-as <paket> ls -R files databases shared_prefs` enthält keine Namen/Embeddings (nur der verschlüsselte Schlüsselspeicher); Audit-Export und Logs enthalten weder Personennamen noch Vektoren.

## E2E (Emulator, synthetisches Audio)

Mit den WAV-Fixtures aus `docs/testing/m5/README.md` (Mikrofon-Ersatz `WavAudioInput`, synthetische Stimmen aus `packages/wendelin_voice/test/fixtures/speaker/README.md`): zwei synthetische Sprecher (z. B. Thorsten/Kerstin) einlernen, mit je einem neuen Satz identifizieren (richtige Person), Fremdstimme (LJSpeech) = unbekannt. Echte Stimmen und Schwellen (Floor 0,45, Ceiling 0,60 stammen aus synthetischen Stimmen) werden auf dem Gerät mit echten Sprechern geprüft.

Aufruf (Emulator `Wendelin_AOSP_35`, App als Debug-Build installiert): Modell und synthetische WAVs liegen nicht im Repo, sondern unter dem Unterordner wp92a-e2e im lokalen Handoff-Ordner neben dem Repo (gen_wavs.py erzeugt die WAVs, prepare.sh kopiert Modell und WAVs in den App-Ordner files/e2e/wp92a, nur auf Emulatoren). Ohne Define wird der Test übersprungen.

```sh
../james-wt/handoff/wp92a-e2e/prepare.sh emulator-5554
WENDELIN_WP92A_DIR=wp92a tool/e2e_android.sh integration_test/speaker_e2e_test.dart
```

Ergebnis 2026-10-19 (synthetisch): Einlernen Thorsten 0,865 / Kerstin 0,832 (Schwelle 0,60, an der Obergrenze), Zuordnung Thorsten 0,904, Kerstin 0,789, Fremdstimme Miro 0,284 → unbekannt.
