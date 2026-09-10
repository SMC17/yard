#!/usr/bin/env bash
# Install OpenVSP CLI into vendor/openvsp (Ubuntu 24.04 .deb extract).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor/openvsp"
TMP="${TMPDIR:-/tmp}/openvsp-dl-$$"
DEB_URL="${OPENVSP_DEB_URL:-https://openvsp.org/download.php?file=zips/current/linux/OpenVSP-3.51.3-Ubuntu-24.04_amd64.deb}"

mkdir -p "$TMP"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "Downloading OpenVSP .deb ..."
curl -fL --progress-bar -o "$TMP/openvsp.deb" "$DEB_URL"

echo "Installing runtime libs (sudo) ..."
sudo apt-get update -qq
sudo apt-get install -y -qq libcminpack1 libglew2.2 libglu1-mesa

echo "Extracting to $VENDOR ..."
rm -rf "$VENDOR"
mkdir -p "$TMP/extract"
dpkg-deb -x "$TMP/openvsp.deb" "$TMP/extract"
mv "$TMP/extract/opt/OpenVSP" "$VENDOR"

mkdir -p "${HOME}/.local/bin"
ln -sfn "$VENDOR/vspscript" "${HOME}/.local/bin/vspscript"
ln -sfn "$VENDOR/vsp" "${HOME}/.local/bin/vsp"
ln -sfn "$VENDOR/vspaero" "${HOME}/.local/bin/vspaero"

ls -la "$VENDOR/vspscript" "$VENDOR/vsp" "$VENDOR/vspaero"
echo "OK — vendor/openvsp ready. See docs/OPENVSP_INSTALL.md"
