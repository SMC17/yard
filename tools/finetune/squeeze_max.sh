#!/usr/bin/env bash
# Squeeze maximum value from GTX 1650 4GB: JSON-only FT + eval + datasets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/tools/finetune/gpu_env.sh"

MODEL="${1:-models/yard-stability-json-v1}"
SAMPLES="${2:-500}"
STEPS="${3:-80}"

echo "=== Yard Squeeze-Max Pipeline ==="
echo "Model: $MODEL  Samples: $SAMPLES  Max steps: $STEPS"

# 1. JSON-only training data (fixes train/infer mismatch)
if [[ ! -f tools/dataset/out/train_chat_json_only.jsonl ]]; then
  echo "--- Export JSON-only chat format ---"
  python tools/dataset/export_json_only.py \
    --input tools/dataset/out/train.jsonl \
    --output tools/dataset/out/train_chat_json_only.jsonl \
    --limit "$SAMPLES"
fi

# 2. Seakeeping datasets (if missing)
if [[ ! -f tools/dataset/out/seakeeping_train.jsonl ]]; then
  echo "--- Generate seakeeping train (200) ---"
  python tools/dataset/generate_seakeeping.py \
    --samples 200 --output tools/dataset/out/seakeeping_train.jsonl
fi
if [[ ! -f tools/dataset/out/seakeeping_eval.jsonl ]]; then
  echo "--- Generate seakeeping eval (50) ---"
  python tools/dataset/generate_seakeeping.py \
    --samples 50 --output tools/dataset/out/seakeeping_eval.jsonl --split eval --seed 9999
fi

# 3. Train JSON-only (fresh — don't resume CoT checkpoint)
echo "--- Training JSON-only QLoRA ---"
python tools/finetune/train_local_4gb.py \
  --data tools/dataset/out/train_chat_json_only.jsonl \
  --output "$MODEL" \
  --max-samples "$SAMPLES" \
  --max-steps "$STEPS" \
  --max-seq-len 384 \
  --epochs 1 \
  --save-steps 10 \
  --grad-accum 8 \
  2>&1 | tee "$MODEL/train.log"

# 4. Pick latest checkpoint
CKPT=$(ls -d "$MODEL"/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1)
if [[ -z "${CKPT:-}" ]]; then
  CKPT="$MODEL"
fi
echo "Using checkpoint: $CKPT"

# 5. Post-FT eval (30-case smoke, then full if time)
echo "--- Post-FT infer (n=30) ---"
python tools/finetune/infer_local.py \
  --adapter "$CKPT" \
  --dataset tools/dataset/out/eval.jsonl \
  --output tools/gap_audit/out/json_ft_preds_30.jsonl \
  --limit 30 \
  --max-new-tokens 256 \
  --score

echo "--- Seakeeping gap audit baseline ---"
python tools/gap_audit/gap_audit_seakeeping.py \
  --dataset tools/dataset/out/seakeeping_eval.jsonl \
  --baseline naive --n 50

echo "=== Squeeze-max done. Update GAP_REPORT.md with json_ft numbers ==="