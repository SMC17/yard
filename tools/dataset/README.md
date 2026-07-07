# Yard Stability Dataset Pipeline

Oracle-verified SFT data for IMO IS Code 2008 Part A 2.2 box-barge stability.

## Quick Start

```sh
# Oracle sanity check
python ../oracle/yard_stability_oracle.py

# Generate training data
python generate.py --samples 5000 --output out/train.jsonl --split train

# Held-out eval set (different seed — never train on this)
python generate.py --samples 200 --output out/eval.jsonl --split eval --seed 9999

# Verify integrity
python ../eval/harness.py --dataset out/eval.jsonl --mode oracle
```

## Schema

See `schema.json`. Each record contains:

- `instruction` — natural-language problem (4 style variants)
- `reasoning` — step-by-step with formula citations
- `answer` — structured numerical + pass/fail output
- `input` — machine-readable parameters for oracle replay
- `verification` — source + tolerance metadata

## The Deliverable

The dataset + eval harness is the valuable artifact. Model weights are ephemeral.
Publish `out/eval.jsonl` and eval results; keep training sets versioned.

License: Apache-2.0.