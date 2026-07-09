# yard-stability-bench v0.1

Held-out benchmark for box-barge intact stability (IMO IS Code 2008 Part A 2.2).

## Files

| Path | Description |
|------|-------------|
| `tools/dataset/out/eval.jsonl` | 200 held-out cases (seed 9999, never in training) |
| `tools/dataset/out/train.jsonl` | 5000 training cases |
| `tools/gap_audit/GAP_REPORT.md` | Full results + failure mode catalog |
| `tools/agent/yard_agent.py` | Physical AI agent (recommended path) |

## Quick eval

```sh
# Oracle agent (recommended — 100% criteria on n=30)
python tools/agent/yard_agent.py eval --limit 30

# Full held-out eval (200 cases, ~11 min with Ollama)
python tools/agent/yard_agent.py eval \
  --modes hybrid ollama record_input \
  --output tools/gap_audit/out/ollama_agent_benchmark_200.txt

# Fine-tuned model (GPU)
source tools/finetune/gpu_env.sh
python tools/finetune/infer_local.py \
  --adapter models/yard-stability-json-v1/checkpoint-80 \
  --dataset tools/dataset/out/eval.jsonl \
  --output tools/gap_audit/out/json_ft_preds_200.jsonl \
  --batch-size 4 --score
```

## Published results (2026-07-09)

| Method | n | Overall | GM_corr ≤2cm | Criteria |
|--------|---|---------|--------------|----------|
| qwen2.5-coder:1.5b pre-FT | 200 | 31.5% | 0.5% | 3.0% |
| JSON-only fine-tune ckpt-80 | 200 | 97.0% | 2.0% | 97.0% |
| oracle_agent + regex NL | 200 | 98.5% | 60.5%* | 98.5% |
| oracle_agent + Ollama NL | 30 | **100%** | 66.7%* | **100%** |
| oracle_agent + structured input | 200 | **100%** | **100%** | **100%** |

\* NL extraction uses rounded dimensions from instruction text; oracle math is exact for extracted spec.

## Compliance packet demo

```sh
python tools/agent/yard_agent.py assess \
  --instruction "Box barge 10m x 4m x 1.5m draft, KG=1.0m, Tank 1: 5x3m fresh water" \
  --output out/compliance_packet
```

Produces: `artifact.json`, `criteria_table.md`, `gz_curve.svg`, audit hashes.

## Citation

```
yard-stability-bench v0.1 — SMC17/yard
https://github.com/SMC17/yard
Oracle: yard-stability-oracle-v0.1
```