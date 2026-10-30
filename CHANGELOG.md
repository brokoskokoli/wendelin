# Changelog

All notable changes to Wendelin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.6] - 2026-10-30

Keep screen active during assistant session and protect follow-up countdown (K148 / WP186).

### Fixed

- **Screen timeout / sleep during speech and follow-up window** – `AssistantActivity` now sets `FLAG_KEEP_SCREEN_ON` during active overlay sessions, preventing Android's lock screen inactivity timeout from turning off the display (`SurfaceFlinger` power mode 0) and triggering an unexpected `onStop()` / `_voice.suspend()` cancellation while the assistant is speaking or awaiting input. The flag is cleared when the overlay closes.
- **Follow-up window protection** – `nothingLeftToDo` in `overlay_idle_close.dart` now explicitly accounts for `voice.followUp`, and `IdleCloser` listens for the expiration of the follow-up window, ensuring the 5-second countdown runs to completion before the overlay closes via `by=idle`.

## [0.1.5] - 2026-10-30

Multi-subscriber centralized audio capture & wake pre-roll fix (K147 / WP184).

### Fixed

- **Microphone busy error on follow-up listening** – fixed `VoiceErrorKind.busy` when listening resumes after assistant speech output; `CentralAudioInput.detach()` cleanly unbinds the stream without blocking subsequent listen sessions, and `wakeBargeInDetectorProvider` operates on a decoupled subscription.
- **Wake-word remnant & pause in locked mode** – speech endpointer no longer triggers a premature `EndpointReason.silence` on wake-word decay tail; if the user pauses briefly while the screen turns on, listening continues up to `noSpeechTimeout` (8 seconds), and the user's spoken command is captured completely without truncation.
- **Multi-subscriber support** – Kotlin `CentralAudioChannel` and Dart `CentralAudioBridge` support concurrent audio subscriptions by `subId`, ensuring continuous background ring-buffer recording without stopping/restarting the microphone.

## [0.1.4] - 2026-10-30

Assistant overlay stays open during speech output and undo countdown (K146 / WP182).

### Fixed

- **Assistant overlay auto-close during speech** – the overlay no longer closes prematurely while Wendelin is speaking an answer or announcement; it closes only after speech output completes.
- **Undo window preservation** – when an action with an undo option is executed, the overlay stays open for the full 10-second countdown window (`hasPendingUndo`). If the user taps "Rückgängig", the reversal is confirmed with "Zurückgenommen." before closing. If no action is taken, it automatically closes after the 10 seconds expire.


## [0.1.3] - 2026-10-30

Centralized audio capture service and multi-subscriber ring buffer (ADR 0024 / WP180).

### Added

- **Centralized Android audio recording service** – single capture source for all audio on Android directly within `WakeWordService` using a continuous 16 kHz PCM16 ring buffer (`AudioRingBuffer`, ≥ 6 s).
- **Multi-subscriber audio dispatch** – `CentralAudioHub` distributes audio streams simultaneously to wake detection (`WAKE`), interaction/dialog sessions (`SESSION`), and speaker/wake enrollment (`ENROLL`) without mic contention or restarts.
- **Microphone conflict management** – automatic pause of recording during external mic conflicts (phone calls, third-party apps) and seamless resume when conflicts clear.

### Fixed

- **Concurrent capture restrictions on Android 10** – fixes mic lockout and muted audio (`isClientSilenced`) on devices where multiple `AudioRecord` instances cannot run concurrently (such as Huawei EMUI), allowing speech recognition and speaker enrollment (`SpeakerEnrollScreen`) to work reliably.

## [0.1.2] - 2026-10-29

Continuous audio ring buffer and selectable stage 2 wake word verifiers.

### Added

- **Continuous audio ring buffer** – rolling ring buffer (≥ 5 s) for all microphone recordings. When waiting for the wake word, audio rolls continuously in memory; when a candidate triggers, incoming audio is held throughout stage 2 verification (Parakeet/Whisper/model loading).
- **Seamless fast command recognition** – commands spoken immediately after the wake word ("Wendelin <command>" in a single breath) are captured gaplessly from the buffer without losing audio.
- **Uninterrupted microphone capture** – recording keeps running across speech output and interaction phases instead of restarting repeatedly.
- **Selectable stage 2 wake word verification** – verifier B (voice templates) and the speech recognition model can be toggled independently with OR logic.

## [0.1.1] - 2026-10-29

Easier to set up, more reliable wake word.

### Added

- **Setup assistant** – on first start, an assistant walks through the essentials: AI provider and speech recognition (required), then optionally the wake word, integrations and personalisation. Existing installations see it once after the update, with finished steps already ticked.

### Changed

- **Tidier settings** – the wake word has its own menu entry with the download of the trained model at the top; it can only be switched on with that model. Routing moved under "Providers" → "Advanced settings".
- **More reliable wake word** – the second check is always done by the own verifier; if it cannot decide, the installed recognition model (Parakeet or Whisper) helps. A missing model is reported clearly instead of silently dropping hits. In station mode the wake word stays on while the station is open.
- **The window closes itself** – when listening ends without speech, the assistant window closes and the wake word listens again right away. It only stays open for questions, confirmations or unlocking.
- Without a saved choice, the app languages follow the system language (German, English, French; otherwise English).
- Licence GPL-3.0-or-later, new README (English/German) and project page.

## [0.1.0] - 2026-10-28

First release of Wendelin, a personal voice assistant for Android that does as much as possible on the device.

### Added

- **Voice instead of typing** – set up as the default assistant; start it with the side key, the assistant gesture or "Hey Wendelin". Wake word, speech recognition (Whisper, Parakeet) and speech output run locally. In conversation mode Wendelin keeps listening after its answer, and the wake word interrupts it.
- **Language model of your choice, with verification** – answers come from a provider you pick. For providers with confidential execution (TEE), Wendelin checks the attestation, optionally including the GPU proof, before it sends data.
- **Everyday integrations** – Home Assistant, Spotify, media control, contacts, calls and SMS, navigation with Google Maps or Waze, alarms, Obsidian notes, and your own MCP and HTTP tools.
- **Security levels** – every tool and device type gets a level from A to D that decides what is allowed while the phone is locked: free, only with a recognised voice, only unlocked, or always with confirmation. Actions such as navigation wait for unlocking and then run exactly once.
- **Useful while locked** – the window shows the request and the answer but no history; contacts are released field by field; addresses for navigation stay on the device and are never shown to the language model.
- **Station mode and speech recognition for other apps** – use the phone as a fixed voice station, or offer the local speech recognition to other apps.
- Works without Google Play Services. User interface languages: German, English, French.

### Installation

Download the APK below and install it. On Android 13 and later, you may have to allow "restricted settings" under App info (three-dot menu) so that SMS and notification access work; the app shows a hint.

Certificate fingerprint (SHA-256): `A9:E9:5A:13:98:34:19:23:4B:DB:8F:CA:F6:0F:1B:84:18:88:36:86:7B:F8:DC:38:99:15:B5:25:39:DC:09:7B`
APK checksum: see `SHA256SUMS`.

[Unreleased]: https://github.com/brokoskokoli/wendelin/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/brokoskokoli/wendelin/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/brokoskokoli/wendelin/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/brokoskokoli/wendelin/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/brokoskokoli/wendelin/releases/tag/v0.1.0
