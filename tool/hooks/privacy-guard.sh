#!/bin/sh
# pre-commit: keine lokalen Pfade und keine Begriffe der lokalen Liste in hinzugefügten Zeilen (WP127).
here=$(cd "$(dirname "$0")" && pwd) || exit 1
exec dart run "$here/../check_privacy.dart" --staged
