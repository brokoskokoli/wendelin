#!/usr/bin/env bash
# Renders the README/website screenshots (WP169 part C): real screens with
# English UI and invented sample content, widget render at @3x (390x844),
# no emulator. Output: docs/images/screenshots/*.webp. See the README there.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/docs/images/screenshots"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
command -v cwebp >/dev/null || { echo "cwebp missing (brew install webp)" >&2; exit 1; }
cd "$root/app"
SCREENSHOT_DIR="$tmp" flutter test --tags screenshots test/screenshots
mkdir -p "$out"
for png in "$tmp"/*.png; do
  name="$(basename "$png" .png)"
  cwebp -quiet -q 82 "$png" -o "$out/$name.webp"
done
ls -l "$out"
