# ADR 0016 – Barge-in und Gesprächsmodus in der Sprach-Pipeline

Status: vorgeschlagen · 2026-10-14

## Kontext
K23 c/d: Während der Ausgabe darf nur „Wendelin“ oder „Stopp“ unterbrechen (freie Sprache experimentell); der Gesprächsmodus ist standardmäßig aus und bietet eine einmalige Nachfrage nach der ersten gesprochenen Antwort. Das Wake-Word-Modell kommt erst mit WP58, Echo-Unterdrückung und Audioquelle gehören der App (WP51).

## Entscheidungen
1. **Port `BargeInDetector`** (`packages/wendelin_voice/lib/src/io/barge_in_detector.dart`): `signals` (Strom von `BargeInSignal`: `keyword(stop|wake)` oder `speech`, optional mit Pre-Roll), `start()`/`stop()`. Die Pipeline startet ihn beim Eintritt in `speaking` und stoppt ihn, wenn sie `speaking`/`thinking` verlässt. Start und Stopp laufen in der Pipeline nacheinander (ein Stopp überholt keinen ausstehenden Start; endet `speaking` während des Starts, wird nach dessen Ende erneut gestoppt). Sie weiß nichts von AEC oder Audioquelle. Fake: `FakeBargeInDetector`, Vertrag: `bargeInDetectorContract`.
2. **Konfiguration** `VoicePipelineConfig.bargeIn` (`off` Standard, `keywords`, `speech`). Signale außerhalb von `VoiceState.speaking` und nicht zugelassene Arten werden ignoriert.
3. **Wirkung**: Das Signal wird synchron behandelt; `SpeechQueue.stop()` ruft `TextToSpeech.stop()` im selben Aufruf (kein Frame Verzug). `keyword(stop)` = `cancel(stopWord)`. `keyword(wake)`/`speech` = `cancel(bargeIn)` (neuer `VoiceCancelReason.bargeIn`) und sofort neues Zuhören (Trigger `wakeWord`) mit dem Pre-Roll des Signals; das Gespräch läuft weiter.
4. **Gesprächsmodus**: bleibt `conversationMode` (Standard aus), Fenster `followUpWindow` (5 s), `maxFollowUps` (5). Jedes Gespräch endet mit genau einem `ConversationEndReason` (`silence`, `stopWord`, `closingPhrase`, `tap`, `cancelled`, `confirmation`, `maxFollowUps`, `error`) als `VoiceConversationEnded`. `maxFollowUps = 5` zählt Folgefragen nach der ersten Frage. Abschlussphrasen (`defaultClosingPhrases`: danke, danke schön, danke sehr, vielen dank, das war’s / das war es, merci, merci beaucoup, thanks, thank you, thanks a lot) zählen nur im Folgefenster und nur, wenn die Äußerung ausschließlich daraus besteht. Eine offene Bestätigungskarte beendet das Gespräch (die Ja/Nein-Logik übernimmt).
5. **Signale für die UI** (WP51): `VoiceFollowUpListening(window, until)`, `VoiceBargeIn`, `VoiceConversationEnded`; Diagnose `conv-exit reason=…` und `barge-in kind=…` ohne Inhalte. Es gibt keinen neuen `VoiceState`.
6. Die „einmalige Nachfrage nach der ersten gesprochenen Antwort“ (K23 d) ist UI (WP51); die Pipeline stellt nur den Modus bereit.

7. **Anforderung an den Adapter (WP51)**: Im Modus `speech` muss der Adapter echo-unterdrücktes Pre-Roll liefern, sonst nimmt die neue Aufnahme die eigene TTS-Ausgabe auf. Im Modus `keywords` stoppt die TTS synchron beim Signal und das Pre-Roll ist optional.

## Folgen
- `VoicePipelineConfig` liegt jetzt in `voice_pipeline_config.dart` (weiterhin über `voice_pipeline.dart` exportiert), die Stopp-Erkennung als Funktion `isStopCommand` in `conversation.dart`.
- K11 d („während der Sprachausgabe wirkt nur Antippen“) gilt nur noch mit `bargeIn: off`.
