#!/usr/bin/env bash
# One-command compliance artifact demo: NL → oracle → JSON + GZ SVG + audit trail.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
OUT="${1:-tools/gap_audit/out/compliance_demo}"
mkdir -p "$OUT"

python tools/agent/oracle_agent.py \
  --record tools/dataset/out/eval.jsonl \
  --id "$(head -1 tools/dataset/out/eval.jsonl | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')" \
  --extract hybrid \
  --ollama-model "${OLLAMA_MODEL:-qwen2.5-coder:1.5b}" \
  --assets-dir "$OUT" \
  --output "$OUT/artifact.json"

echo "=== Compliance demo ==="
echo "Artifact: $OUT/artifact.json"
echo "GZ curve: $OUT/gz_curve.svg"
python3 -c "
import json
a=json.load(open('$OUT/artifact.json'))
print(f\"Overall: {a['answer']['overall']}\")
print(f\"GM_corr: {a['answer']['GM_corrected']:.4f} m\")
print(f\"Audit: {a['audit']['oracle_id']} proof={a['audit']['proof_level']}\")
print(f\"Hashes: in={a['audit']['input_hash']} out={a['audit']['output_hash']}\")
"