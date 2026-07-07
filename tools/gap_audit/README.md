# Gap Audit

Catalog failure modes where frontier/local models miss yard stability behavior.

## Run

```sh
# Simulated baseline (instant) — proves the gap exists
python gap_audit.py --dataset ../dataset/out/eval.jsonl --baseline naive_no_fs
python gap_audit.py --dataset ../dataset/out/eval.jsonl --baseline naive_overconfident

# Live model via Ollama
ollama serve &
python gap_audit.py --dataset ../dataset/out/eval.jsonl --model qwen2.5-coder:1.5b --limit 20 \
  --output out/qwen2.5-coder-1.5b.jsonl
```

## Baseline Results (200-case held-out eval, seed 9999)

### `naive_no_fs` — simulates omitted free-surface + small-angle GZ

| Metric | Score |
|--------|-------|
| Overall PASS/FAIL match | 195/200 (97.5%) |
| GM_corr within 2 cm | 155/200 (77.5%) |
| Flags superset | 117/200 (58.5%) |
| **omitted_free_surface** | **83/200 (41.5%)** |

### `naive_overconfident` — correct math, overconfident PASS

| Metric | Score |
|--------|-------|
| Overall match | 195/200 (97.5%) |
| wrong_is_code_threshold | 5/200 (2.5%) |

## Failure Mode Catalog

| Mode | Description | Fine-tune target |
|------|-------------|------------------|
| `omitted_free_surface` | Skips GG' correction when tanks present | Primary |
| `no_assumption_flags` | Missing validity flags | Primary |
| `small_angle_instead_wall_sided` | Wrong GZ formula | Secondary |
| `wrong_is_code_threshold` | Incorrect regulatory thresholds | Primary |
| `overall_criteria_mismatch` | PASS/FAIL contradicts criteria | Primary |

## Target for Fine-Tune

Beat baseline on **GM_corr within 2 cm** and **flags superset** with minimal prompting.
Overall match alone is insufficient (naive_no_fs already hits 97.5% by overcalling PASS).

License: Apache-2.0.