# WP178 – Durchgehender Audio-Ringpuffer (5–6 s) für Mikrofon und Weckwort

**Zuordnung:** Vorgabe Maintainer 2026-10-29.

## Problemstellung
Bislang wird Sprache direkt und stückweise verarbeitet. Aufnahmen werden gestartet und gestoppt (Dienst-Mikrofon, Übergabe, Overlay-Mikrofon, Wechsel bei Sprachausgabe).
Wenn ein Sprecher schnell „Wendelin <Kommando>“ sagt, fehlt aktuell etwa eine Sekunde des Kommandos, weil:
1. `PreRollBuffer` in `wendelin_voice` standardmäßig nur 300 ms Puffer hält (`defaultCapacity = Duration(milliseconds: 300)`).
2. Während auf das Weckwort gewartet wird und während Stufe 2 (z. B. Parakeet oder Whisper) einen Kandidaten prüft (was Zeit in Anspruch nehmen oder auf Modell-Laden warten kann), die Audiodaten nicht durchgehend in einem ausreichend großen Ringpuffer (5–6 Sekunden) gehalten werden.
3. Bei der Übergabe an die Spracherkennung nach dem Weckwort das unmittelbar nach „Wendelin“ Gesagte abgeschnitten wird oder verloren geht.

## Anforderungen des Maintainers
1. **Ringpuffer für Mikrofonaufnahmen:**
   - Alle Mikrofonaufnahmen laufen in einen Ringpuffer (oder mehrere), der immer mindestens 5–6 Sekunden Historie vorhält.
   - Aus diesem Puffer werden die benötigten Zeiträume entnommen.
2. **Durchgehende Aufnahme:**
   - Nicht ständig eine Aufnahme starten und beenden: Sobald Wendelin zuhört, startet die Aufnahme.
   - Auch wenn Wendelin redet (Sprachausgabe), läuft die Aufnahme weiter (Audio danach verwerfen bzw. für Barge-In nutzen).
3. **Pufferung bei Weckwort-Warten und -Prüfung:**
   - Während auf das Weckwort gewartet wird: fortlaufend sammeln, immer die letzten 5–6 Sekunden im Speicher halten.
   - Sobald ein Weckwort-Kandidat auftritt: Das Audio vor und während des Worts ist bereits im Speicher vorhanden.
   - Solange der Kandidat noch nicht verworfen ist (z. B. Prüfung durch Parakeet / Stufe 2, auch wenn Modelle geladen werden müssen): Alle weiteren Audiodaten im Ringpuffer halten, damit nichts verloren geht.
   - Wird der Kandidat verworfen (kein Ereignis / falscher Alarm): Ältere Daten werden verworfen und wieder die letzten 5–6 Sekunden gehalten.
   - Wird der Kandidat bestätigt: Das Weckwort und das unmittelbar danach gesprochene Kommando stehen lückenlos im Puffer bereit.
4. **Fehlerbehebung:**
   - Wenn jemand schnell „Wendelin <Kommando>“ sagt, darf keine Sekunde mehr fehlen – das gesamte Kommando nach dem Weckwort wird sofort mit aufgenommen.

## Abnahmekriterien
- [ ] Ringpuffer (`AudioRingBuffer` / `PreRollBuffer`) mit 5–6 s Kapazität (mind. 5 s) und Entnahme beliebiger Zeitbereiche (Slices / Ranges / Snapshots).
- [ ] `WakeWordListener` hält durchgehend rollend ≥ 5 s Audio im Speicher; bei Kandidat wird der Puffer während der Verifikation gehalten und wächst mit, sodass kein nachfolgendes Audio verloren geht; bei Verwurf rollt der Puffer weiter (älteres > 5 s verworfen); bei Bestätigung enthält der übergebene Puffer das Weckwort und das gesamte nachfolgende Audio.
- [ ] Test für schnelles Sprechen („Wendelin <Kommando>“ ohne Pause) belegt: das vollständige Kommando nach dem Weckwort ist lückenlos im übergebenen Audio enthalten.
- [ ] Kontinuierliche Audioaufnahme: Aufnahme bricht zwischen Phasen nicht unnötig ab; nicht benötigte Abschnitte werden verworfen.
- [ ] Mindestens 85 % Testabdeckung der geänderten/neuen Logik, Negativtests für Verwurf und Timeout.
- [ ] Keine Verletzung der Architekturgrenzen (`tool/check_deps.dart`).
- [ ] Gate `--changed` lokal grün, CI grün.
- [ ] Review durch Reviewer-Agent (Urteil FREIGABE in `../james-wt/reviews/wp178-review.md`).
