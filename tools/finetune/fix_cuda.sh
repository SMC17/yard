#!/usr/bin/env bash
# CUDA UVM recovery + dependency install + verify for yard fine-tune.
# Root cause: /dev/nvidia-uvm EIO → cuInit 999 (see ~/homelab/docs/cuda-uvm-recovery.md)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "=== Yard CUDA Fix ==="

# --- 1. Diagnose ---
echo ""
echo "--- Pre-fix diagnostics ---"
nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free --format=csv,noheader 2>/dev/null || {
  echo "FAIL: nvidia-smi not working"
  exit 1
}

python3 - <<'PY' 2>/dev/null || true
import os
try:
    fd = os.open("/dev/nvidia-uvm", os.O_RDWR)
    os.close(fd)
    print("nvidia-uvm: OK")
except OSError as e:
    print(f"nvidia-uvm: BROKEN ({e})")
PY

# --- 2. Stop GPU inference services ---
echo ""
echo "--- Stopping Ollama (frees Vulkan/CUDA context) ---"
pkill -f "ollama serve" 2>/dev/null || true
sleep 2

# --- 3. UVM module reload (requires root) ---
echo ""
echo "--- Reloading nvidia_uvm kernel module ---"
if python3 -c "import os; os.open('/dev/nvidia-uvm', os.O_RDWR)" 2>/dev/null; then
  echo "UVM already healthy — skipping reload"
else
  echo "UVM broken — attempting recovery (pkexec will prompt for password)..."
  pkexec fuser -k /dev/nvidia-uvm 2>/dev/null || true
  sleep 2
  pkexec modprobe -r nvidia_uvm
  pkexec modprobe nvidia_uvm
  nvidia-modprobe -u -c=0 -m 2>/dev/null || true
fi

# --- 4. Verify CUDA ---
echo ""
echo "--- Post-recovery CUDA verify ---"
source "$ROOT/tools/finetune/gpu_env.sh"
python3 - <<'PY'
import ctypes, sys
libc = ctypes.CDLL("libcuda.so.1")
rc = libc.cuInit(0)
if rc != 0:
    print(f"FAIL: cuInit returned {rc}")
    sys.exit(1)
import torch
assert torch.cuda.is_available(), "torch.cuda.is_available() is False"
name = torch.cuda.get_device_name(0)
x = torch.randn(512, 512, device="cuda")
y = x @ x.T
torch.cuda.synchronize()
print(f"PASS: {name}, matmul {tuple(y.shape)}")
PY

# --- 5. Install training deps ---
echo ""
echo "--- Installing training dependencies ---"
pip install --no-cache-dir \
  bitsandbytes accelerate peft trl datasets scipy sentencepiece protobuf

# --- 6. Pin CUDA 12.1 libs (match torch cu121) ---
echo ""
echo "--- Pinning nvidia CUDA 12.1 wheels ---"
rm -rf ~/.local/share/mise/installs/python/*/lib/python*/site-packages/~vidia* 2>/dev/null || true
pip install --no-cache-dir \
  nvidia-cublas-cu12==12.1.3.1 \
  nvidia-cuda-runtime-cu12==12.1.105 \
  nvidia-cudnn-cu12==9.1.0.70 \
  nvidia-cuda-nvrtc-cu12==12.1.105

echo ""
echo "=== CUDA READY ==="
echo "Smoke train:"
echo "  source tools/finetune/gpu_env.sh"
echo "  python tools/finetune/train_local_4gb.py \\"
echo "    --data tools/dataset/out/train_chat.jsonl \\"
echo "    --output models/yard-stability-4gb-v1 \\"
echo "    --max-samples 200 --epochs 2"