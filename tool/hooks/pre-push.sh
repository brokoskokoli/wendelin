#!/bin/sh
# pre-push (WP109): main nur über den Orchestrator-Befehl.
# Push auf refs/heads/main nur mit WENDELIN_PUSH_MAIN=1, und jeder neue Commit
# ist entweder von merge_wp.sh freigegeben (sein Tree steht in
# <git-common-dir>/wendelin-merge-ok als „<tree> <commit>“; Zeilen, deren Commit schon
# in origin/main liegt, räumt der nächste Push weg; übersteht ein Amend der Nachricht; die
# Commits, die er mitbringt, gelten mit) oder ändert nur docs/** bzw. das
# Gesamtkonzept. wp/*- und alle anderen Pushes (auch Löschungen) bleiben frei.
# Einrichtung: docs/ENGINEERING.md → Git. Eingabe (stdin) wie bei Git:
#   <lokale ref> <lokaler sha> <remote ref> <remote sha>
zero=0000000000000000000000000000000000000000
ok_file="$(git rev-parse --path-format=absolute --git-common-dir)/wendelin-merge-ok"
concept='Voice Agent App – Gesamtkonzept.md'
rc=0
while read -r lref lsha rref rsha; do
  [ "$rref" = refs/heads/main ] || continue
  if [ "${WENDELIN_PUSH_MAIN:-}" != 1 ]; then
    echo "pre-push: Push auf main nur mit WENDELIN_PUSH_MAIN=1 (Orchestrator: nach tool/merge_wp.sh bzw. für reine Doku-Commits). Arbeitsbranches: wp/<nr>-<slug>." >&2
    rc=1; continue
  fi
  if [ "$lsha" = "$zero" ]; then
    echo "pre-push: main darf nicht gelöscht werden." >&2; rc=1; continue
  fi
  if [ "$rsha" != "$zero" ] && ! git cat-file -e "$rsha^{commit}" 2>/dev/null; then
    echo "pre-push: Remote-Stand $rsha von main ist lokal unbekannt; erst fetch/merge." >&2; rc=1; continue
  fi
  # Kein Zurücksetzen/Force-Push: der Remote-Stand muss Vorfahr des neuen sein
  # (sonst wäre der Bereich rsha..lsha leer und die Prüfung wirkungslos).
  if [ "$rsha" != "$zero" ] && ! git merge-base --is-ancestor "$rsha" "$lsha" 2>/dev/null; then
    echo "pre-push: main wäre kein Fast-Forward von $rsha (Rücksetzen/Force-Push); abgelehnt." >&2
    rc=1; continue
  fi
  if [ "$rsha" = "$zero" ]; then excl=--remotes; else excl=$rsha; fi
  range="$lsha --not $excl"
  # Verbrauchte Freigaben (Commit schon in origin/main) entfernen; ein Push wird dadurch nie blockiert.
  if [ -f "$ok_file" ] && git rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
    pruned=$(mktemp)
    recent=$(git log -n 300 --format=%T refs/remotes/origin/main)
    while read -r nt nc _; do
      [ -n "$nt" ] || continue
      if [ -n "$nc" ] && git merge-base --is-ancestor "$nc" refs/remotes/origin/main 2>/dev/null; then continue; fi
      if printf '%s\n' "$recent" | grep -qx "$nt"; then continue; fi
      echo "$nt${nc:+ $nc}"
    done < "$ok_file" > "$pruned"
    cat "$pruned" > "$ok_file"; rm -f "$pruned"
  fi
  # Durch einen notierten Tree abgedeckte Commits (der Commit und was er mitbringt).
  covered=$(mktemp)
  # shellcheck disable=SC2086
  for c in $(git rev-list $range); do
    t=$(git rev-parse "$c^{tree}")
    if [ -f "$ok_file" ] && awk -v t="$t" '$1==t{f=1} END{exit !f}' "$ok_file"; then
      # shellcheck disable=SC2086
      git rev-list "$c" --not $excl >> "$covered"
    fi
  done
  # shellcheck disable=SC2086
  for c in $(git rev-list $range); do
    grep -qx "$c" "$covered" && continue
    if git rev-parse -q --verify "$c^" >/dev/null; then
      files=$(git diff --no-renames --name-only -z "$c^" "$c" | tr '\0' '\n')
    else
      files=$(git diff-tree --no-renames --root -r --name-only --no-commit-id "$c")
    fi
    bad=$(printf '%s\n' "$files" | grep -v '^$' | grep -vE "^docs/|^$concept\$")
    if [ -n "$bad" ]; then
      echo "pre-push: $(git rev-parse --short "$c") ändert Code ($(echo "$bad" | head -3 | tr '\n' ' ')…) und ist nicht von tool/merge_wp.sh freigegeben (Tree nicht in $ok_file). main nur über merge_wp.sh." >&2
      rc=1; break
    fi
  done
  rm -f "$covered"
done
exit $rc
