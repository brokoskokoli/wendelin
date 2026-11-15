#!/bin/sh
# pre-push (WP109): main ändert sich nur über gemergte Pull Requests.
# Push auf refs/heads/main nur mit WENDELIN_PUSH_MAIN=1, nur als Fast-Forward
# (kein Löschen, kein Rücksetzen) und nur mit Commits, die ausschließlich
# docs/** bzw. das Gesamtkonzept ändern. Code kommt über einen Branch mit Pull
# Request und grünem CI auf main. Alle anderen Pushes (Branches, Tags,
# Löschungen) bleiben frei.
# Einrichtung: docs/ENGINEERING.md → Git. Eingabe (stdin) wie bei Git:
#   <lokale ref> <lokaler sha> <remote ref> <remote sha>
zero=0000000000000000000000000000000000000000
concept='Voice Agent App – Gesamtkonzept.md'
rc=0
while read -r lref lsha rref rsha; do
  [ "$rref" = refs/heads/main ] || continue
  if [ "${WENDELIN_PUSH_MAIN:-}" != 1 ]; then
    echo "pre-push: Push auf main nur mit WENDELIN_PUSH_MAIN=1 und nur für reine Doku-Commits. Code über einen eigenen Branch und Pull Request." >&2
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
  # shellcheck disable=SC2086
  for c in $(git rev-list "$lsha" --not $excl); do
    parents=$(git rev-parse "$c^@")
    if [ -n "$parents" ]; then
      # Gegen jeden Elternteil prüfen (ein Merge darf main nicht über den zweiten Elternteil zurücksetzen).
      files=""
      for pa in $parents; do
        files="$files
$(git diff --no-renames --name-only -z "$pa" "$c" | tr '\0' '\n')"
      done
    else
      files=$(git diff-tree --no-renames --root -r --name-only --no-commit-id "$c")
    fi
    bad=$(printf '%s\n' "$files" | grep -v '^$' | grep -vE "^docs/|^$concept\$")
    if [ -n "$bad" ]; then
      echo "pre-push: $(git rev-parse --short "$c") ändert Code ($(echo "$bad" | head -3 | tr '\n' ' ')…). Auf main nur reine Doku-Commits; Code über einen Pull Request." >&2
      rc=1; break
    fi
  done
done
exit $rc
