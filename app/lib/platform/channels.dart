/// Names of all platform channels (Kotlin side: `CHANNEL` constants in
/// `app/android/app/src/main/kotlin/app/wendelin/`). The manifest
/// `app/channels.json` lists their methods; `tool/check_channels.dart`
/// compares it with both sides.
library;

/// `AppsChannel.kt`: installed-app detection.
const appsChannelName = 'app.wendelin/apps';

/// `AssistantChannel.kt`: default assistant, overlay, recognizer settings.
const assistantChannelName = 'app.wendelin/assistant';

/// `AuthChannel.kt`: OAuth authorization in the browser.
const authChannelName = 'app.wendelin/auth';

/// `BatteryChannel.kt`: battery optimization, standby bucket, vendor settings.
const batteryChannelName = 'app.wendelin/battery';

/// `CalendarChannel.kt`: device calendar.
const calendarChannelName = 'app.wendelin/calendar';

/// `FilesChannel.kt`: single documents (storage access framework).
const filesChannelName = 'app.wendelin/files';

/// `NetworkChannel.kt`: connectivity state.
const networkChannelName = 'app.wendelin/network';

/// `RecognizerEngine.kt`: speech recognizer service.
const recognizerChannelName = 'app.wendelin/recognizer';

/// `TorchChannel.kt`: flash LED as a flashlight.
const torchChannelName = 'app.wendelin/torch';

/// `VaultChannel.kt`: Obsidian vault tree.
const vaultChannelName = 'app.wendelin/vault';

/// `WindowChannel.kt`: screen protection.
const windowChannelName = 'app.wendelin/window';
