# wendelin_voice

Sprach-Kern in reinem Dart (WP15): Schnittstellen für Auslöser, Mikrofon, VAD, STT und TTS, Endpointing, die `VoicePipeline`, das Kürzen von Antworten für die Sprachausgabe, die TTS-Auswahl (K7) sowie Modellkatalog und Download. Die Plattform-Implementierungen (sherpa-onnx, System-TTS, Aufnahme) liegen in der App (WP17).

- `package:wendelin_voice/wendelin_voice.dart`: API
- `package:wendelin_voice/fakes.dart`: Fakes, ohne `package:test`
- `package:wendelin_voice/testing.dart`: Fakes plus Contract-Suites (`audioInputContract`, `voiceActivityDetectorContract`, `speechToTextContract`, `textToSpeechContract`, `modelStoreContract`)

## Übergabe an WP17 (Plattform)

**Contract-Suites.** Jede Implementierung muss ihre Suite bestehen. Die STT-Suite nimmt mit `sample`/`expectedText` echte Aufnahmen (Fixtures), die VAD-Suite mit `speechSample` eine Sprachprobe.

**Endpointing kalibrieren.** Die Standardwerte stehen in `EndpointConfig`: Pre-Roll 300 ms, Ende nach 800 ms Stille, maximal 30 s, Mindestsprechdauer 200 ms, Timeout ohne Sprache 8 s. Die Mindestsprechdauer und die VAD-Schwelle müssen mit echtem Silero-VAD auf Geräten geprüft werden (Klicks und Atmer ausfiltern, „Ja“ und „Nein“ behalten).

**`ModelStore` auf dem Dateisystem.**
- Ein Verzeichnis pro Modell-Id. Der Teil-Download liegt als `<name>.part` daneben.
- `commit` benennt atomar um (`File.rename` im selben Verzeichnis).
- Die Suite `modelStoreContract` muss grün sein.

**Download.** `ModelDownloader` übernimmt bereits:
- Fortsetzen per `Range`
- Prüfung von `Content-Range`: Setzt der Server an anderer Stelle fort, beginnt der Download einmal von vorn.
- SHA-256 und Größe
- Abbruch über `CancelToken`
- Sperre gegen parallele Downloads desselben Modells (`DownloadErrorKind.busy`)
- Dateinamen ohne Pfadtrenner (sonst `ArgumentError`)

Noch Aufgabe der Plattform:
- **Speicherplatz** vor dem Start prüfen: mindestens `SpeechModel.sizeBytes`, bei Archiven zusätzlich etwa das Dreifache für das Entpacken, dazu ein Puffer. Fehlt Platz, gibt es einen verständlichen Hinweis statt eines Abbruchs mitten im Download.
- **Sicheres Entpacken** der `.tar.bz2`-Stimmen (`ModelArchive.tarBz2`). Es werden nur Einträge mit relativen Pfaden ohne `..` angenommen, keine Symlinks oder Hardlinks. Zuerst in ein temporäres Verzeichnis entpacken, danach atomar umbenennen. Das Archiv erst löschen, wenn das Entpacken geklappt hat.
- **Lizenzseite:** `SpeechModel.attribution` ist Pflicht und muss in der App angezeigt werden, sobald das Modell angeboten wird (z. B. SIWIS, CC BY 4.0).
- **Download im Hintergrund:** Ein laufender Download bricht ab, wenn die App beendet wird. Der Teil bleibt erhalten und wird beim nächsten Start fortgesetzt.

**TTS.**
- `TtsSelector.select(language:)` wählt die Systemstimme, sonst sherpa. Eine Engine, die zwar Stimmen nennt, aber keine für die Antwortsprache, gilt als nicht verfügbar.
- `TextToSpeech.speak` bekommt die Antwortsprache, wenn keine Stimme gesetzt ist.

**Abbruch.** Während der Sprachausgabe gibt es noch kein Barge-in (ab v0.4). Stoppen geht dann nur durch Antippen (`VoicePipeline.cancel`). Das Abbruchwort wirkt nur, wenn die ganze Äußerung ein Stopp-Befehl ist: Stoppwörter, Stopp-Phrasen („Hör auf“, „arrête ça“, „stop it“) und Füllwörter („bitte“, „nein“).
