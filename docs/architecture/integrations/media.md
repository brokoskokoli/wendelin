# Integration `media` (WP90)

Medien steuern: was läuft, Pause/Weiter/Spulen/Nächstes/Vorheriges, Audible öffnen. Spec `app/lib/di/integrations/media_spec.dart`, Tools in `packages/wendelin_integrations/lib/src/media/`.

| Kanal (`app.wendelin/…`) | Dart | Kotlin |
| --- | --- | --- |
| media | `app/lib/platform/channel_media_control_port.dart` | `MediaChannel.kt` (`MediaListenerService.kt`, `MediaSessionPick.kt`) |
| audio-focus | `app/lib/platform/channel_audio_focus_port.dart`, `app/lib/platform/voice/ducking_tts.dart` | `AudioFocusChannel.kt` (`AudioFocusKinds.kt`) |

Der Benachrichtigungszugriff (`MediaListenerService`) ist ein optionaler Einrichtungsschritt: ohne ihn wirken Pause/Weiter per Medientaste, „Was läuft?“ und Spulen melden den fehlenden Zugriff. Die Ergebnisse von `media__now_playing` stammen aus fremden Apps und sind nicht vertrauenswürdig (`app/test/trust/media.json`). Sprachausgabe dämpft den Player über den Audiofokus (`GAIN_TRANSIENT_MAY_DUCK`), Aufnahme pausiert ihn kurz (`GAIN_TRANSIENT`).
