#!/usr/bin/env bash
# Source before GPU training/inference on GTX 1650 (4GB).
# Usage: source tools/finetune/gpu_env.sh

export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True,max_split_size_mb:128}"

# Prefer system libcuda (Arch) over broken pip shims
export LD_LIBRARY_PATH="/usr/lib:${LD_LIBRARY_PATH:-}"

# Ollama: official binary (Vulkan/CUDA) over Nix CPU-only build
export PATH="$HOME/.local/share/ollama-official/bin:$HOME/.local/bin:${PATH}"
# GTX 1650 on this machine: CUDA cuInit fails (error 999); Vulkan works.
export OLLAMA_VULKAN="${OLLAMA_VULKAN:-1}"
export OLLAMA_NUM_GPU="${OLLAMA_NUM_GPU:-1}"
export OLLAMA_GPU_LAYERS="${OLLAMA_GPU_LAYERS:-99}"

echo "GPU env:"
echo "  CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
echo "  OLLAMA_NUM_GPU=$OLLAMA_NUM_GPU"
if command -v nvidia-smi &>/dev/null; then
  nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader
fi