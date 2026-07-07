#!/usr/bin/env bash
# Install official Ollama with CUDA support (Nix ollama is CPU-only).
set -euo pipefail

INSTALL_DIR="${OLLAMA_GPU_DIR:-$HOME/.local/share/ollama-official}"
VERSION="${OLLAMA_VERSION:-v0.31.1}"
TARBALL="/tmp/ollama-linux-amd64.tar.zst"
ALT_TARBALL="/tmp/ollama-gpu.tar.zst"
URL="https://github.com/ollama/ollama/releases/download/${VERSION}/ollama-linux-amd64.tar.zst"

echo "Installing Ollama ${VERSION} with CUDA to ${INSTALL_DIR}"

mkdir -p "$INSTALL_DIR"
if [[ -f "$ALT_TARBALL" ]]; then
  TARBALL="$ALT_TARBALL"
elif [[ ! -f "$TARBALL" ]]; then
  echo "Downloading..."
  curl -fsSL "$URL" -o "$TARBALL"
fi

echo "Extracting (1.4GB, takes ~30s)..."
rm -rf "$INSTALL_DIR"/*
tar --use-compress-program=unzstd -xf "$TARBALL" -C "$INSTALL_DIR"

# Tarball layout: bin/ollama, lib/ollama/cuda_v12/, etc.
ln -sf "$INSTALL_DIR/bin/ollama" "$HOME/.local/bin/ollama-gpu"

echo ""
echo "Installed: $(ollama-gpu --version 2>&1 | tail -1)"
echo "CUDA libs: $(ls "$INSTALL_DIR/lib/ollama/cuda_v12/" 2>/dev/null | head -3 | tr '\n' ' ')..."
echo ""
echo "Start GPU server:"
echo "  pkill -x ollama 2>/dev/null; ollama-gpu serve"
echo ""
echo "Gap audit on GPU:"
echo "  python tools/gap_audit/gap_audit.py --dataset tools/dataset/out/eval.jsonl \\"
echo "    --model qwen2.5-coder:1.5b --limit 20"