#!/bin/bash
# Umfang eines CI-Laufs (WP110). Gemeinsame Quelle für .github/workflows/gate.yml und tool/merge_wp.sh.
#   tool/ci_scope.sh --classify          Pfade (eine je Zeile) auf stdin → "docs" oder "code"
#   tool/ci_scope.sh --ci                im Workflow: schreibt docs_only=… und android=… nach $GITHUB_OUTPUT (sonst stdout)
#   tool/ci_scope.sh --self-test         Selbsttest der Einstufung
# "docs" heißt: nur Markdown (außer unter lib/, test/, integration_test/, die Tests lesen können). Dann läuft nur check_docs.
# Alles andere, auch ein leerer Diff, ist "code" und bekommt das volle Gate. Fail-safe: im Zweifel "code".
# --ci: Bezug ist der Diff gegen die Merge-Basis mit origin/main (Branches und PRs: alle Änderungen des Branches, damit
# ein Branch mit Code immer das volle Gate bekommt); auf main der Diff gegen den vorigen Push (BEFORE).
# Umgebung (--ci): REF (github.ref), BEFORE (github.event.before).
set -u

classify() {
  local n=0 p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n + 1))
    case "/$p" in
      */lib/* | */test/* | */integration_test/*) echo code; return ;;
    esac
    case "$p" in
      *.md) ;;
      *) echo code; return ;;
    esac
  done
  [ "$n" -gt 0 ] && echo docs || echo code
}

if [ "${1:-}" = "--classify" ]; then
  classify
  exit 0
fi

if [ "${1:-}" = "--self-test" ]; then
  st=0
  chk() { # erwartet, Pfade…
    local want="$1" got; shift
    got=$(printf '%s\n' "$@" | classify)
    if [ "$got" != "$want" ]; then echo "Selbsttest FEHLER: $* → $got (erwartet $want)" >&2; st=1; else echo "ok: $* → $got"; fi
  }
  chk docs docs/work-packages/STATUS.md
  chk docs AGENTS.md docs/a.md .claude/agents/x.md
  chk code docs/work-packages/STATUS.md app/lib/x.dart
  chk code docs/design/tokens.json
  chk code tool/gate.dart
  chk code README.md .github/workflows/gate.yml
  chk code app/lib/l10n/README.md
  chk code packages/wendelin_core/test/README.md
  got=$(printf '' | classify); [ "$got" = code ] || { echo "Selbsttest FEHLER: leerer Diff ist $got, erwartet code" >&2; st=1; }
  exit $st
fi

if [ "${1:-}" = "--ci" ]; then
  base=""
  if [ "${REF:-}" = refs/heads/main ]; then base="${BEFORE:-}"; fi
  if [ -z "$base" ] || [ "$base" = 0000000000000000000000000000000000000000 ] || ! git cat-file -e "$base" 2>/dev/null; then
    base=$(git merge-base origin/main HEAD 2>/dev/null || true)
  fi
  if [ -z "$base" ]; then paths=""; else paths=$(git diff --name-only "$base" HEAD); fi
  docs_only=false
  [ "$(printf '%s\n' "$paths" | classify)" = docs ] && docs_only=true
  android=false
  printf '%s\n' "$paths" | grep -qE '^(app/android/|native/|\.github/workflows/gate\.yml|tool/check_apk|pubspec|.*/pubspec[^/]*$)' && android=true
  out=${GITHUB_OUTPUT:-/dev/stdout}
  echo "docs_only=$docs_only" >> "$out"
  echo "android=$android" >> "$out"
  echo "Umfang: docs_only=$docs_only android=$android (Basis ${base:-unbekannt})"
  exit 0
fi

echo "Aufruf: tool/ci_scope.sh --classify | --ci | --self-test" >&2
exit 64
