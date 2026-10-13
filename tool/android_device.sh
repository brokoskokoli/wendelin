# Gemeinsame Geräteauswahl der Gerätetests (zum Einbinden mit `source`).
#
# Setzt ADB und DEVICE und definiert `adb` (immer mit -s DEVICE) sowie
# `is_emulator`. DEVICE kommt aus der Umgebung (DEVICE, sonst
# ANDROID_SERIAL). Ohne beides muss genau ein Gerät verbunden sein: bei
# mehreren bricht das Skript ab, statt irgendeins zu nehmen.
#
#   bash tool/android_device.sh --self-test   # Selbsttest mit Fake-adb (Gate)

if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = "--self-test" ]; then
  set -euo pipefail
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' EXIT
  # Fake-adb: `devices` gibt $dir/devices.txt aus, alles andere nichts.
  cat >"$dir/adb" <<'STUB'
#!/usr/bin/env bash
d="$(dirname "$0")"
[ "$1" = devices ] && { echo "List of devices attached"; cat "$d/devices.txt"; }
exit 0
STUB
  chmod +x "$dir/adb"
  status=0
  check() { # name, devices.txt-Inhalt, DEVICE, ANDROID_SERIAL, Exit, Ausgabe
    local out got=0
    printf '%b' "$2" >"$dir/devices.txt"
    out="$(ADB="$dir/adb" DEVICE="$3" ANDROID_SERIAL="$4" bash -c \
      '. "$0" && echo "DEVICE=$DEVICE"' "${BASH_SOURCE[0]}" 2>&1)" || got=$?
    if [ "$got" != "$5" ] || ! grep -qF "$6" <<<"$out"; then
      echo "Selbsttest FEHLER: $1 (Exit $got, erwartet $5): $out" >&2
      status=1
    else
      echo "ok: $1"
    fi
  }
  check "kein Gerät: Abbruch" "" "" "" 1 "Kein Android-Gerät verbunden"
  check "ein Gerät wird genommen" "emulator-5554\tdevice\n" "" "" 0 "DEVICE=emulator-5554"
  check "nicht autorisiertes Gerät zählt nicht" "emulator-5554\tdevice\nR58\tunauthorized\n" "" "" 0 "DEVICE=emulator-5554"
  check "zwei Geräte: Abbruch" "emulator-5554\tdevice\nemulator-5556\tdevice\n" "" "" 1 "Mehrere Geräte verbunden"
  check "zwei Geräte, DEVICE gesetzt" "emulator-5554\tdevice\nemulator-5556\tdevice\n" "emulator-5556" "" 0 "DEVICE=emulator-5556"
  check "zwei Geräte, ANDROID_SERIAL gesetzt" "emulator-5554\tdevice\nemulator-5556\tdevice\n" "" "emulator-5554" 0 "DEVICE=emulator-5554"
  exit $status
fi

SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
ADB="${ADB:-$SDK/platform-tools/adb}"

pick_device() {
  local devices count
  devices="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')"
  count="$(printf '%s' "$devices" | grep -c . || true)"
  if [ "$count" = 0 ]; then
    echo "Kein Android-Gerät verbunden" >&2
    return 1
  fi
  if [ "$count" != 1 ]; then
    echo "Mehrere Geräte verbunden ($(echo "$devices" | tr '\n' ' '))." \
      "DEVICE=<seriennummer> oder ANDROID_SERIAL setzen." >&2
    return 1
  fi
  echo "$devices"
}

DEVICE="${DEVICE:-${ANDROID_SERIAL:-}}"
if [ -z "$DEVICE" ]; then
  DEVICE="$(pick_device)" || exit 1
fi
export ANDROID_SERIAL="$DEVICE"

adb() { "$ADB" -s "$DEVICE" "$@"; }

# Emulator: Seriennummer emulator-* und ro.kernel.qemu=1.
is_emulator() {
  case "$DEVICE" in emulator-*) ;; *) return 1 ;; esac
  [ "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = "1" ]
}
