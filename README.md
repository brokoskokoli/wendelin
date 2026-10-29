<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
**English** · [Deutsch](README.de.md)

<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="app/assets/logo/wendelin-lockup-on-dark.svg">
  <img src="app/assets/logo/wendelin-lockup.svg" width="320" alt="Wendelin">
</picture>

**A personal voice assistant for Android that does as much as possible on your phone: wake word, speech recognition and speech output run locally, and the language model is one you choose.**

[![Gate](https://github.com/brokoskokoli/wendelin/actions/workflows/gate.yml/badge.svg)](https://github.com/brokoskokoli/wendelin/actions/workflows/gate.yml)
[![Latest release](https://img.shields.io/github/v/release/brokoskokoli/wendelin?include_prereleases&sort=semver)](https://github.com/brokoskokoli/wendelin/releases)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
[![Platform: Android 10+](https://img.shields.io/badge/platform-Android%2010%2B-3ddc84.svg)](#install)

<img src="docs/images/screenshots/conversation.webp" width="300" alt="Wendelin conversation: a spoken request, the tool calls it triggered and the answer">

[![Download for Android](https://img.shields.io/badge/Download_for_Android-latest_release-3ddc84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/brokoskokoli/wendelin/releases/latest)

[Website](https://brokoskokoli.github.io/wendelin/)

</div>

> **Status:** version 0.1.0 is the first public release. See the [changelog](CHANGELOG.md).

## Why Wendelin?

Most voice assistants send your voice to someone else's cloud and only talk to the services their maker has picked. Wendelin turns that around: it becomes your phone's default assistant, understands you **on the device**, and only the text goes to a language model **of your choice** (your own API key, no Wendelin server). For providers that run in a confidential environment (TEE), Wendelin checks the attestation itself before it sends anything.

It runs without Google Play Services, so it also works on AOSP-based systems.

## Features

- **Speak instead of type.** Wendelin registers as the default assistant and starts with the side key, the assistant gesture or "Hey Wendelin". The wake word, speech recognition (Whisper, Parakeet) and speech output run locally. In conversation mode Wendelin keeps listening after its answer, and you can interrupt it with the wake word.
- **A language model of your choice, with verification.** Answers come from a provider you set up (for example Claude, OpenAI, Mistral, OpenRouter, Ollama or your own endpoint). For providers with confidential execution (Phala, NEAR AI, Tinfoil) Wendelin verifies the attestation, and the GPU proof on request, before it sends data.
- **Everyday integrations.** Home Assistant (lights, blinds, scenes ...), Spotify (plays on the device that is currently playing, or on the phone), media control, contacts, calls and SMS, navigation with Google Maps or Waze (also "navigate to <contact>"), calendar, alarms and timers, tasks (Todoist, Google Tasks), weather, shopping lists (Bring!), Obsidian notes, plus your own MCP and HTTP tools. Each integration is off until you switch it on.
- **Security in levels.** Every tool and device kind gets a level from A to D, which decides what is allowed while the phone is locked: free, only with a recognised voice, only unlocked, or always with a confirmation. Actions such as navigation ask after unlocking and then run exactly once. Changes can be undone briefly, and risky actions always ask first.
- **Useful while locked.** On a locked phone the window shows the request and the answer, but no history. Contacts are handed out field by field. Addresses for navigation stay on the device; the language model does not see them.
- **Station mode and speech recognition for other apps.** The phone can serve as a fixed voice station (clock, weather, appointments, playback, smart-home tiles). The local speech recognition is also available to other apps on request.
- **Audit log.** Every request, tool call and attestation result is logged on the device and can be exported.
- **Languages:** the interface is available in German, English and French.

## Screenshots

| | | |
|---|---|---|
| <img src="docs/images/screenshots/conversation.webp" width="250" alt="Conversation with tool calls"> | <img src="docs/images/screenshots/confirmation.webp" width="250" alt="Confirmation sheet for a risky action"> | <img src="docs/images/screenshots/settings.webp" width="250" alt="Settings overview"> |
| **Conversation** with tool calls | **Confirmation** for risky actions | **Settings** |

More on the [website](https://brokoskokoli.github.io/wendelin/).

## Install

Requirements: **Android 10 or later**. Google Play Services are not needed.

1. Download `wendelin-<version>.apk` and `SHA256SUMS` from the [latest release](https://github.com/brokoskokoli/wendelin/releases/latest) and install the APK (allow installing from this source when Android asks).
2. **Verify it (recommended).** Compare the checksum with `SHA256SUMS` (`sha256sum -c SHA256SUMS`) and the signing certificate with the published fingerprint, for example with `apksigner verify --print-certs wendelin-<version>.apk`. Certificate fingerprint (SHA-256) of version 0.1.0:

   ```text
   A9:E9:5A:13:98:34:19:23:4B:DB:8F:CA:F6:0F:1B:84:18:88:36:86:7B:F8:DC:38:99:15:B5:25:39:DC:09:7B
   ```

   The fingerprint is also in the notes of every release. Background: [docs/RELEASE.md](docs/RELEASE.md) (German).
3. **Android 13 and later: restricted settings.** For an APK installed outside a store, Android blocks SMS and notification access at first. Open *Settings > Apps > Wendelin*, tap the menu (three dots) and choose **Allow restricted settings** (the entry appears only after the first failed attempt to grant the access), then grant the access. Wendelin shows these steps, with a button to the app info, when it is needed.

## Getting started

1. Open Wendelin and follow the onboarding. Grant the microphone permission; the speech models are downloaded in the app.
2. **Set up a provider** (Settings > Providers): pick a template, enter your API key and run the connection test. The key stays in the Android Keystore. For providers with confidential execution, the verification result is shown with the provider.
3. Make Wendelin your **default assistant** (the app takes you to the Android setting) and switch on **Hey Wendelin** (Settings > Wake word) if you want hands-free use.
4. Switch on the **integrations** you want (Settings > Integrations) and grant the permissions each one asks for.
5. Say, for example: "Hey Wendelin, set a timer for ten minutes."

## Privacy

Wendelin has no account, no analytics and no telemetry, and no backend of its own.

- **Stays on the device:** audio, the wake word, speech recognition and speech output (with the local engines), the conversation history, memory, the audit log and all secrets (API keys and tokens in the Android Keystore). Audio does not leave the phone.
- **Goes to your language-model provider:** the transcript, the system prompt, selected memory entries, the tool descriptions and tool results. Which privacy level a provider has (local, TEE, EU, standard) is shown per provider, and you can restrict sensitive integrations to stricter providers.
- **Other connections, only for features you switch on:** the services of the integrations you set up (for example your Home Assistant, Spotify, Todoist, Google Tasks, a web-search service, public web pages the model asks to read, a weather service, your MCP servers and HTTP tools) and, for attestation, the verification endpoints of the TEE providers (for example NVIDIA's GPU attestation service and the AMD and Intel certificate services). The speech models are downloaded once in the app from Hugging Face, the sherpa-onnx project and this repository's release page.
- Every connection is listed on the [privacy page](https://brokoskokoli.github.io/wendelin/privacy.html).
- You can export and delete the audit log in Settings > Privacy and logs.

The speech models are not part of this repository. Their licenses and attributions are listed in the app under Settings > Speech > Licenses of the speech models.

## Build from source

You need Flutter 3.47 / Dart 3.13 (the Android SDK with API 35 for the app, Rust for `native/attest`).

```sh
flutter pub get                      # in the repository root (Pub workspace)
dart run tool/gate.dart --changed    # format, analysis, tests for what you changed
cd app && flutter build apk --release
```

Without signing keys the build falls back to the debug key (for local tests only). Layout, dependency rules, tests and git workflow: [docs/ENGINEERING.md](docs/ENGINEERING.md) (German). Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), decisions: [docs/adr/](docs/adr/), design: [docs/design/DESIGN.md](docs/design/DESIGN.md).

## Contributing

Bug reports, ideas, translations and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first. Report security issues privately, see [SECURITY.md](SECURITY.md).

## License

Wendelin is free software under the **GNU General Public License v3.0 or later** (GPL-3.0-or-later), see [LICENSE](LICENSE). The repository follows the [REUSE](https://reuse.software) specification ([REUSE.toml](REUSE.toml), license texts in [LICENSES/](LICENSES/)). The bundled fonts (IBM Plex Mono, Instrument Sans) are under the SIL Open Font License 1.1. The speech models are downloaded separately under their own licenses (see the in-app license page).

## Acknowledgements

Wendelin builds on many open-source projects, among them [Flutter](https://flutter.dev), [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (local speech recognition and output), [Whisper](https://github.com/openai/whisper) and [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [openWakeWord](https://github.com/dscripka/openWakeWord) (feature extractors for the wake word), and the [Model Context Protocol](https://modelcontextprotocol.io). Thanks to everyone who maintains them.

The French speech test fixtures (`app/test/fixtures/stt/fr-*.wav`, `b6-06.wav`) are synthesized with the Piper voice `fr_FR-siwis-medium`, trained on the SIWIS French Speech Synthesis Database (University of Edinburgh, [doi:10.7488/ds/1705](https://doi.org/10.7488/ds/1705), CC-BY-4.0). The German and English fixtures use voices from the CC0 Thorsten-Voice and public-domain LJ Speech datasets. Details: header of `tool/make_stt_fixtures.sh`.
