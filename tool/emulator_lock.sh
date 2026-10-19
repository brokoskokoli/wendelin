# Sperre je Emulator-Serial (WP110), zum Einbinden mit `source`.
#
# emu_lock_acquire <serial>  belegt den Emulator oder bricht mit Exit 1 ab:
#   „Emulator <serial> belegt durch WPnn, PID n“. Kein Warten.
# emu_lock_release           gibt die eigene Sperre frei (idempotent; auch per trap).
#
# Die Sperre ist ein Verzeichnis `<WENDELIN_LOCK_DIR>/<serial>.lock` (Standard
# ${TMPDIR:-/tmp}/wendelin-emulator-locks, rechnerweit, außerhalb des Repos) mit der
# Datei `info` („<pid> <wp>“). Das Paket kommt aus WENDELIN_WP, sonst aus dem
# Branch wp/<nr>-… des Repos. Ist die PID des Besitzers tot, wird die Sperre übernommen.

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

emu_lock_acquire() {
  local serial="$1" base lock owner opid owp
  base="${WENDELIN_LOCK_DIR:-${TMPDIR:-/tmp}/wendelin-emulator-locks}"
  mkdir -p "$base" || return 0 # fail-open wie die Gate-Sperre
  lock="$base/$serial.lock"
  local try
  for try in 1 2; do
    if mkdir "$lock" 2>/dev/null; then
      echo "$$ $(emu_lock_wp)" >"$lock/info"
      _emu_lock_dir="$lock"
      trap 'emu_lock_release' EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      return 0
    fi
    owner="$(cat "$lock/info" 2>/dev/null || true)"
    opid="${owner%% *}"
    owp="${owner#* }"
    # Besitzer lebt: belegt. Info fehlt noch (Besitzer legt sie gerade an): als belegt behandeln.
    if [ -z "$opid" ] || kill -0 "$opid" 2>/dev/null; then
      echo "Emulator $serial belegt durch ${owp:-unbekannt}, PID ${opid:-?}. Nicht warten: Gerätetest als offen melden (Zuteilung durch den Orchestrator)." >&2
      return 1
    fi
    echo "Hinweis: verwaiste Emulator-Sperre ($owp, PID $opid) übernommen." >&2
    rm -rf "$lock"
  done
  echo "Emulator $serial: Sperre nicht zu bekommen." >&2
  return 1
}

emu_lock_release() {
  [ -n "$_emu_lock_dir" ] || return 0
  if [ "$(cut -d' ' -f1 "$_emu_lock_dir/info" 2>/dev/null)" = "$$" ]; then
    rm -rf "$_emu_lock_dir"
  fi
  _emu_lock_dir=""
}
