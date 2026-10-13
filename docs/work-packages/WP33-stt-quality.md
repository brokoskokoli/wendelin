# WP33 – Erkennungsqualität: Standard whisper-small, Eigennamen und Notiztitel (`wendelin_voice`, `wendelin_integrations`, `app/`)

Abhängig von: – (sofort startbar auf main). Bezug: Gerätetest 2026-10-13 (`M2-fixes.md`), Laufzeitmessung und Befund **B6**. Konzept: K11 (a) und (b). Andockpunkte: `app/lib/di/voice_providers.dart` (`VoiceSettings.sttModel`, Standard heute `whisper-base`), `app/lib/ui/onboarding/voice_download_step.dart` (Vorauswahl), `app/lib/ui/settings/voice_screen.dart`, `packages/wendelin_voice/lib/src/models/speech_model_catalog.dart`, `WhisperSpeechToText` und Bereinigung in `wendelin_voice`, `packages/wendelin_integrations/lib/src/obsidian/obsidian_integration.dart` (`resolveNote`, `bestMatches`), Notiz-Index (`wendelin_storage`, FTS5).

## Entscheidung (bestätigt)

**Der Maintainer hat entschieden (2026-10-13): whisper-small mit fester Sprache wird Standard, base bleibt als „schnell“ wählbar** (K11 a bestätigt). Die Gerätemessung ergab small Ø 1,32 s je Satz (RTF 0,33) und alle Testsätze in de/fr/en richtig, base Ø 0,46 s (RTF 0,11) mit Fehlern bei Eigennamen.

## Inhalt

**Standardmodell**
- `VoiceSettings.sttModel` hat den Standard `whisper-small`, die Erkennungssprache bleibt fest „wie die App“ (K11 b). Katalog- und UI-Texte: small heißt „genauer (empfohlen)“, base „schnell, für schwache Geräte“.
- Onboarding: small ist vorausgewählt. Hat das Gerät wenig Arbeitsspeicher (Vorschlag < 4 GB laut `ActivityManager.MemoryInfo.totalMem`, über einen kleinen Kanal oder vorhandenen Plattformport), wird base vorausgewählt und der Grund genannt.
- **Bestand:** Wer schon ein Modell gespeichert oder nur base installiert hat, behält es. Das gilt auch, wenn `sttModel` nie ausdrücklich gesetzt wurde, aber base installiert und small nicht installiert ist: Dann bleibt base aktiv, sonst wäre das Mikrofon plötzlich ausgegraut. Einstellungen → Sprache zeigt dann den Hinweis „Empfohlen: small (genauer), 376 MB laden“.

**B6 Eigennamen und Notiztitel** (Datenschutz: alles nur lokal, nichts davon geht an Provider oder ins Log)
- **(a) Erkennungshilfe.** Die eingesetzte sherpa-onnx-Version (1.13.8) bietet für Whisper weder Initialprompt noch Hotwords (`OfflineWhisperModelConfig` hat nur `language`, `task`, `tailPaddings`, Zeitstempel; Hotwords gibt es nur für andere Modellarten). Deshalb gilt:
  1. **Spike (kurz, mit Bericht):** Prüfen, ob eine neuere sherpa-onnx-Version einen Whisper-Prompt (`prompt`/`initial_prompt`) unterstützt. Falls ja und das Update ohne GMS und ohne große APK-Änderung möglich ist, kommt ein Prompt mit dem Assistentennamen und bis zu N häufig genutzten Notiztiteln (Längengrenze der Whisper-Prompt-Tokens beachten). Falls nein, nur Variante 2.
  2. **Vokabular-Korrektur nach der Erkennung** (in `wendelin_voice`, reines Dart): Ein lokales Vokabular aus dem Assistentennamen, den Notiztiteln aus dem Index und den Listennamen. Wortfolgen im Transkript, die phonetisch und nach Editierdistanz eindeutig einem Vokabulareintrag entsprechen („Wandel Intest“ → „Wendelin-Test“), werden ersetzt. Das ist konservativ: nur bei eindeutigem Treffer über einer Schwelle, nie für gewöhnliche Wörter (Stoppliste, Mindestlänge). Das Vokabular wird bei Index-Änderungen neu gebaut, liegt nur im Speicher und wird nie geloggt.
- **(b) Phonetisch tolerantere Titelsuche** in `resolveNote`/`bestMatches`: Leerzeichen, Bindestrich und Unterstrich werden ignoriert. Dazu kommt ein phonetischer Schlüssel (Kölner Phonetik für de, einfache Variante für fr/en) und eine begrenzte Editierdistanz auf dem gefalteten Titel. Die Rangfolge bleibt: exakter Pfad > exakter Titel > gefaltet > phonetisch. `resolveNote` liefert zusätzlich die **Trefferart** (`exact`/`folded`/`fuzzy`/`phonetic`). WP31 nutzt sie für den Hinweis auf der Bestätigungskarte (B8). Die Signatur wird in Absprache mit WP31 erweitert, ohne bestehende Aufrufer zu brechen.
- **(c) Rückfrage mit Vorschlag:** Findet die Suche nichts Eindeutiges, gibt es aber einen phonetischen Kandidaten, lautet der Tool-Fehler nicht mehr „gibt es nicht“, sondern „Meinst du die Notiz „Wendelin-Test“? Bitte nachfragen.“ Bei mehreren Kandidaten werden höchstens drei genannt. Für reine Lesezugriffe darf ein einziger starker phonetischer Treffer direkt genommen werden, mit Nennung in der Antwort. Schreibzugriffe fragen immer nach (wie bisher bei `score == 1`).

## Abnahmekriterien
- [ ] Standard `whisper-small` mit fester Sprache. Tests: frische Einstellungen ergeben small. Gespeicherte M2-Einstellungen mit base bleiben base. Nur base installiert und nichts gespeichert ergibt base mit Hinweis.
- [ ] Onboarding wählt small vor, bei wenig RAM base mit Begründung (Widget-Test mit Fake-Speicherwert). Texte „genauer (empfohlen)“ und „schnell, für schwache Geräte“.
- [ ] Spike-Ergebnis zu Whisper-Prompt in sherpa-onnx im Abschlussbericht (Version, unterstützt ja/nein, Auswirkung auf APK-Größe).
- [ ] Vokabular-Korrektur als Tabellentest: „Wandel Intest“ → „Wendelin-Test“, „Wendeline Test“ → „Wendelin-Test“, „Wendelin“-Varianten. Gegenbeispiele bleiben unverändert (gewöhnliche Wörter, zwei gleich gute Kandidaten, zu kurze Wörter). Abdeckung `wendelin_voice` ≥ 85 %.
- [ ] Titelsuche: Tabellentest der Trefferarten und der Rangfolge. „Wandel Intest“ findet `Wendelin-Test.md` als `phonetic`. Keine Verschlechterung der bestehenden `resolveNote`-Tests.
- [ ] Rückfrage mit Vorschlag statt „gibt es nicht“ (Test), Schreibzugriff fragt bei `phonetic` immer nach.
- [ ] Datenschutz-Test: Vokabular und Korrekturen erscheinen weder im Log noch im Audit-Log. Das Audit enthält wie bisher nur den Text, der an das Modell ging.
- [ ] Evals bzw. STT-Fixtures (WP17): WER-Messung base/small mit und ohne Korrektur auf den vorhandenen Fixtures, Ergebnis im Abschlussbericht. Die Korrektur darf die WER nicht verschlechtern.
- [ ] `m2-device.md` (Abschnitt 2 und 10): Standardmodell small, base als „schnell“ (in Absprache mit WP32, wer zuletzt merged, gleicht ab).
- [ ] Emulator (`Wendelin_AOSP_35`, expliziter Serial): E2E mit eingespeistem D2-Satz (WAV) und base. Die Notiz wird gefunden.
- [ ] Gate grün, APK baut.

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] Neu-Installation: Onboarding wählt small vor. Eine bestehende Installation behält ihr Modell.
- [ ] Mit base: D2 „Was steht in meiner Notiz Wendelin-Test?“ 3×. Die Notiz wird jedes Mal gefunden, oder Wendelin fragt „Meinst du Wendelin-Test?“.
- [ ] Mit base: D3 mit dem Notiznamen. Die Bestätigung nennt die richtige Notiz.
