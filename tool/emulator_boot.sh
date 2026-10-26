# Emulator selbst starten und beenden (WP124), zum Einbinden mit `source`.
#
# emu_boot_ensure  setzt DEVICE (und ANDROID_SERIAL) auf einen laufenden Emulator und
#   startet das AVD, falls keiner läuft. Vor `android_device.sh` aufrufen.
#   - DEVICE/ANDROID_SERIAL = emulator-NNNN: genau dieser (Port NNNN); läuft er nicht, wird er gestartet.
#   - DEVICE/ANDROID_SERIAL = anderes Gerät: nichts passiert (echte Geräte werden nie angefasst).
#   - ohne DEVICE: genau ein laufender Emulator wird genommen (ein echtes Gerät
#     daneben stört nicht); keiner -> Start auf emulator-5554; mehrere -> DEVICE bleibt
#     leer (android_device.sh bricht mit klarer Meldung ab).
#   Start im Hintergrund (nohup), Log ${TMPDIR}/wendelin-emulator-<serial>.log, Wartezeit
#   bis sys.boot_completed EMU_BOOT_TIMEOUT Sekunden (Standard 240), sonst Abbruch (Exit 1)
#   und der gestartete Emulator wird wieder beendet.
#   Start-Mutex `<serial>.start` im Sperr-Verzeichnis: ein zweiter gleichzeitiger Start bricht sofort ab.
# emu_boot_stop    beendet den Emulator DEVICE (`adb emu kill`, wartet bis er weg ist), außer bei
#   E2E_KEEP_EMULATOR=1. Echte Geräte: nie. Idempotent; gehört in cleanup VOR emu_lock_release.
#
# Überschreibbar (Selbsttest): ADB, EMULATOR, EMU_AVD, EMU_BOOT_TIMEOUT, EMU_KILL_TIMEOUT,
# EMU_POLL (Sekunden zwischen Abfragen), WENDELIN_LOCK_DIR.

_emu_sdk() { echo "${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"; }
_emu_adb() { "${ADB:-$(_emu_sdk)/platform-tools/adb}" "$@"; }
_emu_poll() { sleep "${EMU_POLL:-2}"; }

_EMU_STARTED_PID=""
_EMU_MUTEX_DIR=""

# Zustand des Serials aus `adb devices` oder leer.
_emu_state() {
  _emu_adb devices 2>/dev/null | awk -v s="$1" 'NR>1 && $1==s {print $2}'
}

_emu_booted() {
  [ "$(_emu_adb -s "$1" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]
}

_emu_kill() { # <serial>: beenden und warten, bis er aus `adb devices` verschwunden ist
  local serial="$1" i n
  _emu_adb -s "$serial" emu kill >/dev/null 2>&1 || true
  n=$(( ${EMU_KILL_TIMEOUT:-30} ))
  for ((i = 0; i < n; i++)); do
    [ -z "$(_emu_state "$serial")" ] && return 0
    _emu_poll
  done
  echo "Warnung: Emulator $serial ist nach ${n} Abfragen noch da." >&2
  return 1
}

emu_boot_stop() {
  case "${DEVICE:-}" in emulator-*) ;; *) return 0 ;; esac
  if [ "${E2E_KEEP_EMULATOR:-}" = "1" ]; then
    echo "E2E_KEEP_EMULATOR=1: Emulator $DEVICE läuft weiter."
    return 0
  fi
  [ -n "$(_emu_state "$DEVICE")" ] || return 0
  echo "Beende Emulator $DEVICE"
  _emu_kill "$DEVICE" || true
}

# Start-Mutex (mkdir, Besitzer-PID); verwaister Mutex (PID tot) wird übernommen.
_emu_start_mutex() { # <serial>
  local base dir opid=""
  base="${WENDELIN_LOCK_DIR:-${TMPDIR:-/tmp}/wendelin-emulator-locks}"
  mkdir -p "$base" || return 0
  dir="$base/$1.start"
  if ! mkdir "$dir" 2>/dev/null; then
    opid="$(cat "$dir/pid" 2>/dev/null || true)"
    if [ -n "$opid" ] && ! kill -0 "$opid" 2>/dev/null; then
      rm -rf "$dir"
    fi
    if ! mkdir "$dir" 2>/dev/null; then
      echo "Emulator $1 wird gerade von einem anderen Lauf gestartet (PID ${opid:-?}). Nicht warten: Gerätetest als offen melden." >&2
      return 1
    fi
  fi
  echo "$$" >"$dir/pid"
  _EMU_MUTEX_DIR="$dir"
}

_emu_start_mutex_release() {
  if [ -n "$_EMU_MUTEX_DIR" ]; then rm -rf "$_EMU_MUTEX_DIR"; fi
  _EMU_MUTEX_DIR=""
}

_emu_start() { # <serial>
  local serial="$1" port="${1#emulator-}" emu log tmo t0
  emu="${EMULATOR:-$(_emu_sdk)/emulator/emulator}"
  log="${TMPDIR:-/tmp}/wendelin-emulator-$serial.log"
  # Läuft er schon und ist fertig: nichts zu tun.
  if [ "$(_emu_state "$serial")" = "device" ] && _emu_booted "$serial"; then return 0; fi
  _emu_start_mutex "$serial" || return 1
  if [ -z "$(_emu_state "$serial")" ]; then
    if [ ! -x "$emu" ]; then
      echo "Emulator-Programm nicht gefunden: $emu" >&2
      _emu_start_mutex_release
      return 1
    fi
    echo "Starte Emulator ${EMU_AVD:-Wendelin_AOSP_35} auf $serial (Log $log)"
    # EMU_AUDIO: Audio-Option des Emulators statt -no-audio (z. B. -allow-host-audio für das Host-Mikrofon, WP149).
    # shellcheck disable=SC2086 # absichtlich ohne Anführungszeichen: kann mehrere Optionen enthalten
    nohup "$emu" -avd "${EMU_AVD:-Wendelin_AOSP_35}" -port "$port" -no-window ${EMU_AUDIO:--no-audio} \
      -no-boot-anim -no-snapshot-save -gpu swiftshader_indirect >"$log" 2>&1 </dev/null &
    _EMU_STARTED_PID=$!
    disown "$_EMU_STARTED_PID" 2>/dev/null || true
  fi
  tmo=$(( ${EMU_BOOT_TIMEOUT:-240} ))
  t0=$SECONDS
  while ! { [ "$(_emu_state "$serial")" = "device" ] && _emu_booted "$serial"; }; do
    if [ -n "$_EMU_STARTED_PID" ] && ! kill -0 "$_EMU_STARTED_PID" 2>/dev/null; then
      echo "Emulator $serial hat sich vorzeitig beendet. Log: $log" >&2
      _emu_start_mutex_release
      return 1
    fi
    if [ $((SECONDS - t0)) -ge "$tmo" ]; then
      echo "Emulator $serial ist nach ${tmo}s nicht hochgefahren (EMU_BOOT_TIMEOUT). Log: $log" >&2
      _emu_kill "$serial" || true
      _emu_start_mutex_release
      return 1
    fi
    _emu_poll
  done
  _emu_start_mutex_release
  echo "Emulator $serial ist hochgefahren."
}

emu_boot_ensure() {
  local want="${DEVICE:-${ANDROID_SERIAL:-}}" emus n
  if [ -z "$want" ]; then
    emus="$(_emu_adb devices 2>/dev/null | awk 'NR>1 && $1 ~ /^emulator-/ {print $1}')"
    n="$(printf '%s' "$emus" | grep -c . || true)"
    if [ "$n" = 0 ]; then
      want="emulator-5554"
    elif [ "$n" = 1 ]; then
      want="$emus"
    else
      return 0 # mehrere Emulatoren: pick_device meldet es
    fi
  fi
  case "$want" in
    emulator-[0-9]*) ;;
    *) return 0 ;; # echtes Gerät: nie starten
  esac
  _emu_start "$want" || return 1
  export DEVICE="$want" ANDROID_SERIAL="$want"
}
