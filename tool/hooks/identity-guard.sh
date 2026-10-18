#!/bin/sh
# Blockiert Commits mit nicht erlaubter Identität (siehe docs/ENGINEERING.md → Git).
ALLOWED_EMAIL="16724498+brokoskokoli@users.noreply.github.com"
ALLOWED_NAME="brokoskokoli"
an=$(git var GIT_AUTHOR_IDENT | sed 's/ <.*//'); ae=$(git var GIT_AUTHOR_IDENT | sed 's/.*<\(.*\)>.*/\1/')
cn=$(git var GIT_COMMITTER_IDENT | sed 's/ <.*//'); ce=$(git var GIT_COMMITTER_IDENT | sed 's/.*<\(.*\)>.*/\1/')
for pair in "$an|$ae" "$cn|$ce"; do
  n=${pair%%|*}; e=${pair#*|}
  if [ "$e" != "$ALLOWED_EMAIL" ] || { [ "$n" != "$ALLOWED_NAME" ] && [ "$n" != "Stefan Richter" ]; }; then
    echo "identity-guard: Commit-Identität '$n <$e>' nicht erlaubt. Erlaubt: $ALLOWED_NAME <$ALLOWED_EMAIL>" >&2
    exit 1
  fi
done
exit 0
