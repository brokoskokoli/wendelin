#!/bin/sh
# Hook für tool/merge_wp.sh: erzeugt die in .gitattributes als linguist-generated
# markierten Dateien neu, wenn ein Merge nur dort Konflikte hatte.
# Argumente: die konfliktbehafteten Dateien. Heute sind das die l10n-Dateien
# (app_*.arb, gen/**): Sie entstehen aus den Fragmenten unter app/lib/l10n/src.
for f in "$@"; do
  case "$f" in
    app/lib/l10n/app_*.arb | app/lib/l10n/gen/*) ;;
    *) echo "regen_generated: kein Erzeuger für $f" >&2; exit 1 ;;
  esac
done
exec dart run tool/l10n_merge.dart
