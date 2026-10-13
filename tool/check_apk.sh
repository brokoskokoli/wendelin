#!/usr/bin/env bash
# Prüft ein Android-APK auf K7 (keine Google Play Services) und das
# Manifest (kein Backup, nur die erwarteten Berechtigungen).
#
#   tool/check_apk.sh [pfad/zum.apk]   # Standard: Release-APK, wird gebaut
#
# Prüfungen:
#   - keine Klassen aus com.google.android.gms, com.google.firebase,
#     com.google.android.play, com.android.vending (apkanalyzer dex packages)
#   - Manifest: android:allowBackup="false", dataExtractionRules gesetzt,
#     keine Berechtigungen außer der erlaubten Liste
#   - Gradle-Abhängigkeiten (releaseRuntimeClasspath) ohne GMS/Firebase
set -euo pipefail

SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
APKANALYZER="$(ls -d "$SDK"/cmdline-tools/*/bin/apkanalyzer 2>/dev/null | head -1)"
[ -x "$APKANALYZER" ] || { echo "apkanalyzer fehlt (Android cmdline-tools)" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK="${1:-}"
if [ -z "$APK" ]; then
  (cd "$ROOT/app" && flutter build apk --release >/dev/null)
  APK="$ROOT/app/build/app/outputs/flutter-apk/app-release.apk"
fi
[ -f "$APK" ] || { echo "APK nicht gefunden: $APK" >&2; exit 1; }

fail=0
FORBIDDEN='^(com\.google\.android\.gms|com\.google\.firebase|com\.google\.android\.play|com\.android\.vending)(\.|$)'

packages="$("$APKANALYZER" dex packages --defined-only "$APK" | awk '{print $NF}')"
if hits="$(echo "$packages" | grep -E "$FORBIDDEN")"; then
  echo "FEHLER: GMS-/Firebase-Klassen im APK:" >&2
  echo "$hits" | sort -u | head -20 >&2
  fail=1
else
  echo "ok: keine GMS-/Firebase-Klassen ($(echo "$packages" | wc -l | tr -d ' ') Pakete/Klassen geprüft)"
fi

manifest="$("$APKANALYZER" manifest print "$APK")"
if echo "$manifest" | grep -q 'android:allowBackup="false"'; then
  echo 'ok: allowBackup="false"'
else
  echo 'FEHLER: android:allowBackup ist nicht "false"' >&2
  fail=1
fi
if echo "$manifest" | grep -q 'android:dataExtractionRules='; then
  echo 'ok: dataExtractionRules gesetzt'
else
  echo 'FEHLER: android:dataExtractionRules fehlt' >&2
  fail=1
fi
ALLOWED='^(android\.permission\.INTERNET|android\.permission\.READ_CALENDAR|android\.permission\.WRITE_CALENDAR|com\.android\.alarm\.permission\.SET_ALARM|app\.wendelin\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION)$'
perms="$("$APKANALYZER" manifest permissions "$APK")"
if extra="$(echo "$perms" | grep -vE "$ALLOWED")"; then
  echo "FEHLER: unerwartete Berechtigungen:" >&2
  echo "$extra" >&2
  fail=1
else
  echo "ok: Berechtigungen $(echo "$perms" | tr '\n' ' ')"
fi

if [ -x "$ROOT/app/android/gradlew" ]; then
  deps="$(cd "$ROOT/app/android" && ./gradlew -q :app:dependencies --configuration releaseRuntimeClasspath 2>/dev/null || true)"
  if [ -z "$deps" ]; then
    echo "Hinweis: Gradle-Abhängigkeitsbaum nicht lesbar, übersprungen"
  elif echo "$deps" | grep -qE 'com\.google\.android\.gms|com\.google\.firebase'; then
    echo "FEHLER: GMS/Firebase im Gradle-Abhängigkeitsbaum:" >&2
    echo "$deps" | grep -E 'com\.google\.android\.gms|com\.google\.firebase' | head >&2
    fail=1
  else
    echo "ok: Gradle-Abhängigkeiten ohne GMS/Firebase"
  fi
fi

exit $fail
