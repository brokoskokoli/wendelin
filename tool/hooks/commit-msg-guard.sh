#!/bin/sh
# Erlaubt in der Commit-Nachricht nur die eigene und die Claude-noreply-Adresse; verbietet lokal hinterlegte Begriffe.
msg="$1"
# Verbotene Begriffe stehen nur lokal (nicht im öffentlichen Repo), ein Regex je Zeile.
terms="$HOME/.config/wendelin/forbidden-identities"
if [ -f "$terms" ] && grep -v '^#' "$terms" | grep -v '^$' | grep -qiEf - "$msg"; then echo "commit-msg-guard: verbotener Begriff in der Nachricht" >&2; exit 1; fi
bad=$(grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+' "$msg" | grep -vE '^(16724498\+brokoskokoli@users\.noreply\.github\.com|noreply@anthropic\.com)$')
if [ -n "$bad" ]; then echo "commit-msg-guard: nicht erlaubte Adresse(n): $bad" >&2; exit 1; fi
# Co-Autor nur in der freigegebenen Schreibweise (Agenten mit anderem Modell setzen sonst ihren eigenen Namen).
coauth=$(grep -i '^Co-Authored-By:' "$msg" | grep -vx 'Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>')
if [ -n "$coauth" ]; then echo "commit-msg-guard: Co-Authored-By nur als 'Claude Opus 5.5 (1M context) <noreply@anthropic.com>': $coauth" >&2; exit 1; fi
# Keine Sitzungs-Links in Commit-Nachrichten (nur Co-Authored-By).
if grep -qiE '^Claude-Session:|claude\.ai/code/session' "$msg"; then echo "commit-msg-guard: keine Claude-Session-Zeile in der Commit-Nachricht" >&2; exit 1; fi
exit 0
