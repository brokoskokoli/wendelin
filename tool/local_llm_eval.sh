#!/usr/bin/env bash
# WP57: Eval-Set nacheinander gegen lokale Ollama-Modelle (OpenAI-kompatibel).
# Aufruf: [INTEGRATIONS=calendar,alarms,...] tool/local_llm_eval.sh <modell>...
# Reports: evals/reports/2026-10-14-ollama-<modell>[-reduced].local.json
set -euo pipefail
cd "$(dirname "$0")/../evals"
extra=(); suffix=""
if [ -n "${INTEGRATIONS:-}" ]; then extra=(--integrations "$INTEGRATIONS"); suffix="-reduced"; fi
for m in "$@"; do
  slug=$(echo "$m" | tr ':/' '__')
  echo "== $m"
  dart run wendelin_evals:run -p profiles/ollama-local.json -m "$m" ${extra[@]+"${extra[@]}"} \
    -o "reports/2026-10-14-ollama-$slug$suffix.local.json" | tail -8
  ollama stop "$m" || true
done
