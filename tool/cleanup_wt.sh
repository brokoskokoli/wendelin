#!/bin/bash
# Räumt ein gemergtes Arbeitspaket auf (WP109). Standard ist ein Probelauf.
#   tool/cleanup_wt.sh <wp|branch> [--apply] [--no-remote]
# <wp> ist `wp109` (Branch `wp/109-*`, nie `wp/10-*`), <branch> z. B. `wp/109-guardrails`
# (ein Branch ohne `/` gilt unter seinem Namen als <wp>).
# Entfernt, falls vorhanden: Worktree ../james-wt/<wp>, Prüf-Worktree
# ../james-wt/rev-<wp>, den lokalen Branch, ../james-wt/handoff/<wp>.md und
# handoff/<wp>-*; den Remote-Branch (origin) nur, wenn er in origin/main
# enthalten ist (nach dem Push von main erneut aufrufen; --no-remote lässt ihn aus).
# Gemergt heißt: Tip ist Vorfahr von main (origin/main bei Remote), oder
# merge_wp.sh hat ihn als Squash vermerkt (<git-common-dir>/wendelin-merged-branches,
# „<tip> <merge-commit>“), oder die Patch-ID des Gesamtdiffs steht unter den
# Commits seit der Merge-Basis auf main. Nie Ungemergtes, nie schmutzige
# Worktrees (kein --force), nie andere Branches. Umgebung (Tests):
# CLEANUP_WT_BASE (main), CLEANUP_WT_REMOTE (origin), CLEANUP_WT_DIR
# (Standard: <Hauptcheckout>/../james-wt).
set -u
BASE=${CLEANUP_WT_BASE:-main}
REMOTE=${CLEANUP_WT_REMOTE:-origin}

die() { echo "cleanup_wt: $*" >&2; exit 1; }

arg=""; apply=0; remote=1
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --dry-run) apply=0 ;;
    --no-remote) remote=0 ;;
    -*) die "unbekannte Option $1" ;;
    *) [ -z "$arg" ] || die "mehrere Ziele angegeben"; arg=$1 ;;
  esac
  shift
done
[ -n "$arg" ] || die "Aufruf: tool/cleanup_wt.sh <wp|branch> [--apply] [--no-remote]"

git rev-parse --git-dir >/dev/null 2>&1 || die "kein Git-Repo"
common=$(git rev-parse --path-format=absolute --git-common-dir)
main_wt=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
wtdir=${CLEANUP_WT_DIR:-$(cd "$main_wt/.." && pwd)/james-wt}
here=$(git rev-parse --show-toplevel)
merged_list="$common/wendelin-merged-branches"

# Ziel auflösen: wp-Nummer und Branch (lokal und/oder remote).
case "$arg" in
  wp/[0-9]*-*) num=${arg#wp/}; num=${num%%-*}; pattern="$arg"; wp="wp$num" ;;
  wp[0-9]*) num=${arg#wp}; pattern="wp/$num-*"; wp="wp$num" ;;
  */*) die "'$arg' ist weder wp<nr> noch wp/<nr>-<slug> noch ein Branch ohne '/'" ;;
  *) num=""; pattern="$arg"; wp="$arg" ;;  # Branch ohne wp-Schema (Tests): Pfade nach dem Namen
esac
case "$wp" in *[!0-9A-Za-z._-]*|"") die "ungültiger Name '$wp'" ;; esac

locals=$(git for-each-ref --format='%(refname:short)' "refs/heads/$pattern")
remotes=""
git rev-parse --verify -q "refs/remotes/$REMOTE/$BASE" >/dev/null \
  && remotes=$(git for-each-ref --format='%(refname:short)' "refs/remotes/$REMOTE/$pattern" | sed "s|^$REMOTE/||")
branches=$(printf '%s\n%s\n' "$locals" "$remotes" | grep -v '^$' | sort -u)
nb=$(printf '%s' "$branches" | grep -c .)
[ "$nb" -le 1 ] || die "mehrdeutig, mehrere Branches zu $arg: $(echo "$branches" | tr '\n' ' ')"
branch=$branches
[ -n "$branch" ] || { echo "cleanup_wt: kein Branch zu $arg gefunden, nichts zu tun (ohne Branch ist nicht prüfbar, ob gemergt)."; exit 0; }

# gemergt? <tip> <base-ref> → 0/1
is_merged() {
  local tip=$1 base=$2 mb pid rec c tr x
  git merge-base --is-ancestor "$tip" "$base" 2>/dev/null && return 0
  mb=$(git merge-base "$base" "$tip" 2>/dev/null) || return 1
  if [ -f "$merged_list" ]; then
    while read -r rec c tr; do
      [ "$rec" = "$tip" ] || continue
      # Der vermerkte Merge-Commit steht in der Basis ...
      git merge-base --is-ancestor "$c" "$base" 2>/dev/null && return 0
      # ... oder ein Commit der Basis trägt seinen Tree (Amend nach gen_docs/Nachricht).
      [ -n "$tr" ] || continue
      for x in $(git rev-list "$mb..$base"); do
        [ "$(git rev-parse "$x^{tree}")" = "$tr" ] && return 0
      done
    done < "$merged_list"
  fi
  pid=$(git diff "$mb" "$tip" | git patch-id --stable | cut -d' ' -f1)
  [ -n "$pid" ] || return 1
  for c in $(git rev-list --no-merges "$mb..$base"); do
    [ "$(git diff-tree -p "$c" | git patch-id --stable | cut -d' ' -f1)" = "$pid" ] && return 0
  done
  return 1
}

actions=(); problems=()
local_tip=""; remote_tip=""
[ -n "$locals" ] && local_tip=$(git rev-parse "refs/heads/$branch")
[ -n "$remotes" ] && remote_tip=$(git rev-parse "refs/remotes/$REMOTE/$branch")

# Lokal gemergt (Voraussetzung für Worktrees, lokalen Branch und Handoff).
local_ok=0; okbase=$BASE; okref=""
if [ -n "$local_tip" ]; then
  is_merged "$local_tip" "$BASE" && { local_ok=1; okref=$local_tip; } || problems+=("Branch $branch ist nicht in $BASE gemergt: nichts wird gelöscht")
elif [ -n "$remote_tip" ]; then
  # Nur noch remote vorhanden (lokal schon aufgeräumt): Beleg über origin/main.
  okbase="$REMOTE/$BASE"
  is_merged "$remote_tip" "$REMOTE/$BASE" && { local_ok=1; okref=$remote_tip; } || problems+=("Branch $REMOTE/$branch ist nicht in $REMOTE/$BASE enthalten: nichts wird gelöscht")
fi

wt_of_branch() { git worktree list --porcelain | awk -v b="refs/heads/$1" '/^worktree /{p=$2} $1=="branch" && $2==b{print p}'; }
registered() { git worktree list --porcelain | awk -v d="$1" '/^worktree /{ if ($2==d) f=1 } END{exit !f}'; }

if [ $local_ok -eq 1 ]; then
  for wtname in "$wp" "rev-$wp"; do
    d="$wtdir/$wtname"
    [ -e "$d" ] || continue
    if ! registered "$d"; then problems+=("$d ist kein registrierter Worktree dieses Repos: bleibt"); continue; fi
    wb=$(git -C "$d" symbolic-ref -q --short HEAD || true)
    if [ -n "$wb" ] && [ "$wb" != "$branch" ]; then problems+=("$d hat Branch $wb (nicht $branch): bleibt"); continue; fi
    if [ "$wtname" = "$wp" ] && [ -z "$wb" ]; then problems+=("$d ohne Branch ($branch erwartet): bleibt"); continue; fi
    if [ -z "$wb" ]; then
      # Detached (Prüf-Worktree): HEAD muss in gemergtem Stand stehen.
      wh=$(git -C "$d" rev-parse HEAD 2>/dev/null) || { problems+=("$d: HEAD nicht lesbar: bleibt"); continue; }
      if ! { is_merged "$wh" "$okbase" || { [ -n "${okref:-}" ] && git merge-base --is-ancestor "$wh" "$okref" 2>/dev/null; }; }; then
        problems+=("$d steht auf $(git rev-parse --short "$wh"), nicht in $okbase gemergt: bleibt"); continue
      fi
    fi
    if [ "$(cd "$d" && pwd -P)" = "$(cd "$here" && pwd -P)" ]; then problems+=("$d ist der aktuelle Worktree: bleibt"); continue; fi
    [ -z "$(git -C "$d" status --porcelain 2>/dev/null)" ] || { problems+=("$d ist nicht sauber (uncommittete oder neue Dateien): bleibt"); continue; }
    actions+=("worktree|$d")
  done
  if [ -n "$local_tip" ]; then
    other=$(wt_of_branch "$branch")
    if [ -n "$other" ] && ! printf '%s\n' "${actions[@]:-}" | grep -qxF "worktree|$other"; then
      problems+=("Branch $branch ist in $other ausgecheckt: Branch bleibt")
    else
      actions+=("branch|$branch")
    fi
  fi
  for f in "$wtdir/handoff/$wp.md" "$wtdir"/handoff/"$wp"-*; do
    [ -e "$f" ] && actions+=("file|$f")
  done
fi

# Remote nur mit Beleg in origin/main.
if [ $remote -eq 1 ] && [ -n "$remote_tip" ]; then
  if is_merged "$remote_tip" "$REMOTE/$BASE"; then
    actions+=("remote|$branch")
  else
    echo "cleanup_wt: Remote-Branch $REMOTE/$branch bleibt (noch nicht in $REMOTE/$BASE enthalten)."
  fi
fi

# Alles oder nichts: bei jedem Befund wird nichts gelöscht.
if [ "${#problems[@]}" -gt 0 ]; then
  for p in "${problems[@]}"; do echo "cleanup_wt: $p" >&2; done
  echo "cleanup_wt: abgebrochen, nichts entfernt." >&2
  exit 1
fi

[ "${#actions[@]}" -gt 0 ] || echo "cleanup_wt: nichts zu entfernen."
rc=0
for a in "${actions[@]:-}"; do
  [ -n "$a" ] || continue
  kind=${a%%|*}; what=${a#*|}
  if [ $apply -eq 0 ]; then echo "cleanup_wt (Probelauf): würde entfernen: $kind $what"; continue; fi
  case "$kind" in
    worktree) git worktree remove "$what" && echo "cleanup_wt: Worktree $what entfernt" || { echo "cleanup_wt: Worktree $what nicht entfernbar" >&2; rc=1; } ;;
    branch) git branch -D "$what" >/dev/null && echo "cleanup_wt: Branch $what entfernt" || { echo "cleanup_wt: Branch $what nicht löschbar" >&2; rc=1; } ;;
    file) rm -f -- "$what" && echo "cleanup_wt: $what entfernt" ;;
    remote) git push "$REMOTE" --delete "$what" "--force-with-lease=refs/heads/$what:$remote_tip" >/dev/null 2>&1 && echo "cleanup_wt: $REMOTE/$what entfernt" || { echo "cleanup_wt: $REMOTE/$what nicht löschbar" >&2; rc=1; } ;;
  esac
done
[ $apply -eq 1 ] && git worktree prune
exit $rc
