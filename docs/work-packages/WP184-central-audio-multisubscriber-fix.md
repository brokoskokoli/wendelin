# WP184 – Zentrale Audio-Anbindung vervollständigen (Multi-Subscriber, kein Mic-Busy bei Follow-Up, sauberer Vorlauf ohne Weckwort-Doppeltranskription)

**Zuordnung:** Auftrag Maintainer 2026-10-30 (Befund: Pause im gesperrten Modus, Befehlsanfang fehlt, „Audio ist schon belegt“ nach Ansage).
**Konzept:** K147 (erweitert K144, K145, ADR 0024).

---

## 1. Problemstellung & Befunde

1. **„Audio ist schon belegt“ (`VoiceErrorKind.busy`) beim Weiterhören nach Ansage:**
   - In `voicePipelineProvider` und `wakeBargeInDetectorProvider` teilten sich Pipeline und Barge-In denselben `CentralAudioInput`-Singleton.
   - Wenn Wendelin spricht, läuft Barge-In (`audio.start()`). Am Ende der Sprachausgabe ruft Barge-In `detach()` auf, aber `CentralAudioInput.detach()` stoppte den Stream nicht sofort und setzte `isRunning` nicht zurück.
   - Die Pipeline versuchte für das Weiterhören (`followUp = true`) `audio.start()` aufzurufen, was an `if (isRunning) throw VoiceErrorKind.busy` scheiterte.
   - Folge: Fehlermeldung *„Das Mikrofon war noch belegt. Bitte sprich noch einmal.“* und Abbruch des Dialogs.

2. **Pause und fehlender Befehlsanfang im gesperrten Modus (und nach Weckwort allgemein):**
   - Beim Weckwort wurde das Weckwort-Audio samt Nachlauf in den Vorlauf der Voice-Pipeline gepackt.
   - Da `wakeEndMargin` nur 100 ms betrug und die akustische Ausklingphase des Weckworts („-lin“) darüber hinausreichte, wertete der VAD-Endpointer den Rest des Weckworts als Beginn einer Nutzeräußerung.
   - Eine Sprechpause des Nutzers nach dem Weckwort (z. B. 400–800 ms beim Warten auf den Bildschirm im gesperrten Modus) wurde als `EndpointReason.silence` gewertet.
   - Der Endpointer brach sofort ab, und Parakeet/Whisper brauchte 1,8 Sekunden, um die isolierte Silbe zu transkribieren und als „nur das Weckwort“ zu verwerfen (`relisten reason=wake-only`).
   - Während dieser 1,8-sekündigen Denkpause sprach der Nutzer seinen eigentlichen Befehl. Da die Pipeline aber mit STT beschäftigt war und das Mikrofon noch nicht im zweiten Relisten lief, ging der erste Teil des Befehls verloren, und es wurde nur noch der zweite Teil erfasst.

3. **Multi-Subscriber auf Android-Kanal:**
   - `CentralAudioChannel.kt` speicherte nur eine einzige `currentSubscriptionId`.
   - Mehrere gleichzeitige Abonnenten (z. B. Dialog und Barge-In oder Sprecher-Einlernen) müssen parallel und unterbrechungsfrei über dieselbe Hardware-Aufnahme bedient werden können.

---

## 2. Abnahmekriterien

- [ ] **Multi-Subscriber in `CentralAudioChannel` & `CentralAudioBridge`:**
  - `CentralAudioChannel.kt` verwaltet mehrere aktive Abonnements anhand einer eindeutigen `subId`.
  - Jeder Stream empfängt seine Chunks separat (`subId`), ohne Kollisionen.
  - `start` und `stop` arbeiten mit `subId`.
- [ ] **`CentralAudioInput` & Detach:**
  - Jeder Stream / jede Instanz von `CentralAudioInput` erhält seine eigene Subscription.
  - `detach()` entkoppelt den laufenden Stream sauber, sodass ein nachfolgender `start()`-Aufruf sofort einen neuen Stream auf dem zentralen Hub beginnen kann, ohne `VoiceErrorKind.busy` auszulösen.
  - `wakeBargeInDetectorProvider` und `voicePipelineProvider` kollidieren beim Übergang von der Sprachausgabe zum Weiterhören (Follow-Up) nicht mehr.
- [ ] **Keine Weckwort-Remnant-Endpointer-Auslösung:**
  - Nach einem Weckwort-Treffer triggert das Weckwort selbst (oder sein Ausklingen) keinen vorzeitigen `EndpointReason.silence`.
  - Macht der Nutzer nach dem Weckwort eine Pause (z. B. im gesperrten Modus, bis der Bildschirm leuchtet), bleibt der Assistent bis zu `noSpeechTimeout` (8 Sekunden) im Zuhören, statt mit einer 1,8-Sekunden-STT-Denkpause abzubrechen.
  - Spricht der Nutzer flüssig weiter („Wendelin, <Kommando>“), wird der Befehl lückenlos erfasst.
- [ ] **Vollständige Prüfung aller Audiozugriffe:**
  - Alle Konsumenten (`voicePipelineProvider`, `wakeBargeInDetectorProvider`, `wakeAudioProvider`, `WakeEnrollScreen`, `SpeakerEnrollScreen`) nutzen sauber die zentrale Quelle.
  - Kein konkurrierendes `AudioRecord` / `package:record` unter Android.
- [ ] **Qualität & Tests:**
  - Unit-Tests in Kotlin (`app/android/app/src/test/`) für Multi-Subscription in `CentralAudioChannel` und `CentralAudioHub`.
  - Unit-Tests in Dart (`app/test/`) für `CentralAudioInput`, `CentralAudioBridge`, Barge-In Follow-Up und Wake-Pre-Roll.
  - `dart run tool/gate.dart --changed` grün.
  - CI grün.
