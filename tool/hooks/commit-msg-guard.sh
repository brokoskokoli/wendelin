#!/bin/sh
# Erlaubt in der Commit-Nachricht nur die eigene und die Claude-noreply-Adresse; verbietet Arbeitgeber-Domains.
msg="$1"
if grep -qiE 'web-?fabric|[entfernt]' "$msg"; then echo "commit-msg-guard: verbotener Begriff in der Nachricht" >&2; exit 1; fi
bad=$(grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+' "$msg" | grep -vE '^(16724498\+brokoskokoli@users\.noreply\.github\.com|noreply@anthropic\.com)$')
if [ -n "$bad" ]; then echo "commit-msg-guard: nicht erlaubte Adresse(n): $bad" >&2; exit 1; fi
exit 0
