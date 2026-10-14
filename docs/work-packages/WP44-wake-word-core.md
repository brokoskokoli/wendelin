# WP44 – Wake-Word-Kern (`packages/wendelin_voice/lib/src/wake/`)

Abhängig von: WP42 (Modell, Varianten, Schwellen). Port und Puffer können vorher beginnen. Andockpunkte: `TriggerSource`/`TriggerKind.wakeWord` (`packages/wendelin_voice/lib/src/io/trigger.dart`), `AudioInput` (`src/io/audio_input.dart`), Modellkatalog `src/models/speech_model_catalog.dart`, `ModelStore`/Downloader (`src/models/`), Barrels `wendelin_voice.dart`, `fakes.dart`, `testing.dart` (nur anhängen). Reines Dart, kein Flutter.

## Inhalt
- **Port `WakeWordEngine`**: wird mit `KeywordSpec`-Liste geöffnet, nimmt PCM-Frames (16 kHz mono) an und liefert `WakeWordHit` (Schlüsselwort-ID, Zeitpunkt im Strom, Konfidenz, soweit die Engine sie liefert). Mit `reset()` und `close()`. Die sherpa-Implementierung liegt in der App (`app/lib/platform/voice/`, WP50).
- **`KeywordSpec`**: ID (`wake`, `stop`), Aussprachevarianten als Phonemfolgen, Boost, Schwelle. Die Empfindlichkeitsstufen (niedrig/mittel/hoch) bildet `keywordsFile()` auf Schwellen ab und erzeugt das sherpa-Format (`… :boost #threshold @ID`). Keine freien Nutzereingaben in Phonemen in M4 (Wake Word fest „Wendelin“, Konfiguration nur Empfindlichkeit und Bestätigungston).
- **`PreRollBuffer`**: Ringpuffer der letzten N ms (Standard 300 ms, Konzept), danach lückenlose Weitergabe der Folgeframes. Obergrenze, damit kein Audio unbegrenzt gepuffert wird.
- **`WakeWordListener`**: verbindet `AudioInput` → Engine → Treffer. Nach einem Treffer folgt eine Sperrzeit (z. B. 1,5 s) gegen Doppeltreffer, dazu Pause/Fortsetzen (Mikrofon freigeben, wenn das Overlay übernimmt) und ein Zähler für Treffer und Laufzeit (Diagnose ohne Audio).
- **`WakeWordTrigger implements TriggerSource`**: meldet `TriggerKind.wakeWord`, trägt den Pre-Roll als Anhang (z. B. `TriggerEvent` um optionales `Int16List preRoll` erweitern. Das ist eine Vertragsänderung in `wendelin_voice`, im Bericht nennen).
- **Modell im Katalog**: Eintrag für das KWS-Modell (Dateien, Größen, SHA-256, Lizenz), Download wie bei Whisper/Silero, nicht im APK.
- **Fakes/Contract**: `FakeWakeWordEngine` (Treffer per Skript bzw. bei bestimmten Frame-Markern), `wakeWordEngineContract` für die App-Implementierung.

## Abnahmekriterien
- [ ] Unit-Tests: Pre-Roll liefert genau die letzten 300 ms vor dem Treffer und danach lückenlos weiter (Sample-genau). Die Obergrenze greift.
- [ ] Sperrzeit gegen Doppeltreffer, Pause/Fortsetzen geben das `AudioInput` frei (`FakeAudioInput.isRunning`), Fehler im Audio-Strom beenden den Listener mit Grundcode statt still.
- [ ] `keywordsFile()` erzeugt das sherpa-Format, Tabellentest für Varianten × Stufen.
- [ ] Contract-Suite `wakeWordEngineContract` in `testing.dart`, Fake besteht sie.
- [ ] Katalogeintrag mit Prüfsumme, Download-Test mit `FakeModelStore`.
- [ ] Keine Flutter-Imports (`tool/check_deps.dart`), Gate grün.

## Nachtrag (2026-10-14)
- Nach WP42 ist Plan B ausgelöst: Das Modell kommt aus **WP58** (openWakeWord, eigenes Modell). WP44 startet erst nach WP58 bzw. baut die Engine-Schnittstelle so, dass das Modell austauschbar ist (Fake-Detektor in Tests).

## Nachtrag 2 – persönliches Einlernen und Nachprüfung (Entscheidung Maintainer 2026-10-14, K29)
Aktivierungswort bleibt „Wendelin“. Erkennung zweistufig plus persönliche Vorlagen:
- **Stufe 1 – Kandidat:** openWakeWord-Feature-Kette (Mel + Embedding, Apache-2.0, aus WP58) liefert je Fenster ein Embedding; ein Kandidat entsteht, wenn (a) das WP58-Modell über einer **niedrigen** Schwelle liegt **oder** (b) die Kosinus-Ähnlichkeit zu einer der persönlichen Vorlagen über der kalibrierten Schwelle liegt.
- **Persönliche Vorlagen:** Port `WakeTemplateStore` (je Sprecher eine Menge Embeddings + kalibrierte Schwelle, Versionsnummer der Feature-Modelle); nur Embeddings, nie Rohaudio. Ähnlichkeitsmaß und Entscheidungsregel als reine Funktionen mit Tabellentests.
- **Stufe 2 – Nachprüfung:** Kandidat → Whisper (bereits geladenes bzw. bei Bedarf base) transkribiert Pre-Roll + Fenster (max. ~2 s); nur wenn der Text unscharf „Wendelin“ (Varianten, Faltung aus `fold.dart`) enthält, wird ausgelöst. Port, damit Tests ohne Whisper laufen. Kennzahl im Diagnose-Log: Kandidaten/h, bestätigt/h (ohne Inhalte).
- **Kalibrierfunktion** (für WP60): nimmt Positiv-Embeddings und Negativ-Embeddings (Hintergrund) und berechnet die Schwelle für eine Ziel-Falschauslösungsrate (z. B. ≤ 1/h vor Stufe 2) – reine Funktion, getestet.
- Ausführung der ONNX-Feature-Modelle über das vorhandene onnxruntime (sherpa-onnx) in der schlanken Engine (WP42-Empfehlung); Modelldateien per Katalog-Download (Lizenz/Attribution).
- Messung: `tool/kws_measure.py` um die zweistufige Entscheidung erweitern (synthetische Sprecher als „Einlerner“: je Stimme 15 Vorlagen, Rest als Test) und Ergebnis in der Notiz.
