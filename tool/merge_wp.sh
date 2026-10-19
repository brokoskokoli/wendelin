#!/bin/bash
# Mergt einen Arbeitspaket-Branch in main (im main-Checkout ausführen).
#   tool/merge_wp.sh <branch> [--squash [-m msg]] [--dry-run] [--keep]
# Prüft Identität und Nachricht, mergt, startet das --changed-Gate und räumt Worktree/Branch auf.
# Kein Push. Umgebung (für Tests): MERGE_WP_GATE (Gate-Befehl), MERGE_WP_NAME/MERGE_WP_EMAIL (erlaubte Identität),
# MERGE_WP_BASE (Basisbranch, Standard main).
set -u
NAME=${MERGE_WP_NAME:-brokoskokoli}
EMAIL=${MERGE_WP_EMAIL:-16724498+brokoskokoli@users.noreply.github.com}
BASE=${MERGE_WP_BASE:-main}
GATE=${MERGE_WP_GATE:-dart run tool/gate.dart --changed}
TRAILER='Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>'

die() { echo "merge_wp: $*" >&2; exit 1; }

branch=""; squash=0; msg=""; dry=0; keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --squash) squash=1 ;;
    -m) shift; msg=${1:-} ;;
    --dry-run) dry=1 ;;
    --keep) keep=1 ;;
    -*) die "unbekannte Option $1" ;;
    *) [ -z "$branch" ] || die "mehrere Branches angegeben"; branch=$1 ;;
  esac
  shift
done
[ -n "$branch" ] || die "Aufruf: tool/merge_wp.sh <branch> [--squash [-m msg]] [--dry-run] [--keep]"

root=$(git rev-parse --show-toplevel) || die "kein Git-Repo"
cd "$root" || exit 1
git rev-parse --verify -q "refs/heads/$branch" >/dev/null || die "Branch $branch nicht gefunden"
[ "$(git symbolic-ref --short HEAD 2>/dev/null)" = "$BASE" ] || die "Checkout steht nicht auf $BASE"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "Arbeitsverzeichnis nicht sauber"
orig=$(git rev-parse HEAD)
range="$BASE..$branch"
[ -n "$(git rev-list "$range")" ] || die "$branch enthält keine neuen Commits"

reset_back() { git merge --abort 2>/dev/null; git reset -q --hard "$orig"; }

# 1. Identität (bei --squash darf die Historie alt sein, das Ergebnis trägt die globale Identität).
if [ $squash -eq 0 ]; then
  bad=$(git log --format='%an <%ae>%n%cn <%ce>' "$range" | sort -u | grep -vx "$NAME <$EMAIL>")
  [ -z "$bad" ] || die "Identität nicht erlaubt in $range: $(echo "$bad" | tr '\n' ';') (Hinweis: --squash)"
  if git log --format=%B "$range" | grep -qiE '^Claude-Session:|claude\.ai/code/session'; then
    die "Claude-Session-Zeile in den Commit-Nachrichten von $range (Hinweis: --squash -m)"
  fi
fi
if [ -n "$msg" ] && printf '%s\n' "$msg" | grep -qiE '^Claude-Session:|claude\.ai/code/session'; then
  die "Claude-Session-Zeile in der Nachricht"
fi

wt=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{p=$2} $1=="branch" && $2==b{print p}')
if [ $dry -eq 1 ]; then
  echo "merge_wp (dry-run): Prüfungen ok; würde $branch ($(git rev-list --count "$range") Commits) $([ $squash -eq 1 ] && echo squash-)mergen,"
  echo "  Gate '$GATE' laufen lassen, danach ${wt:+Worktree $wt und }Branch löschen$([ $keep -eq 1 ] && echo ' (--keep: entfällt)')."
  exit 0
fi

# 2. Merge. Konflikte nur in linguist-generated-Dateien löst der Hook.
if [ $squash -eq 1 ]; then
  [ -n "$msg" ] || msg="$(git log -1 --format=%s "$branch")"
  git merge --squash "$branch" >/dev/null 2>&1; rc=$?
else
  git merge --no-ff --no-commit "$branch" >/dev/null 2>&1; rc=$?
fi
if [ $rc -ne 0 ]; then
  conflicts=$(git diff --name-only --diff-filter=U)
  [ -n "$conflicts" ] || { reset_back; die "Merge fehlgeschlagen ohne Konfliktdateien"; }
  for f in $conflicts; do
    git check-attr linguist-generated -- "$f" | grep -q ": set$" \
      || { reset_back; die "Konflikt in $f (nicht linguist-generated), manuell lösen; Merge zurückgesetzt"; }
  done
  # shellcheck disable=SC2086
  sh tool/regen_generated.sh $conflicts || { reset_back; die "regen_generated.sh fehlgeschlagen; Merge zurückgesetzt"; }
  # shellcheck disable=SC2086
  git add -- $conflicts
fi

# 2b. Listen-Dateien mit merge=union (Registry, Barrel): Sortierung/Doppelte reparieren.
if [ -f tool/check_registry.dart ]; then
  dart run tool/check_registry.dart --fix >/dev/null 2>&1
  git add -- app/lib/di/integrations/registry.dart packages/wendelin_integrations/lib/wendelin_integrations.dart 2>/dev/null
fi

# 2c. Erzeugte Doku (auch nach glattem Merge neu ableiten).
if [ -f tool/gen_docs.dart ]; then
  dart run tool/gen_docs.dart >/dev/null 2>&1
  git add -- docs/architecture/generated docs/testing/m5/README.md 2>/dev/null
fi

# 3. Commit mit Nachricht (ohne Session-Zeile).
if [ $squash -eq 1 ]; then
  full="$msg

$TRAILER"
else
  full="Merge branch '$branch'

$TRAILER"
fi
if printf '%s\n' "$full" | grep -qiE '^Claude-Session:|claude\.ai/code/session'; then
  reset_back; die "Claude-Session-Zeile in der Ergebnisnachricht; zurückgesetzt"
fi
git commit -q -m "$full" || { reset_back; die "Commit fehlgeschlagen; zurückgesetzt"; }
echo "merge_wp: $(git rev-parse --short HEAD) auf $BASE"

# 4. Gate.
if ! sh -c "$GATE"; then
  echo "merge_wp: Gate ROT. Merge-Commit liegt lokal auf $BASE (nicht gepusht)." >&2
  echo "  Rückgängig: git reset --hard $orig   |   Aufräumen unterblieben." >&2
  exit 1
fi

# 5. Aufräumen.
if [ $keep -eq 0 ]; then
  [ -z "$wt" ] || git worktree remove --force "$wt" || die "Worktree $wt nicht entfernbar"
  git branch -D "$branch" >/dev/null || die "Branch nicht löschbar"
  echo "merge_wp: ${wt:+Worktree $wt und }Branch $branch entfernt. Push separat."
fi
