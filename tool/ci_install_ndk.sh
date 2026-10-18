#!/usr/bin/env bash
# CI: installiert das Android-NDK mit bis zu drei Versuchen. Der Download
# bricht gelegentlich mit "unknown archive"/"not a ZIP archive" ab
# (Infrastruktur, kein Testfehler). Ist das NDK schon da (Cache), passiert nichts.
set -u
ver="${1:?NDK-Version}"
dir="$ANDROID_HOME/ndk/$ver"
[ -f "$dir/source.properties" ] && { echo "NDK $ver vorhanden"; exit 0; }
for i in 1 2 3; do
  echo "y" | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --install "ndk;$ver" >/dev/null \
    && [ -f "$dir/source.properties" ] && { echo "NDK $ver installiert (Versuch $i)"; exit 0; }
  echo "NDK-Versuch $i fehlgeschlagen" >&2
  rm -rf "$dir" "$ANDROID_HOME/.temp"
  sleep $((i * 15))
done
exit 1
