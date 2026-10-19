#!/bin/bash
# Probe: zwei parallele Branches, die je eine (Fake-)Integration hinzufügen,
# lassen sich nacheinander ohne manuellen Konflikt mergen (WP98 Abnahme 1).
#   tool/probe_parallel_merge.sh [--keep]
# Arbeitet in einem temporären `git clone --local` (aus dem aktuellen HEAD,
# auch ohne Commit-Stand von main), das Repo selbst bleibt unberührt. Je Branch:
# Spec-Datei, Registry-Import und -Zeile, Barrel-Export, l10n-Fragment (de/en/fr),
# Trust-JSON und eine Zeile in docs/ARCHITECTURE.md. Gemergt wird mit
# tool/merge_wp.sh; danach l10n_merge --check und check_registry.
# Die Doku-Zeile darf kollidieren (erwartet offen bis WP98 D2): Die Probe meldet
# das, lässt den Doku-Commit des zweiten Branches weg und prüft den Rest.
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
  # Doku-Zeile: neue Tabellenzeile direkt unter der letzten Zeile der Tabelle mit `evals`.
  awk -v row="| \`$n\` | Probe-Integration $n |" '
    { print } /^\| `evals` \|/ { print row }' docs/ARCHITECTURE.md > docs/ARCHITECTURE.md.new \
    && mv docs/ARCHITECTURE.md.new docs/ARCHITECTURE.md
  git add -A
  git commit -q -m "probe: Doku-Zeile $n

$TRAILER" || fail "commit doku $n"
}

add_integration probeone
add_integration probetwo
git checkout -q main

# Wirkungsprüfung der Gate-Schritte in der Probe (ohne die Tool-Self-Tests).
export MERGE_WP_GATE='dart run tool/l10n_merge.dart --check && dart run tool/check_registry.dart'
export MERGE_WP_BASE=main

bash tool/merge_wp.sh probe/probetwo --keep || fail "Merge probetwo"

echo "probe: merge probe/probeone"
# Vorab: welche Dateien kollidieren ohne Hilfen? (Erzeugtes löst merge_wp.sh selbst.)
git merge --no-commit --no-ff probe/probeone >/dev/null 2>&1
conflicts=$(git diff --name-only --diff-filter=U)
git merge --abort 2>/dev/null; git reset -q --hard HEAD
open_doc=0; manual=""
for f in $conflicts; do
  if git check-attr linguist-generated -- "$f" | grep -q ': set$'; then continue; fi
  if [ "$f" = docs/ARCHITECTURE.md ]; then open_doc=1; else manual="$manual $f"; fi
done
[ -z "$manual" ] || fail "manueller Konflikt in:$manual"
target=probe/probeone
if [ $open_doc -eq 1 ]; then
  echo "probe: erwartet offen (WP98 D2): Doku-Zeile in docs/ARCHITECTURE.md kollidiert; Probe lässt den Doku-Commit weg."
  git branch -q -f probe/probeone-nodoc probe/probeone~1
  target=probe/probeone-nodoc
fi
bash tool/merge_wp.sh "$target" --keep || fail "Merge $target"

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
[ -z "$(git status --porcelain)" ] || fail "Arbeitsverzeichnis nach dem Merge nicht sauber"
echo "probe: OK (kein manueller Konflikt$([ $open_doc -eq 1 ] && echo "; Doku-Zeile erwartet offen bis D2"))"
