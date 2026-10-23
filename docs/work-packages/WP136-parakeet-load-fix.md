# WP136 – Parakeet (NeMo) lädt nach dem Download nicht

**Zuordnung:** Testbefund Maintainer 2026-10-23 (zweites Testhandy, APK 0.1.0 vom 2026-10-23). Entscheidung Maintainer: sofort starten.

## Befund (Log, nur Zählungen)
- `model-unpacked model=parakeet-tdt-0.6b-v3 bytes≈671 MB` erfolgreich; danach Umstellung auf Parakeet (`model-free whisper-small reason=replaced`).
- Ab dann jeder Start `start-failed reason=no-models` (UI: „Spracherkennung laden: Einstellungen → Sprache“), kein `model-load model=parakeet…`; Wake-Bestätigung `wake-verify … error=voiceexception` bei jedem Kandidaten.
- `isInstalled` ist wahr (`app/lib/platform/voice/model_installer.dart:44-64`, prüft nur, ob `unpackedDir` existiert), das Laden wirft `modelMissing`.

## Vermutung (prüfen, nicht voraussetzen)
- `extractTarBz2` entpackt nach `<modelDir>/<archivname>/` ohne den obersten Ordner abzuschneiden (`app/lib/platform/voice/tar_bz2.dart`); die sherpa-Archive enthalten selbst `sherpa-onnx-nemo-…/`. Dann liegen die Dateien eine Ebene tiefer, `NemoFiles.find` (`app/lib/platform/voice/nemo_sherpa.dart:86-129`) sucht nur in `<modelDir>/<archivname>/` (`listSync`, nicht rekursiv) → `null` → `startSttBackend` wirft `modelMissing` (`stt_loader.dart:30-38`). Andere Ursachen ebenso prüfen (Dateinamen, Speicher, Hotwords-Datei).

## Inhalt
- Ursache am echten Archiv belegen (Inhaltsliste per `tar -tjf` lokal bzw. Download auf dem Emulator), dann beheben: Laden robust gegenüber einer zusätzlichen Ordnerebene **und** `isInstalled` prüft die tatsächlich nötigen Dateien (nicht nur den Ordner), damit „installiert“ und „ladbar“ nicht auseinanderfallen. Bereits entpackte Geräte müssen ohne Neu-Download funktionieren.
- Gleiche Prüfung für Canary und alle anderen `tarBz2`-Modelle (Piper-Stimmen, Wake-Features), damit kein zweites Modell denselben Fehler hat.
- Fehlermeldung: Ist ein Modell „installiert“, aber nicht ladbar, zeigt die App das ehrlich („Modell beschädigt, neu laden“) statt „Spracherkennung laden“; Log-Zeile mit Grund (ohne Pfade).

## Abnahmekriterien
- [ ] Ursache mit Beleg (Archivliste, Log vom Emulator) im Bericht; Test mit echter Archivstruktur (kleines Fixture mit oberstem Ordner), der ohne Fix rot ist (Mutationsbeleg).
- [ ] E2E auf dem Emulator: Parakeet laden, auswählen, eine Spracheingabe erkannt (`model-load model=parakeet…` im Log).
- [ ] Gate `--changed`, CI grün, Review FREIGABE; Gerätetest-Block ins laufende Protokoll.

## Parallel-Hinweise
- WP129 (Wake, gleiche Voice-Provider evtl.), WP135 (Smart Home), WP133 (Training) laufen. Emulator nur nach Absprache mit dem Orchestrator (WP129 zuerst).
