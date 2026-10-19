# Plattformkanäle

Kotlin unter `app/android/app/src/main/kotlin/app/wendelin/`. Kanalnamen sind Konstanten in `app/lib/platform/channels.dart` und `CHANNEL` in der Kotlin-Klasse. **Das Manifest `app/channels.json` listet je Kanal Dart-/Kotlin-Dateien, Methoden (Richtung, Argumentschlüssel, Rückgabeart); `tool/check_channels.dart` (Gate) vergleicht es per Textanalyse mit beiden Seiten** (Methode nur auf einer Seite, Argumentschlüssel nur auf einer Seite, Kanal ohne Manifest-Eintrag und umgekehrt sind Fehler mit Datei und Zeile).

Die Logik ohne Android-Abhängigkeit liegt in reinen Kotlin-Klassen mit JVM-Unit-Tests (`app/android/app/src/test/kotlin/app/wendelin/`, Gate-Schritt `kotlin-unit`): `ChannelArgs.kt` (Argumentprüfung), `CalendarRows.kt` (Zeilen → Maps, Zeitzonen, Dauer, Filter), `VaultTree.kt` (`VaultResolver`: Pfade, Ordner anlegen, Lesen/Schreiben auf einem `VaultTree`), `OAuthRedirect.kt` (Redirect-Prüfung). Die Android-Seite dazu: `CalendarStore.kt`, `SafVaultTree.kt`.

| Kanal (`app.wendelin/…`) | Dart | Kotlin |
| --- | --- | --- |
| calendar | `app/lib/platform/device_calendar_port.dart` | `CalendarChannel.kt` |
| files | `app/lib/platform/saf_list_file_port.dart`, `app/lib/platform/document_text_import.dart` | `FilesChannel.kt` |
| vault | `app/lib/platform/saf_vault_port.dart` | `VaultChannel.kt` |
| apps | `app/lib/platform/channel_app_presence_port.dart` | `AppsChannel.kt` |
| torch | `app/lib/platform/channel_torch_port.dart` | `TorchChannel.kt` |
| multicast | `app/lib/platform/ha_discovery.dart` | `MulticastChannel.kt` |
| network | `app/lib/platform/channel_network_status.dart` | `NetworkChannel.kt` |
| assistant | `app/lib/platform/assistant_platform.dart` | `AssistantChannel.kt` |
| window | `app/lib/platform/screen_protection.dart` | `WindowChannel.kt` |
| auth | `app/lib/platform/channel_authorization_browser.dart` | `AuthChannel.kt` (mit `OAuthRedirectActivity.kt`) |
| notify (WP52) | `app/lib/platform/channel_notifier.dart` | `NotifyChannel.kt` |
| memory (WP103, `onTrimMemory`) | `app/lib/platform/channel_memory_trim.dart` | `MemoryChannel.kt` (in `WendelinActivity.kt` eingehängt) |
| recognizer | `app/lib/platform/recognizer/recognizer_host.dart` | `RecognizerEngine.kt` (mit `WendelinRecognitionService.kt`, `RecognizerSwitch.kt`) |
| wake (WP50, Einstellungen der Haupt-App) | `app/lib/platform/wake/wake_platform.dart` | `WakeChannel.kt` (mit `WakeSettingsStore.kt`, `WakeStarter.kt`) |
| wake-engine (WP50, kopflose Engine des Dienstes) | `app/lib/platform/wake/wake_host.dart`, `app/lib/platform/wake/service_audio_input.dart` | `WakeWordService.kt` (mit `RecognizerEngine.kt`, `WakeConflictWatcher.kt`, `WakeNotifications.kt`) |
