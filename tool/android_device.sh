# Gemeinsame Geräteauswahl der Gerätetests (zum Einbinden mit `source`).
#
# Setzt ADB und DEVICE und definiert `adb` (immer mit -s DEVICE) sowie
# `is_emulator`. DEVICE kommt aus der Umgebung (DEVICE, sonst
# ANDROID_SERIAL). Ohne beides muss genau ein Gerät verbunden sein: bei
# mehreren bricht das Skript ab, statt irgendeins zu nehmen.

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
