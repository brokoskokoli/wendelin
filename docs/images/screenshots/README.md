# Screenshots

README and website screenshots, rendered reproducibly by the widget test
engine (no emulator, no device): real screens with English UI and invented
sample content (no real names, contacts, devices or paths). 390 x 844 logical
pixels at @3x (1170 x 2532), real fonts, WebP.

The app has only a dark theme, so there are no light variants.

| File | Screen |
| --- | --- |
| `conversation.webp` | Main screen: conversation with tool calls |
| `confirmation.webp` | Confirmation sheet for a risky action (security level) |
| `settings.webp` | Settings overview |
| `onboarding.webp` | Onboarding, step 1 |

## Regenerate

```sh
tool/make_screenshots.sh
```

Needs Flutter and `cwebp` (`brew install webp`). The script runs
`app/test/screenshots/screenshots_test.dart` (tag `screenshots`; it skips
itself without `SCREENSHOT_DIR`, so gate and CI never render or compare it),
converts the PNGs with `cwebp -q 82` and writes the files here. Fonts and
text rendering differ slightly per platform: regenerate on macOS and check
every image by eye before committing (content, language, nothing cut off).

Sample content lives in the test file; change it there.
