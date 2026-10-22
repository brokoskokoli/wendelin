# WP120 – Antwortzeit vermessen, Pausen beim Vorlesen, früher vorlesen

**Zuordnung:** M6, Wunsch Maintainer 2026-10-21: „mach auch mal die Vermessung … auf dem Handy“, „früher vorlesen finde ich eine gute Idee“, Befund „hier und da Pausen beim Vorlesen, zwischen zwei Sätzen bestimmt 2 Sekunden“.

## Inhalt

### 1. Zeitleiste je Anfrage (Messung)
- Eine Logzeile `latency` je Anfrage (nur Zahlen, kein Text) mit den Abschnitten ab Sprechende: VAD-Ende → STT fertig → je Modellaufruf (Anfrage gesendet, erstes Token, fertig, Anzahl Aufrufe, Tools) → erster Satz an TTS → TTS-Synthese fertig → erster Ton → letzter Ton; dazu je Satz Synthesezeit und Lücke zum vorherigen Satz.
- Auswerte-Skript (`tool/`), das aus `adb logcat` eine Tabelle macht (p50/p90 je Abschnitt). Gerätetest mit 10 typischen Befehlen (Anleitung in `docs/testing/m5/wp120.md`), Maintainer führt aus.
- Vergleichsmessung Modell-Abschnitt optional mit einem Schnell-Anbieter (Groq oder Cerebras, gpt-oss-120b) im Eval-Runner, nur wenn ein Key in `~/.wendelin-live.env` steht; Budget ≤ 0,50 €. Fehlt der Key: weglassen und melden.

### 2. Pausen zwischen Sätzen
- Ursache finden (Vermutung: der nächste Satz wird erst synthetisiert, wenn der vorige fertig gesprochen ist, oder die Stimme ist auf dem Handy langsamer als Echtzeit; `SentenceChunker` liefert einen Satz erst, wenn der nächste begonnen hat).
- Fix: den nächsten Satz synthetisieren, während der vorige noch spielt (Vorlauf ≥ 1 Satz), ohne Stopp/Barge-in (WP113/K90) und Gesprächston (WP118/K93) zu brechen. Bei Abbruch werden vorbereitete Sätze verworfen.

### 3. Früher vorlesen
- Prüfen, ob der erste Satz schon während des Streamings zur TTS geht (alle Provider-Adapter, die streamen). Wo nicht: nachziehen. Lange erste Sätze: an Komma/Doppelpunkt nach ≥ N Wörtern teilen (Wert begründen).
- Kurze Befehle ohne zweiten Modellaufruf (App bildet die Bestätigung selbst, z. B. „Taschenlampe ist an“) gehören **nicht** zu diesem Paket; die Messung soll zeigen, ob sich das lohnt (Anteil des zweiten Aufrufs).

## Abnahmekriterien
- [ ] Logzeile `latency` ohne Nutzertext (Test), Auswerte-Skript mit Beispiel-Log als Test.
- [ ] Vorlauf-Synthese: Test (fakeAsync) zeigt, dass Satz 2 während Satz 1 synthetisiert wird; Stopp verwirft vorbereitete Sätze (Mutationsbeleg).
- [ ] Stopp-E2E und Barge-in-E2E grün (bei ruhigem Host; WAV erst nach `barge-listen on=true` freigeben, Folgepunkt aus STATUS, gern mit erledigen).
- [ ] Gerätetest-Anleitung; `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Läuft neben WP121 (nur `tool/train_wake_word/`, `tool/kws_measure.py`, `docs/notes/`). WP120 berührt `app/lib/voice/`, `app/lib/platform/voice/` (TTS/Wiedergabe), Provider-Adapter, `tool/`.
