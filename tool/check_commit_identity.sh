#!/bin/bash
# Prüft Autor, Committer und Trailer aller Commits eines Bereichs (WP109, CI-Job
# „commit-identity“ in .github/workflows/gate.yml):
#   tool/check_commit_identity.sh <rev-bereich>   z. B. origin/main..HEAD
#   tool/check_commit_identity.sh --ci             Bereich aus der CI-Umgebung:
#     REF (github.ref), BEFORE (github.event.before),
#     AFTER (github.sha), PR_HEAD (github.event.pull_request.head.sha).
#     main: BEFORE..AFTER (ohne brauchbares BEFORE: der letzte Commit);
#     sonst merge-base(origin/main, Kopf)..Kopf. Braucht fetch-depth 0.
# Erlaubt ist nur die noreply-Identität, genau eine Zeile Co-Authored-By (in der
# freigegebenen Schreibweise) und keine Claude-Session-Zeile. Ein leerer Bereich
# ist grün. Exit 1 mit einer Zeile je Verstoß.
set -u
EMAIL='16724498+brokoskokoli@users.noreply.github.com'
TRAILER='Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>'
if [ "${1:-}" = --ci ]; then
  zero=0000000000000000000000000000000000000000
  if [ "${REF:-}" = refs/heads/main ]; then
    if [ -n "${BEFORE:-}" ] && [ "$BEFORE" != "$zero" ] && git cat-file -e "$BEFORE^{commit}" 2>/dev/null; then
      set -- "$BEFORE..${AFTER:-HEAD}"
    else
      set -- "${AFTER:-HEAD}~1..${AFTER:-HEAD}"
    fi
  else
    head=${PR_HEAD:-${AFTER:-HEAD}}
    base=$(git merge-base origin/main "$head") || { echo "check_commit_identity: keine Merge-Basis mit origin/main (fetch-depth 0?)" >&2; exit 2; }
    set -- "$base..$head"
  fi
  echo "check_commit_identity: Bereich $1"
fi
[ $# -eq 1 ] || { echo "Aufruf: tool/check_commit_identity.sh <rev-bereich>" >&2; exit 2; }
revs=$(git rev-list "$1") || { echo "check_commit_identity: Bereich '$1' nicht auflösbar" >&2; exit 2; }
bad=0
n=0
fail() { echo "check_commit_identity: $(git rev-parse --short "$1"): $2" >&2; bad=$((bad + 1)); }
for c in $revs; do
  n=$((n + 1))
  while IFS='|' read -r role name mail; do
    if [ "$mail" != "$EMAIL" ] || [ "$name" != brokoskokoli ]; then
      fail "$c" "$role '$name <$mail>' ist nicht die noreply-Identität"
    fi
  done <<IDENT
Autor|$(git log -1 --format='%an|%ae' "$c")
Committer|$(git log -1 --format='%cn|%ce' "$c")
IDENT
  msg=$(git log -1 --format=%B "$c")
  count=$(printf '%s\n' "$msg" | grep -ciE '^Co-Authored-By:')
  [ "$count" -eq 1 ] || fail "$c" "$count Co-Authored-By-Trailer (genau einer erwartet)"
  if [ "$count" -ge 1 ] && printf '%s\n' "$msg" | grep -iE '^Co-Authored-By:' | grep -vqxF "$TRAILER"; then
    fail "$c" "Co-Authored-By nicht als '$TRAILER'"
  fi
  if printf '%s\n' "$msg" | grep -qiE '^Claude-Session:|claude\.ai/code/session'; then
    fail "$c" "Claude-Session-Zeile in der Nachricht"
  fi
done
[ $bad -eq 0 ] || { echo "check_commit_identity: ROT ($bad Verstöße in $n Commits)" >&2; exit 1; }
echo "check_commit_identity: ok ($n Commits)"
