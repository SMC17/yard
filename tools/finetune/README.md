# Yard Stability Fine-Tune — GPU Edition

Fine-tune IMO IS Code 2008 stability behavior on your **GTX 1650 4GB**.

## Your GPU Stack (diagnosed 2026-07-07)

| Component | Status | Fix |
|-----------|--------|-----|
| `nvidia-smi` | ✅ GTX 1650 4GB visible | — |
| Nix `ollama` | ❌ CPU-only | Use `setup_ollama_gpu.sh` |
| Official `ollama` | ✅ **Vulkan on GTX 1650** (1115 MiB VRAM) | `ollama ps` → `100% GPU` |
| Mise `torch` cu121 | ❌ `cuInit 999` (CUDA context stuck) | **Reboot** or `nix develop` |
| `bitsandbytes` | ✅ Installed | Ready when CUDA works |

## Quick Start (3 paths)

### Path A: Ollama GPU — inference + gap audit (fastest win)

```sh
# One-time: install official Ollama with CUDA (not Nix CPU build)
bash tools/finetune/setup_ollama_gpu.sh

# Start GPU server
pkill -x ollama 2>/dev/null; ollama-gpu serve &

# Gap audit on GPU (20x faster than CPU)
python tools/gap_audit/gap_audit.py \
  --dataset tools/dataset/out/eval.jsonl \
  --model qwen2.5-coder:1.5b --limit 50 \
  --output tools/gap_audit/out/qwen_gpu.jsonl
```

Verify GPU:
```sh
ollama ps
# NAME  PROCESSOR
# ...   100% GPU     ← Vulkan backend on GTX 1650

nvidia-smi  # llama-server ~1100 MiB
```

Note: CUDA backend fails with `cuInit 999` on this machine; Ollama auto-falls back to Vulkan (works fine).

### Path B: Nix CUDA shell — training (recommended for PyTorch)

```sh
cd tools/finetune
nix develop   # builds CUDA-enabled python+torch (first run ~10min)

python ../../tools/finetune/train_local_4gb.py \
  --data ../../tools/dataset/out/train_chat.jsonl \
  --output ../../models/yard-stability-4gb-v1 \
  --max-samples 500 --epochs 2
```

### Path C: Fix mise PyTorch CUDA (if Path B unavailable)

```sh
bash tools/finetune/fix_gpu.sh

# Remove corrupted pip metadata
rm -rf ~/.local/share/mise/installs/python/*/lib/python*/site-packages/~vidia*

# Pin CUDA 12.1 libs to match torch cu121
pip install --no-cache-dir \
  nvidia-cublas-cu12==12.1.3.1 \
  nvidia-cuda-runtime-cu12==12.1.105 \
  nvidia-cudnn-cu12==9.1.0.70 \
  nvidia-cuda-nvrtc-cu12==12.1.105

pip install --no-cache-dir bitsandbytes

source tools/finetune/gpu_env.sh
python -c "import torch; print(torch.cuda.is_available())"

# If still False: reboot (CUDA context stuck after driver/Hyprland init)
#   sudo nvidia-modprobe -u -c=0   # alternative before reboot
```

## 4GB VRAM Training Settings

`train_local_4gb.py` defaults (safe on GTX 1650):

| Parameter | Value | Why |
|-----------|-------|-----|
| Model | `Qwen2.5-0.5B-Instruct` | ~1GB in 4-bit |
| `max_seq_len` | 1024 | Fits in 4GB |
| `batch_size` | 1 | Memory |
| `grad_accum` | 8 | Effective batch 8 |
| `lora_r` | 8 | Small adapter |
| Optimizer | `paged_adamw_8bit` | VRAM efficient |

Smoke test first:
```sh
python tools/finetune/train_local_4gb.py \
  --data tools/dataset/out/train_chat.jsonl \
  --output models/smoke-test --max-samples 50 --epochs 1
```

Scale up: remove `--max-samples` for full 5k dataset.

## Full Pipeline

```sh
bash tools/pipeline.sh                              # generate 5k + gap baselines
bash tools/finetune/setup_ollama_gpu.sh             # GPU inference
source tools/finetune/gpu_env.sh
python tools/finetune/train_local_4gb.py ...      # fine-tune (CUDA required)
python tools/finetune/infer_ollama.py --model yard-stability-4gb-v1 ...
python tools/eval/harness.py --mode model ...
```

## Model Selection

| Base model | 4GB QLoRA | Notes |
|------------|-----------|-------|
| Qwen2.5-0.5B-Instruct | ✅ Default | Safest on 4GB |
| Qwen2.5-1.5B-Instruct | ⚠️ Tight | `--max-seq-len 768` |
| Qwen2.5-7B | ❌ | Needs ≥12GB |

## Proof Discipline

Beat gap-audit baselines on held-out eval before claiming success:

- GM_corr within 2cm: **≥95%** (baseline: 77.5%)
- omitted_free_surface: **≤5%** (baseline: 41.5%)

License: Apache-2.0.