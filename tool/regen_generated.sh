#!/bin/sh
# Hook für tool/merge_wp.sh: erzeugt die in .gitattributes als linguist-generated
# markierten Dateien neu, wenn ein Merge nur dort Konflikte hatte.
# Argumente: die konfliktbehafteten Dateien. Vorerst ein Stub (kommt mit l10n).
echo "regen_generated: noch nichts zu erzeugen ($*)" >&2
exit 1
