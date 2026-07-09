#!/usr/bin/env bash
# Full Physical AI pipeline: Ollama NL→spec → Yard oracle → compliance artifact.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/.local/share/ollama-official/bin:${PATH}"
MODEL="${OLLAMA_MODEL:-qwen2.5-coder:1.5b}"
HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
OUT="${1:-tools/gap_audit/out/ollama_agent_demo}"
LIMIT="${2:-30}"

if ! curl -sf "${HOST}/api/tags" >/dev/null 2>&1; then
  echo "Starting ollama serve..."
  ollama serve >/tmp/ollama-serve.log 2>&1 &
  sleep 3
fi

mkdir -p "$OUT"

# Single-case demo with hybrid extraction
CASE_ID=$(head -1 tools/dataset/out/eval.jsonl | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
python tools/agent/oracle_agent.py \
  --record tools/dataset/out/eval.jsonl \
  --id "$CASE_ID" \
  --extract hybrid \
  --ollama-model "$MODEL" \
  --ollama-host "$HOST" \
  --assets-dir "$OUT" \
  --output "$OUT/artifact.json"

echo ""
echo "=== Ollama + Oracle demo ==="
python3 -c "
import json
a=json.load(open('$OUT/artifact.json'))
print('Extraction:', a['audit']['extraction_mode'])
print('Overall:', a['answer']['overall'])
print('GM_corr:', round(a['answer']['GM_corrected'], 4), 'm')
print('Audit:', a['audit']['oracle_id'])
print('GZ SVG:', a['assets'].get('gz_curve_svg',''))
"

echo ""
echo "--- Benchmark (limit=$LIMIT) ---"
python tools/agent/eval_oracle_agent.py \
  --dataset tools/dataset/out/eval.jsonl \
  --limit "$LIMIT" \
  --modes hybrid ollama regex record_input \
  --ollama-model "$MODEL" \
  --ollama-host "$HOST" \
  --output "$OUT/benchmark_${LIMIT}.txt"

echo "Report: $OUT/benchmark_${LIMIT}.txt"