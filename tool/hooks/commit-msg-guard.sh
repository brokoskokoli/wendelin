#!/bin/sh
# Erlaubt in der Commit-Nachricht nur die eigene und die Claude-noreply-Adresse; verbietet lokal hinterlegte Begriffe.
msg="$1"
# Verbotene Begriffe stehen nur lokal (nicht im öffentlichen Repo), ein Regex je Zeile.
terms="$HOME/.config/wendelin/forbidden-identities"
if [ -f "$terms" ] && grep -v '^#' "$terms" | grep -v '^$' | grep -qiEf - "$msg"; then echo "commit-msg-guard: verbotener Begriff in der Nachricht" >&2; exit 1; fi
bad=$(grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+' "$msg" | grep -vE '^(16724498\+brokoskokoli@users\.noreply\.github\.com|noreply@anthropic\.com)$')
if [ -n "$bad" ]; then echo "commit-msg-guard: nicht erlaubte Adresse(n): $bad" >&2; exit 1; fi
exit 0
