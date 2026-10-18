#!/usr/bin/env bash
# Wartet auf den CI-Lauf des aktuellen Commits eines Branches (ein einziges
# `gh run watch`) und gibt eine kompakte Zusammenfassung aus: je Job das
# Ergebnis, bei Rot die letzten Zeilen des Fehlerprotokolls.
# Aufruf: tool/ci_wait.sh [branch]   (Standard: aktueller Branch)
# Exit 0 = grün, 1 = rot, 2 = kein Lauf gefunden.
set -uo pipefail
branch="${1:-$(git rev-parse --abbrev-ref HEAD)}"
sha="$(git rev-parse HEAD)"
id=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  id="$(gh run list -b "$branch" -c "$sha" -w gate -L1 --json databaseId -q '.[0].databaseId' 2>/dev/null)"
  [ -n "$id" ] && break
  sleep 5
done
if [ -z "$id" ]; then
  echo "Kein CI-Lauf für $branch@${sha:0:7} gefunden (gepusht?)."
  exit 2
fi
gh run watch "$id" --interval 20 >/dev/null 2>&1
conclusion="$(gh run view "$id" --json conclusion,url,createdAt,updatedAt \
  -q '.conclusion + " " + .url + " " + .createdAt + " " + .updatedAt')"
set -- $conclusion
echo "CI $1  $2"
gh run view "$id" --json jobs -q '.jobs[] | "\(.conclusion)\t\(.name)"' | sort | sed 's/^/  /'
if [ "$1" != "success" ]; then
  echo "--- Ende der Fehlerprotokolle ---"
  # Nur Fehlerzeilen (rote Tests, ##[error], Exceptions), je Job gekürzt.
  gh run view "$id" --log-failed 2>/dev/null \
    | grep -aE '❌|##\[error\]|Error:|Exception|Expected:|Actual:|Golden "|error •|failed' \
    | grep -av '✅' | sed -E 's/\t[^\t]*\t[0-9T:.-]+Z / /' | cut -c1-200 | tail -n 30
  exit 1
fi
