#!/usr/bin/env bash
# Full dataset + gap-audit pipeline for yard stability SFT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/tools"

echo "=== 1. Oracle self-test ==="
python oracle/yard_stability_oracle.py

echo "=== 2. Generate datasets ==="
python dataset/generate.py --samples 5000 --output dataset/out/raw_train.jsonl --split train --seed 42
python dataset/generate.py --samples 200 --output dataset/out/eval.jsonl --split eval --seed 9999
python dataset/generate.py --samples 500 --output dataset/out/val.jsonl --split val --seed 7777

echo "=== 3. Filter training data ==="
python dataset/filter.py --input dataset/out/raw_train.jsonl --output dataset/out/train.jsonl

echo "=== 4. Export SFT format ==="
python dataset/export_sft.py --input dataset/out/train.jsonl --output dataset/out/train_chat.jsonl

echo "=== 5. Oracle integrity on eval ==="
python eval/harness.py --dataset dataset/out/eval.jsonl --mode oracle

echo "=== 6. Gap audit baselines ==="
python gap_audit/gap_audit.py --dataset dataset/out/eval.jsonl --baseline naive_no_fs \
  --output gap_audit/out/baseline_naive_no_fs.jsonl
python gap_audit/gap_audit.py --dataset dataset/out/eval.jsonl --baseline naive_overconfident \
  --output gap_audit/out/baseline_overconfident.jsonl

echo "=== 7. Multimodal assets (sample) ==="
python dataset/render_multimodal.py --input dataset/out/eval.jsonl \
  --output dataset/out/eval_multimodal.jsonl \
  --images-dir dataset/out/images --max 50

echo "=== Done ==="
echo "Train: $(wc -l < dataset/out/train.jsonl) records"
echo "Eval:  $(wc -l < dataset/out/eval.jsonl) records"
echo "Chat:  $(wc -l < dataset/out/train_chat.jsonl) records"