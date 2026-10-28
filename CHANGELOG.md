# Changelog

All notable changes to Wendelin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/brokoskokoli/wendelin/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/brokoskokoli/wendelin/releases/tag/v0.1.0
