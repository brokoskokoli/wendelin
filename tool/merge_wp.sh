#!/bin/bash
# Mergt einen Arbeitspaket-Branch in main (im main-Checkout ausführen).
#   tool/merge_wp.sh <branch> [--squash [-m msg]] [--dry-run] [--keep]
# Prüft CI-Lauf, Identität und Nachricht, mergt, startet das --changed-Gate, notiert den Tree des Ergebnisses
# (<git-common-dir>/wendelin-merge-ok, Freigabe für den pre-push-Hook) und räumt über tool/cleanup_wt.sh auf.
# Kein Push. Umgebung (für Tests): MERGE_WP_GATE (Gate-Befehl), MERGE_WP_NAME/MERGE_WP_EMAIL (erlaubte Identität),
# MERGE_WP_BASE (Basisbranch, Standard main), MERGE_WP_CI (Befehl für die CI-Läufe, siehe unten),
# MERGE_WP_CLEANUP (Aufräum-Befehl, Standard tool/cleanup_wt.sh).
#
# CI-Beleg: Der neueste Lauf des Workflows gate mit headSha == Branch-SHA und headBranch == Branch muss
# completed/success sein (cancelled, in_progress, fehlend, anderer Branch → Abbruch). MERGE_WP_CI ist ein
# Befehl (Umgebung: BRANCH, SHA), der je Lauf eine Zeile `<createdAt>\t<headSha>\t<headBranch>\t<status>\t<conclusion>`
# ausgibt (optional als 6. Spalte die Lauf-ID); Standard ist `gh run list --workflow gate`.
# Verkürzte Läufe (WP110): Ein Lauf, der nur Doku prüft (Job docs-only), genügt nur für einen Branch, dessen Diff gegen
# main ausschließlich Doku ist (tool/ci_scope.sh --classify). Sobald der Diff Code enthält, muss der Lauf ein voller sein.
# MERGE_WP_CI_MODE ist ein Befehl (Umgebung: RUN, BRANCH, SHA), der "docs" oder "full" ausgibt; Standard: gh run view.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
NAME=${MERGE_WP_NAME:-brokoskokoli}
EMAIL=${MERGE_WP_EMAIL:-16724498+brokoskokoli@users.noreply.github.com}
BASE=${MERGE_WP_BASE:-main}
GATE=${MERGE_WP_GATE:-dart run tool/gate.dart --changed}
CI_CMD=${MERGE_WP_CI:-}
if [ -z "$CI_CMD" ]; then
  CI_CMD='gh run list --workflow gate --branch "$BRANCH" --limit 50 --json createdAt,headSha,headBranch,status,conclusion,databaseId --jq ".[] | [.createdAt,.headSha,.headBranch,.status,.conclusion,(.databaseId|tostring)] | @tsv"'
fi
MODE_CMD=${MERGE_WP_CI_MODE:-}
if [ -z "$MODE_CMD" ]; then
  MODE_CMD='gh run view "$RUN" --json jobs --jq "[.jobs[] | select(.name==\"docs-only\" and .conclusion==\"success\")] | if length>0 then \"docs\" else \"full\" end"'
fi
CLEANUP=${MERGE_WP_CLEANUP:-tool/cleanup_wt.sh}
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

# CI-Entscheidung aus den Laufzeilen auf stdin: 0 nur, wenn der neueste Lauf auf (sha, branch) completed/success ist.
ci_green() {
  local want_sha=$1 want_branch=$2 line
  line=$(awk -F'\t' -v s="$want_sha" -v b="$want_branch" '$2==s && $3==b' | sort -r | head -n 1)
  [ -n "$line" ] || { echo "kein CI-Lauf (Workflow gate) für $want_branch auf $want_sha" >&2; return 1; }
  [ "$(printf '%s' "$line" | cut -f4)/$(printf '%s' "$line" | cut -f5)" = completed/success ] \
    || { echo "neuester CI-Lauf für $want_sha ist nicht grün: $(printf '%s' "$line" | cut -f4-5 | tr '\t' '/')" >&2; return 1; }
  printf '%s\n' "$(printf '%s' "$line" | cut -f6)"   # Lauf-ID (leer, wenn die Zeile keine hat)
}

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

# 0. CI-Beleg auf genau dem Branch-SHA.
sha=$(git rev-parse "refs/heads/$branch")
ci_out=$(BRANCH=$branch SHA=$sha sh -c "$CI_CMD") || die "CI-Abfrage fehlgeschlagen ($CI_CMD)"
ci_run=$(printf '%s\n' "$ci_out" | ci_green "$sha" "$branch") || die "Merge ohne grünen CI-Lauf abgelehnt (Branch pushen, tool/ci_wait.sh $branch)"
# Enthält der Diff gegen main Code, muss der grüne Lauf ein voller sein (kein verkürzter Doku-Lauf).
if [ "$(git diff --name-only "$(git merge-base "$BASE" "$branch")" "$branch" | sh "$HERE/ci_scope.sh" --classify)" != docs ]; then
  ci_mode=$(RUN=$ci_run BRANCH=$branch SHA=$sha sh -c "$MODE_CMD") || die "CI-Modus nicht ermittelbar ($MODE_CMD)"
  [ "$ci_mode" = full ] || die "CI-Lauf auf ${sha:0:8} war verkürzt ($ci_mode), der Branch enthält aber Code: voller Lauf nötig (Branch neu pushen oder gh run rerun, tool/ci_wait.sh $branch)"
fi

wt=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{p=$2} $1=="branch" && $2==b{print p}')
if [ $dry -eq 1 ]; then
  echo "merge_wp (dry-run): Prüfungen ok (CI grün auf ${sha:0:8}); würde $branch ($(git rev-list --count "$range") Commits) $([ $squash -eq 1 ] && echo squash-)mergen,"
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
  out=$(dart run tool/check_registry.dart --fix 2>&1) \
    || { reset_back; die "check_registry --fix fehlgeschlagen; zurückgesetzt: $out"; }
  git add -- app/lib/di/integrations/registry.dart packages/wendelin_integrations/lib/wendelin_integrations.dart 2>/dev/null
fi

# 2c. Erzeugte Doku (auch nach glattem Merge neu ableiten).
if [ -f tool/gen_docs.dart ]; then
  out=$(dart run tool/gen_docs.dart 2>&1) \
    || { reset_back; die "gen_docs fehlgeschlagen; zurückgesetzt: $out"; }
  git add -- docs/architecture/generated docs/testing/m5/README.md 2>/dev/null
fi

# 3. Commit mit Nachricht (ohne Session-Zeile).
if [ $squash -eq 1 ]; then
  # Trägt die Nachricht den Trailer schon, wird er nicht verdoppelt.
  if printf '%s\n' "$msg" | grep -qxF "$TRAILER"; then
    full="$msg"
  else
    full="$msg

$TRAILER"
  fi
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

# 5. Freigabe für den pre-push-Hook (Tree des Ergebnisses) und Squash-Vermerk für cleanup_wt.sh.
common=$(git rev-parse --path-format=absolute --git-common-dir)
tree=$(git rev-parse 'HEAD^{tree}')
echo "$tree $(git rev-parse HEAD)" >> "$common/wendelin-merge-ok"
echo "$sha $(git rev-parse HEAD) $tree" >> "$common/wendelin-merged-branches"

# 6. Aufräumen (nur lokal; den Remote-Branch räumt ein späterer Aufruf nach dem Push von main).
if [ $keep -eq 0 ]; then
  sh -c "$CLEANUP \"\$0\" --apply --no-remote" "$branch" \
    || echo "merge_wp: Aufräumen abgebrochen (siehe oben); der Merge ist erledigt. Nach Klärung: tool/cleanup_wt.sh $branch --apply. Push separat." >&2
  echo "merge_wp: Merge fertig. Push separat (WENDELIN_PUSH_MAIN=1), danach tool/cleanup_wt.sh $branch --apply für den Remote-Branch."
fi
