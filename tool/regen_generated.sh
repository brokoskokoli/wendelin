#!/bin/sh
# Hook für tool/merge_wp.sh: erzeugt die in .gitattributes als linguist-generated
# markierten Dateien neu, wenn ein Merge nur dort Konflikte hatte.
# Argumente: die konfliktbehafteten Dateien. Das sind die l10n-Dateien
# (app_*.arb, gen/**; Fragmente unter app/lib/l10n/src, Erzeuger
# tool/l10n_merge.dart) und die Doku-Dateien, die tool/gen_docs.dart erzeugt
# (docs/architecture/generated/**, docs/testing/m5/README.md).
l10n=0; docs=0
for f in "$@"; do
  case "$f" in
    app/lib/l10n/app_*.arb | app/lib/l10n/gen/*) l10n=1 ;;
    docs/architecture/generated/* | docs/testing/m5/README.md) docs=1 ;;
    *) echo "regen_generated: kein Erzeuger für $f" >&2; exit 1 ;;
  esac
done
[ $l10n -eq 1 ] && { dart run tool/l10n_merge.dart || exit 1; }
[ $docs -eq 1 ] && { dart run tool/gen_docs.dart || exit 1; }
exit 0
