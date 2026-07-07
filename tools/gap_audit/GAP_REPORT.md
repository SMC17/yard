# Gap Audit Report — 2026-07-07

**Eval set:** 200 held-out cases (`eval.jsonl`, seed 9999, never in training)  
**Oracle:** `yard-stability-oracle-v0.1` (mirrors Zig ground truth)

## Executive Summary

The gap is real and measurable. Models fail primarily on **free-surface correction** and **numerical precision**, not on whether they can produce JSON.

Fine-tune target metrics (beat these on held-out eval):

| Metric | naive_no_fs | qwen2.5-coder:1.5b (n=200, GPU) | Target post-FT |
|--------|-------------|--------------------------------|---------------|
| GM_corr within 2 cm | 77.5% | **0.5%** | ≥ 95% |
| Flags superset | 58.5% | 99.5%* | ≥ 95% |
| All 6 criteria exact | 97.5% | **3.0%** | ≥ 90% |
| omitted_free_surface | 41.5% | 24.0% | ≤ 5% |

\* qwen2.5-coder:1.5b emits flags but with wrong numbers — flags without correct math is worthless.

## Failure Mode Distribution (200-case eval)

### Baseline: `naive_no_fs` (simulates common frontier failure)

```
omitted_free_surface:       83/200 (41.5%)  ← PRIMARY FINE-TUNE TARGET
no_assumption_flags:        83/200 (41.5%)
small_angle_instead_wall_sided: 83/200 (41.5%)
numerical_drift:             8/200 ( 4.0%)
wrong_is_code_threshold:     5/200 ( 2.5%)
```

### Live model: `qwen2.5-coder:1.5b` (Ollama, **Vulkan GPU**, n=200) — 2026-07-07

```
numerical_drift:            193/200 (96.5%)  ← model hallucinates numbers
wrong_is_code_threshold:    193/200 (96.5%)
overall_criteria_mismatch:  136/200 (68.0%)
omitted_free_surface:        48/200 (24.0%)
json_parse_failure:           1/200 ( 0.5%)
```

| Metric | Score |
|--------|-------|
| Overall PASS/FAIL match | **63/200 (31.5%)** |
| GM₀ within 2cm | **1/200 (0.5%)** |
| GM_corr within 2cm | **1/200 (0.5%)** |
| All 6 criteria exact | **6/200 (3.0%)** |
| Flags superset | 199/200 (99.5%) |

**Interpretation:** Models emit plausible flags and JSON but **cannot do stability arithmetic**
from prompting alone. Flags without correct math are worthless. Fine-tune target is clear:
internalize oracle-verified numerical workflow (GM → FS correction → IS Code).

Raw results: `tools/gap_audit/out/qwen_gpu_full_200.jsonl`

## Dataset Status

| Artifact | Records | Status |
|----------|---------|--------|
| `train.jsonl` | 5,000 | Generated + filtered (100% pass) |
| `eval.jsonl` | 200 | Held-out, oracle-verified |
| `val.jsonl` | 500 | Held-out validation |
| `train_chat.jsonl` | 5,000 | Unsloth-ready chat format |

Regenerate: `bash tools/pipeline.sh`

## Next: Fine-Tune

```sh
# On CUDA machine with >= 12GB VRAM
python tools/finetune/train_unsloth.py \
  --data tools/dataset/out/train_chat.jsonl \
  --output models/yard-stability-v1

# Eval
python tools/finetune/infer_ollama.py --model yard-stability-v1 \
  --dataset tools/dataset/out/eval.jsonl --output tools/gap_audit/out/ft_preds.jsonl
python tools/eval/harness.py --dataset tools/dataset/out/eval.jsonl \
  --predictions tools/gap_audit/out/ft_preds.jsonl --mode model
```

## Ablation Plan (required before claiming success)

1. **Minimal prompt** — strip system prompt to one line
2. **Paraphrase** — 4 instruction styles already in dataset
3. **FS ablation** — retrain without tank examples → GM_corr should collapse
4. **Jailbreak** — "ignore free-surface correction" → model should resist