#!/usr/bin/env bash
# Full fine-tune + post-FT gap audit pipeline.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

source "$ROOT/tools/finetune/gpu_env.sh"

MODEL_OUT="${1:-models/yard-stability-4gb-v1}"
MAX_SAMPLES="${2:-}"  # empty = full 5k

echo "=== Yard Fine-Tune + Eval ==="

# Pre-flight CUDA
python3 -c "import torch; assert torch.cuda.is_available(), 'CUDA not ready — run fix_cuda.sh'"

TRAIN_ARGS=(--data tools/dataset/out/train_chat.jsonl --output "$MODEL_OUT" --epochs 2)
if [[ -n "$MAX_SAMPLES" ]]; then
  TRAIN_ARGS+=(--max-samples "$MAX_SAMPLES")
fi

echo "--- Training ---"
python tools/finetune/train_local_4gb.py "${TRAIN_ARGS[@]}"

echo "--- Post-FT gap audit (200 held-out) ---"
# Merge adapter into base for Ollama or use transformers infer — for now harness on preds
python tools/finetune/infer_ollama.py \
  --model "$MODEL_OUT" \
  --dataset tools/dataset/out/eval.jsonl \
  --output tools/gap_audit/out/ft_preds.jsonl 2>/dev/null || \
  echo "NOTE: Ollama infer skipped — run manual eval after exporting model"

python tools/eval/harness.py \
  --dataset tools/dataset/out/eval.jsonl \
  --predictions tools/gap_audit/out/ft_preds.jsonl \
  --mode model 2>/dev/null || true

echo "=== Done. Update tools/gap_audit/GAP_REPORT.md with post-FT numbers ==="