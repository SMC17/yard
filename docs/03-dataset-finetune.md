# Dataset & Fine-Tuning Execution Plan

## The Game

> The model is not the deliverable. The dataset is.

Frontier models are 80–90% good at naval architecture. They fail on reliability-sensitive
narrow behaviors. A small fine-tuned model wins by internalizing behaviors that prompting cannot fix.

## 6-Step Pipeline

### Step 1: Gap Audit

Take 30–50 held-out cases from `validation_fixtures.md` and module READMEs.
Run against frontier models with strong CoT prompting. Catalog:

- Formula mix-ups
- Missed corrections
- Threshold errors
- Overconfidence outside envelope

Store failures in `tools/dataset/out/gap-audit.jsonl` with `--split gap-audit`.

### Step 2: Generate Data

```sh
# Seed training set
python tools/dataset/generate.py --samples 5000 --output tools/dataset/out/train.jsonl --split train

# Held-out eval (never seen in training)
python tools/dataset/generate.py --samples 200 --output tools/dataset/out/eval.jsonl --split eval --seed 9999

# Validation split
python tools/dataset/generate.py --samples 500 --output tools/dataset/out/val.jsonl --split val --seed 7777
```

Schema: `tools/dataset/schema.json`

### Step 3: Filter Hard

Automated gates (implement in your filter script):

1. **Numerical verify** — Recompute via oracle; discard if any field outside tolerance
2. **Reasoning rubric** — Must cite formulas, apply FS correction, flag assumptions
3. **Diversity** — Cover edge cases (no tanks, multiple tanks, marginal GM)
4. **Dedup** — Aggressive hash-based deduplication
5. **Gap-only** — Remove cases frontier models already solve

Target: 5k–15k high-quality examples beats 100k mediocre ones.

### Step 4: Fine-Tune

**Base models (mid-2026):**

| Model | Why |
|-------|-----|
| Phi-4-reasoning | Strong structured math bias |
| Qwen3.5-7B / 14B | Fine-tunability + capability balance |
| Gemma-4 | Apache-2.0 license |

**Framework:** Unsloth + QLoRA (4-bit), 2–4 epochs, conservative LR.

**Training format:**

```json
{"messages": [
  {"role": "user", "content": "<instruction>"},
  {"role": "assistant", "content": "<reasoning>\n\n<json answer>"}
]}
```

### Step 5: Eval

```sh
# Dataset integrity (must be 100%)
python tools/eval/harness.py --dataset tools/dataset/out/eval.jsonl --mode oracle

# Model predictions
python tools/eval/harness.py --dataset tools/dataset/out/eval.jsonl \
  --predictions your_model_preds.jsonl --mode model
```

Score dimensions:

- Overall PASS/FAIL exact match
- GM₀ / GM_corrected numerical tolerance
- All 6 criteria exact match
- Flags superset check

### Step 6: Prove Behavior in Weights

Required evidence before claiming success:

1. Large improvement on gap-audit failure modes
2. Minimal-prompt consistency (no CoT leakage)
3. Paraphrase robustness
4. Ablation: remove FS examples → performance drops
5. Jailbreak resistance test
6. Public release of eval set + numbers

## Hardware Notes

| Setup | Training | Inference |
|-------|----------|-----------|
| Single RTX 4090 | Unsloth QLoRA 7B | ✓ |
| Mac Studio M2 Ultra | MLX inference | Training → cloud |
| Multi-GPU | Axolotl | Production scale |

## Open-Source Artifacts to Publish

1. `tools/dataset/out/eval.jsonl` (held-out, no train overlap)
2. `tools/eval/harness.py` + rubric
3. Gap-audit baseline numbers (frontier vs fine-tuned)
4. Ablation results

The dataset + eval harness is the moat. The model weights are ephemeral.