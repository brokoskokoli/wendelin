# WP171 – Weckwort: zweite Prüfung scheitert still, wenn Whisper fehlt (Zweitgerät)

**Zuordnung:** Gerätetest des Maintainers mit v0.1.0 auf einem Zweitgerät (Huawei, Android 10, frisch installiert 2026-10-28). Geladen laut Maintainer: Parakeet und Weckwort-Modell, kein Whisper.

## Befund (Log, 18:06–18:07)
- `wake-cand stage=1 detector=templates score=0.754/0.761 direct=false` → `wake-decision path=stage2` → `wake-verify result=skip error=voiceexception`. `wake-alive cand=18 ok=0` in 11 min: jeder Treffer wird verworfen, das Overlay öffnet nie. Per Taste funktioniert der Assistent.
- Code: Detektor `templates` → Stufe 2 nur `LazyWhisperVerifier` (`app/lib/platform/wake/device_wake_parts.dart:305-315`), `checkInstalled('whisper-base')` wirft vermutlich `VoiceException(modelMissing)`; `_LoggingVerifier` (`wake_host.dart:~490-502`) wertet jeden Fehler als „nicht bestätigt“, still.
- Offen: Warum läuft der Detektor `templates`, obwohl das Weckwort-Modell geladen ist (Modell nicht lauffähig auf dem Gerät? Einstellung? fehlende Vorlagen-Folgen für Prüfer B?). Log-Auszug: `../james-wt/handoff/wp171-phone2-log-2026-10-28.txt` (nicht ins Repo).

## Entscheidung Maintainer (2026-10-28): robust machen
- Stufe 2 nimmt jedes installierte Erkennungsmodell (Parakeet bevorzugt, sonst Whisper) – auch im Vorlagen-Pfad – bzw. Prüfer B, wo vorgesehen.
- Fehlt jedes passende Modell oder ist das Weckwort-Modell nicht nutzbar, zeigt die App einen deutlichen Hinweis (Weckwort-Einstellungen und Dienst-Benachrichtigung) mit Knopf zum Download, statt Treffer still zu verwerfen. Log nennt die Ursache (`wake-verify ... error=model_missing` o. ä., ohne Inhalte).

## Präzisierung Maintainer (2026-10-28, sinngemäß)
„Eigentlich sollte Whisper nicht mehr benutzt werden; es soll einfach das gerade geladene Modell verwendet werden, ob Parakeet oder Whisper. Und eigentlich soll immer Prüfer B prüfen – der sollte aktiv sein, war er bei mir gerade nicht.“
- Stufe 2 ist **immer Prüfer B** (mit eingelernten Vorlagen), in beiden Detektor-Pfaden. Heute gibt `verifier()` im Pfad `templates` sofort Whisper zurück (`device_wake_parts.dart:315`), B wird dort nie genutzt. Rückfall nur, wenn B nicht entscheiden kann: das **geladene** Erkennungsmodell (Parakeet oder Whisper, was installiert/aktiv ist), nie fest Whisper.
- Klären und belegen, warum B auf dem Gerät nicht aktiv war (Detektor `templates`, `useVerifierB` aus, keine Vorlagen-Folgen?). Fehlen Vorlagen für B: Hinweis „Weckwort neu einlernen“.

## Inhalt
- Ursache belegen (Test mit nur Parakeet installiert: vorher rot), Detektor-Wahl prüfen und ggf. korrigieren (Weckwort-Modell geladen → Detektor `model`).
- Fallback-Kette im Vorlagen-Pfad und beim Modell-Pfad vereinheitlichen; „Stopp“-Bezug ist seit WP134 entfallen (Kommentar in `device_wake_parts.dart:313` prüfen).
- Hinweis + Download-Knopf (l10n de/en/fr), Gerätetest-Anleitung `docs/testing/m5/wp171.md` (frisches Gerät nur mit Parakeet, nur mit Whisper, ohne Weckwort-Modell).

## Abnahmekriterien
- [ ] Tests: nur Parakeet → Weckwort wird bestätigt; kein Erkennungsmodell → Hinweis sichtbar, Log-Ursache; Mutationsbelege.
- [ ] E2E auf dem Emulator mit nur Parakeet (bzw. Fake) falls machbar.
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- WP172 (Overlay schließt nach dem Zuhören) läuft gleichzeitig: berührt Overlay/Sprach-Controller, wake_host nur über das Wiederaufnehmen nach dem Schließen. Absprache über die Orchestrator-Sitzung, kleine Diffs in `wake_host.dart`.
- WP169/WP170 (Doku) laufen; keine gemeinsamen Code-Dateien.
