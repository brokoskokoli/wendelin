# Medien (`media`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `media__now_playing` | read | App, Titel, Autor, Position, Länge, läuft/pausiert |
| `media__play` | write | Wiedergabe starten (Undo: pausieren) |
| `media__pause` | write | Pausieren (Undo: abspielen) |
| `media__next` / `media__previous` | write | Nächster/vorheriger Titel kein Undo (der übersprungene Titel ist nicht wiederherstellbar) |
| `media__seek` | write | `seconds` relativ (negativ = zurück) oder `position_seconds` absolut; Undo springt zurück |
| `media__open_audible` | write | Audible öffnen; mit Suchbegriff suchen und das beste Ergebnis direkt abspielen (`MEDIA_PLAY_FROM_SEARCH`); nur wenn installiert |

Keine Nachfrage. Die Integration ist `sensitive` (was jemand hört, ist persönlich). `now_playing` liefert Titel fremder Apps und ist deshalb kein `TrustedContentSource`; die Schreib-Tools geben nie Titel zurück und sind vertrauenswürdig.

**Port**: `MediaControlPort` (`hasSessionAccess`, `openSessionAccessSettings`, `nowPlaying`, `send`, `seekTo`, `openApp`). Fehler als `PortException`: Zugriff fehlt (`permissionDenied`), kein Player (`notFound`), Player kann nicht spulen (`unsupported`). Fake: `FakeMediaControlPort`, Vertrag: `mediaControlPortContract`.

**Berechtigung / Einrichtung**: „Benachrichtigungszugriff“ (`NotificationListenerService`), Schritt `notification_access` (optional). Ohne ihn gehen play/pause/next/previous über Medientasten (`AudioManager.dispatchMediaKeyEvent`) und `open_audible`; `now_playing` und `seek` melden, dass der Zugriff fehlt. Android erlaubt den Zugriff nur über die Systemseite, der Nutzer schaltet „Wendelin“ dort selbst ein.

**Kotlin**: `MediaChannel` (`MediaSessionManager.getActiveSessions`, Medientasten, Intents), `MediaListenerService` (leer, nur Anker für die Berechtigung), `MediaSessionPick` (reine Auswahl der Session).

**Audiofokus**: Kotlin `AudioFocusChannel` (`app.wendelin/audiofocus`) hält den Fokus selbst. Für die ganze gesprochene Antwort (`DuckingTextToSpeech` um System- und Sherpa-Stimme, Abgabe 1,5 s nach dem letzten Satz) `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`: Player werden leiser und laufen danach mit voller Lautstärke weiter. Während der Aufnahme eines Befehls `AUDIOFOCUS_GAIN_TRANSIENT`: Player pausieren und setzen danach fort; das `record`-Plugin fordert selbst keinen Fokus mehr (`none`). `audioplayers` nutzt `gainTransientMayDuck`. Nach `media__pause` bleibt der Player pausiert (vom Nutzer pausierte Player setzen nach Fokusgewinn nicht fort). **Plattformen**: Android.
