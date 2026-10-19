#!/bin/bash
# Probe: zwei parallele Branches, die je eine (Fake-)Integration hinzufügen,
# lassen sich nacheinander ohne manuellen Konflikt mergen (WP98 Abnahme 1).
#   tool/probe_parallel_merge.sh [--keep]
# Arbeitet in einem temporären `git clone --local` (aus dem aktuellen HEAD,
# auch ohne Commit-Stand von main), das Repo selbst bleibt unberührt. Je Branch:
# Spec-Datei, Registry-Import und -Zeile, Barrel-Export, l10n-Fragment (de/en/fr),
# Trust-JSON, Integrationsdoku (docs/architecture/integrations/<id>.md), Gerätetest-
# Datei (docs/testing/m5/<id>.md) und die erzeugten Tabellen (gen_docs). Gemergt wird
# mit tool/merge_wp.sh; danach l10n_merge --check, check_registry und check_docs.
# Es darf kein manueller Konflikt entstehen (erzeugte Dateien löst regen_generated.sh).
# Voraussetzung: dart und flutter (gen-l10n, ohne Build); Dauer rund eine Minute.
set -u
keep=0; [ "${1:-}" = "--keep" ] && keep=1
src=$(git rev-parse --show-toplevel) || exit 2
base=$(git rev-parse HEAD)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/probe-merge.XXXXXX") || exit 2
clone="$tmp/repo"
cleanup() { [ $keep -eq 1 ] && echo "probe: Klon bleibt: $clone" || rm -rf "$tmp"; }
trap cleanup EXIT
fail() { echo "probe: FEHLER: $*" >&2; exit 1; }

NAME=brokoskokoli; MAIL=16724498+brokoskokoli@users.noreply.github.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=$NAME GIT_AUTHOR_EMAIL=$MAIL GIT_COMMITTER_NAME=$NAME GIT_COMMITTER_EMAIL=$MAIL
TRAILER='Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>'

git clone -q --local "$src" "$clone" || fail "clone"
cd "$clone" || exit 2
git checkout -q -b main "$base" || fail "checkout main"
# Uncommittete Änderungen des Quell-Worktrees sind nicht Teil der Probe.

add_integration() { # <name>
  local n=$1 N
  N=$(printf '%s' "$n" | tr '[:lower:]' '[:upper:]')
  git checkout -q -b "probe/$n" main
  cat > "app/lib/di/integrations/${n}_spec.dart" <<DART
import 'integration_spec.dart';

/// Probe-Integration $n (nur Konflikttest, wird nicht kompiliert).
final ${n}Spec = IntegrationSpec(id: '$n');
DART
  # Registry: Import in Sortierposition (hinter obsidian), Zeile ans Listenende.
  sed -i.bak "s|^import 'obsidian_spec.dart';|&\nimport '${n}_spec.dart';|" app/lib/di/integrations/registry.dart
  sed -i.bak "s|^  tasksSpec,|&\n  ${n}Spec,|" app/lib/di/integrations/registry.dart
  # Barrel: Export hinter obsidian.dart
  sed -i.bak "s|^export 'obsidian.dart';|&\nexport '${n}.dart';|" packages/wendelin_integrations/lib/wendelin_integrations.dart
  rm -f app/lib/di/integrations/registry.dart.bak packages/wendelin_integrations/lib/wendelin_integrations.dart.bak
  printf '// Probe\n' > "packages/wendelin_integrations/lib/${n}.dart"
  mkdir -p "app/lib/l10n/src/$n"
  for l in de en fr; do
    printf '{\n  "%sTitle": "Probe %s %s"\n}\n' "$n" "$n" "$l" > "app/lib/l10n/src/$n/${n}_$l.arb"
  done
  printf '{\n  "%s__ping": false\n}\n' "$n" > "app/test/trust/$n.json"
  dart run tool/l10n_merge.dart >/dev/null 2>&1 || fail "l10n_merge ($n)"
  git add -A
  git commit -q -m "probe: Integration $n (Code, Texte, Trust)

$TRAILER" || fail "commit code $n"
  # Doku auf dem neuen Weg: eigene Datei je Integration, eigener Gerätetest-Block,
  # erzeugte Tabellen/Index per tool/gen_docs.dart (keine gemeinsame Zeile).
  mkdir -p docs/architecture/integrations docs/testing/m5
  printf '# Probe-Integration %s\n\nBesonderheiten von %s.\n' "$n" "$n" > "docs/architecture/integrations/${n}.md"
  printf '# WP%s Probe %s\n\n- [ ] **Einschalten.** Erwartet: aktiv.\n' "$N" "$n" > "docs/testing/m5/${n}.md"
  dart run tool/gen_docs.dart >/dev/null 2>&1 || fail "gen_docs ($n)"
  git add -A
  git commit -q -m "probe: Doku $n

$TRAILER" || fail "commit doku $n"
}

add_integration probeone
add_integration probetwo
git checkout -q main

# Wirkungsprüfung der Gate-Schritte in der Probe (ohne die Tool-Self-Tests).
export MERGE_WP_GATE='dart run tool/l10n_merge.dart --check && dart run tool/check_registry.dart && dart run tool/gen_docs.dart --check'
export MERGE_WP_BASE=main

bash tool/merge_wp.sh probe/probetwo --keep || fail "Merge probetwo"

echo "probe: merge probe/probeone"
# Vorab: welche Dateien kollidieren ohne Hilfen? (Erzeugtes löst merge_wp.sh selbst.)
git merge --no-commit --no-ff probe/probeone >/dev/null 2>&1
conflicts=$(git diff --name-only --diff-filter=U)
git merge --abort 2>/dev/null; git reset -q --hard HEAD
manual=""
for f in $conflicts; do
  if git check-attr linguist-generated -- "$f" | grep -q ': set$'; then continue; fi
  manual="$manual $f"
done
[ -z "$manual" ] || fail "manueller Konflikt in:$manual"
bash tool/merge_wp.sh probe/probeone --keep || fail "Merge probeone"

# Ergebnis: beide Integrationen vollständig vorhanden, Prüfungen grün.
for n in probeone probetwo; do
  grep -q "^  ${n}Spec," app/lib/di/integrations/registry.dart || fail "Registry ohne ${n}Spec"
  grep -q "^import '${n}_spec.dart';" app/lib/di/integrations/registry.dart || fail "Registry ohne Import $n"
  grep -q "^export '${n}.dart';" packages/wendelin_integrations/lib/wendelin_integrations.dart || fail "Barrel ohne $n"
  [ -f "app/test/trust/$n.json" ] || fail "Trust-JSON $n fehlt"
  grep -q "\"${n}Title\"" app/lib/l10n/app_en.arb || fail "app_en.arb ohne ${n}Title"
done
dart run tool/l10n_merge.dart --check || fail "l10n_merge --check rot"
dart run tool/check_registry.dart || fail "check_registry rot"
dart run tool/gen_docs.dart --check || fail "gen_docs --check rot"
dart run tool/check_docs.dart || fail "check_docs rot"
for n in probeone probetwo; do
  grep -q "\`$n\`" docs/architecture/generated/integrations.md || fail "Tabelle ohne $n"
  [ -f "docs/architecture/integrations/$n.md" ] && [ -f "docs/testing/m5/$n.md" ] || fail "Doku-Dateien $n fehlen"
  grep -q "($n.md)" docs/testing/m5/README.md || fail "m5-Index ohne $n"
done
[ -z "$(git status --porcelain)" ] || fail "Arbeitsverzeichnis nach dem Merge nicht sauber"
echo "probe: OK (kein manueller Konflikt, Doku konfliktfrei)"
