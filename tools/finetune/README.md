# Yard Stability Fine-Tune

QLoRA fine-tune pipeline for IMO IS Code 2008 Part A 2.2 box-barge stability behavior.

## Prerequisites

- CUDA GPU with **≥ 12 GB VRAM** (GTX 1650 4GB is insufficient for 3B QLoRA)
- Python 3.10+
- `pip install unsloth transformers datasets trl peft accelerate`

## Pipeline

```sh
# 1. Generate + filter dataset
python ../dataset/generate.py --samples 5000 --output ../dataset/out/raw.jsonl
python ../dataset/filter.py --input ../dataset/out/raw.jsonl --output ../dataset/out/train.jsonl
python ../dataset/export_sft.py --input ../dataset/out/train.jsonl --output ../dataset/out/train_chat.jsonl

# 2. Gap audit BEFORE fine-tune (establish baseline)
python ../gap_audit/gap_audit.py --dataset ../dataset/out/eval.jsonl --baseline naive_no_fs

# 3. Fine-tune (CUDA required)
python train_unsloth.py --data ../dataset/out/train_chat.jsonl --output ../../models/yard-stability-v1

# 4. Eval AFTER fine-tune
python infer_ollama.py --model yard-stability-v1 --dataset ../dataset/out/eval.jsonl
python ../eval/harness.py --dataset ../dataset/out/eval.jsonl --predictions ../gap_audit/out/preds.jsonl --mode model
```

## Model Selection

| Base model | VRAM (QLoRA) | Notes |
|------------|--------------|-------|
| Qwen2.5-3B-Instruct | ~8 GB | Minimum viable |
| Phi-4-mini | ~10 GB | Strong math bias |
| Qwen2.5-7B-Instruct | ~14 GB | Better capacity |

## Proof Discipline

Do not claim "behavior in weights" without:

1. Held-out eval set (seed 9999, never in training)
2. Gap-audit failure modes showing improvement
3. Minimal-prompt ablation
4. FS-example ablation (remove FS records → performance drops)

License: Apache-2.0.