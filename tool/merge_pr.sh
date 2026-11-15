#!/bin/bash
# Mergt einen grünen Pull Request lokal nach main (im Checkout auf main ausführen). Kein Push.
#   tool/merge_pr.sh <pr-nummer> --model "<Modell>"     z. B. --model "Opus 5.5"
# Ablauf: fetch; PR lesen (offen, Basis main, Kopf-Branch, Kopf-SHA, Titel); origin/<kopf-branch> muss der Kopf-SHA
# sein; CI-Beleg (neuester Lauf des Workflows gate auf dem Kopf-SHA completed/success, bei Code im Diff ein voller Lauf);
# Identität der PR-Commits (tool/check_commit_identity.sh); main auf origin/main (nur ohne lokale Commits);
# git merge --no-ff mit der Nachricht „Merge #<pr>: <titel>“ und genau einem Trailer
# „Co-Authored-By: Claude <Modell> <noreply@anthropic.com>“; Freigabe „<tree> <commit>“ nach
# <git-common-dir>/wendelin-merge-ok (wertet tool/hooks/pre-push.sh aus). Danach: WENDELIN_PUSH_MAIN=1 git push origin main
#
# Umgebung (für Tests):
#   MERGE_PR_VIEW     Befehl (Umgebung: PR), der eine Zeile `<state>\t<base>\t<head-branch>\t<head-sha>\t<titel>` ausgibt;
#                     Standard: gh pr view.
#   MERGE_PR_CI       Befehl (Umgebung: BRANCH, SHA), der je Lauf eine Zeile
#                     `<createdAt>\t<headSha>\t<headBranch>\t<status>\t<conclusion>[\t<lauf-id>]` ausgibt; Standard: gh run list.
#   MERGE_PR_CI_MODE  Befehl (Umgebung: RUN, BRANCH, SHA), der "docs" (nur Job docs-only) oder "full" ausgibt; Standard: gh run view.
#   MERGE_PR_NAME, MERGE_PR_EMAIL  erwartete Identität des Merge-Commits (Standard aus tool/check_commit_identity.sh).
#   MERGE_PR_REMOTE   Remote (Standard origin).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
IDENT="$HERE/check_commit_identity.sh"
REMOTE=${MERGE_PR_REMOTE:-origin}
BASE=main
OK_NAME=wendelin-merge-ok

die() { echo "merge_pr: $*" >&2; exit 1; }

# Identität und Trailer-Muster nicht duplizieren: aus tool/check_commit_identity.sh lesen.
TRAILER_RE=$(sed -n "s/^TRAILER_RE='\(.*\)'\$/\1/p" "$IDENT")
DEF_NAME=$(sed -n "s/^NAME='\(.*\)'\$/\1/p" "$IDENT")
DEF_EMAIL=$(sed -n "s/^EMAIL='\(.*\)'\$/\1/p" "$IDENT")
[ -n "$TRAILER_RE" ] && [ -n "$DEF_NAME" ] && [ -n "$DEF_EMAIL" ] \
  || die "Identität/Trailer-Muster in $IDENT nicht gefunden"
NAME=${MERGE_PR_NAME:-$DEF_NAME}
EMAIL=${MERGE_PR_EMAIL:-$DEF_EMAIL}

VIEW_CMD=${MERGE_PR_VIEW:-}
if [ -z "$VIEW_CMD" ]; then
  VIEW_CMD='gh pr view "$PR" --json state,baseRefName,headRefName,headRefOid,title --jq "[.state,.baseRefName,.headRefName,.headRefOid,.title] | @tsv"'
fi
CI_CMD=${MERGE_PR_CI:-}
if [ -z "$CI_CMD" ]; then
  CI_CMD='gh run list --workflow gate --commit "$SHA" --limit 50 --json createdAt,headSha,headBranch,status,conclusion,databaseId --jq ".[] | [.createdAt,.headSha,.headBranch,.status,.conclusion,(.databaseId|tostring)] | @tsv"'
fi
MODE_CMD=${MERGE_PR_CI_MODE:-}
if [ -z "$MODE_CMD" ]; then
  MODE_CMD='gh run view "$RUN" --json jobs --jq "[.jobs[] | select(.name==\"docs-only\" and .conclusion==\"success\")] | if length>0 then \"docs\" else \"full\" end"'
fi

usage='Aufruf: tool/merge_pr.sh <pr-nummer> --model "<Modell>"'
pr=""; model=""; have_model=0
while [ $# -gt 0 ]; do
  case "$1" in
    --model) [ $# -ge 2 ] || die "--model ohne Wert. $usage"; model=$2; have_model=1; shift ;;
    --model=*) model=${1#--model=}; have_model=1 ;;
    -*) die "unbekannte Option $1. $usage" ;;
    *) [ -z "$pr" ] || die "mehrere PR-Nummern angegeben"; pr=$1 ;;
  esac
  shift
done
[ -n "$pr" ] || die "$usage"
case "$pr" in *[!0-9]* | 0*) die "PR-Nummer '$pr' ist keine Zahl. $usage" ;; esac
[ $have_model -eq 1 ] && [ -n "$model" ] || die "--model fehlt (Modell, auf dem der mergende Agent läuft). $usage"
trailer="Co-Authored-By: Claude $model <noreply@anthropic.com>"
printf '%s\n' "$trailer" | grep -qxE "$TRAILER_RE" \
  || die "--model '$model' ergibt keinen gültigen Trailer ($trailer), Muster in tool/check_commit_identity.sh"

root=$(git rev-parse --show-toplevel) || die "kein Git-Repo"
cd "$root" || exit 1
[ "$(git symbolic-ref --short HEAD 2>/dev/null)" = "$BASE" ] || die "Checkout steht nicht auf $BASE"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "Arbeitsverzeichnis nicht sauber"
ident=$(git var GIT_COMMITTER_IDENT | sed 's/ [0-9]* [-+][0-9]*$//')
aident=$(git var GIT_AUTHOR_IDENT | sed 's/ [0-9]* [-+][0-9]*$//')
[ "$ident" = "$NAME <$EMAIL>" ] && [ "$aident" = "$NAME <$EMAIL>" ] \
  || die "lokale Git-Identität ist nicht die erlaubte ($NAME <$EMAIL>)"

git fetch -q "$REMOTE" || die "git fetch $REMOTE fehlgeschlagen"

# 1. PR-Daten.
view=$(PR=$pr sh -c "$VIEW_CMD") || die "PR #$pr nicht lesbar ($VIEW_CMD)"
view=$(printf '%s\n' "$view" | head -n 1)
state=$(printf '%s' "$view" | cut -f1)
base=$(printf '%s' "$view" | cut -f2)
head_branch=$(printf '%s' "$view" | cut -f3)
sha=$(printf '%s' "$view" | cut -f4)
title=$(printf '%s' "$view" | cut -f5-)
[ "$state" = OPEN ] || die "PR #$pr ist nicht offen ($state)"
[ "$base" = "$BASE" ] || die "PR #$pr hat die Basis '$base', nicht $BASE"
[ -n "$head_branch" ] || die "PR #$pr: Kopf-Branch fehlt"
printf '%s' "$sha" | grep -qxE '[0-9a-f]{40}' || die "PR #$pr: Kopf-SHA '$sha' ungültig"
[ -n "$title" ] || die "PR #$pr: Titel fehlt"
local_head=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$head_branch") \
  || die "$REMOTE/$head_branch lokal nicht vorhanden"
[ "$local_head" = "$sha" ] \
  || die "$REMOTE/$head_branch steht auf ${local_head:0:8}, der PR-Kopf ist ${sha:0:8}; abgelehnt"
upstream=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BASE") || die "$REMOTE/$BASE lokal nicht vorhanden"
[ -n "$(git rev-list "$upstream..$sha")" ] || die "PR #$pr bringt keine neuen Commits gegenüber $REMOTE/$BASE"

# 2. CI-Beleg: der neueste gate-Lauf auf genau dem Kopf-SHA ist completed/success.
ci_out=$(BRANCH=$head_branch SHA=$sha sh -c "$CI_CMD") || die "CI-Abfrage fehlgeschlagen ($CI_CMD)"
line=$(printf '%s\n' "$ci_out" | awk -F'\t' -v s="$sha" '$2==s' | sort -r | head -n 1)
[ -n "$line" ] || die "kein CI-Lauf (Workflow gate) auf ${sha:0:8}; Merge abgelehnt"
ci_state="$(printf '%s' "$line" | cut -f4)/$(printf '%s' "$line" | cut -f5)"
[ "$ci_state" = completed/success ] || die "neuester CI-Lauf auf ${sha:0:8} ist nicht grün ($ci_state); Merge abgelehnt"
ci_run=$(printf '%s' "$line" | cut -f6)
# Enthält der Diff gegen main Code, muss der grüne Lauf ein voller sein (nicht nur der Job docs-only).
scope=$(git diff --name-only "$(git merge-base "$upstream" "$sha")" "$sha" | bash "$HERE/ci_scope.sh" --classify)
if [ "$scope" != docs ]; then
  ci_mode=$(RUN=$ci_run BRANCH=$head_branch SHA=$sha sh -c "$MODE_CMD") || die "CI-Modus nicht ermittelbar ($MODE_CMD)"
  [ "$ci_mode" = full ] \
    || die "CI-Lauf auf ${sha:0:8} war verkürzt ($ci_mode), der PR enthält aber Code: voller Lauf nötig"
fi

# 3. Identität der PR-Commits.
bash "$IDENT" "$upstream..$sha" >&2 || die "Commit-Identität im PR #$pr nicht erlaubt"

# 4. main auf origin/main (ohne lokale Commits zu verlieren), dann Merge.
orig=$(git rev-parse HEAD)
git merge-base --is-ancestor "$orig" "$upstream" \
  || die "lokales $BASE hat Commits, die nicht in $REMOTE/$BASE liegen; abgelehnt"
git reset -q --hard "$upstream" || die "Zurücksetzen auf $REMOTE/$BASE fehlgeschlagen"
back() { git merge --abort 2>/dev/null; git reset -q --hard "$orig"; }
if ! git merge -q --no-ff --no-commit "$sha" >/dev/null 2>&1; then
  conflicts=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
  back
  die "Merge von PR #$pr mit Konflikt ($conflicts); zurückgesetzt. Erst $BASE in den PR-Branch mergen."
fi
msg="Merge #$pr: $title

$trailer"
git commit -q -m "$msg" || { back; die "Commit fehlgeschlagen; zurückgesetzt"; }
bash "$IDENT" 'HEAD^!' >&2 || { back; die "Merge-Commit verletzt die Identitätsregeln; zurückgesetzt"; }

# 5. Freigabe für den pre-push-Hook.
common=$(git rev-parse --path-format=absolute --git-common-dir)
echo "$(git rev-parse 'HEAD^{tree}') $(git rev-parse HEAD)" >> "$common/$OK_NAME"
echo "merge_pr: $(git rev-parse --short HEAD) auf $BASE (Merge #$pr, CI grün auf ${sha:0:8}). Nicht gepusht."
echo "  Push: WENDELIN_PUSH_MAIN=1 git push $REMOTE $BASE"
