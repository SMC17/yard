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

## Smoke Fine-Tune Eval — checkpoint-25 (2026-07-08)

**Not a success claim.** Smoke train stopped at step 40/50 (CUBLAS error); only
checkpoint-25 saved. Eval via `infer_local.py` on 30 held-out cases.

| Metric | qwen2.5-coder:1.5b pre-FT (n=200) | checkpoint-25 smoke (n=30) | Target post-FT |
|--------|-----------------------------------|---------------------------|----------------|
| Overall PASS/FAIL match | 31.5% | **40.0%** | ≥ 90% |
| GM₀ within 2 cm | 0.5% | **0%** | ≥ 95% |
| GM_corr within 2 cm | 0.5% | **0%** | ≥ 95% |
| All 6 criteria exact | 3.0% | **26.7%** | ≥ 90% |
| Flags superset | 99.5% | 40.0% | ≥ 95% |
| JSON parse failure | 0.5% | **60.0%** | ≤ 2% |

**Failure modes (n=30):** `json_parse_failure` 18/30 (60%), `numerical_drift` 12/30,
`wrong_is_code_threshold` 4/30, `omitted_free_surface` 2/30.

**Interpretation:** 25 training steps on Qwen2.5-0.5B (not the 1.5B Ollama baseline)
improved criteria matching slightly but **worsened JSON compliance** — model emits
Chinese chain-of-thought and malformed JSON arrays. Numerics still at zero.
Full 5k train on stable GPU required before any post-FT claim.

Raw: `tools/gap_audit/out/smoke_preds.jsonl`

## JSON-Only Fine-Tune — checkpoint-80 (2026-07-08) ✅ TRAIN COMPLETE

**Train:** 500 JSON-only samples, 80 steps, seq_len=384, Qwen2.5-0.5B QLoRA  
**Loss:** 2.88 → 0.27 | **Token accuracy:** 0.46 → 0.89 | **Runtime:** 42 min

| Metric | pre-FT 1.5B (n=200) | CoT ckpt-25 (n=30) | **JSON ckpt-80 (n=30)** | Target |
|--------|---------------------|-------------------|------------------------|--------|
| Overall PASS/FAIL | 31.5% | 40.0% | **93.3%** | ≥ 90% |
| JSON parse failure | 0.5% | 60.0% | **6.7%** | ≤ 2% |
| All 6 criteria exact | 3.0% | 26.7% | **93.3%** | ≥ 90% |
| GM_corr within 2 cm | 0.5% | 0% | **3.3%** | ≥ 95% |
| omitted_free_surface | 24.0% | 6.7% | **26.7%** | ≤ 5% |
| Flags superset | 99.5% | 40.0% | 6/30 (20%) | ≥ 95% |

**Interpretation:** JSON-only training **fixed format compliance** (criteria matching
93%). Model learned regulatory PASS/FAIL patterning but **still hallucinates GM
numbers** (83% numerical_drift) and **skips free-surface** on tank cases. Next:
full 5k JSON-only train + FS-weighted sampling + numeric loss emphasis in dataset.

Raw: `tools/gap_audit/out/json_ft_preds_30.jsonl`

## JSON-Only Fine-Tune — checkpoint-80 FULL EVAL (2026-07-09) ✅ n=200

**Train:** 500 JSON-only samples, 80 steps, seq_len=384, Qwen2.5-0.5B QLoRA  
**Eval:** `infer_local.py --batch-size 4` on full held-out `eval.jsonl`

| Metric | pre-FT 1.5B (n=200) | JSON ckpt-80 (n=30) | **JSON ckpt-80 (n=200)** | Target |
|--------|---------------------|---------------------|---------------------------|--------|
| Overall PASS/FAIL | 31.5% | 93.3% | **97.0%** | ≥ 90% ✅ |
| JSON parse failure | 0.5% | 6.7% | **0.5%** | ≤ 2% ✅ |
| All 6 criteria exact | 3.0% | 93.3% | **97.0%** | ≥ 90% ✅ |
| GM_corr within 2 cm | 0.5% | 3.3% | **2.0%** | ≥ 95% ❌ |
| GM₀ within 2 cm | 0.5% | — | **2.0%** | ≥ 95% ❌ |
| omitted_free_surface | 24.0% | 26.7% | **28.0%** | ≤ 5% ❌ |
| Flags superset | 99.5% | 20% | **16.0%** | ≥ 95% ❌ |

**Failure modes (n=200):** `numerical_drift` 190/200 (95%), `omitted_free_surface` 56/200 (28%),
`no_assumption_flags` 52/200 (26%), `overall_criteria_mismatch` 5/200 (2.5%),
`json_parse_failure` 1/200 (0.5%).

**Interpretation:** Format/criteria lane **scales** — 97% on full held-out eval. Model learned
regulatory PASS/FAIL patterning reliably. **Numerics lane still blocked:** 95% numerical_drift,
GM_corr at 2%. Next: FS3x warm-start from checkpoint-80 (`train_fs3x.sh`).

Raw: `tools/gap_audit/out/json_ft_preds_200.jsonl`