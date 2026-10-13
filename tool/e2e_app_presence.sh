#!/usr/bin/env bash
# Gerätetest der App-Erkennung (WP25) – nur auf einem Emulator.
#
#   DEVICE=emulator-5554 tool/e2e_app_presence.sh
#
# Baut zwei Attrappen-APKs ohne Code (aapt2 aus den Build-Tools, signiert
# mit dem Debug-Keystore):
#   md.obsidian              – in <queries> deklariert
#   app.wendelin.e2e.hidden  – nicht deklariert
# und prüft mit integration_test/app_presence_e2e_test.dart:
#   1. beide installiert: `pm list packages` (Shell) sieht beide, der Kanal
#      nur md.obsidian (Paket-Sichtbarkeit ab Android 11 greift),
#      ch.publisheria.bring (deklariert, nicht installiert) ist false;
#   2. md.obsidian deinstalliert: der Kanal meldet false.
# Danach werden die Attrappen wieder entfernt. Ein echtes Gerät wird
# abgelehnt (keine Ausnahme): das Skript installiert Pakete mit fremden
# Paketnamen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tool/android_device.sh
. "$ROOT/tool/android_device.sh"

if ! is_emulator; then
  echo "Abbruch: $DEVICE ist kein Emulator. Dieser Test läuft nur auf Emulatoren." >&2
  exit 1
fi

SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
PLATFORM="$(ls -d "$SDK"/platforms/android-* | sort -V | tail -1)"
KEYSTORE="${E2E_KEYSTORE:-$HOME/.android/debug.keystore}"
WORK="$(mktemp -d)"
DECLARED=md.obsidian
HIDDEN=app.wendelin.e2e.hidden
NOT_INSTALLED=ch.publisheria.bring

installed_pkgs() { adb shell pm list packages | tr -d '\r' | sed 's/^package://'; }
has_pkg() { installed_pkgs | grep -qx "$1"; }

cleanup() {
  for p in "$DECLARED" "$HIDDEN"; do
    if [ -f "$WORK/ours-$p" ]; then adb uninstall "$p" >/dev/null 2>&1 || true; fi
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

dummy_apk() { # <paket>
  local dir="$WORK/$1"
  mkdir -p "$dir"
  cat >"$dir/AndroidManifest.xml" <<XML
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$1">
  <application android:hasCode="false" android:label="Wendelin E2E $1"/>
</manifest>
XML
  "$BT/aapt2" link -o "$dir/u.apk" -I "$PLATFORM/android.jar" \
    --manifest "$dir/AndroidManifest.xml" --min-sdk-version 26 \
    --target-sdk-version 35 --version-code 1 --version-name 1.0 >&2
  "$BT/zipalign" -f 4 "$dir/u.apk" "$dir/a.apk" >&2
  "$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass pass:android \
    --out "$dir/$1.apk" "$dir/a.apk" >&2
  echo "$dir/$1.apk"
}

for p in "$DECLARED" "$HIDDEN" "$NOT_INSTALLED"; do
  if has_pkg "$p"; then
    echo "Abbruch: $p ist auf $DEVICE schon installiert (kein sauberer Emulator)." >&2
    exit 1
  fi
done

for p in "$DECLARED" "$HIDDEN"; do
  apk="$(dummy_apk "$p")"
  adb install -r "$apk" >/dev/null
  touch "$WORK/ours-$p"
done
has_pkg "$DECLARED" && has_pkg "$HIDDEN" || {
  echo "Attrappen nicht installiert" >&2
  exit 1
}
echo "pm list packages: $DECLARED und $HIDDEN installiert, $NOT_INSTALLED nicht"

cd "$ROOT/app"
run_test() { # <APPS_EXPECT>
  flutter test integration_test/app_presence_e2e_test.dart -d "$DEVICE" \
    --dart-define=APPS_EXPECT="$1"
}

echo "== 1. installiert: Kanal sieht nur das deklarierte Paket"
run_test "$DECLARED=1,$HIDDEN=0,$NOT_INSTALLED=0"

echo "== 2. $DECLARED deinstalliert"
adb uninstall "$DECLARED" >/dev/null
rm -f "$WORK/ours-$DECLARED"
has_pkg "$DECLARED" && { echo "$DECLARED noch da" >&2; exit 1; }
run_test "$DECLARED=0,$HIDDEN=0,$NOT_INSTALLED=0"

echo "App-Erkennung auf $DEVICE: ok"
