#!/bin/sh
# Erzeugt die STT-Fixtures (16 kHz, mono, 16 bit PCM WAV) aus
# app/test/fixtures/stt/manifest.tsv mit Piper (Neural-TTS, offline).
#
#   tool/make_stt_fixtures.sh            # alle fehlenden Dateien erzeugen
#   tool/make_stt_fixtures.sh --force    # alle neu erzeugen
#
# Voraussetzungen: `piper` (pip-Paket piper-tts, getestet mit 1.8.0, GPL-3.0;
# z. B. `python3.13 -m venv v && v/bin/pip install piper-tts==1.8.0`, dann
# PIPER="v/bin/python -m piper") und ein Umwandler nach 16 kHz (macOS
# `afconvert`, sonst `ffmpeg`). Die Stimmen werden beim ersten Lauf nach
# $PIPER_VOICES geladen (Standard: ${TMPDIR:-/tmp}/wendelin-piper-voices, nie ins
# Repo) und per SHA-256 geprüft. Quelle: Hugging Face rhasspy/piper-voices,
# Revision $REV (gepinnt).
#
# Stimmen und Lizenzen (Model Card je Stimme; Lizenz = Lizenz des Datensatzes):
#   de_DE-thorsten-medium  Datensatz Thorsten-Voice (T. Müller, Thorsten-Voice
#                          https://github.com/thorstenMueller/Thorsten-Voice) – CC0-1.0
#   en_US-ljspeech-medium  LJ Speech (K. Ito, L. Johnson,
#                          https://keithito.com/LJ-Speech-Dataset/) – Public Domain
#   fr_FR-siwis-medium     SIWIS French Speech Synthesis Database (Univ. Edinburgh,
#                          https://doi.org/10.7488/ds/1705) – CC-BY-4.0
# Die erzeugten WAVs stehen deshalb unter CC-BY-4.0 (REUSE.toml, Namensnennung
# wegen SIWIS); die Texte stehen im Manifest.
#
# Spalten im Manifest (Tab-getrennt): id, Sprache, Piper-Stimme, Text.
# Eigene Aufnahmen des Maintainers kommen als <id>.wav (gleiches Format)
# mit einer Zeile und der Stimme "own" ins Manifest; das Skript überspringt
# sie. Umwandeln z. B. mit
#   afconvert --no-filler -f WAVE -d LEI16@16000 -c 1 aufnahme.m4a own-de-01.wav
set -eu

REV=5041a7a49ae5b3a0f30e6837769eb03fdbb231bd
HF="https://huggingface.co/rhasspy/piper-voices/resolve/$REV"
PIPER="${PIPER:-piper}"
voices="${PIPER_VOICES:-${TMPDIR:-/tmp}/wendelin-piper-voices}"
dir="$(cd "$(dirname "$0")/.." && pwd)/app/test/fixtures/stt"
force="${1:-}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/stt-fixtures.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Stimme -> Pfad im Repo piper-voices und SHA-256 der .onnx
voice_path() {
  case "$1" in
    de_DE-thorsten-medium) echo "de/de_DE/thorsten/medium" ;;
    en_US-ljspeech-medium) echo "en/en_US/ljspeech/medium" ;;
    fr_FR-siwis-medium) echo "fr/fr_FR/siwis/medium" ;;
    *) echo "unbekannte Stimme $1" >&2; return 1 ;;
  esac
}
voice_sha() {
  case "$1" in
    de_DE-thorsten-medium) echo 7e64762d8e5118bb578f2eea6207e1a35a8e0c30595010b666f983fc87bb7819 ;;
    en_US-ljspeech-medium) echo 6f52a751e2349abe7a76735eb09dc1875298c77ea2342ffd2fef79ff81b87f22 ;;
    fr_FR-siwis-medium) echo 641d1ab097da2b81128c076810edb052b385decc8be3381814802a64a73baf99 ;;
  esac
}

fetch_voice() {
  v="$1"
  mkdir -p "$voices"
  if [ ! -f "$voices/$v.onnx" ]; then
    p="$(voice_path "$v")"
    curl -fsSL -o "$voices/$v.onnx" "$HF/$p/$v.onnx"
    curl -fsSL -o "$voices/$v.onnx.json" "$HF/$p/$v.onnx.json"
  fi
  got="$(shasum -a 256 "$voices/$v.onnx" | cut -d' ' -f1)"
  [ "$got" = "$(voice_sha "$v")" ] || { echo "SHA-256 von $v.onnx stimmt nicht" >&2; exit 1; }
}

to16k() { # in out
  if command -v afconvert >/dev/null; then
    afconvert --no-filler -f WAVE -d LEI16@16000 -c 1 "$1" "$2"
  else
    ffmpeg -loglevel error -y -i "$1" -ar 16000 -ac 1 -c:a pcm_s16le "$2"
  fi
}

tab="$(printf '\t')"
grep -v '^#' "$dir/manifest.tsv" | while IFS="$tab" read -r id lang voice text; do
  [ -n "$id" ] || continue
  [ "$voice" = "own" ] && continue
  out="$dir/$id.wav"
  if [ -f "$out" ] && [ "$force" != "--force" ]; then continue; fi
  fetch_voice "$voice"
  printf '%s\n' "$text" | $PIPER -m "$voices/$voice.onnx" -f "$tmp/$id.wav" >/dev/null 2>&1
  to16k "$tmp/$id.wav" "$out"
  echo "$id ($lang, $voice): $text"
done
