#!/usr/bin/env bash
# Stage B numerics lane: FS3x oversampled JSON-only, warm-start from format checkpoint.
# Targets GM_corr + free_surface_applied (hallucinated numerics on tank cases).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/tools/finetune/gpu_env.sh"

WARM="${1:-models/yard-stability-json-v1/checkpoint-80}"
OUT="${2:-models/yard-stability-fs3x-v1}"
SAMPLES="${3:-1500}"
STEPS="${4:-100}"
LR="${5:-5e-5}"

DATA="tools/dataset/out/train_chat_json_only_fs3x.jsonl"
if [[ ! -f "$DATA" ]]; then
  echo "--- Export FS3x JSON-only (tank cases 3×) ---"
  python tools/dataset/export_json_only.py \
    --input tools/dataset/out/train.jsonl \
    --output "$DATA" \
    --tank-weight 3
fi

echo "=== FS3x Numerics Train ==="
echo "Warm: $WARM  Out: $OUT  Samples: $SAMPLES  Steps: $STEPS  LR: $LR"
mkdir -p "$OUT"

python tools/finetune/train_local_4gb.py \
  --data "$DATA" \
  --output "$OUT" \
  --resume "$WARM" \
  --max-samples "$SAMPLES" \
  --max-steps "$STEPS" \
  --max-seq-len 384 \
  --lr "$LR" \
  --save-steps 10 \
  --grad-accum 8 \
  2>&1 | tee "$OUT/train.log"

CKPT=$(ls -d "$OUT"/checkpoint-* 2>/dev/null | sort -t- -k2 -n | tail -1)
echo "Latest checkpoint: ${CKPT:-$OUT}"

echo "--- Post-train eval (n=30 smoke) ---"
python tools/finetune/infer_local.py \
  --adapter "$CKPT" \
  --dataset tools/dataset/out/eval.jsonl \
  --output tools/gap_audit/out/fs3x_preds_30.jsonl \
  --limit 30 \
  --max-new-tokens 256 \
  --batch-size 4 \
  --score

echo "=== FS3x done. Run full 200 eval when GPU idle. ==="