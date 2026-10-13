#!/usr/bin/env bash
# Gerätetest MCP (WP27) – nur auf einem Emulator.
#
#   DEVICE=emulator-5580 tool/e2e_mcp.sh
#
# Startet app/tool/mcp_test_server.dart auf dem Rechner (nur 127.0.0.1; der
# Emulator erreicht ihn als 10.0.2.2) und führt
# integration_test/mcp_e2e_test.dart aus: Prüfen, Anlegen mit Bearer-Token,
# Tools in der Registry, Aufruf, Löschen; OAuth ohne Browser (AOSP) gibt
# einen Hinweis. Danach integration_test/oauth_redirect_e2e_test.dart: die
# Rückleitung app.wendelin://oauth/mcp per `am start`, falscher state wird
# ignoriert. Klartext-http ist erlaubt, weil 10.0.2.2 als Heimnetz-Ziel
# gilt (ADR 0010 §6). Ein echtes Gerät wird abgelehnt (keine Ausnahme).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tool/android_device.sh
. "$ROOT/tool/android_device.sh"

if ! is_emulator; then
  echo "Abbruch: $DEVICE ist kein Emulator. Dieser Test läuft nur auf Emulatoren." >&2
  exit 1
fi

TOKEN="e2e-$(date +%s)"
WORK="$(mktemp -d)"
mkfifo "$WORK/in"
(cd "$ROOT/app" && dart run tool/mcp_test_server.dart --token "$TOKEN" <"$WORK/in" >"$WORK/out" 2>"$WORK/err") &
SERVER=$!
exec 3>"$WORK/in"
cleanup() {
  exec 3>&- || true
  wait "$SERVER" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

for _ in $(seq 1 120); do
  grep -q 'port=[0-9]' "$WORK/out" 2>/dev/null && break
  sleep 0.5
done
# `dart run` may print „Running build hooks...“ in the same line.
PORT="$(grep -o 'port=[0-9]*' "$WORK/out" | head -1 | cut -d= -f2)"
[ -n "$PORT" ] || { echo "Test-MCP-Server startet nicht: $(cat "$WORK/err")" >&2; exit 1; }
echo "Test-MCP-Server auf 127.0.0.1:$PORT (Emulator: 10.0.2.2:$PORT)"

cd "$ROOT/app"
flutter test integration_test/mcp_e2e_test.dart -d "$DEVICE" \
  --dart-define=MCP_URL="http://10.0.2.2:$PORT/mcp" \
  --dart-define=MCP_TOKEN="$TOKEN"

# Rückleitung über die Intent-Filter-Activity: während der Test auf die
# Anmeldung wartet, erst ein falscher, dann der richtige state.
redirects() {
  while true; do
    sleep 3
    adb shell am start -W -a android.intent.action.VIEW \
      -d "'app.wendelin://oauth/mcp?state=e2e-falsch&code=boese'" >/dev/null 2>&1 || true
    sleep 1
    adb shell am start -W -a android.intent.action.VIEW \
      -d "'app.wendelin://oauth/mcp?state=e2e-richtig&code=e2e-code'" >/dev/null 2>&1 || true
  done
}
redirects &
REDIRECTS=$!
status=0
flutter test integration_test/oauth_redirect_e2e_test.dart -d "$DEVICE" || status=$?
kill "$REDIRECTS" 2>/dev/null || true
exit $status
