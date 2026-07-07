#!/usr/bin/env bash
# Source before GPU training/inference on GTX 1650 (4GB).
# Usage: source tools/finetune/gpu_env.sh

export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True,max_split_size_mb:128}"

# Production LD wire (mise python + nvidia cu12 + torch + triton cupti + system libcuda)
_MISE_SITE="${HOME}/.local/share/mise/installs/python/3.12.13/lib/python3.12/site-packages"
export LD_LIBRARY_PATH="${_MISE_SITE}/nvidia/cusparse/lib:${_MISE_SITE}/nvidia/cuda_runtime/lib:${_MISE_SITE}/nvidia/cublas/lib:${_MISE_SITE}/nvidia/cuda_cupti/lib:${_MISE_SITE}/torch/lib:${_MISE_SITE}/triton/backends/nvidia/lib/cupti:/usr/lib:/usr/lib64:${LD_LIBRARY_PATH:-}"

# Ollama: official binary (Vulkan/CUDA) over Nix CPU-only build
export PATH="${HOME}/.local/share/ollama-official/bin:${HOME}/.local/bin:${PATH}"
export OLLAMA_VULKAN="${OLLAMA_VULKAN:-1}"
export OLLAMA_NUM_GPU="${OLLAMA_NUM_GPU:-1}"
export OLLAMA_GPU_LAYERS="${OLLAMA_GPU_LAYERS:-99}"

echo "GPU env:"
echo "  CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
echo "  OLLAMA_NUM_GPU=$OLLAMA_NUM_GPU"
if command -v nvidia-smi &>/dev/null; then
  nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader
fi

# Quick UVM health check
python3 - <<'PY' 2>/dev/null || echo "  WARN: nvidia-uvm broken — run: bash tools/finetune/fix_cuda.sh"
import os
fd = os.open("/dev/nvidia-uvm", os.O_RDWR)
os.close(fd)
import torch
if not torch.cuda.is_available():
    raise SystemExit("  WARN: torch.cuda not available")
print(f"  CUDA OK: {torch.cuda.get_device_name(0)}")
PY