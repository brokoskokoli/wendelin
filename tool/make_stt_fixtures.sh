#!/bin/sh
# Erzeugt die STT-Fixtures (16 kHz, mono, 16 bit PCM WAV) aus
# app/test/fixtures/stt/manifest.tsv mit sherpa-onnx-TTS (Neural-TTS, offline)
# und Piper-Stimmen (VITS) im sherpa-onnx-Export.
#
#   tool/make_stt_fixtures.sh            # alle fehlenden Dateien erzeugen
#   tool/make_stt_fixtures.sh --force    # alle neu erzeugen
#
# Voraussetzungen: Python 3.13 mit `sherpa-onnx==1.13.8` und `numpy`
# (Apache-2.0; z. B. `python3.13 -m venv v && v/bin/pip install
# sherpa-onnx==1.13.8 numpy`, dann PY=v/bin/python) und ein Umwandler nach
# 16 kHz (macOS `afconvert`, sonst `ffmpeg`). Warum nicht `piper-tts`: Dessen
# macOS-arm64-Wheels (1.3 bis 1.8) finden ihre espeak-ng-Daten nicht.
# Die Modelle (je ~65 MB, mit espeak-ng-data) lädt das Skript beim ersten Lauf
# nach $TTS_MODELS (Standard: ${TMPDIR:-/tmp}/wendelin-tts-models, nie ins Repo)
# und prüft das Archiv per SHA-256. Quelle: GitHub-Release `tts-models` von
# https://github.com/k2-fsa/sherpa-onnx (vits-piper-<stimme>.tar.bz2); es sind
# die Piper-Stimmen von https://huggingface.co/rhasspy/piper-voices, die .onnx
# tragen zusätzlich sherpa-Metadaten (SHA-256 weicht vom Original ab).
#
# Stimmen und Lizenzen (MODEL_CARD im Archiv; Lizenz = Lizenz des Datensatzes,
# die sherpa-Exporte fügen keine Bedingungen hinzu):
#   de_DE-thorsten-medium  Datensatz Thorsten-Voice (T. Müller, Thorsten-Voice
#                          https://github.com/thorstenMueller/Thorsten-Voice) – CC0-1.0
#   en_US-ljspeech-medium  LJ Speech (K. Ito, L. Johnson,
#                          https://keithito.com/LJ-Speech-Dataset/) – Public Domain (CC0-1.0)
#   fr_FR-siwis-medium     SIWIS French Speech Synthesis Database (Univ. Edinburgh,
#                          https://doi.org/10.7488/ds/1705) – CC-BY-4.0
# Die erzeugten WAVs stehen deshalb teils unter CC0-1.0, die französischen
# unter CC-BY-4.0 (REUSE.toml, Namensnennung wegen SIWIS); Texte: Manifest.
#
# Spalten im Manifest (Tab-getrennt): id, Sprache, Stimme, Text.
# Eigene Aufnahmen des Maintainers kommen als <id>.wav (gleiches Format)
# mit einer Zeile und der Stimme "own" ins Manifest; das Skript überspringt
# sie. Umwandeln z. B. mit
#   afconvert --no-filler -f WAVE -d LEI16@16000 -c 1 aufnahme.m4a own-de-01.wav
set -eu

BASE="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models"
PY="${PY:-python3.13}"
models="${TTS_MODELS:-${TMPDIR:-/tmp}/wendelin-tts-models}"
dir="$(cd "$(dirname "$0")/.." && pwd)/app/test/fixtures/stt"
here="$(cd "$(dirname "$0")" && pwd)"
force="${1:-}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/stt-fixtures.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# SHA-256 des Archivs vits-piper-<stimme>.tar.bz2
voice_sha() {
  case "$1" in
    de_DE-thorsten-medium) echo 50487d9c95fdf2191f31d2588569381063ba1591dcd4c7d4bdd30f12b2191714 ;;
    en_US-ljspeech-medium) echo 3dfb4b759d8be032a4903a9538d128b0fda2a06ab1de6cbc2d93a97e2dd83dba ;;
    fr_FR-siwis-medium) echo 375909aa30842b3a4efa10b1beb1d761af792960ae6873b4d53889f96c66195b ;;
    *) echo "unbekannte Stimme $1" >&2; return 1 ;;
  esac
}

fetch_voice() {
  v="$1"
  [ -d "$models/vits-piper-$v" ] && return 0
  mkdir -p "$models"
  curl -fsSL -o "$models/$v.tar.bz2" "$BASE/vits-piper-$v.tar.bz2"
  got="$(shasum -a 256 "$models/$v.tar.bz2" | cut -d' ' -f1)"
  [ "$got" = "$(voice_sha "$v")" ] || { echo "SHA-256 von $v.tar.bz2 stimmt nicht" >&2; rm -f "$models/$v.tar.bz2"; exit 1; }
  tar -xjf "$models/$v.tar.bz2" -C "$models"
  rm -f "$models/$v.tar.bz2"
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
  printf '%s\n' "$text" | "$PY" -I "$here/stt_tts.py" "$models/vits-piper-$voice" "$tmp/$id.wav"
  to16k "$tmp/$id.wav" "$out"
  echo "$id ($lang, $voice): $text"
done
