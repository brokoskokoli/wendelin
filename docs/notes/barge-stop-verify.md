# „Stopp“/„Wendelin“ während der Ausgabe: Gegenprüfung (WP113, K84)

Anlass: Gerätetest 2026-10-20 (T20-B.1). Mit Aufschlag +0,05 (`thr=0.90 sthr=0.95`) erreichte „Stopp“ nie die Schwelle (gemessen 0,72–0,94). Mit 0,00 gab es Fehlabbrüche (3× `keyword-wake` bei sim 0,85–0,86) und zweimal wurde `wake` gewertet, obwohl `stop` über `sthr` lag.

## Ablauf

1. **Stufe 1** (Vorlagen, `CandidateWakeEngine`) liefert einen Kandidaten mit abgesenkter Schwelle.
2. **Stufe 2**: Das Mikrofon-Ringpuffer (letzte 2,5 s) geht an den Whisper der Pipeline (`TranscriptBargeVerifier`). Erst das erkannte Wort löst aus: „Wendelin“ (Wake-Regeln, unscharf) oder ein Stoppwort der App-Sprache (de: Stopp/Stop, en: Stop, fr: Arrête/Stop; eine Abweichung ab fünf Buchstaben). Das erkannte Wort zählt, nicht der Kandidat: ein „Stopp“-Kandidat, der „Wendelin“ ist, wird zum Wake-Signal. Sind beide im Text („Wendelin, stopp“), gilt Wake (die Pipeline wertet den Rest als Stopp-Befehl).
3. **Eigen-Echo**: Die Pipeline meldet jeden Satz, der zu spielen beginnt (`SpokenTextSink`). Steht das erkannte Schlüsselwort selbst im bisher vorgelesenen Text der Antwort, zählt es nicht (Ergebnis `echo`). Dazu kommt wie bisher AEC (Quelle „Kommunikation + AEC“) und das Pegel-Gate von WP80.
4. **Fail closed**: Fehler, fehlendes Modell oder mehr als 6 s ohne Ergebnis ergeben `skip`, nie ein Signal. Während eine Prüfung läuft und 1,5 s danach (wenn nichts erkannt wurde) werden weitere Kandidaten verworfen (CPU/Akku, die eigene Stimme macht viele Kandidaten).

## Wertung bei zwei Treffern

Liegen „Stopp“ und „Wendelin“ im selben Fenster über ihrer Schwelle, gewinnt „Stopp“ (vorher: der größere Abstand zur Schwelle, mit der Wartepause für das zweite Fenster, in der ein Wake-Treffer des Folgefensters durchrutschte). Dasselbe gilt, wenn „Stopp“ in einem der beiden Vorgängerfenster über der Schwelle lag und nun nur noch „Wendelin“ (Log 00:24:26/00:24:54). Test: `packages/wendelin_voice/test/wake/barge_verify_test.dart` („Wertung Stopp vor Wake“). Ist das ein falsches „Stopp“ in „Wendelin“, korrigiert Stufe 2 es zum Wake-Signal.

## Schwellen

Mit Stufe 2 muss Stufe 1 nur noch wenig verpassen. Standard (Konstanten in `app/lib/voice/wake/wake_barge_in.dart`):

| Wert | Vorlage (Beispiel) | Aufschlag | Kandidatenschwelle |
| --- | --- | --- | --- |
| Wendelin | 0,85 | -0,10 | 0,75 |
| Stopp | 0,90 | -0,20 | 0,70 |

Begründung: gemessene „Stopp“-Werte 0,72–0,94 gehen als Kandidat durch (0,70 liegt darunter); die Fehlauslöser auf Wake lagen bei 0,85–0,86 und werden jetzt von Whisper verworfen statt abgebrochen. Zwei Fenster in Folge (`stopWindows`) und das Pegel-/Abstands-Gate (WP80) bleiben. Ohne Stufe 2 (Nachprüfung in den Wake-Einstellungen aus) gilt wie früher +0,05. Die Entwicklereinstellung `debug.bargeMargin` ersetzt weiter beide Aufschläge.

## „Stopp“ außerhalb der Ausgabe (Punkt 4)

Laut K40/K47 gilt das eingelernte „Stopp“ nur während der Sprachausgabe (der Barge-in-Zuhörer startet mit dem Zustand `speaking`, auch über „thinking“ hinweg, und endet mit dem Gespräch). Im Ruhezustand hört nur der Wake-Word-Dienst auf „Wendelin“, und beim offenen Zuhören wird „Stopp“ aus dem Transkript gewertet (`isStopWord`: nur Stopp- und Füllwörter). Damit ist das Verhalten laut Stefan („geht auch nicht, wenn Wendelin nicht spricht“) wie im Konzept vorgesehen: kein Fehler, keine Änderung. Falls gewünscht, wäre ein „Stopp“ im Ruhezustand eine neue Anforderung (Konzeptänderung).

## Gleichzeitiger Whisper-Zugriff (Stufe 2 und Folge-Zuhören)

Kein Fix nötig. Stufe 2 nutzt das `SpeechToText` der Pipeline; alle Aufrufe laufen über `IsolateWhisperBackend.transcribe` (`app/lib/platform/voice/whisper_sherpa.dart`, `_queue`) in einem einzigen Isolat nacheinander ab, auch die der anderen Engines (`publishSharedWhisper`, ADR 0008). Es laufen nie zwei Läufe zugleich. Folge: Läuft bei Ende der Ausgabe noch eine Gegenprüfung (höchstens eine, 2,5 s Audio, `verifyTimeout` 6 s), wartet die Erkennung der Folgefrage um deren Rechenzeit (etwa 0,3 bis 1 s). Das ist vertretbar; die Gegenprüfung wird mit `stop()` verworfen (Generation), blockiert aber die Queue bis zum Ende des Laufs.

## Log (ohne Inhalt)

- `barge-config … smargin=… verify=true|false`
- `barge-cand kind=wake|stop busy=true|false` mit den Maxima (`sim`, `stop`, `thr`, `sthr`)
- `barge-verify result=stop|wake|no|echo|skip ms=…` (nur das erkannte Schlüsselwort, nie der Text)
- `barge-hit` wie bisher, jetzt erst nach `barge-verify`.

E2E: `app/integration_test/support/barge_log.dart` prüft das Log aus dem Overlay (Datei `files/e2e/voice.log`): kein `barge-hit` ohne `barge-cand` und passendes `barge-verify` (Regeln in `app/test/voice/barge_log_check_test.dart`).
