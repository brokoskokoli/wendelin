# Sperre je Emulator-Serial (WP110), zum Einbinden mit `source`.
#
# emu_lock_acquire <serial>  belegt den Emulator oder bricht mit Exit 1 ab:
#   „Emulator <serial> belegt durch WPnn, PID n“. Kein Warten.
# emu_lock_release           gibt die eigene Sperre frei (idempotent; auch per trap).
#
# Die Sperre ist ein Verzeichnis `<WENDELIN_LOCK_DIR>/<serial>.lock` (Standard
# ${TMPDIR:-/tmp}/wendelin-emulator-locks, rechnerweit, außerhalb des Repos) mit der
# Datei `info` („<pid> <wp>“). Das Paket kommt aus WENDELIN_WP, sonst aus dem
# Branch wp/<nr>-… des Repos. Ist die PID des Besitzers tot (oder fehlt die info-Datei länger als eine Minute), wird die Sperre
# atomar übernommen (Übernahme-Verzeichnis `<serial>.lock.takeover` als Mutex; der Verlierer bricht ab).

_emu_lock_dir=""

emu_lock_wp() {
  if [ -n "${WENDELIN_WP:-}" ]; then echo "$WENDELIN_WP"; return; fi
  local b
  b="$(git -C "${ROOT:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$b" in
    wp/[0-9]*) echo "WP$(echo "$b" | sed -E 's#^wp/([0-9]+[a-z]?)-.*#\1#; s#^wp/([0-9]+[a-z]?)$#\1#')" ;;
    *) echo "unbekannt" ;;
  esac
}

# Belegt die Sperre atomar (mkdir) und trägt PID und WP ein.
_emu_lock_claim() {
  local lock="$1"
  mkdir "$lock" 2>/dev/null || return 1
  echo "$$ $(emu_lock_wp)" >"$lock/info"
  _emu_lock_dir="$lock"
  trap 'emu_lock_release' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# Wahr, wenn das Verzeichnis [1] älter als eine Minute ist.
_emu_lock_old() {
  [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]
}

emu_lock_acquire() {
  local serial="$1" base lock owner opid owp tk owner2 opid2
  base="${WENDELIN_LOCK_DIR:-${TMPDIR:-/tmp}/wendelin-emulator-locks}"
  mkdir -p "$base" || return 0 # fail-open wie die Gate-Sperre
  lock="$base/$serial.lock"
  _emu_lock_claim "$lock" && return 0
  owner="$(cat "$lock/info" 2>/dev/null || true)"
  opid="${owner%% *}"
  owp="${owner#* }"
  # Besitzer lebt: belegt. Ohne info-Datei gilt die Sperre eine Minute lang als belegt
  # (der Besitzer legt sie gerade an), danach als verwaist.
  if [ -n "$opid" ]; then
    if kill -0 "$opid" 2>/dev/null; then _emu_lock_busy "$serial" "$owp" "$opid"; return 1; fi
  elif ! _emu_lock_old "$lock"; then
    _emu_lock_busy "$serial" "$owp" "$opid"; return 1
  fi
  # Übernahme atomar: Wer das Übernahme-Verzeichnis anlegt, räumt und belegt neu;
  # wer es nicht bekommt, bricht als Verlierer ab (kein Löschen einer frischen Sperre).
  tk="$lock.takeover"
  if [ -d "$tk" ] && _emu_lock_old "$tk"; then rmdir "$tk" 2>/dev/null || true; fi
  if ! mkdir "$tk" 2>/dev/null; then
    _emu_lock_busy "$serial" "wird übernommen" ""; return 1
  fi
  owner2="$(cat "$lock/info" 2>/dev/null || true)"
  opid2="${owner2%% *}"
  if [ "$opid2" != "$opid" ] || { [ -n "$opid2" ] && kill -0 "$opid2" 2>/dev/null; }; then
    rmdir "$tk" 2>/dev/null || true
    _emu_lock_busy "$serial" "${owner2#* }" "$opid2"; return 1
  fi
  echo "Hinweis: verwaiste Emulator-Sperre (${owp:-unbekannt}, PID ${opid:-?}) übernommen." >&2
  rm -rf "$lock"
  if _emu_lock_claim "$lock"; then rmdir "$tk" 2>/dev/null || true; return 0; fi
  rmdir "$tk" 2>/dev/null || true
  _emu_lock_busy "$serial" "unbekannt" ""; return 1
}

_emu_lock_busy() {
  echo "Emulator $1 belegt durch ${2:-unbekannt}, PID ${3:-?}. Nicht warten: Gerätetest als offen melden (Zuteilung durch den Orchestrator)." >&2
}

emu_lock_release() {
  [ -n "$_emu_lock_dir" ] || return 0
  if [ "$(cut -d' ' -f1 "$_emu_lock_dir/info" 2>/dev/null)" = "$$" ]; then
    rm -rf "$_emu_lock_dir"
  fi
  _emu_lock_dir=""
}
