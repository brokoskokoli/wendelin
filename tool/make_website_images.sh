#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Renders the website's images (committed; rerun only after changing the icon, the preview
# template or the screenshots):
#   website/favicon.png (64), website/apple-touch-icon.png (180), website/images/icon.png (512)
#     from packaging/brand/icon.svg (app mark on the app's ink colour)
#   website/images/social-preview.png (1280 x 640) from packaging/brand/social-preview.svg
#   website/images/shot-*.webp from docs/images/screenshots/*.webp (390 px wide, 2x = 780 px)
# Requires resvg and cwebp (brew install resvg webp). The preview's tagline uses a system font
# (Helvetica Neue on macOS), the wordmark is outlines: render on macOS for identical results.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
[[ -d /opt/homebrew/bin ]] && export PATH="/opt/homebrew/bin:$PATH"
for t in resvg cwebp; do command -v "$t" >/dev/null || { echo "$t missing" >&2; exit 1; }; done

ICON=packaging/brand/icon.svg
PREVIEW=packaging/brand/social-preview.svg
mkdir -p website/images
resvg -w 64 -h 64 "$ICON" website/favicon.png
resvg -w 180 -h 180 "$ICON" website/apple-touch-icon.png
resvg -w 512 -h 512 "$ICON" website/images/icon.png
# resvg resolves the <image> href relative to the template's directory.
resvg -w 1280 -h 640 --resources-dir "$(dirname "$PREVIEW")" "$PREVIEW" website/images/social-preview.png

# Screenshots: the repository ones are 1170 px wide (@3x); the page shows at most ~390 css px.
for n in conversation confirmation settings; do
  src=docs/images/screenshots/$n.webp
  tmp=$(mktemp -d)/$n.png
  # cwebp cannot read WebP as input: decode via dwebp, then resize and re-encode.
  dwebp -quiet "$src" -o "$tmp"
  cwebp -quiet -q 80 -m 6 -resize 780 0 "$tmp" -o "website/images/shot-$n.webp"
  rm -f "$tmp"
done
touch website/.nojekyll
echo "wrote website/favicon.png, apple-touch-icon.png, images/{icon,social-preview}.png, images/shot-*.webp"
