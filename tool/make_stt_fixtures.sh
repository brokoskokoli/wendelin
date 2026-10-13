#!/bin/sh
# Erzeugt die STT-Fixtures (16 kHz, mono, 16 bit PCM WAV) aus
# app/test/fixtures/stt/manifest.tsv mit macOS `say` und `afconvert`.
#
#   tool/make_stt_fixtures.sh            # alle fehlenden Dateien erzeugen
#   tool/make_stt_fixtures.sh --force    # alle neu erzeugen
#
# Spalten im Manifest (Tab-getrennt): id, Sprache, macOS-Stimme, Text.
# Eigene Aufnahmen des Maintainers kommen als <id>.wav (gleiches Format)
# mit einer Zeile und der Stimme "own" ins Manifest; das Skript überspringt
# sie. Umwandeln z. B. mit
#   afconvert --no-filler -f WAVE -d LEI16@16000 -c 1 aufnahme.m4a own-de-01.wav
set -eu

dir="$(cd "$(dirname "$0")/.." && pwd)/app/test/fixtures/stt"
force="${1:-}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/stt-fixtures.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

command -v say >/dev/null || { echo "say fehlt (nur macOS)" >&2; exit 1; }

tab="$(printf '\t')"
grep -v '^#' "$dir/manifest.tsv" | while IFS="$tab" read -r id lang voice text; do
  [ -n "$id" ] || continue
  [ "$voice" = "own" ] && continue
  out="$dir/$id.wav"
  if [ -f "$out" ] && [ "$force" != "--force" ]; then continue; fi
  say -v "$voice" -o "$tmp/$id.aiff" -- "$text"
  afconvert --no-filler -f WAVE -d LEI16@16000 -c 1 "$tmp/$id.aiff" "$out"
  echo "$id ($lang, $voice): $text"
done
