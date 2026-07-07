# Deep Execution Playbook

How to take yard from "bag of parts" to frontier verifiable engineering AI.

## The Game (Restated)

> The model is not the deliverable. The dataset is.

A small model wins only where frontier models fail reliably — even with strong prompting.

## Step 1: Find the Gap (DONE — baseline published)

```sh
python tools/gap_audit/gap_audit.py \
  --model qwen2.5-coder:1.5b \
  --dataset tools/dataset/out/eval.jsonl \
  --output tools/gap_audit/out/qwen_gpu_full_200.jsonl
```

**Proven gap (200-case held-out):**
- GM_corr within 2cm: **0.5%** (frontier)
- omitted_free_surface: **24%**
- numerical_drift: **96.5%**

See `tools/gap_audit/GAP_REPORT.md`.

## Step 2: Generate Data (DONE — 5k train)

```sh
bash tools/pipeline.sh
```

Oracle: `tools/oracle/yard_stability_oracle.py` mirrors Zig `stability/` + `hydro/`.

## Step 3: Filter Hard (DONE — 100% pass rate)

```sh
python tools/dataset/filter.py --input raw --output train.jsonl
```

Gates: numerical verify, reasoning rubric, dedup, diversity.

## Step 4: Fine-Tune (BLOCKED — CUDA cuInit 999)

```sh
# After reboot or nix develop tools/finetune/
python tools/finetune/train_local_4gb.py \
  --data tools/dataset/out/train_chat.jsonl \
  --output models/yard-stability-4gb-v1 \
  --max-samples 200 --epochs 2  # smoke
```

GTX 1650 4GB → Qwen2.5-0.5B QLoRA. Ollama inference works via Vulkan.

## Step 5: Build Eval (DONE)

```sh
python tools/eval/harness.py \
  --dataset tools/dataset/out/eval.jsonl \
  --predictions tools/gap_audit/out/preds.jsonl \
  --mode model
```

Post-FT targets:
| Metric | Baseline | Target |
|--------|----------|--------|
| GM_corr ±2cm | 0.5% | ≥95% |
| 6 criteria exact | 3.0% | ≥90% |
| omitted_free_surface | 24% | ≤5% |

## Step 6: Prove Behavior in Weights (PENDING)

Required ablations before claiming success:
1. Minimal prompt (one-line system)
2. FS ablation retrain (GM_corr should collapse)
3. Jailbreak resistance ("ignore free-surface")

## Phase 1 Extension: Multimodal

```sh
python tools/dataset/render_multimodal.py \
  --input tools/dataset/out/train.jsonl \
  --output tools/dataset/out/train_multimodal.jsonl \
  --images-dir tools/dataset/out/images \
  --max 500  # start small
```

Renders oracle-verified GZ SVG per record. Model learns structured JSON **and** curve shape.

## Phase 1 Extension: CLI + Agent

```sh
python tools/cli/yard-cli.py stability --L 10 --B 4 --T 1.5 --kg 1.0 \
  --tank 5,3,1000 --json --render /tmp/gz.svg

python tools/agent/orchestrate.py --spec examples/agent_spec.json
```

## Phase 2: Composition Depth

```sh
zig build run-full-assessment
```

Wires `compose/vessel_assessment.zig`: stability + Holtrop resistance.

## Phase 2: Vulkan

See `viz-vulkan/ROADMAP.md`. Zig-native renderer; scene graph in, pixels out.

## Anti-Patterns (Do Not)

- Claim "69 production modules"
- Ship without oracle verification on every training record
- Use model output as engineering numbers without Zig cross-check
- Add peripheral modules before core composes