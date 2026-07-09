#!/usr/bin/env bash
# Run yard-stability-bench v0.1 eval suite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.local/share/ollama-official/bin:${PATH}"

LIMIT="${1:-200}"
OUT="tools/gap_audit/out/bench_v0.1_${LIMIT}.txt"

if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "Starting ollama serve..."
  ollama serve >/tmp/ollama-serve.log 2>&1 &
  sleep 3
fi

echo "=== yard-stability-bench v0.1 (n=${LIMIT}) ==="
python tools/agent/yard_agent.py eval \
  --dataset tools/dataset/out/eval.jsonl \
  --limit "$([ "$LIMIT" = "200" ] && echo "" || echo "$LIMIT")" \
  --modes hybrid ollama regex record_input \
  --output "$OUT"

echo "Report: $OUT"