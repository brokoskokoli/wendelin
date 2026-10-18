#!/usr/bin/env bash
# Gezielter Testlauf für Agenten: tool/t.sh <pfad…> [--name <text>]
# Wählt dart oder flutter je Paket, zeigt nur Fehlschläge (Name, Datei:Zeile,
# Fehler, wenige Stack-Zeilen), höchstens 80 Zeilen.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
exec dart run tool/t.dart "$PWD" "$OLDPWD" "$@"
