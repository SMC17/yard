#!/usr/bin/env bash
# Diagnose and repair GPU stack for yard fine-tune on GTX 1650.
set -euo pipefail

echo "=== Yard GPU Diagnostics ==="

echo ""
echo "--- NVIDIA driver ---"
nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free --format=csv 2>/dev/null || {
  echo "FAIL: nvidia-smi not working"
  exit 1
}

echo ""
echo "--- Device holders ---"
fuser -v /dev/nvidia0 2>&1 || true

echo ""
echo "--- PyTorch (mise python) ---"
python3 -c "
import torch
print(f'torch {torch.__version__}')
print(f'cuda available: {torch.cuda.is_available()}')
print(f'device count: {torch.cuda.device_count()}')
" 2>&1 || true

echo ""
echo "--- Corrupted pip packages ---"
ls -d ~/.local/share/mise/installs/python/*/lib/python*/site-packages/~vidia* 2>/dev/null && \
  echo "FOUND corrupted ~vidia packages — run fix below" || echo "OK: no corrupted ~vidia dirs"

echo ""
echo "--- Ollama GPU ---"
ollama ps 2>/dev/null || true
echo ""
echo "--- Ollama (official + Vulkan) ---"
if [[ -x "$HOME/.local/share/ollama-official/bin/ollama" ]]; then
  echo "Official ollama installed at ~/.local/share/ollama-official"
  echo "Start: OLLAMA_VULKAN=1 ollama serve"
  echo "       (CUDA may fail cuInit 999 — Vulkan uses GTX 1650 successfully)"
else
  echo "Run: bash tools/finetune/setup_ollama_gpu.sh"
fi

echo ""
echo "=== Fixes ==="
echo "1. Remove corrupted nvidia pip metadata:"
echo "   rm -rf ~/.local/share/mise/installs/python/*/lib/python*/site-packages/~vidia*"
echo ""
echo "2. Pin CUDA 12.1 libs to match torch cu121:"
echo "   pip install --no-cache-dir nvidia-cublas-cu12==12.1.3.1 nvidia-cuda-runtime-cu12==12.1.105 \\"
echo "     nvidia-cudnn-cu12==9.1.0.70 nvidia-cuda-nvrtc-cu12==12.1.105"
echo ""
echo "3. Install bitsandbytes:"
echo "   pip install --no-cache-dir bitsandbytes"
echo ""
echo "4. Use Nix CUDA shell (recommended):"
echo "   cd tools/finetune && nix develop"
echo ""
echo "5. Train on 4GB GPU:"
echo "   source tools/finetune/gpu_env.sh"
echo "   python tools/finetune/train_local_4gb.py --data tools/dataset/out/train_chat.jsonl \\"
echo "     --output models/yard-stability-4gb-v1 --max-samples 200"